# Architecture

Pi Web Desktop is a menu bar **launcher** for a local `pi-web` server. It owns
no server: its job is to detect, start, open and stop the `pi-web` process, and
to make that visible in the menu bar. The GUI presents the UI in its own
**single native `NSWindow`** (`AppWindowController`) with a native tab strip —
each tab is an independent `WKWebView` loaded at its own pi-web URL. Chrome app
mode survives only as the fallback for the headless `--open-url` flag and
`--resolve`.

```
  right ⌥ ──► HotKeyMonitor (CGEvent tap / NSEvent monitors)
                    │ toggles
                    ▼
                 ┌──────────────────────────┐      ┌────────────────────────────┐
   menu bar  ◄───┤ MenuController           │─────►│ AppWindowController        │
                 │ (AppKit, NSStatusItem)   │ show │ (single NSWindow + tab bar)│
                 └───────────────┬──────────┘      └────────────────────────────┘
                                 │ reads state / calls actions
                 ┌───────────────▼──────────────────────────┐
                 │ StatusController   (orchestration, state)│
                 └──┬────────┬────────┬─────────┬───────────┘
                    │        │        │         │
        ┌───────────▼──┐ ┌───▼─────┐ ┌▼──────┐ ┌▼──────────────┐
        │ RunRecordStore│ │PortPlanner│ │Process│ │PiWebCommands │
        │  (detection) │ │ (ports)  │ │Manager│ │(attached stop)│
        └───────┬───────┘ └──────────┘ └───┬───┘ └──────┬───────┘
                │                          │            │
     <agentDir>/pi-web-run/*.json    spawned child   pi-web stop --port N
```

All blocking work — reading records, HTTP probes, spawning, waiting, signalling
— runs on the private serial queue `StatusController.work`. State is published
back to the main queue through `publish(_:)`, which notifies `onChange` and
triggers `MenuController.render()`.

## Module map

`Sources/` is a single flat directory, because `build.sh` compiles it with the
glob `"$ROOT"/Sources/*.swift`. Subdirectories would silently drop out of the
build.

