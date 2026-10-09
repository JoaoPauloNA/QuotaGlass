import Foundation

struct ProviderDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let endpoint: String
    let symbol: String
    var windowLabels: [String: [String: String]]? = nil
}

struct QuotaWindow: Decodable {
    let label: String?
    let usedPercent: Double?
    let resetAt: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        label = try? c.decode(String.self, forKey: .label)
        usedPercent = try? c.decode(Double.self, forKey: .usedPercent)
        resetAt = try? c.decode(String.self, forKey: .resetAt)
    }
    private enum Keys: String, CodingKey { case label, usedPercent, resetAt }
    var remaining: Double? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return max(0, min(100, 100 - usedPercent))
    }
}

struct QuotaGroup: Decodable {
    let label: String?
    let windows: [QuotaWindow]?
}

struct QuotaAccount: Decodable {
    let connectionId: String?
    let label: String?
    let plan: String?
    let status: String?
    let hidden: Bool?
    let windows: [QuotaWindow]?
    let groups: [QuotaGroup]?
    let availableResets: Int?
}

struct QuotaPayload: Decodable {
    let updatedAt: String?
    let accounts: [QuotaAccount]
}

struct WindowPresentation: Identifiable {
    let id: String
    let group: String?
    let label: String
    let remaining: Double?
    let reset: Date?
}

struct AccountPresentation: Identifiable {
    let id: String
    let provider: ProviderDefinition
    let label: String
    let plan: String
    let status: String
    let hidden: Bool
    let windows: [WindowPresentation]
    var availableResets: Int? = nil
}

struct ProviderResult: Identifiable {
    var id: String { provider.id }
    let provider: ProviderDefinition
    let accounts: [AccountPresentation]
    let updatedAt: Date?
    let error: String?
}

enum QuotaAdapter {
    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func localized(_ label: String?, fallback: String) -> String {
        guard let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fallback }
        let names = ["gemini models": "Modelos Gemini", "claude and gpt models": "Modelos Claude e GPT",
                "weekly limit remaining": "Cota semanal", "five hour limit remaining": "Cota de 5 horas"]
        return names[label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] ?? label
    }

    static func parse(_ data: Data, provider: ProviderDefinition) throws -> ProviderResult {
        let payload = try JSONDecoder().decode(QuotaPayload.self, from: data)
        let accounts = payload.accounts.enumerated().map { index, account in
            let identity = provider.id + ":" + (account.connectionId ?? "account-\(index)")
            var windows: [WindowPresentation] = []
            let flat = account.windows ?? []
            for (windowIndex, window) in flat.enumerated() {
                let accountKey = (account.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let displayLabel = window.label.flatMap { provider.windowLabels?[accountKey]?[$0] } ?? window.label
                windows.append(WindowPresentation(id: identity + ":\(windowIndex)", group: nil,
                    label: localized(displayLabel, fallback: "Janela de uso"), remaining: window.remaining,
                    reset: date(window.resetAt)))
            }
            for (groupIndex, group) in (account.groups ?? []).enumerated() {
                for (windowIndex, window) in (group.windows ?? []).enumerated() {
                    windows.append(WindowPresentation(id: identity + ":g\(groupIndex):\(windowIndex)",
                        group: localized(group.label, fallback: "Grupo de modelos"),
                        label: localized(window.label, fallback: "Janela de uso"), remaining: window.remaining,
                        reset: date(window.resetAt)))
                }
            }
            return AccountPresentation(id: identity, provider: provider,
                label: account.label?.isEmpty == false ? account.label! : "Conta \(provider.name)",
                plan: account.plan ?? "", status: account.status ?? "unavailable",
                hidden: account.hidden == true || account.status == "hidden", windows: windows,
                availableResets: account.availableResets.flatMap { (0...10000).contains($0) ? $0 : nil })
        }
        return ProviderResult(provider: provider, accounts: accounts, updatedAt: date(payload.updatedAt), error: nil)
    }

}
