# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The version shown in the menu is `<semver>-<builddate>`, e.g. `V0.7.0-20261019`.
The semantic part comes from the [`VERSION`](VERSION) file; the build date is
stamped by `build.sh` at build time.

## [Unreleased]

Nothing yet.

## [0.7.0] - 2026-10-19

Native multi-tab support in the single window; each tab is its own `WKWebView`
loaded at its own pi-web URL, so different tabs can point at different sessions.
Client-side only — upstream pi-web is untouched.

### Added

- **Native tab bar** (`TabBar.swift`) — a 34pt strip at the top of the single
  window: one item per tab with a colour dot, a truncating title from the page,
  and a borderless close button, plus a trailing `+` button. Selected tabs get
  an accent-tinted rounded background. The strip scrolls horizontally and keeps
  the selected item in view.
- **Manual tab creation only** — the `+` button, ⌘T and the menu create tabs;
  nothing auto-creates sessions and no state-changing API is called at startup.
  A new tab loads the session list, scoped to the active tab's `cwd` when it has
  one (`base + "/?cwd=<path>"`), otherwise `base + "/"`.
- **Per-tab colours and context menu** — right-clicking a tab opens a `颜色`
  submenu (无颜色, 红, 橙, 黄, 绿, 薄荷, 蓝, 靛蓝, 紫, 粉, 灰 — adaptive system
  colours, checkmark on the current one) plus `关闭标签页` and `关闭其他标签页`.
