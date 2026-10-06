import ClockifyCore
import Combine
import Foundation

@MainActor
final class TrackerModel: ObservableObject {
    @Published var workspaces: [Workspace] = []
    @Published private(set) var workspaceID = ""
    @Published private(set) var running: TimeEntry?
    @Published private(set) var recent: [TimeEntry] = []
    @Published private(set) var projects: [Project] = []
    @Published var selectedProjectID = ""
    @Published private(set) var projectError: String?
    @Published private(set) var busy = false
    @Published private(set) var connected = false
    @Published private(set) var statusKnown = false
    @Published var error: String?
    @Published var showSettings = false
    @Published private(set) var lastSync: Date?
    var onStarted: (() -> Void)?
    private var client: ClockifyClient?
    private var userID = ""
    private var lastHistorySync: Date?
    private var lastProjectSync: Date?
    private var retryAfter = Date.distantPast
    private let makeClient: (String) -> ClockifyClient
    private let saveAPIKey: (String) throws -> Void

    init(makeClient: @escaping (String) -> ClockifyClient = { ClockifyClient(apiKey: $0) },
         saveAPIKey: @escaping (String) throws -> Void = Keychain.save) {
        self.makeClient = makeClient
        self.saveAPIKey = saveAPIKey
    }

    var workspaceName: String { workspaces.first { $0.id == workspaceID }?.name ?? "Clockify" }

    func restore() async {
        do {
            if let key = try Keychain.read() { await connect(key: key) }
            else { showSettings = true }
        } catch { self.error = error.localizedDescription; showSettings = true }
    }

    func connect(key: String) async {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !key.isEmpty else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let candidate = makeClient(key)
            async let userRequest = candidate.user()
            async let workspaceRequest = candidate.workspaces()
            let (user, available) = try await (userRequest, workspaceRequest)
            guard !available.isEmpty else { error = "No Clockify workspaces are available for this account."; return }
            try saveAPIKey(key)
            client = candidate
            userID = user.id
            workspaces = available
            let saved = UserDefaults.standard.string(forKey: "workspaceID")
            workspaceID = available.first { $0.id == saved }?.id
                ?? available.first { $0.id == user.activeWorkspace }?.id ?? available[0].id
            UserDefaults.standard.set(workspaceID, forKey: "workspaceID")
            connected = true
            running = nil
            recent = []
            resetProjects()
            statusKnown = false
            lastHistorySync = nil
            retryAfter = .distantPast
            showSettings = false
            try await loadStatus()
            try await loadHistory()
            await loadProjects()
        } catch { handle(error) }
    }

    func selectWorkspace(_ id: String) async {
        guard !busy, id != workspaceID, workspaces.contains(where: { $0.id == id }) else { return }
        workspaceID = id
        UserDefaults.standard.set(id, forKey: "workspaceID")
        running = nil
        recent = []
        resetProjects()
        statusKnown = false
        lastHistorySync = nil
        lastSync = nil
        retryAfter = .distantPast
        await refresh(includeHistory: true, force: true)
    }

    func refresh(includeHistory: Bool = false, force: Bool = false) async {
        guard connected, !busy, Date() >= retryAfter else { return }
        // History and timer status have independent caches: a fresh timer status
        // must not prevent missing, failed, or stale history from being loaded.
        let needsStatus = force || !statusKnown || lastSync == nil
            || Date().timeIntervalSince(lastSync!) >= (includeHistory ? 60 : 300)
        let needsHistory = includeHistory && (force || lastHistorySync == nil
            || Date().timeIntervalSince(lastHistorySync!) >= 60)
        let needsProjects = includeHistory && (force || lastProjectSync == nil
            || Date().timeIntervalSince(lastProjectSync!) >= 900)
        guard needsStatus || needsHistory || needsProjects else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            if needsStatus { try await loadStatus() }
            if needsHistory { try await loadHistory() }
            if needsProjects { await loadProjects() }
        } catch { handle(error) }
    }

    func start(description: String, copying entry: TimeEntry? = nil) async {
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, let client, connected, Date() >= retryAfter else { return }
        guard !description.isEmpty || entry != nil else { return }
        guard description.count <= 3000 else { error = "Descriptions can contain up to 3,000 characters."; return }
        let project = projects.first { $0.id == selectedProjectID }
        guard entry != nil || selectedProjectID.isEmpty || project != nil else {
            error = "The selected project is no longer available. Choose another project."
            return
        }
        busy = true
        error = nil
        defer { busy = false }
        do {
            // Check the server before creating a timer, including after an ambiguous timeout.
            try await loadStatus()
            guard running == nil else { error = "A timer is already running in Clockify. Stop it before starting another."; return }
            running = try await client.start(workspace: workspaceID, entry: StartEntry(description: description, copying: entry, project: project))
            statusKnown = true
            lastSync = Date()
            onStarted?()
        } catch { statusKnown = false; handle(error) }
    }

    func stop() async {
        guard !busy, let client, connected, running != nil, Date() >= retryAfter else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let stopped = try await client.stop(workspace: workspaceID, user: userID)
            running = nil
            recent = TimeEntry.recent([stopped] + recent)
            statusKnown = true
            lastSync = Date()
        } catch {
            // A timeout may mean the server accepted the stop. Do not display an idle state until verified.
            statusKnown = false
            handle(error)
        }
    }

    private func loadStatus() async throws {
        guard let client else { return }
        do {
            running = try await client.entries(workspace: workspaceID, user: userID, runningOnly: true).first
            statusKnown = true
            lastSync = Date()
        } catch { statusKnown = false; throw error }
    }

    private func loadHistory() async throws {
        guard let client else { return }
        recent = TimeEntry.recent(try await client.entries(workspace: workspaceID, user: userID))
        lastHistorySync = Date()
    }

    private func resetProjects() {
        projects = []
        selectedProjectID = ""
        projectError = nil
        lastProjectSync = nil
    }

    private func loadProjects() async {
        guard let client else { return }
        do {
            projects = try await client.projects(workspace: workspaceID)
            if !projects.contains(where: { $0.id == selectedProjectID }) { selectedProjectID = "" }
            lastProjectSync = Date()
            projectError = nil
        } catch {
            projectError = "Couldn’t load projects. \(error.localizedDescription)"
            if let apiError = error as? ClockifyAPIError, apiError.status == 429 { handle(error) }
        }
    }

    private func handle(_ failure: Error) {
        error = failure.localizedDescription
        if let apiError = failure as? ClockifyAPIError, apiError.status == 429 {
            retryAfter = Date().addingTimeInterval(300)
        }
    }
}
