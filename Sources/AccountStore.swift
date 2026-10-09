import AppKit
import SwiftUI
import WidgetKit

struct LocalProfile: Codable, Identifiable {
    let id: UUID
    let provider: String
    var label: String
}
enum ConnectionState: Equatable { case checking, login, ready, failed(String) }

@MainActor final class AccountStore: ObservableObject {
    @Published var state: ConnectionState = .checking
    @Published var results: [ProviderResult] = []
    @Published var loading = false
    @Published var updatedAt: Date?
    @Published var showingSettings = false
    @Published var maximumPanelHeight: CGFloat = 420
    @Published var profiles: [LocalProfile] = []
    @Published var providerFilter = "all"
    @Published var showHidden = false
    @Published var widgetInUse = false
    @Published var widgetError: String?
    @Published var configurationError: String?
    @Published var codexExecutable = UserDefaults.standard.string(forKey: "codexExecutable") ?? "/opt/homebrew/bin/codex" {
        didSet { UserDefaults.standard.set(codexExecutable, forKey: "codexExecutable") }
    }
    @Published var widgetAccountIDs = WidgetSelection.normalized(UserDefaults.standard.stringArray(forKey: "widgetAccountIDs") ?? []) {
        didSet { UserDefaults.standard.set(widgetAccountIDs, forKey: "widgetAccountIDs"); publishWidget() }
    }
    @Published var desktopPanelVisible = UserDefaults.standard.bool(forKey: "desktopPanelVisible") {
        didSet { UserDefaults.standard.set(desktopPanelVisible, forKey: "desktopPanelVisible") }
    }
    @Published var backgroundOpacity = max(0.1, min(1, UserDefaults.standard.object(forKey: "backgroundOpacity") as? Double ?? 0.45)) {
        didSet { UserDefaults.standard.set(backgroundOpacity, forKey: "backgroundOpacity") }
    }
    @Published var resetEmoji = UserDefaults.standard.string(forKey: "resetEmoji") ?? "" {
        didSet { UserDefaults.standard.set(resetEmoji, forKey: "resetEmoji"); publishWidget() }
    }
    @Published var resetColorHex = UserDefaults.standard.string(forKey: "resetColorHex") ?? "FF6685" {
        didSet { UserDefaults.standard.set(resetColorHex, forKey: "resetColorHex"); publishWidget() }
    }
    @Published var resetCustomColor = UserDefaults.standard.bool(forKey: "resetCustomColor") {
        didSet { UserDefaults.standard.set(resetCustomColor, forKey: "resetCustomColor"); publishWidget() }
    }
    var resetIndicatorStyle: ResetIndicatorStyle { .init(emoji: resetEmoji, colorHex: resetCustomColor ? resetColorHex : nil) }
    var repositionDesktopPanel: (() -> Void)?
    var onChange: (() -> Void)?
    var wantsPanelAfterLogin = false
    var lastAttempt: Date?
    let providers = [
        ProviderDefinition(id: "codex", name: "Codex / GPT", endpoint: "", symbol: "command"),
        ProviderDefinition(id: "claude", name: "Claude", endpoint: "", symbol: "asterisk")
    ]
    private var codex: [UUID: CodexConnection] = [:]
    private var claude: [UUID: ClaudeConnection] = [:]
    private var claudeMessages: [UUID: String] = [:]
    private var claudeReadings: [UUID: (Date, AccountPresentation)] = [:]
    private var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QuotaGlass/accounts", isDirectory: true)
    }
    init() {
        if let data = UserDefaults.standard.data(forKey: "profiles"), let saved = try? JSONDecoder().decode([LocalProfile].self, from: data) {
            profiles = Array(saved.prefix(20))
        }
    }
    func start() { refresh() }
    func refreshIfNeeded() { if Date().timeIntervalSince(lastAttempt ?? .distantPast) >= 60 { refresh() } }
    private func connection(_ profile: LocalProfile) async throws -> CodexConnection {
        if let active = codex[profile.id] { return active }
        let path = [codexExecutable, "/opt/homebrew/bin/codex", "/usr/local/bin/codex"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let path else { throw CodexConnection.ConnectionError.unavailable }
        let next = try CodexConnection(profile: profile.id, root: root, executable: URL(fileURLWithPath: path))
        do { try await next.initialize() } catch { next.stop(); throw error }
        next.onLogin = { [weak self] in self?.refresh() }
        codex[profile.id] = next
        return next
    }
    private func claudeConnection(_ profile: LocalProfile) -> ClaudeConnection {
        if let active = claude[profile.id] { return active }
        let next = ClaudeConnection(profile: profile.id)
        next.onLoaded = { [weak self] in self?.refresh() }
        claude[profile.id] = next
        return next
    }
    func addAccount(_ provider: String) {
        guard profiles.count < 20, providers.contains(where: { $0.id == provider }) else { return }
        let profile = LocalProfile(id: UUID(), provider: provider, label: provider == "claude" ? "Conta Claude" : "Conta Codex")
        profiles.append(profile); saveProfiles(); login(profile)
    }
    func login(_ profile: LocalProfile) {
        if profile.provider == "claude" { claudeConnection(profile).login(); return }
        Task {
            do {
                let active = try await connection(profile)
                let response = try await active.request("account/login/start", params: ["type": "chatgpt"])
                guard let text = response["authUrl"] as? String, let url = URL(string: text), url.scheme == "https", url.host == "auth.openai.com" else {
                    throw CodexConnection.ConnectionError.requestFailed
                }
                NSWorkspace.shared.open(url)
                configurationError = nil
            } catch { configurationError = error.localizedDescription }
        }
    }
    func removeAccount(_ profile: LocalProfile) {
        guard !loading else { return }
        Task {
            if let active = codex[profile.id] { _ = try? await active.request("account/logout"); active.stop() }
            if let active = claude[profile.id] { await active.logout() }
            codex.removeValue(forKey: profile.id); claude.removeValue(forKey: profile.id); claudeReadings.removeValue(forKey: profile.id)
            profiles.removeAll { $0.id == profile.id }; saveProfiles()
            widgetAccountIDs = widgetAccountIDs.map { $0 == profile.id.uuidString ? "" : $0 }
            refresh()
        }
    }
    func stop() { for active in codex.values { active.stop() } }
    private func saveProfiles() { UserDefaults.standard.set(try? JSONEncoder().encode(profiles), forKey: "profiles") }
    func refresh() {
        guard !loading else { return }
        loading = true; lastAttempt = Date()
        Task {
            var accounts: [AccountPresentation] = []
            var errors: [String: String] = [:]
            for profile in profiles {
                guard let provider = providers.first(where: { $0.id == profile.provider }) else { continue }
                do {
                    if profile.provider == "codex" {
                        let active = try await connection(profile)
                        let identity = try await active.request("account/read", params: ["refreshToken": false])
                        guard let account = identity["account"] as? [String: Any], account["type"] as? String == "chatgpt" else {
                            accounts.append(empty(profile, provider: provider)); continue
                        }
                        let response = try await active.request("account/rateLimits/read")
                        let buckets = response["rateLimitsByLimitId"] as? [String: Any]
                        let quota = buckets?["codex"] as? [String: Any] ?? response["rateLimits"] as? [String: Any] ?? [:]
                        let windows: [WindowPresentation] = ["primary", "secondary"].compactMap { key in
                            guard let w = quota[key] as? [String: Any], let used = w["usedPercent"] as? Double, used.isFinite else { return nil }
                            let minutes = w["windowDurationMins"] as? Int
                            let label = minutes.map { $0 % 1440 == 0 ? "\($0 / 1440) dias" : $0 % 60 == 0 ? "\($0 / 60) horas" : "\($0) minutos" } ?? "Janela de uso"
                            return .init(id: profile.id.uuidString + key, group: nil, label: label, remaining: max(0, min(100, 100 - used)), reset: (w["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) })
                        }
                        let rawCount = (response["rateLimitResetCredits"] as? [String: Any])?["availableCount"] as? Int
                        let count = rawCount.flatMap { (0...10000).contains($0) ? $0 : nil }
                        accounts.append(.init(id: profile.id.uuidString, provider: provider, label: account["email"] as? String ?? profile.label, plan: account["planType"] as? String ?? "", status: windows.isEmpty ? "unavailable" : "ready", hidden: false, windows: windows, availableResets: count))
                    } else {
                        if let cached = claudeReadings[profile.id], Date().timeIntervalSince(cached.0) < 300 { accounts.append(cached.1); errors[provider.id] = claudeMessages[profile.id]; continue }
                        claudeMessages.removeValue(forKey: profile.id)
                        let packet = try await claudeConnection(profile).usage()
                        let rawWindows = packet["windows"] as? [[String: Any]] ?? []
                        let windows: [WindowPresentation] = rawWindows.enumerated().compactMap { i,w in
                            guard let used = w["usedPercent"] as? Double, used.isFinite else { return nil }
                            return .init(id: profile.id.uuidString + String(i), group: nil, label: w["label"] as? String ?? "Janela de uso", remaining: max(0, min(100, 100 - used)), reset: QuotaAdapter.date(w["resetAt"] as? String))
                        }
                        let status = packet["status"] as? String ?? "unavailable"
                        var result = AccountPresentation(id: profile.id.uuidString, provider: provider, label: profile.label, plan: packet["plan"] as? String ?? "", status: windows.isEmpty ? status == "ready" ? "unavailable" : status : "ready", hidden: false, windows: windows)
                        if status == "rate_limited", let cached = claudeReadings[profile.id] {
                            result = cached.1
                            errors[provider.id] = "Claude limitou as consultas. Exibindo a última leitura; nova tentativa em cinco minutos."
                        }
                        claudeMessages[profile.id] = errors[provider.id]
                        claudeReadings[profile.id] = (Date(), result)
                        accounts.append(result)
                    }
                } catch { accounts.append(empty(profile, provider: provider)); errors[provider.id] = error.localizedDescription }
            }
            results = providers.map { provider in .init(provider: provider, accounts: accounts.filter { $0.provider.id == provider.id }, updatedAt: Date(), error: errors[provider.id]) }
            updatedAt = Date(); state = profiles.isEmpty ? .login : .ready; loading = false
            if widgetAccountIDs.allSatisfy(\.isEmpty), !accounts.isEmpty { widgetAccountIDs = WidgetSelection.initialAccounts(from: accounts) }
            publishWidget(); onChange?()
        }
    }
    private func empty(_ profile: LocalProfile, provider: ProviderDefinition) -> AccountPresentation {
        .init(id: profile.id.uuidString, provider: provider, label: profile.label, plan: "", status: "unavailable", hidden: false, windows: [])
    }
    func setWidgetAccount(_ id: String, at slot: Int) {
        guard (0..<3).contains(slot) else { return }
        var next = WidgetSelection.normalized(widgetAccountIDs)
        if !id.isEmpty { for i in next.indices where i != slot && next[i] == id { next[i] = "" } }
        next[slot] = id; widgetAccountIDs = next
    }
    func checkWidgetUsage() {
        WidgetCenter.shared.getCurrentConfigurations { [weak self] value in
            Task { @MainActor in self?.widgetInUse = (try? value.get().contains { $0.kind == "QuotaGlassWidget" }) ?? false }
        }
    }
    private func publishWidget() {
        guard let url = WidgetSnapshotStorage.url else { return }
        do {
            try WidgetSnapshotStorage.write(.make(accounts: results.flatMap(\.accounts), slots: widgetAccountIDs, state: state == .ready ? "ready" : "open", updatedAt: updatedAt, resetIndicatorStyle: resetIndicatorStyle), to: url)
            widgetError = nil; WidgetCenter.shared.reloadTimelines(ofKind: "QuotaGlassWidget")
        } catch { widgetError = "Não foi possível atualizar o widget." }
    }
}
