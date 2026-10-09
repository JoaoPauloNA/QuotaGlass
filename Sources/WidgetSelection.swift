import Foundation

enum WidgetSelection {
    static let maximumAccounts = 3

    static func normalized(_ slots: [String]) -> [String] {
        var seen = Set<String>()
        let unique = slots.prefix(maximumAccounts).map { id in
            id.isEmpty || !seen.insert(id).inserted ? "" : id
        }
        return unique + Array(repeating: "", count: maximumAccounts - unique.count)
    }

    static func initialAccounts(from accounts: [AccountPresentation]) -> [String] {
        let visible = accounts.filter { !$0.hidden && $0.status != "disabled" }
        let pro = visible.first { $0.provider.id == "codex" && $0.plan.lowercased() == "pro" }
        let lite = visible.first { $0.provider.id == "codex" && $0.plan.lowercased() == "prolite" }
        let claude = visible.first { $0.provider.id == "claude" }
        var chosen = [pro, lite, claude].compactMap { $0?.id }
        for account in visible where chosen.count < maximumAccounts && !chosen.contains(account.id) {
            chosen.append(account.id)
        }
        return normalized(chosen)
    }

    static func selected(_ slots: [String], from accounts: [AccountPresentation]) -> [AccountPresentation] {
        normalized(slots).compactMap { id in accounts.first { $0.id == id && !$0.hidden && $0.status != "disabled" } }
    }
}
