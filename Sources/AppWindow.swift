import AppKit
import WebKit

/// Owns the single native `NSWindow` and its native tab strip.
///
/// One window, many `WKWebView`s: each tab is an independent web view loaded at
/// its own pi-web URL, so every tab can point at a different session. The
/// window itself is created once and reused; closing it only orders it out.
///
/// `toggleAction(isVisible:isKey:)` stays pure so `--self-test` can assert the
/// toggle semantics without a GUI, and `TabSupport` holds the other pure
/// helpers shared with the tests.
final class AppWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, TabBarDelegate {
    /// Pure toggle decision: hide only when the window is visible *and* key.
    enum ToggleAction: Equatable { case show, hide }

    static func toggleAction(isVisible: Bool, isKey: Bool) -> ToggleAction {
        (isVisible && isKey) ? .hide : .show
    }

    /// One open tab and its observations. `url`/`title` mirror the last values
    /// seen from KVO so persistence does not depend on reading the web view.
    private struct Tab {
        let webView: WKWebView
        var url: String
        var title: String
        var color: Int
        var urlObs: NSKeyValueObservation?
        var titleObs: NSKeyValueObservation?
    }

    /// Soft cap for manually created tabs: beyond this a new tab is refused
    /// with a beep rather than quietly consuming unbounded memory.
    private static let maxTabs = 20

    /// Hard sanity ceiling for restoring a persisted tab list; a restore is not
    /// subject to the manual soft cap so a large saved list is not truncated.
    private static let restoreTabCeiling = 100

    private var window: NSWindow?
    private var tabBar: TabBarView?
    private var contentContainer: NSView?

    private var tabs: [Tab] = []
    private var selectedIndex = 0
    private var currentBase: String?
    private var didRestore = false
    private var isRestoring = false

    /// Fired after any change that affects the status menu (add/close/select/
    /// colour/url/title).
    var onTabsChanged: (() -> Void)?

    var isVisible: Bool { window?.isVisible ?? false }
    var tabCount: Int { tabs.count }
    var tabTitles: [String] { tabs.map { $0.title } }
    var selectedTabIndex: Int { selectedIndex }

    private var activeTab: Tab? {
        guard selectedIndex >= 0, selectedIndex < tabs.count else { return nil }
        return tabs[selectedIndex]
    }

    private var activeBase: String? {
        currentBase ?? activeTab.flatMap { Self.baseURL(from: $0.url) }
    }

    // MARK: - Show / hide / toggle

