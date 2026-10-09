import AppKit
import SwiftUI

// Select the property wrapper explicitly; the SDK also exports a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct FixedSectionHeightsKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private extension View {
    func measureFixedSection(_ name: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: FixedSectionHeightsKey.self, value: [name: geometry.size.height])
        })
    }
}

private struct AdaptiveScrollArea<Content: View>: View {
    let maximumHeight: CGFloat
    @ViewBuilder var content: Content
    @ViewState private var contentHeight: CGFloat = 0

    private var measuredContent: some View {
        content.fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: ContentHeightKey.self, value: geometry.size.height)
            })
    }

    var body: some View {
        Group {
            if PanelSizing.needsScrolling(contentHeight: contentHeight, maximumHeight: maximumHeight) {
                ScrollView(.vertical) { measuredContent }
                    .frame(height: PanelSizing.viewportHeight(contentHeight: contentHeight, maximumHeight: maximumHeight))
            } else {
                measuredContent
            }
        }.onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
    }
}

struct QuotaSurface: View {
    let content: QuotaView
    @ObservedObject var store: AccountStore
    var body: some View {
        content.background {
            ZStack {
                if #available(macOS 26.0, *) {
                    Rectangle().fill(.clear).glassEffect(.regular, in: Rectangle())
                        .opacity(0.25 + store.backgroundOpacity * 0.75)
                } else {
                    LegacyGlassBackground().opacity(0.25 + store.backgroundOpacity * 0.75)
                }
                Color(nsColor: .windowBackgroundColor).opacity(pow(store.backgroundOpacity, 3))
            }
        }
    }
}

private struct LegacyGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct ProviderLogo: View {
    let provider: ProviderDefinition
    @Environment(\.colorScheme) private var colorScheme
    private var artwork: NSImage? {
        let name: String
        switch provider.id {
        case "codex": name = colorScheme == .dark ? "openai-white" : "openai-black"
        case "claude": name = "claude"
        case "gemini": name = "gemini-vector"
        default: return nil
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "brands") else { return nil }
        return NSImage(contentsOf: url)
    }
    var body: some View {
        Group {
            if let artwork { Image(nsImage: artwork).resizable().interpolation(.high).scaledToFit() }
            else { Image(systemName: provider.symbol).resizable().scaledToFit().foregroundStyle(.secondary) }
        }.frame(width: 32, height: 32).accessibilityLabel(provider.name)
    }
}

struct QuotaView: View {
    @ObservedObject var store: AccountStore
    let close: () -> Void
    let onHeight: (CGFloat) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if store.showingSettings {
                    Button("Voltar") { store.showingSettings = false }
                    Spacer()
                    Text("Configurações").font(.headline)
                } else {
                    Image(systemName: "gauge.with.needle").foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text("QuotaGlass").font(.headline)
                        Text("Suas assinaturas, num olhar").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.loading { ProgressView().controlSize(.small) }
                    Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }.disabled(store.loading)
                    Button { store.showingSettings = true } label: { Image(systemName: "gearshape") }
                }
            }.buttonStyle(.plain).padding(16)
            Divider()
            AdaptiveScrollArea(maximumHeight: max(100, store.maximumPanelHeight - 100)) {
                if store.showingSettings { settings }
                else {
                    VStack(spacing: 12) {
                        if store.profiles.isEmpty {
                            Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 32)).foregroundStyle(.green)
                            Text("Conecte sua primeira conta").font(.headline)
                            Text("Faça login pelo aplicativo. Sua sessão fica neste Mac.").font(.caption).foregroundStyle(.secondary)
                            addButtons
                        }
                        ForEach(store.results) { provider in
                            ForEach(provider.accounts) { account in AccountCard(account: account) }
                            if let error = provider.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                        }
                    }.padding(16)
                }
            }
            Divider()
            HStack {
                Text(store.updatedAt.map { "Atualizado às " + $0.formatted(date: .omitted, time: .shortened) } ?? "Login direto · dados locais")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Contas") { store.showingSettings = true }.buttonStyle(.plain).font(.caption)
            }.padding(12)
        }
        .frame(width: 386).fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { geometry in Color.clear.preference(key: PanelHeightKey.self, value: geometry.size.height) })
        .onPreferenceChange(PanelHeightKey.self, perform: onHeight)
    }
    private var addButtons: some View {
        HStack {
            Button("Conectar Codex") { close(); store.addAccount("codex") }
            Button("Conectar Claude") { close(); store.addAccount("claude") }
        }.buttonStyle(.bordered)
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contas").font(.headline)
            addButtons
            if let error = store.configurationError { Text(error).font(.caption).foregroundStyle(.red) }
            ForEach(store.profiles) { profile in
                HStack {
                    Text(profile.label).font(.caption)
                    Spacer()
                    Button("Entrar") { close(); store.login(profile) }
                    Button("Remover") { store.removeAccount(profile) }.disabled(store.loading)
                }
            }
            Text("Codex: login oficial no navegador. Claude: sessão própria do site em janela do aplicativo.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Executável do Codex CLI").font(.caption.bold())
            TextField("Caminho do CLI instalado", text: $store.codexExecutable).textFieldStyle(.roundedBorder)
            Text("Instale o Codex CLI oficial antes de conectar contas Codex.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Contas do widget").font(.headline)
            ForEach(0..<3, id: \.self) { slot in
                Picker("Conta \(slot + 1)", selection: Binding(get: { store.widgetAccountIDs[slot] }, set: { store.setWidgetAccount($0, at: slot) })) {
                    Text("Nenhuma").tag("")
                    ForEach(store.results.flatMap(\.accounts)) { account in Text(account.label + " · " + account.provider.name).tag(account.id) }
                }
            }
            Divider()
            Text("Indicadores de reset").font(.headline)
            HStack {
                TextField("Emoji (vazio usa círculo)", text: $store.resetEmoji).textFieldStyle(.roundedBorder)
                    .onChange(of: store.resetEmoji) { value in
                        let next = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1))
                        if next != value { store.resetEmoji = next }
                    }
                Button("Limpar") { store.resetEmoji = "" }
            }
            Text("Control + Command + Espaço abre a seleção de emojis.").font(.caption).foregroundStyle(.secondary)
            Toggle("Aplicar cor ao emoji", isOn: $store.resetCustomColor).disabled(store.resetEmoji.isEmpty)
            if store.resetCustomColor && !store.resetEmoji.isEmpty {
                HStack {
                    Text("Cor do emoji")
                    ResetColorPicker(color: Binding(get: { store.resetIndicatorStyle.color ?? .pink }, set: { if let hex = ResetIndicatorStyle.hex($0) { store.resetColorHex = hex } })).fixedSize()
                }
                Text("Cor única, com contorno no estado ativo.").font(.caption).foregroundStyle(.secondary)
            }
            HStack { Text("Prévia").font(.caption); ResetIndicators(count: 2, style: store.resetIndicatorStyle) }
            Divider()
            Text("Opacidade do menu").font(.headline)
            Slider(value: $store.backgroundOpacity, in: 0.1...1)
            Toggle("Painel extra na Mesa", isOn: $store.desktopPanelVisible)
            Button("Reposicionar painel extra") { store.repositionDesktopPanel?() }
            Text("O widget da galeria é independente deste painel extra.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("Encerrar QuotaGlass") { NSApp.terminate(nil) }
        }.padding(16)
    }
}

