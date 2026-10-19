# Pi Web Desktop (macOS)

A tiny native macOS menu bar launcher for the **pi-web** web UI: it detects, reuses, starts, opens and stops a local `pi-web` instance without a terminal.

**English** · [简体中文](README.zh-CN.md)

[![CI](https://github.com/bestxia0/pi-web-desktop-macos/actions/workflows/ci.yml/badge.svg)](https://github.com/bestxia0/pi-web-desktop-macos/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: macOS 13+](https://img.shields.io/badge/Platform-macOS%2013%2B-lightgrey.svg)](#requirements)
[![Swift 5](https://img.shields.io/badge/Swift-5-orange.svg)](#requirements)
[![Zero dependencies](https://img.shields.io/badge/dependencies-0-brightgreen.svg)](#requirements)
[![Latest release](https://img.shields.io/github/v/release/bestxia0/pi-web-desktop-macos?display_name=tag)](https://github.com/bestxia0/pi-web-desktop-macos/releases)

![The Pi Web Desktop menu open in the macOS menu bar](docs/images/menu-open.png)

## What it is / What it is not

| What it is | What it is not |
| --- | --- |
| A native Swift + AppKit `NSStatusItem` menu bar app (`LSUIElement`, no Dock icon) | A webview or Electron shell — it embeds no browser engine |
| A **launcher only**: it finds, starts and stops the `pi-web` CLI for you | A bundler — it never ships Node, npm or the `pi-web` package |
| A front end for the upstream `pi-web` service on `127.0.0.1` | A replacement for `pi-web`; the CLI and `node` must already be installed |
| A **zero-dependency** app built by `swiftc` alone | Dependent on SPM, CocoaPods or any third-party package |

> **Runtime dependency:** a globally installed `pi-web` CLI plus `node`. The app is a launcher only — it does not embed a webview and does not bundle Node.

## Features

- **Menu bar native** — a single `NSStatusItem` with an SF Symbol plus a short `Pi` title, coloured by state (green running / orange busy / red failed), and no Dock icon.
- **Detect, then reuse** — on every launch it runs the same run-record contract as `pi-web` and attaches to a healthy existing instance instead of starting a second one.
- **Start on demand** — spawns `pi-web --port <N> --no-open` on a free port, waits (up to 60s) until the URL answers, then opens the UI.
- **Browser app mode** — opens the UI in a Chrome-family browser's app mode (no address bar), falling back to the default browser.
- **Two stop paths** — the instance it owns gets a `SIGINT → SIGTERM → SIGKILL` escalation; an attached instance is stopped through upstream `pi-web stop --port N` after a confirmation prompt.
- **Port fallback** — `bind()`-probes `30141`, scans upward from `30151`, then falls back to a kernel-assigned ephemeral port, because `pi-web` itself has no fallback.
- **Finder-friendly PATH resolution** — recovers the login shell's `PATH` and `pi-web` location once, so a GUI launch can find Homebrew's `pi-web` and `node`.
- **Start at Login** — an `SMAppService.mainApp` toggle that always reflects the real system status.
- **Stop-attached-on-quit toggle** — decides whether quitting also stops instances that were not started by this shell.
- **Headless verification** — the same binary runs `--self-test`, `--probe`, `--test-cycle`, `--test-fallback`, `--resolve`, `--stop-port` and `--test-quit` with no display.
- **Single source of truth for the version** — read from the `VERSION` file plus the build date at build time; nothing is hardcoded in Swift.

## Screenshots

![Pi Web Desktop menu bar icon](docs/images/menubar-icon.png)
*The menu bar icon: an SF Symbol plus the `Pi` title, tinted by launcher state.*

![The menu open with all items visible](docs/images/menu-open.png)
*The full menu: open, start, stop, refresh, logs, Start at Login, quit behaviour and the version row.*

![The Pi Web Desktop application icon](docs/images/app-icon.png)
*The app icon in Finder / Launchpad, generated at build time from `Resources/AppIcon.jpg`.*

![The pi-web web UI running locally](docs/images/piweb-ui.png)
*The `pi-web` UI opened in the browser's app mode.*

## Requirements

- **macOS 13.0 or later** (`LSMinimumSystemVersion` is `13.0`; `SMAppService` needs macOS 13).
- **Xcode Command Line Tools** providing `swiftc` — the only build tool required.
- To actually launch a server: a **globally installed `pi-web` CLI** and **`node`** on your `PATH`.

No SPM, no CocoaPods, no third-party packages. The app compiles with `swiftc` alone against the system frameworks (Foundation, AppKit, ServiceManagement, UniformTypeIdentifiers).

## Quick start

```sh
git clone https://github.com/bestxia0/pi-web-desktop-macos.git
cd pi-web-desktop-macos
./build.sh                 # swiftc + assemble build/PiWeb.app + ad-hoc sign
open build/PiWeb.app
```

`./build.sh --run` builds and launches in one step. The app then appears in the menu bar and, on first launch, detects/attaches or starts a `pi-web` instance and opens the UI.

## Installation to /Applications

`SMAppService.mainApp` needs a stable bundle location, so install the app to `/Applications` before enabling Start at Login:

```sh
./scripts/install.sh       # build, copy to /Applications/PiWeb.app, re-register
# or, equivalently:
make install
```

`make uninstall` removes `/Applications/PiWeb.app`. The developer shortcuts are `make help`, `build`, `run`, `install`, `uninstall`, `verify`, `clean`, `version` and `log`.

## Usage

Menu items are shown in Simplified Chinese. The table below lists them top to bottom.

### Menu reference

| Menu item | What it does | State / conditions |
| --- | --- | --- |
| `Pi Web — <detail>` | Status header at the top of the menu; shows the current phase, active URL/version or instance count. | Always present, disabled (display only). |
| `错误：<message>` | Surfaces the most recent failure (newlines flattened to one line). | Appears only when there is an error. |
| 打开 Pi Web | Opens the active URL in a Chrome/Edge/Brave/Arc app-mode window (no address bar), otherwise the default browser. Key equivalent `O`. | Enabled only while a live instance URL is known. |
| 启动 Pi Web | Detects first; attaches to an existing instance, otherwise starts one with `--no-open` on a free port and opens it. Key equivalent `S`. | Enabled only when the launcher is stopped or failed. |
| 停止 Pi Web | Stops the instance. Owned → `SIGINT → 10s → SIGTERM → 5s → SIGKILL`; attached → a confirmation prompt, then upstream `pi-web stop --port N`. | Enabled when exactly one live instance. With several it becomes `停止 Pi Web（N 个实例）` with a per-instance submenu (`<url>  pid <pid>（本壳）` for owned). |
| 刷新状态 | Re-runs detection and republishes the menu. Key equivalent `R`. | Always enabled. |
| 打开日志 | Opens `~/Library/Logs/PiWeb/pi-web.log`. Key equivalent `L`. | Always enabled. |
| 在 Finder 中显示日志 | Reveals the log file in Finder. | Always enabled. |
| 开机自启 | Registers/unregisters the app as a login item via `SMAppService.mainApp`. | Checkbox reflects the real state; title becomes `开机自启（需在系统设置中批准）` when approval is required and `开机自启（App 需位于 /Applications）` when the bundle is not installed; disabled with `开机自启不可用：<reason>` when unsupported. |
| 退出时同时停止后台 pi-web | Toggles whether quitting also stops attached instances. Persisted in UserDefaults key `PiWebStopAttachedOnQuit`. | Checkbox, default **on**. Always enabled. |
| 退出 Pi Web | Stops the owned child (and, when the toggle is on, every attached instance), then quits. Key equivalent `Q`. | Always enabled. |
| `V<semver>-<builddate>` | The launcher version, e.g. `V0.5.0-20261019`. | Always present, disabled (display only), last row. |

### Status icon

The status icon is drawn by `MenuController.updateIcon()`: an SF Symbol plus the short title `Pi`, tinted per state.

| State | Symbol | Colour |
| --- | --- | --- |
| Running | `play.circle.fill` | Green |
| Starting / stopping (busy) | `arrow.triangle.2.circlepath` | Orange |
| Stopped | `power.circle.fill` | Label colour |
| Failed | `exclamationmark.triangle.fill` | Red |

## Headless and verification flags

The same binary supports headless flags, so detection, start/stop and port fallback can be verified without a display:

```sh
BIN=build/PiWeb.app/Contents/MacOS/PiWeb

$BIN --self-test                                # assertions: record parsing + stale-record logic + PATH/node resolution
$BIN --probe                                    # print every run record with its classification and the attach/start decision
$BIN --test-cycle --port 30199                  # start on 30199, wait ready, stop
$BIN --test-cycle --occupy --port 30199         # occupy 30199, then start on the fallback (30151)
$BIN --test-cycle --gui-path --port 30199       # simulate a LaunchServices (system-default) PATH end-to-end
$BIN --test-fallback --port 30199               # show which port the planner picks when 30199 is busy
$BIN --open-url http://127.0.0.1:30141          # open the app-mode window
$BIN --resolve [--gui-path]                     # print resolved pi-web + source + child PATH + node
$BIN --stop-port 30199                          # stop one instance via upstream `pi-web stop --port 30199`
$BIN --test-quit --port 30199                   # exercise stopForQuit (attached stopped)
$BIN --test-quit --port 30199 --keep-attached   # same, but with the toggle off
$BIN --port 30199                               # override the preferred port
$BIN --version                                  # print the exact string the menu's bottom row shows
$BIN --log-path                                 # print the log file path
```

> `--stop-port`, `--test-cycle`, `--test-fallback` and `--test-quit` are for **verification only** and are not part of the normal menu flow. `--test-cycle` never touches the `30141` instance: it only signals the child it spawned.

### Flag reference

| Flag | Purpose | Notes |
| --- | --- | --- |
| `--self-test` | Run the built-in assertions (record parsing, stale records, orphan handling, PATH/node resolution, stop command, stop menu, version composition). | Exits non-zero if any check fails. Verification only. |
| `--probe` | Print every run record with its step-2/step-3 classification and the attach/start decision. | Read-only; never deletes records. Verification only. |
| `--test-cycle [--occupy] [--gui-path]` | Full start → ready → stop cycle against a throwaway instance. | `--occupy` pre-occupies the preferred port to exercise fallback; `--gui-path` forces the system-default PATH. Verification only. |
| `--test-fallback` | Occupy the preferred port and report the fallback port the planner would pick. | Verification only. |
| `--open-url <url>` | Open a URL in app mode, or the default browser, and print the command used. | — |
| `--resolve [--gui-path]` | Print the resolved `pi-web`, its source, the child PATH, `node`, the run dir and the browser plan. | `--gui-path` bypasses every cache and forces a probe. |
| `--stop-port <n>` | Stop one instance through upstream `pi-web stop --port n` and print before/after detection. | Verification only. |
| `--test-quit [--keep-attached]` | Exercise `stopForQuit`, scoped to `--port`. | `--keep-attached` simulates the toggle being off. Verification only. |
| `--port <n>` | Override the preferred port. | Also settable via `PI_WEB_DESKTOP_PORT`; `--port` wins. |
| `--version` | Print the exact version string shown in the menu's bottom row. | — |
| `--log-path` | Print the log file path. | — |

## How detection works (reused pi-web contract)

Run records live at `<agentDir>/pi-web-run/<launcherPid>.json`, where `agentDir` is `PI_CODING_AGENT_DIR` (expanded `~` / `~/` / `file://`) or `~/.pi/agent`. This shell reuses pi-web's exact format and mirrors `bin/run-records.js`:

1. Read every `*.json`.
2. Validate `pid` is alive (`kill(pid,0)`; `EPERM` counts) **and** that the process is ours (`ps -ww -p <pid> -o args=`; launcher args contain `pi-web`, next args contain `next`). A record whose launcher is gone but whose `nextPid` is alive is an *orphaned* record.
3. **Only then** probe the URL (any HTTP status counts, 2s timeout).

Order matters: a stale record can point at a URL that still answers because a different instance owns that port, so the process check must come first.

This shell deliberately makes detection **read-only** — unlike pi-web's own `listRunRecords`, it never deletes stale records during detection. Stale records are simply ignored.

## Port selection

`pi-web` has no port fallback: it exits with "Next.js exited unexpectedly" when the port is taken. The shell therefore picks the port before spawning:

1. `bind()`-probe `127.0.0.1:30141` — use it if free.
2. Otherwise scan upward from `30151` (up to 500 attempts) for the first free port.
3. Otherwise ask the kernel for an ephemeral port by binding to port `0`.

## Stopping

Two paths, decided per instance:

- **Owned** (spawned by this shell): Next.js keeps SSE connections open and its `instrumentation-node.ts` closes them on SIGINT/SIGTERM. The shell sends **SIGINT first**, waits up to 10s, then SIGTERM (5s), then SIGKILL.
- **Attached** (started elsewhere): the shell delegates to the upstream command `pi-web stop --port N`, always with `--port` (without it, upstream errors out when several instances run). Upstream already handles orphaned records, pid-reuse ownership validation and run-record cleanup, so the kill logic is never reimplemented here. The resolved login-shell PATH is used so `node` and `pi-web` resolve. This path is destructive, so it asks for confirmation first.

After any stop the shell re-detects and republishes state, so the menu always reflects reality. Failures (timeout / non-zero exit) are surfaced as a red failed state plus the command's output.

On quit, the `退出时同时停止后台 pi-web` toggle decides whether attached instances are stopped too; the owned child is always stopped.

| Path | Mechanism | Escalation | Confirmation |
| --- | --- | --- | --- |
| Owned | Direct signals to the spawned child | `SIGINT` (10s) → `SIGTERM` (5s) → `SIGKILL` | None |
| Attached | `pi-web stop --port N` | Handled upstream | Yes, a modal warning |

## Logging

The append-only log lives at `~/Library/Logs/PiWeb/pi-web.log`. The spawned `pi-web`'s stdout and stderr are redirected into the same file, and startup failures leave their reason in its tail. The menu exposes both `打开日志` and `在 Finder 中显示日志`; `make log` tails the file.

## App icon

The bundle icon comes from `Resources/AppIcon.jpg`, converted by `build.sh` with `sips` + `iconutil` into `Contents/Resources/PiWeb.icns` (all ten required sizes, `CFBundleIconFile` = `PiWeb`).

The source is only 282x267 and not square, so it is **centre-cropped** to a square first: no stretching and no padded colour bands. Because the source is small, the 512 and 1024 entries are upscaled and look soft. Drop a square source of at least 1024x1024 in at the same path and rebuild to fix that; no code change is needed.

This only changes the *app* icon (Finder, Launchpad, Get Info). The **menu bar status icon is untouched** — it stays the SF Symbol plus `Pi` text that `MenuController.updateIcon()` draws, one appearance per state.

## Version

`V0.5.0-20261019` is shown as the menu's last row, below `退出 Pi Web`, as a disabled display-only item. It comes from one place:

| Source | Value | Written to Info.plist as |
| --- | --- | --- |
| `VERSION` file | `0.5.0` | `CFBundleShortVersionString` |
| `date +%Y%m%d` at build time | `20261019` | `CFBundleVersion` |
| both, joined | `0.5.0-20261019` | `PiWebVersion` |

So bumping the version is: edit `VERSION`, run `./build.sh`. Nothing is hardcoded in Swift and the date is never hand-maintained.

`VersionInfo` reads the key back from the bundle and prefixes `V`; outside a built bundle it falls back to `V0.0.0-dev` instead of showing blank. `--version` prints the identical string. Any future update check would compare `CFBundleShortVersionString` against the latest published release; no network code exists yet, by design.

## Configuration and preferences

### UserDefaults keys

Stored in the bundle domain `com.piweb.desktop`. Set them with `defaults write com.piweb.desktop <key> <value>`.

| Key | Type | Default | Effect |
| --- | --- | --- | --- |
| `PiWebStopAttachedOnQuit` | Bool | `true` | Whether `退出 Pi Web` also stops attached instances. Toggled in the menu. |
| `PiWebExecutablePath` | String | unset | Explicit path to the `pi-web` executable; highest discovery precedence. |
| `PiWebLoginShellPATH` | String | unset | Cached `PATH` captured from the one-time login-shell probe. |
| `PiWebLoginShellPiWeb` | String | unset | Cached path to `pi-web` captured from the login shell. |

### Environment variables

Because a GUI launch does not inherit a login shell, the app asks the login shell once with `/bin/zsh -lic 'command -v pi-web; echo "$PATH"'` (5s timeout), caches the result in UserDefaults, and falls back to scanning `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/.bun/bin`, `~/.npm-global/bin` plus `npm prefix -g`. Explicit paths always win.

| Variable | Default | Effect |
| --- | --- | --- |
| `PI_WEB_DESKTOP_EXECUTABLE` | unset | Explicit `pi-web` executable; wins over discovery (after `PiWebExecutablePath`). |
| `PI_CODING_AGENT_DIR` | `~/.pi/agent` | Agent directory holding `pi-web-run/`; `~`, `~/` and `file://` are expanded. |
| `PI_WEB_DESKTOP_PORT` | `30141` | Preferred port override; `--port` wins over this. |
| `HOME` | user home | Base for `~` expansion and the log / support directories. |

On a GUI launch the app detects first, then attaches or starts, and opens the window; it never starts a second instance. Double-clicking an already-running app posts a `com.piweb.desktop.activate` distributed notification that pops the running instance's menu, so the action is never silent.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| The app launches but there is no menu bar icon | The icon is hidden by menu bar overflow / the notch, or another instance is already running and holds the single-instance lock. | Check the menu bar overflow area and Activity Monitor for `PiWeb`; the running instance can be revealed by launching the app again (it posts `com.piweb.desktop.activate`). Inspect `~/Library/Logs/PiWeb/pi-web.log`. |
| "pi-web not found" after launching from Finder | LaunchServices gives the app only `/usr/bin:/bin:/usr/sbin:/sbin`, and the login-shell probe failed or timed out (slow `.zshrc`). | Install `pi-web` globally, verify with `/bin/zsh -lic 'command -v pi-web'`, then set `PiWebExecutablePath` or `PI_WEB_DESKTOP_EXECUTABLE`. Diagnose with `--resolve` / `--probe`. |
| The preferred port is busy | `pi-web` itself has no fallback and dies with "Next.js exited unexpectedly"; the shell has already fallen back. | Let the shell use `30151+` or an ephemeral port; check the active URL in the status header. Find and stop stale instances with `停止 Pi Web` or `--probe`. |
| A second launch appears to do nothing | LaunchServices deduplicates bundle launches; the already-running instance receives the activate notification and pops its own menu. | Click the menu bar icon. If nothing appears, verify the running instance via the log and the status header. |
| The Start at Login item points into the repository | The `.app` bundle is not in `/Applications`, so `SMAppService.mainApp` registers the repo path. | Run `./scripts/install.sh` or `make install` first, then enable `开机自启`; the menu shows `开机自启（App 需位于 /Applications）` until then. |
| The pi-web UI opens in the default browser instead of app mode | None of the four canonical Chrome-family apps were found under `/Applications`. | Install Google Chrome, Microsoft Edge, Brave or Arc in `/Applications`, or accept the default browser. |

## Known limitations

- **Not tested:** `Start at Login` (`SMAppService.mainApp`) was not switched on in this environment, because the bundle currently lives in the repository and registering would create a login item pointing there. The menu reflects the real status returned by `SMAppService`.
- Browser detection only checks the four canonical `/Applications` paths (Chrome, Edge, Brave, Arc); a non-standard install location falls back to the default browser.
- Detection is read-only and never prunes stale records (by design). Note that the *attached* stop path invokes `pi-web stop`, and upstream prunes stale records as part of that command.
- The shell tracks ownership in memory only; after a shell crash, an instance it previously started becomes an attached instance on restart (still stoppable, now via `pi-web stop`).
- `--stop-port`, `--test-cycle`, `--test-fallback` and `--test-quit` are for verification and are not part of the normal menu flow.
- The on-screen menu pop-up triggered by a second launch was not captured in a screenshot under the headless test session (macOS did not render the programmatic pop-up for the accessory app); the reveal code path runs and the menu contents are covered by the `menu build:` log line and the self-test.

## Project layout

```text
pi-web-desktop-macos/
├── Sources/                    Swift sources compiled by swiftc (no SPM)
│   ├── main.swift              Entry point + headless verification modes + single-instance lock
│   ├── MenuController.swift    NSStatusItem menu, icon and menu actions
│   ├── StatusController.swift  Detect / start / stop orchestration and UI state
│   ├── ProcessManager.swift    pi-web resolution, child spawn, readiness, signal escalation
│   ├── RunRecords.swift        Run-record parsing, validation order and classification
│   ├── PortPlanner.swift       bind() probe, fallback scan and ephemeral port
│   ├── EnvironmentResolver.swift Login-shell probe and child PATH assembly
│   ├── BrowserOpener.swift     Chrome-family app-mode opening with default-browser fallback
│   ├── PiWebCommands.swift     Upstream `pi-web stop --port N` invocation
│   ├── LoginItem.swift         SMAppService.mainApp Start at Login
│   ├── Preferences.swift       UserDefaults-backed preferences
│   ├── StopMenu.swift          Testable model for the per-instance stop submenu
│   ├── VersionInfo.swift       VERSION + build-date composition and display
│   ├── Logger.swift            Append-only file logger
│   ├── AppConfig.swift         Constants and agent-directory resolution
│   ├── HTTPProbe.swift         HTTP liveness probe
│   └── SelfTest.swift          `--self-test` assertions
├── Resources/AppIcon.jpg       App icon source (centre-cropped at build time)
├── docs/
│   ├── ARCHITECTURE.md         Design notes for the launcher
│   └── images/                 Screenshots used by this README
├── scripts/
│   ├── install.sh              Build, copy to /Applications and re-register
│   ├── verify.sh               Headless verification suite (make verify)
│   └── capture-screenshots.sh  Regenerate the docs/images screenshots
├── .github/                    CI workflow (ci.yml) and issue templates
├── build.sh                    swiftc build, .app assembly and ad-hoc codesign
├── Makefile                    help / build / run / install / uninstall / verify / clean / version / log
├── VERSION                     Semantic version stamped into Info.plist
├── CHANGELOG.md                Release history
├── CONTRIBUTING.md             Contribution guide
├── SECURITY.md                 Security policy
├── CODE_OF_CONDUCT.md          Contributor Covenant
└── LICENSE                     MIT
```

`build/` is generated output and is not checked in.

## Development

```sh
./build.sh              # compile + assemble build/PiWeb.app + ad-hoc sign
./build.sh --run        # build and launch
make verify             # run the headless verification suite (scripts/verify.sh)
./scripts/verify.sh     # the same suite, directly
```

`make verify` builds the app and runs the headless modes described above. See [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution workflow and [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the design of detection, port selection, stopping and environment resolution. Release history lives in [CHANGELOG.md](CHANGELOG.md).

## Roadmap

- [ ] Notarised, signed release builds (Developer ID + `notarytool`).
- [ ] Update check against the latest GitHub release.
- [ ] Square 1024x1024 source icon to remove the soft upscaled 512/1024 entries.
- [ ] CI-run integration cycle (`--test-cycle`) on a macOS runner.
- [ ] Homebrew tap / cask.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) first, and report vulnerabilities per [SECURITY.md](SECURITY.md). Run `make verify` before opening a pull request.

## License

Released under the [MIT License](LICENSE). Copyright (c) 2026 bestxia0.

## Acknowledgements

This launcher is a thin front end for the upstream **pi-web** project (`@agegr/pi-web`), whose run-record format, `pi-web stop --port N` command and port behaviour it reuses. Thanks to the pi-web authors and the Pi community.
