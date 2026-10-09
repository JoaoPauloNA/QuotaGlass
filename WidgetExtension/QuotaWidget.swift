import AppKit
import SwiftUI
import WidgetKit

struct QuotaWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct QuotaWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaWidgetEntry {
        QuotaWidgetEntry(date: Date(), snapshot: .empty)
    }
    func getSnapshot(in context: Context, completion: @escaping (QuotaWidgetEntry) -> Void) {
        completion(entry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaWidgetEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(900))))
    }
    private func entry() -> QuotaWidgetEntry {
        let snapshot = WidgetSnapshotStorage.url.flatMap { WidgetSnapshotStorage.read(from: $0) } ?? .empty
        return QuotaWidgetEntry(date: Date(), snapshot: snapshot)
    }
}

struct QuotaWidgetView: View {
    let entry: QuotaWidgetEntry
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var fullColor: Bool { renderingMode == .fullColor }
    private var stale: Bool { entry.snapshot.isStale(at: entry.date) }
    // The host uses the same blurred background style as the Batteries widget.
    private var ink: Color { .white.opacity(fullColor ? 0.95 : 0.72) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<WidgetSelection.maximumAccounts, id: \.self) { index in
                if index < entry.snapshot.accounts.count { column(entry.snapshot.accounts[index]) }
                else { emptyColumn }
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(ink)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "quotaglass://panel"))
        .privacySensitive()
    }

    private func column(_ account: WidgetAccount) -> some View {
        let primary = account.windows.first
        return VStack(spacing: 14) {
            ZStack {
                ring(primary?.remaining)
                logo(account.providerID).frame(width: 27, height: 27)
            }
            VStack(spacing: 6) {
                Text(percentage(primary?.remaining))
                    .font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.75)
                ResetIndicators(count: account.availableResets, style: entry.snapshot.resetIndicatorStyle ?? ResetIndicatorStyle(), showsOutline: fullColor)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(([account.label, account.title] + (account.windows.isEmpty ? ["Sem dados"] :
            account.windows.map { "\($0.label), \(percentage($0.remaining)) livre" }) + (account.availableResets.map { ["\($0) resets disponíveis"] } ?? [])).joined(separator: ". "))
    }

    private var emptyColumn: some View {
        VStack(spacing: 14) {
            ring(nil)
            Text(" ").font(.system(size: 18, weight: .semibold, design: .rounded))
        }.frame(maxWidth: .infinity).accessibilityHidden(true)
    }

    private func ring(_ remaining: Double?) -> some View {
        ZStack {
            Circle().strokeBorder(ink.opacity(0.14), lineWidth: 6)
            if let remaining {
                Circle().inset(by: 3).trim(from: 0, to: max(0, min(100, remaining)) / 100)
                    .stroke(ringColor(remaining), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }.frame(width: 64, height: 64)
    }

    private func ringColor(_ remaining: Double) -> Color {
        guard fullColor, !stale else { return ink }
        return remaining <= 10 ? .red : remaining <= 25 ? .orange : .green
    }

    @ViewBuilder private func logo(_ provider: String) -> some View {
        let name = provider == "codex" ? "openai-black"
            : provider == "claude" ? "claude" : "gemini-vector"
        if let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "brands"),
           let artwork = NSImage(contentsOf: url) {
            Image(nsImage: artwork).resizable()
                .renderingMode(.template).scaledToFit()
        } else { Image(systemName: "circle.grid.2x2") }
    }

    private func percentage(_ value: Double?) -> String {
        value.map { $0.formatted(.number.locale(Locale(identifier: "pt_BR")).precision(.fractionLength(0...1))) + "%" } ?? "—"
    }

}

@main struct QuotaGlassWidget: Widget {
    let kind = "QuotaGlassWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaWidgetProvider()) { entry in
            QuotaWidgetView(entry: entry)
        }
        .configurationDisplayName("Cotas")
        .description("Acompanhe até três contas conectadas diretamente no aplicativo.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(true)
        .preferredBackgroundStyle(.blur)
    }
}