    /// Ensures the window exists, restores persisted tabs once (rewriting each
    /// stored URL onto the current pi-web base), otherwise creates a first tab
    /// from `url`, then focuses the window. Repeated calls only focus.
    @discardableResult
    func show(url: String?) -> Bool {
        let requested = (url?.isEmpty == false) ? url : nil

        // Nothing to reveal: no URL and no tabs already in memory. A hotkey
        // press in that state stays cheap (and never pops a blank window).
        if requested == nil && tabs.isEmpty && didRestore {
            return isVisible
        }

        let nsWindow = ensureWindow()
        nsWindow.contentView?.layoutSubtreeIfNeeded()

        let base = requested.flatMap { Self.baseURL(from: $0) }
        if !didRestore {
            didRestore = true
            if let base { currentBase = base }
            // Restore persisted tabs even without a URL, so the right-Option
            // hotkey can reveal tabs saved by a previous session.
            restoreTabs(fallbackURL: requested, base: base)
        } else if let base {
            currentBase = base
        }

        if tabs.isEmpty {
            // All tabs may have been closed since the window was last shown, or
            // nothing was persisted: create a first tab only when a URL is
            // known, otherwise there is nothing to show.
            guard let requested else { return isVisible }
            _ = createTab(url: requested, color: 0)
        }

        applySelection()
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

    // MARK: - Tab lifecycle

    /// Opens a new tab. With no explicit `url`, loads the session list scoped
    /// to the active tab's `cwd` (or unscoped). Never creates a session.
    func newTab(url: String? = nil) {
        let nsWindow = ensureWindow()
        nsWindow.contentView?.layoutSubtreeIfNeeded()

        if !didRestore {
            didRestore = true
            // A tab can be requested before the window was ever shown (⌘T,
            // the status menu, or `window.open`). Restore the persisted tabs
            // first; appending one tab and persisting would otherwise clobber
            // the stored list.
            let restoreBase = url.flatMap { Self.baseURL(from: $0) } ?? activeBase
            if let restoreBase { currentBase = restoreBase }
            restoreTabs(fallbackURL: nil, base: restoreBase)
        }

        let base = activeBase ?? AppConfig.url(port: AppConfig.preferredPort)
        let target = url ?? TabSupport.newTabURL(base: base, activeURL: activeTab?.url)
        guard createTab(url: target, color: 0) else { return }

        selectedIndex = tabs.count - 1
        applySelection()
    }

    /// Menu/⌘T entry point: no explicit URL.
    func newTabFromMenu() {
        newTab(url: nil)
    }

    /// ⌘W: closes the current tab, hiding the window when it was the last one.
    func closeCurrentTab() {
        guard !tabs.isEmpty else {
            hide()
            return
        }
        closeTab(at: selectedIndex)
    }

    func closeTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        let countBefore = tabs.count
        removeTab(at: index)

        if tabs.isEmpty {
            selectedIndex = 0
            renderTabBar()
            persist()
            hide()
            return
        }

        if index < selectedIndex {
            selectedIndex -= 1
        } else if index == selectedIndex {
            selectedIndex = min(
                TabSupport.indexAfterClose(closed: index, count: countBefore) ?? 0,
                tabs.count - 1
            )
        }
        if selectedIndex < 0 { selectedIndex = 0 }
        if selectedIndex >= tabs.count { selectedIndex = tabs.count - 1 }
        applySelection()
    }

    func closeOtherTabs(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        let keep = tabs[index]
        for (i, tab) in tabs.enumerated() where i != index {
            dispose(tab)
        }
        tabs = [keep]
        selectedIndex = 0
        applySelection()
    }

