import Foundation

public struct ClockifyUser: Decodable {
    public let id: String
    public let activeWorkspace: String?
}

public struct Workspace: Decodable, Identifiable {
    public let id: String
    public let name: String
}

public struct Project: Decodable, Identifiable {
    public let id: String
    public let name: String
    public let billable: Bool?
}

public struct TimeEntry: Decodable, Identifiable {
    public struct Interval: Decodable {
        public let start: Date
        public let end: Date?
    }
    public let id: String
    public let description: String?
    public let projectId: String?
    public let taskId: String?
    public let tagIds: [String]?
    public let billable: Bool?
    public let type: String?
    public let timeInterval: Interval

    public var title: String {
        let text = (description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Untitled entry" : text
    }
    public var isRunning: Bool { timeInterval.end == nil }

    public static func recent(_ entries: [TimeEntry], limit: Int = 10) -> [TimeEntry] {
        var seen = Set<EntryIdentity>()
        return Array(entries.filter { !$0.isRunning }.sorted {
            $0.timeInterval.start > $1.timeInterval.start
        }.filter { seen.insert(EntryIdentity($0)).inserted }.prefix(limit))
    }

    private struct EntryIdentity: Hashable {
        let description: String
        let project: String?
        let task: String?
        let tags: [String]
        let billable: Bool
        let type: String
        init(_ entry: TimeEntry) {
            description = entry.description ?? ""
            project = entry.projectId
            task = entry.taskId
            tags = (entry.tagIds ?? []).sorted()
            billable = entry.billable ?? false
            type = entry.type ?? "REGULAR"
        }
    }
}

public struct StartEntry: Encodable {
    public let description: String
    public let start: String
    public let projectId: String?
    public let taskId: String?
    public let tagIds: [String]?
    public let billable: Bool?
    public let type: String

    public init(description: String, copying entry: TimeEntry? = nil, project: Project? = nil, now: Date = Date()) {
        self.description = description
        start = ISO8601DateFormatter().string(from: now)
        projectId = entry != nil ? entry?.projectId : project?.id
        taskId = entry?.taskId
        tagIds = entry?.tagIds
        billable = entry != nil ? entry?.billable : project?.billable
        type = entry?.type ?? "REGULAR"
    }
}

public enum ClockifyCoding {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Clockify date")
        }
        return decoder
    }
}