struct AccountCard: View {
    let account: AccountPresentation
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                ProviderLogo(provider: account.provider)
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.label).font(.system(size: 12, weight: .semibold)).lineLimit(1).help(account.label)
                    Text(account.provider.name).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                if !account.plan.isEmpty {
                    Text(account.plan).font(.system(size: 9, weight: .medium)).lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.quaternary.opacity(0.5), in: Capsule())
                }
            }
            if account.hidden { Text("Conta oculta").font(.caption).foregroundStyle(.secondary) }
            else if account.status != "ready" {
                Text(account.status == "disabled" ? "Conta desativada" : "Cota indisponível nesta consulta")
                    .font(.caption).foregroundStyle(.secondary)
            } else if account.windows.isEmpty {
                Text("A fonte não retornou janelas de cota").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(account.windows) { window in
                    HStack(spacing: 13) {
                        QuotaRing(remaining: window.remaining)
                        VStack(alignment: .leading, spacing: 3) {
                            if let group = window.group { Text(group).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary) }
                            Text(window.label).font(.system(size: 12, weight: .medium))
                            if let reset = window.reset {
                                Text(resetLabel(reset)).font(.system(size: 10)).foregroundStyle(.secondary)
                            } else { Text("Renovação não informada").font(.system(size: 10)).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 0)
                    }.accessibilityElement(children: .combine)
                }
            }
        }.padding(14)
         .frame(maxWidth: .infinity, alignment: .leading)
         .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 17))
         .overlay(RoundedRectangle(cornerRadius: 17).stroke(.primary.opacity(0.08), lineWidth: 0.7))
    }
    private func resetLabel(_ date: Date) -> String {
        if date <= Date() { return "Renovação prevista já passou · atualize" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = TimeZone(identifier: "America/Cuiaba")
        formatter.dateFormat = "dd/MM 'às' HH:mm"
        return "Renova em \(formatter.string(from: date))"
    }
}

struct QuotaRing: View {
    let remaining: Double?
    private var color: Color { guard let remaining else { return .secondary }; return remaining <= 10 ? .red : remaining <= 25 ? .orange : .green }
    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.09), lineWidth: 4)
            if let remaining { Circle().trim(from: 0, to: remaining / 100).stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90)) }
            VStack(spacing: 0) {
                Text(remaining.map { $0.formatted(.number.locale(Locale(identifier: "pt_BR")).precision(.fractionLength(0...1))) + "%" } ?? "—")
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(remaining == nil ? "sem dado" : "livre").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }.frame(width: 53, height: 53)
         .accessibilityLabel(remaining.map { "\($0) por cento disponível" } ?? "Percentual não informado")
    }
}
