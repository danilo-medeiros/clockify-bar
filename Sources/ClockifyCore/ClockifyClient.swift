import Foundation

public struct ClockifyAPIError: LocalizedError {
    public let status: Int
    public var errorDescription: String? {
        switch status {
        case 401: return "Clockify rejected the API key. Update it in Settings."
        case 403: return "You don’t have permission for this action in this workspace."
        case 400: return "Clockify couldn’t save this entry. Your workspace may require a project, task, tags, or custom fields. Try a recent entry or open Clockify."
        case 404: return "This workspace or entry is no longer available. Check Settings or open Clockify."
        case 429: return "Clockify’s API limit was reached. Please wait before trying again (Free plan: 30 requests/hour/workspace)."
        default: return "Clockify returned an error (HTTP \(status)). Please try again later."
        }
    }
}

public final class ClockifyClient {
    private let apiKey: String
    private let session: URLSession
    private let baseURL = URL(string: "https://api.clockify.me/api/v1/")!

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func user() async throws -> ClockifyUser { try await request("user") }
    public func workspaces() async throws -> [Workspace] { try await request("workspaces") }

    public func projects(workspace: String) async throws -> [Project] {
        var projects: [Project] = []
        var page = 1
        let pageSize = 200
        while true {
            let batch: [Project] = try await request("workspaces/\(workspace)/projects", query: [
                URLQueryItem(name: "archived", value: "false"),
                URLQueryItem(name: "sort-column", value: "NAME"),
                URLQueryItem(name: "sort-order", value: "ASCENDING"),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page-size", value: String(pageSize))
            ])
            projects.append(contentsOf: batch)
            if batch.count < pageSize { return projects }
            page += 1
        }
    }

    public func entries(workspace: String, user: String, runningOnly: Bool = false) async throws -> [TimeEntry] {
        var query = [URLQueryItem(name: "page-size", value: runningOnly ? "1" : "50")]
        if runningOnly { query.append(URLQueryItem(name: "in-progress", value: "true")) }
        return try await request("workspaces/\(workspace)/user/\(user)/time-entries", query: query)
    }

    public func start(workspace: String, entry: StartEntry) async throws -> TimeEntry {
        try await request("workspaces/\(workspace)/time-entries", method: "POST", body: JSONEncoder().encode(entry))
    }

    public func stop(workspace: String, user: String, now: Date = Date()) async throws -> TimeEntry {
        let body = try JSONEncoder().encode(["end": ISO8601DateFormatter().string(from: now)])
        return try await request("workspaces/\(workspace)/user/\(user)/time-entries", method: "PATCH", body: body)
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else { throw ClockifyAPIError(status: response.statusCode) }
        return try ClockifyCoding.decoder().decode(T.self, from: data)
    }
}
