import Foundation

struct WidgetQuota: Codable, Identifiable {
    let id: String
    let label: String
    let remaining: Double?
    let reset: Date?
}

struct WidgetAccount: Codable, Identifiable {
    let id: String
    let providerID: String
    let label: String
    let plan: String
    let status: String
    let windows: [WidgetQuota]
    let availableResets: Int?

    init(_ account: AccountPresentation) {
        id = account.id; providerID = account.provider.id; label = account.label
        plan = account.plan; status = account.status
        availableResets = account.availableResets
        windows = account.status == "ready" ? account.windows.map {
            WidgetQuota(id: $0.id, label: $0.label, remaining: $0.remaining, reset: $0.reset)
        } : []
    }

    var title: String {
        switch providerID {
        case "codex": return "Codex " + (plan.lowercased() == "prolite" ? "Pro Lite" : plan.capitalized)
        case "claude": return "Claude"
        case "gemini": return "Google"
        default: return providerID.capitalized
        }
    }
}

struct WidgetSnapshot: Codable {
    let version: Int
    let generatedAt: Date
    let updatedAt: Date?
    let state: String
    let accounts: [WidgetAccount]
    var resetIndicatorStyle: ResetIndicatorStyle? = nil

    static func make(accounts: [AccountPresentation], slots: [String], state: String, updatedAt: Date?, now: Date = Date(), resetIndicatorStyle: ResetIndicatorStyle? = nil) -> Self {
        Self(version: 1, generatedAt: now, updatedAt: updatedAt, state: state,
             accounts: state == "ready" ? WidgetSelection.selected(slots, from: accounts).map(WidgetAccount.init) : [],
             resetIndicatorStyle: resetIndicatorStyle)
    }

    static let empty = WidgetSnapshot(version: 1, generatedAt: .distantPast, updatedAt: nil, state: "open", accounts: [])
    func isStale(at now: Date = Date()) -> Bool { now.timeIntervalSince(generatedAt) > 15 * 60 }
}

enum WidgetSnapshotStorage {
    static var url: URL? {
        guard let resource = Bundle.main.url(forResource: "widget-data-path", withExtension: "txt"),
              let path = try? String(contentsOf: resource, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              path.hasPrefix("/"), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func write(_ snapshot: WidgetSnapshot, to destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: destination, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    static func read(from source: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: source), data.count <= 128_000,
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.version == 1, snapshot.accounts.count <= WidgetSelection.maximumAccounts else { return nil }
        return snapshot
    }
}
