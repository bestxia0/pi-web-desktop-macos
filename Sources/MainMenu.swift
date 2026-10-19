import AppKit

/// Builds the real `NSApp.mainMenu`.
///
/// Browser-style key equivalents (⌘T / ⌘W / ⌘1…⌘9 / ⌘⇧[ / ⌘⇧]) only reach the
/// app while a status-item menu is closed, so they must live in the main menu.
/// The tab items target the `AppWindowController` directly; the Edit items use
/// nil targets so the standard first-responder selectors reach the focused
/// `WKWebView` text field.
enum MainMenu {
    static func build(tabTarget: AppWindowController) -> NSMenu {
        let mainMenu = NSMenu()

        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(tabsMenuItem(tabTarget: tabTarget))
        mainMenu.addItem(browseMenuItem(tabTarget: tabTarget))

        return mainMenu
    }

    // MARK: - App menu

    private static func appMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Pi Web")
        item.submenu = menu

        let about = NSMenuItem(
            title: "关于 Pi Web",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        menu.addItem(about)
        menu.addItem(.separator())

        let hide = NSMenuItem(title: "隐藏 Pi Web", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(hide)

        let hideOthers = NSMenuItem(
            title: "隐藏其他",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)

        let showAll = NSMenuItem(
            title: "全部显示",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        menu.addItem(showAll)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 Pi Web", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        return item
    }

    // MARK: - Edit menu

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "编辑")
        item.submenu = menu

        // Standard first-responder selectors (nil target) so the focused web
        // view's editable text behaves like any other macOS text field.
        menu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")

        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())

        menu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        return item
    }

    // MARK: - Tabs menu

    private static func tabsMenuItem(tabTarget: AppWindowController) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "标签页")
        item.submenu = menu

        menu.addItem(targetedItem("新建标签页", #selector(AppWindowController.newTabAction(_:)), "t", tabTarget))
        menu.addItem(targetedItem("关闭标签页", #selector(AppWindowController.closeTabAction(_:)), "w", tabTarget))
        menu.addItem(targetedItem(
            "关闭其他标签页",
            #selector(AppWindowController.closeOtherTabsAction(_:)),
            "",
            tabTarget
        ))
        menu.addItem(.separator())

        let next = targetedItem("下一个标签页", #selector(AppWindowController.nextTabAction(_:)), "]", tabTarget)
        next.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(next)

        let previous = targetedItem("上一个标签页", #selector(AppWindowController.previousTabAction(_:)), "[", tabTarget)
        previous.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(previous)
        menu.addItem(.separator())

        for number in 1...9 {
            let entry = NSMenuItem(
                title: "标签 \(number)",
                action: #selector(AppWindowController.selectTabAction(_:)),
                keyEquivalent: "\(number)"
            )
            entry.keyEquivalentModifierMask = [.command]
            entry.tag = number - 1
            entry.target = tabTarget
            menu.addItem(entry)
        }

        return item
    }

    // MARK: - Browse menu

    private static func browseMenuItem(tabTarget: AppWindowController) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "浏览")
        item.submenu = menu

        menu.addItem(targetedItem("后退", #selector(AppWindowController.goBackAction(_:)), "[", tabTarget))
        menu.addItem(targetedItem("前进", #selector(AppWindowController.goForwardAction(_:)), "]", tabTarget))
        menu.addItem(.separator())
        menu.addItem(targetedItem("重新加载", #selector(AppWindowController.reloadAction(_:)), "r", tabTarget))

        return item
    }

    private static func targetedItem(
        _ title: String,
        _ action: Selector,
        _ keyEquivalent: String,
        _ target: AnyObject
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        return item
    }
}
