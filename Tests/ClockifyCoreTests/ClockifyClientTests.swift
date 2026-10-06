import XCTest
@testable import ClockifyCore

final class ClockifyClientTests: XCTestCase {
    private var session: URLSession!
    private var client: ClockifyClient!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        session = URLSession(configuration: config)
        client = ClockifyClient(apiKey: "test-only-key", session: session)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        MockProtocol.handler = nil
    }

    func testStartCopiesMetadataWithoutOldIDOrEndTime() async throws {
        let previous = try decode(entryJSON(id: "old", end: "2026-09-25T14:00:00Z"))
        MockProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/workspaces/ws/time-entries")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Key"), "test-only-key")
            let body = try Self.body(request)
            XCTAssertEqual(body["description"] as? String, "Build the app")
            XCTAssertEqual(body["projectId"] as? String, "project")
            XCTAssertEqual(body["taskId"] as? String, "task")
            XCTAssertEqual(body["tagIds"] as? [String], ["tag"])
            XCTAssertEqual(body["billable"] as? Bool, true)
            XCTAssertEqual(body["start"] as? String, "1970-01-01T00:00:00Z")
            XCTAssertNil(body["id"])
            XCTAssertNil(body["end"])
            return (201, self.entryJSON(id: "new", end: nil))
        }
        let created = try await client.start(workspace: "ws", entry: StartEntry(description: "Build the app", copying: previous, now: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(created.id, "new")
        XCTAssertTrue(created.isRunning)
    }

    func testStopUsesPatchAndUTCDate() async throws {
        MockProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/workspaces/ws/user/me/time-entries")
            XCTAssertEqual(try Self.body(request)["end"] as? String, "1970-01-01T00:00:00Z")
            return (200, self.entryJSON(id: "stopped", end: "2026-09-25T14:00:00Z"))
        }
        let stopped = try await client.stop(workspace: "ws", user: "me", now: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(stopped.isRunning)
    }

    func testRunningQueryAndEmptyResponse() async throws {
        MockProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertTrue(query.contains(URLQueryItem(name: "in-progress", value: "true")))
            XCTAssertTrue(query.contains(URLQueryItem(name: "page-size", value: "1")))
            return (200, "[]")
        }
        let entries = try await client.entries(workspace: "ws", user: "me", runningOnly: true)
        XCTAssertTrue(entries.isEmpty)
    }

    func testAuthenticationAndRateLimitErrorsDoNotExposeResponseOrKey() async throws {
        for status in [401, 429, 503] {
            MockProtocol.handler = { _ in (status, "private upstream response test-only-key") }
            do {
                _ = try await client.user()
                XCTFail("Expected HTTP failure")
            } catch let error as ClockifyAPIError {
                XCTAssertEqual(error.status, status)
                XCTAssertFalse(error.localizedDescription.contains("test-only-key"))
                XCTAssertFalse(error.localizedDescription.contains("private upstream"))
            }
        }
    }

    func testMutationTimeoutIsNotRetried() async throws {
        var calls = 0
        MockProtocol.handler = { _ in
            calls += 1
            throw URLError(.timedOut)
        }
        do {
            _ = try await client.start(workspace: "ws", entry: StartEntry(description: "Test"))
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        XCTAssertEqual(calls, 1)
    }

    func testDatesWithAndWithoutFractionalSecondsAndRecentDeduplication() throws {
        let older = try decode(entryJSON(id: "old", start: "2026-09-24T12:00:00Z", end: "2026-09-24T14:00:00Z"))
        let newer = try decode(entryJSON(id: "new", start: "2026-09-25T12:00:00.123Z", end: "2026-09-25T14:00:00.456Z"))
        let running = try decode(entryJSON(id: "running", end: nil))
        let differentProject = try decode(entryJSON(id: "different", end: "2026-09-25T14:00:00Z").replacingOccurrences(of: "\"project\"", with: "\"other\""))
        XCTAssertEqual(TimeEntry.recent([older, running, differentProject, newer]).map(\.id), ["new", "different"])
        XCTAssertEqual(TimeEntry.recent([older, newer], limit: 1).map(\.id), ["new"])
        XCTAssertEqual(newer.timeInterval.start.timeIntervalSince(older.timeInterval.start), 86400.123, accuracy: 0.001)
    }

    func testNewEntryOmitsProjectAndOtherUnspecifiedMetadata() throws {
        let data = try JSONEncoder().encode(StartEntry(description: "New work"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(body["projectId"])
        XCTAssertNil(body["taskId"])
        XCTAssertNil(body["end"])
        XCTAssertEqual(body["type"] as? String, "REGULAR")
    }

    func testSelectedProjectIsSentWhenStartingNewEntry() async throws {
        let project = try JSONDecoder().decode(Project.self, from: Data(#"{"id":"chosen","name":"Website","billable":true}"#.utf8))
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(body["projectId"] as? String, "chosen")
            XCTAssertEqual(body["billable"] as? Bool, true)
            XCTAssertNil(body["taskId"])
            return (201, self.entryJSON(id: "new", end: nil))
        }
        _ = try await client.start(workspace: "ws", entry: StartEntry(description: "Design", project: project))

        let previous = try decode(entryJSON(id: "old", end: "2026-09-25T14:00:00Z"))
        let copy = StartEntry(description: previous.title, copying: previous, project: project)
        XCTAssertEqual(copy.projectId, "project", "Resuming an entry must preserve its original project")
    }

    func testProjectListRequestsActiveProjectsAcrossPages() async throws {
        var requestedPages: [String] = []
        MockProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/workspaces/ws/projects")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertTrue(query.contains(URLQueryItem(name: "archived", value: "false")))
            XCTAssertTrue(query.contains(URLQueryItem(name: "sort-column", value: "NAME")))
            let page = query.first { $0.name == "page" }!.value!
            requestedPages.append(page)
            if page == "1" {
                let rows = (0..<200).map { "{\"id\":\"\($0)\",\"name\":\"Project \($0)\"}" }
                return (200, "[" + rows.joined(separator: ",") + "]")
            }
            return (200, #"[{"id":"last","name":"Zebra","billable":false}]"#)
        }
        let projects = try await client.projects(workspace: "ws")
        XCTAssertEqual(projects.count, 201)
        XCTAssertEqual(projects.last?.id, "last")
        XCTAssertEqual(requestedPages, ["1", "2"])
    }

    private func decode(_ json: String) throws -> TimeEntry {
        try ClockifyCoding.decoder().decode(TimeEntry.self, from: Data(json.utf8))
    }

    private func entryJSON(id: String, start: String = "2026-09-25T12:00:00Z", end: String?) -> String {
        let endJSON = end.map { "\"\($0)\"" } ?? "null"
        return """
        {"id":"\(id)","description":"Build the app","projectId":"project","taskId":"task","tagIds":["tag"],"billable":true,"type":"REGULAR","timeInterval":{"start":"\(start)","end":\(endJSON)}}
        """
    }

    private static func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class MockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, json) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