| File | Responsibility |
| --- | --- |
| `main.swift` | Process entry point. Parses the headless flags, applies `--port` / `PI_WEB_DESKTOP_PORT` to `AppConfig.preferredPortOverride`, implements the headless modes (`runProbe`, `runTestCycle`, `runTestFallback`, `runStopPort`, `runTestQuit`), holds the `SingleInstanceLock`, and otherwise starts `NSApplication` with `AppDelegate` in `.accessory` activation policy. `AppDelegate` wires up the `com.piweb.desktop.activate` observer and calls `start(openWhenReady:)` on launch. |
| `AppConfig.swift` | Constants and path resolution: default port `30141`, fallback base `30151`, host `127.0.0.1`, bundle id, and the agent-directory expansion (`PI_CODING_AGENT_DIR` with `~` / `~/` / `file://` handling, else `~/.pi/agent`). Also the log file, support directory and lock file paths. Mirrors pi-web's `bin/run-records.js` `getAgentDir()` so both read the same records. |
| `StatusController.swift` | The orchestrator. Owns `Phase` (`stopped` / `starting` / `running` / `stopping` / `failed`), the human-readable `detail`, `activeURL`, `ownedPid`, `attached`, `liveInstances` and `lastError`. Implements `refresh`, `start`, `stop`, `stopInstance`, `openWindow` and `stopForQuit`. Decides owned-vs-attached per instance and always re-detects after a stop. |
| `MenuController.swift` | Builds the `NSStatusItem` menu and icon. Owns `updateIcon()` (SF Symbol + `Pi` title, tinted by phase), `buildMenu()`, the per-instance stop submenu wiring, the `AppWindowController`/`HotKeyMonitor` items, and `revealMenu()` (used by the activate notification). Logs a `menu build:` line describing the menu it actually built — the regression evidence that the version row exists and is last. |
| `AppWindow.swift` | Owns the single native `NSWindow` and its tab strip. One `WKWebView` per tab, each loaded at its own pi-web URL; `show(url:)` creates the window once, restores persisted tabs (rewriting their URLs onto the current base) or creates a first tab, then only focuses. `toggle(url:)` hides when the window is visible *and* key, otherwise shows; `windowShouldClose` orders the window out, while ⌘W closes the *current tab* and hides the window when it was the last. Also implements `WKNavigationDelegate` (external links to the browser) and `WKUIDelegate` (`window.open` → native tab). `toggleAction(isVisible:isKey:)` is pure and covered by `--self-test`. |
| `TabBar.swift` | The native tab strip: `TabPalette` (the 11 adaptive colours, index 0 = 无颜色), the `TabBarDelegate` protocol, `TabBarView` (34pt horizontally scrolling strip + trailing `+`) and `TabItemView` (colour dot / truncating title / borderless close button + right-click colour menu). AppKit-only; the pure arithmetic lives in `TabSupport`. |
| `TabStore.swift` | `TabRecord` and the `TabStore` JSON codec over `UserDefaults` (`PiWebTabs` / `PiWebTabsSelected`). Missing or corrupt data degrades to "no tabs". |
| `TabSupport.swift` | Pure, AppKit-free tab helpers shared by `AppWindowController` and `--self-test`: `rewriteBase` (scheme/host/port swap preserving path+query), `indexAfterClose`, `neighborIndex`, `newTabURL`. |
| `MainMenu.swift` | Builds the real `NSApp.mainMenu` (App / 编辑 / 标签页 / 浏览). The browser-style shortcuts (⌘T, ⌘W, ⌘1…9, ⌘⇧[ / ⌘⇧], ⌘[ / ⌘], ⌘R) and the nil-target Edit selectors must live here: a status-item menu's key equivalents only fire while that menu is open. |
| `HotKeyMonitor.swift` | The right-Option global hotkey. `classify(keyCode:flags:)` is pure (right Option `61` only; left Option `58` is ignored) and `start()` prefers a listen-only `CGEvent` tap over `NSEvent` global/local monitors. Exposes the Input Monitoring / Accessibility checks, the System Settings deep link, `tapDisabledCount` (event-tap disable events) and `resetInputMonitoringGrant()` (`tccutil reset ListenEvent`), and never consumes events. |
| `ProcessManager.swift` | Resolves, spawns and stops the child. `start(port:spec:childPATH:)` returns the child pid; `waitForReady(url:timeout:)` polls until the URL answers; `stop()` performs the `SIGINT → 10s → SIGTERM → 5s → SIGKILL` escalation. Tracks `ownedPid` / `hasOwnedProcess`. |
| `RunRecords.swift` | Detection. `RunRecordStore(directory:)` loads every `*.json`, and `detectLiveInstances()` classifies each record: liveness via `kill(pid, 0)` (`EPERM` counts), then ownership via `ps -ww -p <pid> -o args=`, and only then an HTTP probe of the recorded URL. Read-only: it never deletes a record. |
| `PortPlanner.swift` | `isFree(port:)` does a `bind()` probe on `127.0.0.1`; `findFreePort(startingAt:)` scans upward (bounded); `ephemeralPort()` asks the kernel by binding to port `0`. Needed because `pi-web` has no fallback of its own. |
| `EnvironmentResolver.swift` | Recovers the login shell's `PATH` and `pi-web` location (`/bin/zsh -lic`, 5s timeout), caches them, and assembles the `PATH` handed to the child — including every directory a `node` binary was found in, so `#!/usr/bin/env node` shebangs work. Also holds `systemDefaultPath`, used by `--gui-path`. |
| `HTTPProbe.swift` | Minimal URL liveness check: any HTTP status counts as alive, with a short timeout. |
| `BrowserOpener.swift` | `openAppMode(url:)` returns `.appMode(command)`, `.defaultBrowser(command)` or `.failed(reason)`. Tries the four canonical Chrome-family paths in `/Applications`, then falls back. `plannedCommand(url:)` exposes the decision without executing it (used by `--resolve`). Retained for the headless `--open-url` flag and as the `openWindow()` fallback when no GUI handler is installed. |
| `PiWebCommands.swift` | Builds and runs the upstream attached-stop command, `pi-web stop --port N`, with the resolved login-shell `PATH` and a timeout. Returns exit code / timed-out / launched, plus captured output. |
| `LoginItem.swift` | `SMAppService.mainApp` wrapper: `currentState()` (`enabled`, `disabled`, `requiresApproval`, `notFound`, `unavailable(reason)`), `setEnabled(_:)`, `isEnabled()`, `isSupported`. |
| `Preferences.swift` | UserDefaults-backed preferences in the bundle domain — `stopAttachedOnQuit` (`PiWebStopAttachedOnQuit`, default `true`) and `hotKeyEnabled` (`PiWebHotKeyEnabled`, default `true`). |
| `StopMenu.swift` | Pure, testable model for the multi-instance stop submenu: given the live instances and the owned pid, produce the titles (`<url>  pid <pid>（本壳）` for the owned one). No AppKit, so `--self-test` can assert on it. |
| `VersionInfo.swift` | Composes the display version from `CFBundleShortVersionString` + `PiWebVersion` read out of the bundle, prefixed with `V`, falling back to `V0.0.0-dev` outside a bundle. Single source of truth for the menu row and `--version`. |
| `Logger.swift` | Append-only logger writing to `~/Library/Logs/PiWeb/pi-web.log`, with `mirrorToStderr` for the headless modes. The spawned child's stdout/stderr are redirected to the same file. |
| `SelfTest.swift` | `--self-test`: assertions over record parsing, stale/orphaned records, the stop menu model, the stop command, PATH/node resolution and version composition. Exits non-zero on failure. |