- **Real `NSApp.mainMenu`** (`MainMenu.swift`) — App / 编辑 / 标签页 / 浏览 menus.
  ⌘T 新建标签页, ⌘W 关闭标签页 (closes the current tab, not the window), ⌘⇧] /
  ⌘⇧[ next/previous, ⌘1…⌘9 select, ⌘[ / ⌘] back/forward, ⌘R reload, and a
  standard Edit menu wired to nil-target first-responder selectors so web-view
  text fields behave normally.
- **Persistence** (`TabStore.swift`) — each tab's URL + colour and the selected
  index are stored in `UserDefaults` (`PiWebTabs` / `PiWebTabsSelected`). On
  restore every stored URL's scheme/host/port is rewritten to the *current*
  pi-web base (the port can change), preserving path and query.
- **`WKUIDelegate`** — pi-web's own `window.open('?session=<id>')` becomes a
  native tab (internal hosts) or opens in the system browser (external hosts);
  a minimal JavaScript alert panel keeps `alert()` visible.
- **Status-menu tab items** — 新建 / 关闭 / 下一个 / 上一个 标签页 plus a `标签页`
  submenu listing every tab (`<n> <title>`, checkmark on the selected one), and
  the `menu build:` log line now reports `tabs` / `selectedTab`.
- **Self-test** — deterministic checks for the colour palette (including
  clamping), `rewriteBase`, `indexAfterClose`, `neighborIndex`, `newTabURL` and
  the `TabStore` round-trip / corrupt-data handling.
- **Pure helpers** (`TabSupport`) shared by `AppWindowController` and
  `--self-test`.

### Changed

- **Single window, many web views** — `AppWindowController` now hosts a
  container: the tab bar pinned on top and an interchangeable content area
  below. Tabs are non-selected-hidden `WKWebView`s of `.default()` data store;
  the window is still created once and closing it still only `orderOut`s it.
- ⌘W now closes the current tab; when the last tab closes the window hides
  (`orderOut`). The red close button and the right-Option hotkey still act on
  the whole window.

### Removed

- Nothing.

## [0.6.0] - 2026-10-19

Native single window and a right-Option global hotkey.

### Added

- **Native single window** — the GUI now renders the pi-web UI in one reusable
  `NSWindow` + `WKWebView` (`AppWindow.swift`) instead of opening a fresh
  Chrome-family `--app` window on every launch. The window is created once and
  reused: opening it again focuses it, reloads only when the URL actually
  changed, and closing it (red button / Cmd+W) hides it rather than destroying
  it. External links (host other than `127.0.0.1`/`localhost`) open in the
  system browser. `Info.plist` gains `NSAppTransportSecurity →
  NSAllowsLocalNetworking` so the web view may load `http://127.0.0.1`.
- **Right-Option global hotkey** — tapping the **right** Option key toggles the
  window (hide when visible and frontmost, otherwise show + focus). Implemented
  in `HotKeyMonitor.swift` with a listen-only `CGEvent` tap and an `NSEvent`
  global/local monitor fallback; the left Option key is ignored entirely and
  the event is never consumed. Requires the macOS **Input Monitoring**
  permission, with a menu helper item while it is missing.
- **Menu items** — `显示 / 隐藏窗口`, a `右侧 Option 唤起窗口` checkbox, and a
  permission warning item. The `menu build:` log line now records the hotkey
  state (enabled, mode, permission).
- **Preferences** — `PiWebHotKeyEnabled` (UserDefaults, default on).
- **Self-test** — pure assertions for the right-vs-left Option classifier, the
  window toggle decision, and the hotkey preference.

### Changed

- `StatusController.openWindow()` now returns `Bool`, prefers the GUI's
  `openWindowHandler` (native window) and only falls back to
  `BrowserOpener.openAppMode` when no handler is installed. `BrowserOpener`
  stays intact for `--open-url`/`--resolve`.
- `build.sh` links `-framework WebKit`.

## [0.5.0] - 2026-10-19

First public release: the menu bar launcher for the upstream `pi-web` web UI.

### Added

- **Menu bar app** — a native Swift + AppKit `NSStatusItem` (`LSUIElement`, no
  Dock icon) built with `swiftc` alone, with zero third-party dependencies.
- **State-tinted status icon** — an SF Symbol plus the short `Pi` title, tinted
  green (running), orange (busy), label colour (stopped) and red (failed).
- **Detection** — reads the upstream `pi-web` run-record contract at
  `<agentDir>/pi-web-run/<launcherPid>.json` and validates liveness *and*
  ownership before probing the URL. Detection is read-only and never prunes
  stale records.
- **Attach or start** — reuses a healthy existing instance instead of starting a
  second one; otherwise spawns `pi-web --port <N> --no-open` and waits (up to
  60s) for readiness.
- **Port fallback** — `bind()`-probes `30141`, scans upward from `30151`, then
  falls back to a kernel-assigned ephemeral port, because `pi-web` itself has no
  fallback.
- **Browser app mode** — opens the UI in Chrome / Edge / Brave / Arc app mode
  (no address bar), falling back to the default browser.
- **Two stop paths** — owned instances get a `SIGINT → 10s → SIGTERM → 5s →
  SIGKILL` escalation; attached instances are stopped through upstream
  `pi-web stop --port N` after an explicit confirmation prompt.
- **Per-instance stop submenu** when more than one instance is live, showing the
  URL and pid and marking the instance this shell owns.
- **Login-shell PATH resolution** — recovers `PATH` and the `pi-web` location
  once via `/bin/zsh -lic` (5s timeout), caches it, and falls back to scanning
  Homebrew, `/usr/local/bin`, `~/.local/bin`, `~/.bun/bin`, `~/.npm-global/bin`
  and `npm prefix -g`, so a Finder launch can find Homebrew's `pi-web` and
  `node`.
- **Start at Login** — an `SMAppService.mainApp` toggle that reflects the real
  system status, including the "requires approval" and
  "app must live in /Applications" states.
- **Stop-attached-on-quit toggle** — UserDefaults key `PiWebStopAttachedOnQuit`,
  default on.
- **Single-instance guard** — an exclusive `flock`; a second launch posts the
  `com.piweb.desktop.activate` distributed notification so the running instance
  reveals its menu instead of staying silent.
- **Logging** — append-only `~/Library/Logs/PiWeb/pi-web.log`, with the child's
  stdout and stderr redirected into the same file.
- **Headless verification** — the same binary runs `--self-test`, `--probe`,
  `--resolve`, `--test-cycle`, `--test-fallback`, `--test-quit`, `--stop-port`,
  `--open-url`, `--log-path` and `--version` with no display attached.
- **Build tooling** — `build.sh` (compile, icon generation, `Info.plist`
  stamping, ad-hoc codesign), a `Makefile` with `help`/`build`/`run`/`install`/
  `uninstall`/`verify`/`clean`/`version`/`log`, and `scripts/verify.sh`.

### Known limitations

- `Start at Login` was not exercised end-to-end in the original environment,
  because the bundle lived in the repository and registering would have created
  a login item pointing there. The menu reflects the real `SMAppService` status.
- Browser detection only checks the four canonical `/Applications` paths.
- Ownership is tracked in memory only; after a crash a previously owned instance
  becomes an attached instance and is stopped via `pi-web stop`.
- The build is ad-hoc signed, not notarised, so a downloaded copy needs
  Gatekeeper approval on first launch.

[Unreleased]: https://github.com/bestxia0/pi-web-desktop-macos/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/bestxia0/pi-web-desktop-macos/releases/tag/v0.7.0
[0.6.0]: https://github.com/bestxia0/pi-web-desktop-macos/releases/tag/v0.6.0
[0.5.0]: https://github.com/bestxia0/pi-web-desktop-macos/releases/tag/v0.5.0
