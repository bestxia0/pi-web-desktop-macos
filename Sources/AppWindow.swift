import AppKit
import WebKit

/// Owns the single native `NSWindow` + `WKWebView` that renders the pi-web UI.
///
/// The window is created once and reused for every open: showing and hiding
/// never destroys it, and closing it (red button / Cmd+W) only orders it out.
/// `toggleAction(isVisible:isKey:)` is pure so `--self-test` can assert the
/// toggle semantics without a GUI.
final class AppWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate {
    /// Pure toggle decision: hide only when the window is visible *and* key.
    enum ToggleAction: Equatable { case show, hide }

    static func toggleAction(isVisible: Bool, isKey: Bool) -> ToggleAction {
        (isVisible && isKey) ? .hide : .show
    }

    private var window: NSWindow?
    private var webView: WKWebView?
    private var loadedURL: String?

    var isVisible: Bool { window?.isVisible ?? false }

    // MARK: - Show / hide / toggle

    /// Shows and focuses the window, loading `url` only when it changed since
    /// the last load. With a nil/empty URL, returns whether the window is
    /// already visible (the menu passes `activeURL`, which can be nil).
    @discardableResult
    func show(url: String?) -> Bool {
        guard let url, !url.isEmpty else {
            return isVisible
        }
        let nsWindow = ensureWindow()
        if loadedURL != url {
            loadedURL = url
            if let target = URL(string: url) {
                webView?.load(URLRequest(url: target))
                Logger.shared.info("window: loading \(url)")
            } else {
                Logger.shared.error("window: invalid url \(url)")
            }
        } else {
            Logger.shared.info("window: reusing loaded url \(url)")
        }
        // An accessory (LSUIElement) app needs an explicit activate before the
        // window can become key.
        NSApp.activate(ignoringOtherApps: true)
        nsWindow.makeKeyAndOrderFront(nil)
        return true
    }

    /// Hides the window without destroying it.
    func hide() {
        window?.orderOut(nil)
        Logger.shared.info("window: hidden")
    }

    /// Right-Option behaviour: hide when visible and frontmost, otherwise show.
    func toggle(url: String?) {
        let visible = isVisible
        let key = window?.isKeyWindow ?? false
        switch Self.toggleAction(isVisible: visible, isKey: key) {
        case .hide:
            hide()
        case .show:
            _ = show(url: url)
        }
    }

    // MARK: - Window construction

    /// Creates the single window + web view on first use.
    private func ensureWindow() -> NSWindow {
        if let window { return window }

        let frame = NSRect(x: 0, y: 0, width: 1200, height: 820)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pi Web"
        window.minSize = NSSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("PiWebMainWindow")

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: frame, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        window.contentView = webView

        self.window = window
        self.webView = webView
        Logger.shared.info("window: created single native NSWindow + WKWebView")
        return window
    }

    // MARK: - NSWindowDelegate

    /// Closing the window only hides it; the single window is never destroyed.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let title = webView.title, !title.isEmpty {
            window?.title = title
        }
    }

    /// External links (anything whose host is not the local pi-web server)
    /// open in the system browser, keeping docs links out of the app window.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           let host = url.host,
           host != "127.0.0.1" && host != "localhost" {
            Logger.shared.info("window: opening external link in browser \(url.absoluteString)")
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