## Startup sequence

1. `main.swift` parses the arguments. If `--port` / `PI_WEB_DESKTOP_PORT` is
   present it sets `AppConfig.preferredPortOverride`. A headless flag short-
   circuits here; otherwise `runGUI()` is called.
2. `runGUI()` takes an exclusive `flock` on
   `~/Library/Application Support/PiWeb/launcher.lock`. If the lock is held, the
   process posts `com.piweb.desktop.activate`, asks the existing app to activate
   and exits — this is the "second launch" path.
3. `PiWebResolver.resolveEnvironment()` runs once and is logged: the resolved
   `pi-web`, its source (explicit / login-shell / scan), and the child `PATH`.
4. AppKit starts with `.accessory` activation policy, so there is a menu bar item
   and no Dock icon.
5. `MenuController` subscribes to `controller.onChange` and renders the initial
   menu. The status icon starts in the `stopped`/`尚未探测` state.
6. `AppDelegate.applicationDidFinishLaunching` registers the
   `com.piweb.desktop.activate` observer and calls
   `controller.start(openWhenReady: true)`.

## Start sequence

1. `StatusController.start` publishes `starting` / `正在选择端口…` and hands off to
   `work`.
2. **Detect first.** `RunRecordStore.detectLiveInstances()` runs again. If
   anything is live the controller attaches: it republishes state, opens the
   window when asked, and returns. A second instance is never started.
3. Resolve the environment, then choose the port: `isFree(preferred)`, else
   `findFreePort(from: 30151)`, else `ephemeralPort()`. None available → `failed`
   with `找不到可用端口`.
4. `ProcessManager.start(port:spec:childPATH:)` spawns
   `pi-web --port <N> --no-open` with the assembled `PATH`; the pid is published
   immediately so the menu shows `启动中 pid <pid> @ <url>…`.
5. `waitForReady(url:timeout: 60)` polls the URL. On success the controller
   publishes `running` and opens the window when requested; `pi-web` writes its
   run record around the same moment, so a `scheduleDetection()` afterwards picks
   the canonical record up. On failure the child is stopped and the phase becomes
   `failed` with the reason surfaced in the menu as `错误：…`.

## Stop sequence

