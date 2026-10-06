import AppKit
import ClockifyCore
import SwiftUI
import XCTest
@testable import ClockifyBar

final class TrackerModelTests: XCTestCase {
    @MainActor
    func testMissingHistoryRetriesEvenWhenStatusWasJustLoaded() async {
        let server = StubServer(historyFailures: 1)
        let (model, session) = makeModel(server)
        defer { session.invalidateAndCancel() }
        await model.connect(key: "test-key")
        XCTAssertTrue(model.statusKnown)
        XCTAssertTrue(model.recent.isEmpty)
        XCTAssertNotNil(model.error)

        await model.refresh(includeHistory: true)

        XCTAssertEqual(model.recent.count, 4)
        XCTAssertNil(model.error)
        XCTAssertEqual(server.historyRequests, 2)
        XCTAssertEqual(server.statusRequests, 1, "Recovering history must not refetch fresh status")
    }

    @MainActor
    func testFreshHistoryAndStatusRemainCachedOnMenuOpening() async {
        let server = StubServer()
        let (model, session) = makeModel(server)
        defer { session.invalidateAndCancel() }
        await model.connect(key: "test-key")
        await model.refresh(includeHistory: true)
        XCTAssertEqual(server.historyRequests, 1)
        XCTAssertEqual(server.statusRequests, 1)
        XCTAssertEqual(server.projectRequests, 1)

        await model.refresh(includeHistory: true, force: true)
        XCTAssertEqual(server.historyRequests, 2)
        XCTAssertEqual(server.statusRequests, 2)
        XCTAssertEqual(server.projectRequests, 2)
    }

    @MainActor
    func testProjectSelectionClearsWhenWorkspaceChanges() async {
        let server = StubServer(multipleWorkspaces: true)
        let (model, session) = makeModel(server)
        defer { session.invalidateAndCancel() }
        await model.connect(key: "test-key")
        await model.selectWorkspace("ws")
        XCTAssertEqual(model.projects.map(\.id), ["ws-project"])
        model.selectedProjectID = "ws-project"

        await model.selectWorkspace("other")

        XCTAssertEqual(model.selectedProjectID, "")
        XCTAssertEqual(model.projects.map(\.id), ["other-project"])
        await model.selectWorkspace("ws")
    }

    @MainActor
    func testFailedProjectsCanRetryWithoutBreakingHistoryOrStatus() async {
        let server = StubServer(projectFailures: 1)
        let (model, session) = makeModel(server)
        defer { session.invalidateAndCancel() }
        await model.connect(key: "test-key")
        XCTAssertTrue(model.statusKnown)
        XCTAssertEqual(model.recent.count, 4)
        XCTAssertNotNil(model.projectError)
        XCTAssertNil(model.error)

        await model.refresh(includeHistory: true)

        XCTAssertEqual(model.projects.map(\.id), ["ws-project"])
        XCTAssertNil(model.projectError)
        XCTAssertEqual(server.statusRequests, 1)
        XCTAssertEqual(server.historyRequests, 1)
        XCTAssertEqual(server.projectRequests, 2)
    }

    @MainActor
    func testRecentEntriesReserveVisibleSpaceWhileIdleAndRunning() async {
        _ = NSApplication.shared
        for running in [false, true] {
            let emptyServer = StubServer(running: running, historyCount: 0)
            let (emptyModel, emptySession) = makeModel(emptyServer)
            await emptyModel.connect(key: "test-key")
            let emptyHeight = NSHostingView(rootView: PopoverView(model: emptyModel)).fittingSize.height
            emptySession.invalidateAndCancel()

            let populatedServer = StubServer(running: running)
            let (model, session) = makeModel(populatedServer)
            await model.connect(key: "test-key")
            XCTAssertEqual(model.recent.count, 4)
            XCTAssertEqual(model.running != nil, running)
            let height = NSHostingView(rootView: PopoverView(model: model)).fittingSize.height
            XCTAssertGreaterThan(height - emptyHeight, 150, "Recent entries need visible space, including while tracking")
            session.invalidateAndCancel()
        }
    }

    @MainActor
    private func makeModel(_ server: StubServer) -> (TrackerModel, URLSession) {
        StubProtocol.server = server
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: configuration)
        let model = TrackerModel(makeClient: { ClockifyClient(apiKey: $0, session: session) }, saveAPIKey: { _ in })
        return (model, session)
    }
}

private final class StubServer {
    let running: Bool
    let historyCount: Int
    private let lock = NSLock()
    private var failures: Int
    private var projectFailures: Int
    private let multipleWorkspaces: Bool
    private(set) var historyRequests = 0
    private(set) var statusRequests = 0
    private(set) var projectRequests = 0

    init(historyFailures: Int = 0, running: Bool = false, historyCount: Int = 4,
         projectFailures: Int = 0, multipleWorkspaces: Bool = false) {
        failures = historyFailures
        self.running = running
        self.historyCount = historyCount
        self.projectFailures = projectFailures
        self.multipleWorkspaces = multipleWorkspaces
    }

    func respond(to request: URLRequest) -> (Int, String) {
        lock.lock()
        defer { lock.unlock() }
        switch request.url!.lastPathComponent {
        case "user": return (200, #"{"id":"me","activeWorkspace":"ws"}"#)
        case "workspaces":
            return (200, multipleWorkspaces
                    ? #"[{"id":"ws","name":"Test workspace"},{"id":"other","name":"Other workspace"}]"#
                    : #"[{"id":"ws","name":"Test workspace"}]"#)
        case "projects":
            projectRequests += 1
            if projectFailures > 0 { projectFailures -= 1; return (500, "{}") }
            let workspace = request.url!.deletingLastPathComponent().lastPathComponent
            return (200, "[{\"id\":\"\(workspace)-project\",\"name\":\"Website\",\"billable\":true}]")
        default:
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if query.contains(URLQueryItem(name: "in-progress", value: "true")) {
                statusRequests += 1
                return (200, running ? "[\(entry(99, running: true))]" : "[]")
            }
            historyRequests += 1
            if failures > 0 { failures -= 1; return (500, "{}") }
            return (200, "[" + (0..<historyCount).map { entry($0) }.joined(separator: ",") + "]")
        }
    }

    private func entry(_ id: Int, running: Bool = false) -> String {
        let end = running ? "null" : "\"2026-09-25T14:00:00Z\""
        return """
        {"id":"\(id)","description":"Activity \(id)","timeInterval":{"start":"2026-09-25T12:00:00Z","end":\(end)}}
        """
    }
}

private final class StubProtocol: URLProtocol {
    static var server: StubServer!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.server.respond(to: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
