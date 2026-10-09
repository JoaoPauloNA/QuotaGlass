import AppKit
import WebKit

/// A separate first-party website session for each profile. Cookies never leave WebKit.
@MainActor final class ClaudeConnection: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private var window: NSWindow?
    private var loaded = false
    var onLoaded: (() -> Void)?
    init(profile: UUID) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: profile)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.load(URLRequest(url: URL(string: "https://claude.ai/settings/usage")!))
    }
    func login() {
        if window == nil {
            let next = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 680), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            next.title = "Entrar no Claude — QuotaGlass"
            next.isReleasedWhenClosed = false
            next.contentView = webView
            next.center()
            window = next
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = webView.url?.host == "claude.ai"
        if loaded { onLoaded?() }
    }
    func usage() async throws -> [String: Any] {
        guard loaded, webView.url?.host == "claude.ai" else { throw Failure.loginRequired }
        let script = """
        if (location.hostname !== 'claude.ai') return {status:'login'};
        const get = async path => {
          const response = await fetch(path, {credentials:'same-origin', cache:'no-store', redirect:'error', signal:AbortSignal.timeout(15000)});
          if(!response.ok) throw new Error(String(response.status));
          return response.json();
        };
        try {
          const organizations = await get('/api/organizations');
          if(!Array.isArray(organizations)) return {status:'login'};
          const organization = organizations.find(o => typeof o.uuid === 'string' && (!o.capabilities || (Array.isArray(o.capabilities) && o.capabilities.includes('chat'))));
          if(!organization) return {status:'login'};
          const usage = await get('/api/organizations/' + encodeURIComponent(organization.uuid) + '/usage');
          const windows = [];
          for(const [key,label] of [['five_hour','5 horas'],['seven_day','7 dias'],['seven_day_sonnet','Sonnet · 7 dias'],['seven_day_opus','Opus · 7 dias']]) {
            const w = usage[key];
            if(w && typeof w.utilization === 'number' && Number.isFinite(w.utilization)) windows.push({label, usedPercent:w.utilization, resetAt:typeof w.resets_at === 'string' ? w.resets_at : null});
          }
          return {status:'ready', plan:organization.billing_type || '', windows};
        } catch(error) {
          return {status:String(error.message) === '429' ? 'rate_limited' : 'unavailable'};
        }
        """
        let value: Any = try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                continuation.resume(with: result)
            }
        }
        guard let packet = value as? [String: Any] else { throw Failure.loginRequired }
        return packet
    }
    func logout() async {
        let data = webView.configuration.websiteDataStore
        let records = await data.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        await data.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records)
        window?.close()
    }
    enum Failure: Error { case loginRequired }
}