`stopInstance(_:)` publishes `stopping` and branches on ownership, determined by
`isOwned(_:)` (does the instance's launcher pid or stop pid equal `ownedPid`?).

**Owned path** — `ProcessManager.stop()`:

1. `SIGINT`. Next.js keeps SSE connections open and its
   `instrumentation-node.ts` closes them on `SIGINT`/`SIGTERM`, so this is the
   graceful signal.
2. Wait up to 10s.
3. `SIGTERM`, wait up to 5s.
4. `SIGKILL`.

**Attached path** — `PiWebCommands.stop(port:resolved:timeout: 30)`:

1. Run `pi-web stop --port N` with the resolved login-shell `PATH`, so `node` and
   `pi-web` resolve.
2. `--port` is always passed: without it upstream errors out when several
   instances are running.
3. Upstream handles orphaned records, pid-reuse validation and run-record
   cleanup, so that logic is never reimplemented here.
4. This is destructive, so the menu asks for confirmation first.

Either way, `detectNow()` runs afterwards so the menu reflects reality, and a
failure republishes `failed` with the command's output as `lastError`.

**On quit**, `stopForQuit()` stops the owned child, then — when
`Preferences.stopAttachedOnQuit` is on (the default) — stops every attached
instance through the same upstream command. `onlyPorts` and
`stopAttachedOverride` exist so `--test-quit` can scope the behaviour to a
throwaway port.

## Design notes

**Why detection is read-only.** The shell only ever *reads* run records. It
never prunes them. Deleting a record is a claim about who owns a process, and
this shell deliberately avoids making that claim: the upstream `pi-web` CLI
already does cleanup correctly as part of `pi-web stop`, and a launcher that
deletes records it does not fully understand risks orphaning a healthy server.

**Why the ownership check comes before the URL probe.** A stale record can point
at a URL that still answers, because a *different* instance now owns that port.
Probing first would report a live instance that does not exist. So the order is
fixed: record → liveness → ownership → HTTP.

**The in-memory ownership tradeoff.** `ownedPid` lives in the process, not on
disk. That keeps the shell stateless and removes any risk of a stale lock file,
at one cost: if the shell crashes while its child is running, the child survives
and the restarted shell has no memory of it. It is then treated as an *attached*
instance — still visible, still stoppable, just through `pi-web stop --port N`
(and therefore behind a confirmation prompt) instead of a direct signal. The
aftermath is indistinguishable from an instance the user started in a terminal,
which is a reasonable default.

**Why there is no dependency.** The app is `swiftc` against system frameworks
only. It has no package manifest to resolve, no lockfile to drift, and no supply
chain beyond Apple's SDK — which matters for a small tool that spawns processes
on your behalf. Keeping it universal does not change that: `build.sh` runs one
`swiftc` pass per architecture and joins them with `lipo`, both of which ship
with the Xcode Command Line Tools.

**Why the build is universal.** `build.sh` compiles `arm64` and `x86_64`
(`PI_WEB_ARCHS` overrides the list) and `lipo`s the slices into one Mach-O.
The app claims macOS 13+ with no architecture qualifier, and an arm64-only
bundle simply refuses to launch on an Intel Mac — Rosetta translates `x86_64`
on Apple silicon, never the other way round. `scripts/verify.sh`, CI and the
release workflow all fail the build when a slice is missing. Cross-compiling
`x86_64` on Apple silicon can print a benign `libswiftCompatibilityPacks.a`
linker warning, because that CLT back-deployment library has no x86_64 slice;
the Intel side is really executed by the `macos-13` CI runner.

**Why releases are cut from a tag.** `make release` (`scripts/release.sh`)
refuses a dirty tree or an existing tag, runs `scripts/check-docs.sh` and the
verification suite, then pushes `v<VERSION>`. GitHub Actions builds the bundle
from that tag, asserts it is universal, and publishes `PiWeb-<version>.zip`.
Nothing is uploaded from a developer machine and no build output is committed;
`VERSION` stays the single source of truth for the version and the release.
`scripts/check-docs.sh` exists because three separate drifts shipped at least
once each (a stale version example, README language drift, and unreferenced
files under `docs/images`), and a human reading a diff is not a reliable gate.

**One window, many tabs.** There is exactly one `NSWindow`
(`AppWindowController`) for the whole process; inside it, each tab is its own
`WKWebView`. `打开 Pi Web`, the right-Option toggle and the launch path all
route through `show(url:)`, which creates the window on first use, restores the
persisted tabs (rewriting their URLs onto the current pi-web base) or creates a
first tab, and then only focuses on later calls. Closing the window (red button)
hits `windowShouldClose` and merely `orderOut`s it; ⌘W instead closes the
*current tab*, and closing the last tab also hides the window. Because the app
is `.accessory` (`LSUIElement`), showing a key window requires an explicit
`NSApp.activate(ignoringOtherApps: true)` before `makeKeyAndOrderFront`.

**Tabs vs sessions.** A pi-web "session" is a query-parameter view of the one
client-rendered route (`/?session=<id>`), not a separate document. A tab is a
separate `WKWebView` at its own URL, so two tabs can show two sessions at once
while sharing only the sidebar/localStorage layout keys. Manually created tabs
load the session list (scoped to the active tab's `cwd`), never a new session:
the launcher must not mutate server state on its own. `WKUIDelegate.createWebView`
captures pi-web's own `window.open('?session=<id>')` and turns it into a native
tab, but that is a convenience — manual creation works without it.

**Why the main menu owns the shortcuts.** A `NSStatusItem` menu's key
equivalents are only dispatched while that menu is open, so ⌘T / ⌘W / ⌘1…9 /
⌘⇧[ / ⌘⇧] and the Edit menu cannot live there. `MainMenu.swift` builds a real
`NSApp.mainMenu` for them and targets the tab actions at `AppWindowController`
directly; the status menu mirrors the tab actions without key equivalents.

**Right Option only.** A modifier-only global hotkey cannot be registered with
Carbon's `RegisterEventHotKey`, so `HotKeyMonitor` uses a listen-only
`CGEvent` tap (`flagsChanged`) and falls back to `NSEvent` global/local monitors
when the tap cannot be created. It classifies keyCode `61` (right Option) as
pressed/released and ignores keyCode `58` (left Option) and everything else, and
the callback always returns the untouched event, so right Option keeps working
as a normal modifier in other apps. macOS gates this behind **Input
Monitoring** (and, for some setups, Accessibility): the menu shows a
"需要「输入监控」权限" helper item while the grant is missing, and a rebuild can
reset an ad-hoc-signed app's grant.

**Ad-hoc signing vs TCC.** macOS binds the Input Monitoring grant to the code
signature. An ad-hoc signed bundle (`codesign --sign -`, the default when no
certificate exists) gets a new `CDHash` on every build, and even moving the
`.app` changes the identity, so TCC's stored requirement stops matching while
the System Settings checkbox can still appear on. `build.sh` resolves a stable
identity (`$PI_WEB_SIGN_IDENTITY` → the exact `PiWeb Local Signing` certificate
→ ad-hoc fallback) and records the resulting `CDHash`; the ad-hoc path warns
explicitly. `HotKeyMonitor.resetInputMonitoringGrant()` and
`scripts/install.sh --reset-permissions` clear the stale entry so it can be
re-granted, and the `menu build:` line reports `tapDisabled=<n>` so a tap that
macOS keeps disabling is visible in the log.

**Data sources at a glance**

| What | Where |
| --- | --- |
| Run records | `<agentDir>/pi-web-run/<launcherPid>.json`, `agentDir` = `PI_CODING_AGENT_DIR` or `~/.pi/agent` |
| Preferences | UserDefaults, bundle domain `com.piweb.desktop` |
| Log | `~/Library/Logs/PiWeb/pi-web.log` |
| Single-instance lock | `~/Library/Application Support/PiWeb/launcher.lock` |
