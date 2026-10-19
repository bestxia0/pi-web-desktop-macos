import AppKit

/// NSStatusItem menu bar UI. Rebuilds the menu whenever the controller state
/// changes, and exposes the log / login-item / quit affordances.
final class MenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let controller: StatusController
    private let appWindow: AppWindowController
    private let hotKey: HotKeyMonitor

    init(controller: StatusController, appWindow: AppWindowController, hotKey: HotKeyMonitor) {
        self.controller = controller
        self.appWindow = appWindow
        self.hotKey = hotKey
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        controller.onChange = { [weak self] in self?.render() }
        if let button = statusItem.button {
            button.toolTip = "Pi Web"
        }
        render()
    }

    func render() {
        hotKey.refreshIfNeeded()
        updateIcon()
        statusItem.menu = buildMenu()
    }

    private func updateIcon() {
        // A solid, tinted symbol plus a short "Pi" title so the icon is easy to
        // spot in a crowded menu bar; each state looks clearly different.
        let symbol: String
        let color: NSColor
        switch controller.phase {
        case .running:
            symbol = "play.circle.fill"
            color = .systemGreen
        case .starting, .stopping:
            symbol = "arrow.triangle.2.circlepath"
            color = .systemOrange
        case .stopped:
            symbol = "power.circle.fill"
            color = .labelColor
        case .failed:
            symbol = "exclamationmark.triangle.fill"
            color = .systemRed
        }
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "Pi Web \(controller.phase)")
        // Colour the symbol explicitly; a template image would be forced to the
        // menu bar's monochrome foreground colour instead.
        let palette = NSImage.SymbolConfiguration(paletteColors: [color])
        let configured = base?.withSymbolConfiguration(palette)
        if let configured {
            configured.isTemplate = false
        } else {
            base?.isTemplate = true
        }
        if let button = statusItem.button {
            button.image = configured ?? base
            button.imagePosition = .imageLeading
            button.title = "Pi"
            button.contentTintColor = configured == nil ? color : nil
            button.toolTip = "Pi Web — \(controller.detail)"
        }
    }

    /// Pops the menu bar menu open. Called when a second launch asks the running
    /// instance to reveal itself, so a double-click always gives visible feedback.
    func revealMenu() {
        render()
        // Bring the accessory app forward, then click on the next runloop tick so
        // the menu is not dismissed by the exiting second instance.
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.button?.performClick(nil)
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let stateItem = NSMenuItem(title: "Pi Web — \(controller.detail)", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        if let error = controller.lastError, !error.isEmpty {
            let errorItem = NSMenuItem(title: "错误：\(error.replacingOccurrences(of: "\n", with: " "))", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        menu.addItem(.separator())

        let open = NSMenuItem(title: "打开 Pi Web", action: #selector(openClicked), keyEquivalent: "o")
        open.target = self
        open.isEnabled = controller.activeURL != nil
        menu.addItem(open)

        let toggleWindow = NSMenuItem(title: "显示 / 隐藏窗口", action: #selector(toggleWindowClicked), keyEquivalent: "")
        toggleWindow.target = self
        toggleWindow.isEnabled = controller.activeURL != nil || appWindow.isVisible
        menu.addItem(toggleWindow)

        let start = NSMenuItem(title: "启动 Pi Web", action: #selector(startClicked), keyEquivalent: "s")
        start.target = self
        start.isEnabled = controller.phase == .stopped || controller.phase == .failed
        menu.addItem(start)

        // Stop: a plain item for one instance, a per-instance submenu for many.
        let stopCount = controller.liveInstances.count
        let stopTitle = stopCount > 1 ? "停止 Pi Web（\(stopCount) 个实例）" : "停止 Pi Web"
        let stop = NSMenuItem(title: stopTitle, action: nil, keyEquivalent: "")
        if stopCount > 1 {
            let submenu = NSMenu()
            let entries = StopMenu.items(for: controller.liveInstances, ownedPid: controller.ownedPid)
            for (index, entry) in entries.enumerated() {
                let item = NSMenuItem(title: entry.title, action: #selector(stopOneClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = controller.liveInstances[index]
                submenu.addItem(item)
            }
            stop.submenu = submenu
            stop.isEnabled = true
        } else {
            stop.action = #selector(stopClicked)
            stop.target = self
            stop.isEnabled = stopCount == 1
        }
        menu.addItem(stop)

        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "刷新状态", action: #selector(refreshClicked), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let openLog = NSMenuItem(title: "打开日志", action: #selector(openLogClicked), keyEquivalent: "l")
        openLog.target = self
        menu.addItem(openLog)

        let revealLog = NSMenuItem(title: "在 Finder 中显示日志", action: #selector(revealLogClicked), keyEquivalent: "")
        revealLog.target = self
        menu.addItem(revealLog)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "开机自启", action: #selector(loginClicked), keyEquivalent: "")
        login.target = self
        switch LoginItem.currentState() {
        case .enabled:
            login.state = .on
            login.isEnabled = true
        case .disabled:
            login.state = .off
            login.isEnabled = true
        case .requiresApproval:
            login.state = .on
            login.isEnabled = true
            login.title = "开机自启（需在系统设置中批准）"
        case .notFound:
            login.state = .off
            login.isEnabled = LoginItem.isSupported
            login.title = "开机自启（App 需位于 /Applications）"
        case .unavailable(let reason):
            login.state = .off
            login.isEnabled = false
            login.title = "开机自启不可用：\(reason)"
        }
        menu.addItem(login)

        let stopOnQuit = NSMenuItem(title: "退出时同时停止后台 pi-web", action: #selector(stopOnQuitClicked), keyEquivalent: "")
        stopOnQuit.target = self
        stopOnQuit.state = Preferences.stopAttachedOnQuit ? .on : .off
        menu.addItem(stopOnQuit)

        let hotKeyItem = NSMenuItem(title: "右侧 Option 唤起窗口", action: #selector(hotKeyClicked), keyEquivalent: "")
        hotKeyItem.target = self
        hotKeyItem.state = Preferences.hotKeyEnabled ? .on : .off
        menu.addItem(hotKeyItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 Pi Web", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Permission helper, offered only while Input Monitoring is missing.
        // Kept before the version row so the actionable item stays visible.
        if !HotKeyMonitor.inputMonitoringGranted {
            let warning = NSMenuItem(
                title: "⚠︎ 需要「输入监控」权限——点击授权",
                action: #selector(grantInputMonitoringClicked),
                keyEquivalent: ""
            )
            warning.target = self
            menu.addItem(warning)
        }

        // The version row is the menu's last entry and is display-only.
        menu.addItem(.separator())
        let versionRow = NSMenuItem(title: VersionInfo.displayVersion, action: nil, keyEquivalent: "")
        versionRow.isEnabled = false
        menu.addItem(versionRow)

        let stopDescription = controller.liveInstances.count > 1
            ? "submenu[" + StopMenu.items(for: controller.liveInstances, ownedPid: controller.ownedPid)
                .map(\.title).joined(separator: " | ") + "]"
            : "item(enabled=\(controller.liveInstances.count == 1))"
        // Log the menu that was actually built, not the values it was built
        // from: this is the regression evidence that the version row exists and
        // sits last.
        let titles = menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
        Logger.shared.info(
            "menu build: instances=\(controller.liveInstances.count) stop=\(stopDescription) "
            + "stopOnQuit=\(Preferences.stopAttachedOnQuit) "
            + "hotkeyEnabled=\(Preferences.hotKeyEnabled) hotkeyMode=\(hotKey.mode.rawValue) "
            + "inputMonitoring=\(HotKeyMonitor.inputMonitoringGranted) accessibility=\(HotKeyMonitor.accessibilityGranted) "
            + "windowVisible=\(appWindow.isVisible) "
            + "version=\(VersionInfo.displayVersion) "
            + "last=\(menu.items.last?.title ?? "<none>") items=\(titles.joined(separator: " | "))"
        )

        return menu
    }

    @objc private func openClicked() {
        appWindow.show(url: controller.activeURL)
    }

    @objc private func toggleWindowClicked() {
        appWindow.toggle(url: controller.activeURL)
    }

    @objc private func hotKeyClicked() {
        Preferences.hotKeyEnabled.toggle()
        hotKey.setEnabled(Preferences.hotKeyEnabled)
        Logger.shared.info(
            "hotkey enabled set to \(Preferences.hotKeyEnabled) (mode=\(hotKey.mode.rawValue))"
        )
        render()
    }

    @objc private func grantInputMonitoringClicked() {
        Logger.shared.info("hotkey: requesting Input Monitoring permission")
        HotKeyMonitor.requestInputMonitoring()
        HotKeyMonitor.openInputMonitoringSettings()
        hotKey.refreshIfNeeded()
        render()
    }

    @objc private func startClicked() { controller.start() }
    @objc private func stopClicked() { controller.stop() }

    @objc private func stopOneClicked(_ sender: NSMenuItem) {
        guard let instance = sender.representedObject as? DetectedInstance else { return }
        requestStop(instance)
    }

    /// owned stops immediately; attached stops only after an explicit warning.
    private func requestStop(_ instance: DetectedInstance) {
        if controller.isOwned(instance) {
            controller.stopInstance(instance)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "停止后台 pi-web？"
        alert.informativeText = "\(instance.url)（pid \(instance.stopPid)）不是本壳启动的，可能来自终端。停止会中断其中正在运行的会话。"
        alert.addButton(withTitle: "停止")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            controller.stopInstance(instance)
        }
    }

    @objc private func stopOnQuitClicked() {
        Preferences.stopAttachedOnQuit.toggle()
        Logger.shared.info("stop-attached-on-quit set to \(Preferences.stopAttachedOnQuit)")
        render()
    }
    @objc private func refreshClicked() { controller.refresh() }

    @objc private func openLogClicked() {
        let url = URL(fileURLWithPath: AppConfig.logFile)
        if !FileManager.default.fileExists(atPath: AppConfig.logFile) {
            Logger.shared.info("log opened before any entry; creating file")
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealLogClicked() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: AppConfig.logFile)])
    }

    @objc private func loginClicked() {
        let enable = !LoginItem.isEnabled()
        if let error = LoginItem.setEnabled(enable) {
            Logger.shared.warn("login item toggle failed: \(error)")
        }
        render()
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
}