    func selectTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        selectedIndex = index
        applySelection()
    }

    func selectNextTab() {
        guard !tabs.isEmpty else { return }
        selectTab(at: TabSupport.neighborIndex(current: selectedIndex, count: tabs.count, delta: 1))
    }

    func selectPreviousTab() {
        guard !tabs.isEmpty else { return }
        selectTab(at: TabSupport.neighborIndex(current: selectedIndex, count: tabs.count, delta: -1))
    }

    func setColor(_ color: Int, at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        tabs[index].color = TabPalette.normalized(color)
        renderTabBar()
        persist()
    }

    // MARK: - Private tab plumbing

    /// Restores persisted tabs. `fallbackURL` is only used when nothing was
    /// stored: `show` passes its URL to synthesise a first tab, `newTab` passes
    /// nil because it appends its own tab afterwards.
    private func restoreTabs(fallbackURL: String?, base: String?) {
        let stored = TabStore.load()
        guard !stored.tabs.isEmpty else {
            if let fallbackURL {
                _ = createTab(url: fallbackURL, color: 0)
            }
            return
        }

        isRestoring = true
        var restored = 0
        for record in stored.tabs {
            guard restored < Self.restoreTabCeiling else { break }
            let rewritten = base.map { TabSupport.rewriteBase(record.url, to: $0) } ?? record.url
            if createTab(url: rewritten, color: record.color, restoring: true) {
                restored += 1
            }
        }
        isRestoring = false

        if stored.tabs.count > restored {
            Logger.shared.warn(
                "window: restore ceiling \(Self.restoreTabCeiling) reached; "
                    + "\(stored.tabs.count - restored) stored tab(s) not opened"
            )
        }
        selectedIndex = max(0, min(stored.selected, max(tabs.count - 1, 0)))
        Logger.shared.info("window: restored \(tabs.count) tab(s) from UserDefaults (base=\(base ?? "unchanged"))")
    }

    @discardableResult
    private func createTab(url: String, color: Int, restoring: Bool = false) -> Bool {
        guard let container = contentContainer else { return false }
        // Manually created tabs keep the low soft cap; a restore is allowed up
        // to the higher sanity ceiling so a large saved list is not truncated.
        let cap = restoring ? Self.restoreTabCeiling : Self.maxTabs
        guard tabs.count < cap else {
            if !restoring {
                NSSound.beep()
                Logger.shared.warn("window: tab cap \(Self.maxTabs) reached; refusing new tab")
            }
            return false
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: container.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true

        var tab = Tab(
            webView: webView,
            url: url,
            title: "新标签页",
            color: TabPalette.normalized(color),
            urlObs: nil,
            titleObs: nil
        )
        tab.urlObs = webView.observe(\.url, options: [.new]) { [weak self] observed, _ in
            self?.urlChanged(for: observed)
        }
        tab.titleObs = webView.observe(\.title, options: [.new]) { [weak self] observed, _ in
            self?.titleChanged(for: observed)
        }

        tabs.append(tab)
        container.addSubview(webView)
        webView.isHidden = true

        if let target = URL(string: url) {
            webView.load(URLRequest(url: target))
            Logger.shared.info("window: tab \(tabs.count - 1) loading \(url)")
        } else {
            Logger.shared.error("window: invalid url \(url)")
        }
        return true
    }

    private func removeTab(at index: Int) {
        let tab = tabs.remove(at: index)
        dispose(tab)
    }

    private func dispose(_ tab: Tab) {
        tab.urlObs?.invalidate()
        tab.titleObs?.invalidate()
        tab.webView.navigationDelegate = nil
        tab.webView.uiDelegate = nil
        tab.webView.removeFromSuperview()
    }

    private func index(of webView: WKWebView) -> Int? {
        tabs.firstIndex(where: { $0.webView === webView })
    }

    private func urlChanged(for webView: WKWebView) {
        guard !isRestoring, let index = index(of: webView) else { return }
        if let url = webView.url?.absoluteString, !url.isEmpty {
            tabs[index].url = url
        }
        renderTabBar()
        persist()
    }

    private func titleChanged(for webView: WKWebView) {
        guard !isRestoring, let index = index(of: webView) else { return }
        if let title = webView.title, !title.isEmpty {
            tabs[index].title = title
            if index == selectedIndex { window?.title = title }
        }
        renderTabBar()
        persist()
    }

    /// Shows the selected tab, hides the rest, reconciles the live URL (KVO on
    /// `.url` is not guaranteed for same-document `router.replace`), refreshes
    /// the bar and persists.
    private func applySelection() {
        guard !tabs.isEmpty else {
            window?.title = "Pi Web"
            renderTabBar()
            persist()
            return
        }
        if selectedIndex < 0 { selectedIndex = 0 }
        if selectedIndex >= tabs.count { selectedIndex = tabs.count - 1 }

        for (index, tab) in tabs.enumerated() {
            tab.webView.isHidden = (index != selectedIndex)
        }

        if let container = contentContainer {
            let frame = container.bounds
            for tab in tabs {
                tab.webView.frame = frame
            }
        }

        let selected = tabs[selectedIndex]
        if let live = selected.webView.url?.absoluteString, !live.isEmpty {
            tabs[selectedIndex].url = live
        }
        window?.title = selected.title
        renderTabBar()
        persist()
    }

    private func renderTabBar() {
        tabBar?.reload(
            titles: tabs.map { $0.title },
            colors: tabs.map { $0.color },
            selected: selectedIndex
        )
    }

    /// Saves the tabs + selection and notifies the status menu. Reconciles each
    /// live `webView.url` first, since KVO on `.url` is not guaranteed for
    /// same-document (`router.replace`) navigation.
    private func persist() {
        for index in tabs.indices {
            if let live = tabs[index].webView.url?.absoluteString,
               !live.isEmpty,
               tabs[index].url != live {
                tabs[index].url = live
            }
        }
        TabStore.save(
            tabs: tabs.map { TabRecord(url: $0.url, color: $0.color) },
            selected: selectedIndex
        )
        onTabsChanged?()
    }

    // MARK: - Window construction

    /// Creates the single window + tab container on first use.
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

        let container = NSView(frame: frame)
        container.autoresizingMask = [.width, .height]

        let tabBar = TabBarView(frame: .zero)
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.delegate = self

        let content = NSView(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(tabBar)
        container.addSubview(content)
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: container.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: TabBarView.barHeight),

            content.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        window.contentView = container

        self.window = window
        self.tabBar = tabBar
        self.contentContainer = content
        Logger.shared.info("window: created single native NSWindow + tab container")
        return window
    }

    // MARK: - TabBarDelegate

    func tabBar(_ bar: TabBarView, didSelect index: Int) {
        selectTab(at: index)
    }

    func tabBar(_ bar: TabBarView, didClose index: Int) {
        closeTab(at: index)
    }

    func tabBarDidRequestNewTab(_ bar: TabBarView) {
        newTab(url: nil)
    }

    func tabBar(_ bar: TabBarView, didSetColor color: Int, at index: Int) {
        setColor(color, at: index)
    }

    func tabBar(_ bar: TabBarView, didRequestCloseOthers index: Int) {
        closeOtherTabs(at: index)
    }

    // MARK: - Main-menu actions

    @objc func newTabAction(_ sender: Any?) { newTabFromMenu() }
    @objc func closeTabAction(_ sender: Any?) { closeCurrentTab() }
    @objc func closeOtherTabsAction(_ sender: Any?) {
        guard !tabs.isEmpty else { return }
        closeOtherTabs(at: selectedIndex)
    }
    @objc func nextTabAction(_ sender: Any?) { selectNextTab() }
    @objc func previousTabAction(_ sender: Any?) { selectPreviousTab() }
    @objc func selectTabAction(_ sender: NSMenuItem) { selectTab(at: sender.tag) }
    @objc func reloadAction(_ sender: Any?) { activeTab?.webView.reload() }
    @objc func goBackAction(_ sender: Any?) { activeTab?.webView.goBack() }
    @objc func goForwardAction(_ sender: Any?) { activeTab?.webView.goForward() }

    // MARK: - NSWindowDelegate

    /// Closing the window only hides it; the single window is never destroyed.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let index = index(of: webView) else { return }
        if let title = webView.title, !title.isEmpty {
            tabs[index].title = title
            if index == selectedIndex { window?.title = title }
        }
        if let url = webView.url?.absoluteString, !url.isEmpty {
            tabs[index].url = url
        }
        renderTabBar()
        persist()
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
            // Open here and cancel, including `target=_blank`: a `.cancel`
            // decision stops WebKit before it ever calls `createWebViewWith`,
            // so cancelling without opening would silently drop the link. JS
            // `window.open` (navigationType `.other`) still reaches
            // `createWebViewWith`, which is where those are caught.
            Logger.shared.info("window: opening external link in browser \(url.absoluteString)")
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - WKUIDelegate

    /// Captures pi-web's own "open session in a new tab" (`window.open`): an
    /// internal target becomes a native tab, anything else goes to the browser.
    /// Neither path lets WebKit create a second window.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        let host = url.host ?? ""
        if host == "127.0.0.1" || host == "localhost" {
            Logger.shared.info("window: window.open -> native tab \(url.absoluteString)")
            newTab(url: url.absoluteString)
        } else {
            Logger.shared.info("window: window.open -> external browser \(url.absoluteString)")
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    /// Minimal alert panel so pi-web's `alert()` calls are visible instead of
    /// being silently dropped by the missing default implementation.
    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
        completionHandler()
    }

    /// `confirm()` — 确定 returns `true`, 取消 returns `false`.
    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    /// `prompt()` — 确定 returns the field text, 取消 returns `nil`.
    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            completionHandler(field.stringValue)
        } else {
            completionHandler(nil)
        }
    }

    // MARK: - Helpers

    /// "http://127.0.0.1:30141/anything" -> "http://127.0.0.1:30141".
    private static func baseURL(from url: String) -> String? {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme,
              let host = components.host else {
            return nil
        }
        var base = "\(scheme)://\(host)"
        if let port = components.port {
            base += ":\(port)"
        }
        return base
    }
}
