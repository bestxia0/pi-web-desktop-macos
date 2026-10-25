# AGENTS.md

Objective: a zero-dependency Swift + AppKit macOS menu-bar launcher for the upstream
`pi-web` CLI. It owns a native single window with multiple `WKWebView` tabs and never
bundles Node or `pi-web`. Built directly with `swiftc`; no SPM, no third-party packages.

## Commands

```sh
./build.sh              # swiftc + assemble build/PiWeb.app + code-sign (the only build path)
./build.sh --run        # build and launch
make verify             # headless verification suite (scripts/verify.sh)
make install            # copy to /Applications (required before SMAppService login item)
make log                # tail ~/Library/Logs/PiWeb/pi-web.log
```

Headless flags on the built binary: `--self-test`, `--probe`, `--test-cycle`,
`--test-fallback`, `--resolve`, `--stop-port`, `--test-quit`, `--version`.
Use them for verification instead of clicking through the UI. `make install` writes to
`/Applications` — confirm with the user before running it.

## Where things live

| File | Owns |
| --- | --- |
| `Sources/main.swift` | app bootstrap, headless-flag dispatch, NSStatusItem |
| `Sources/StatusController.swift` | state machine: probe → attach or launch → stop |
| `Sources/ProcessManager.swift` | spawn/kill escalation (`SIGINT → SIGTERM → SIGKILL`), PID tracking |
| `Sources/MenuController.swift`, `MainMenu.swift`, `StopMenu.swift` | menu construction and enablement rules |
| `Sources/AppWindow.swift`, `TabBar.swift`, `TabSupport.swift`, `TabStore.swift` | native window, tab colours, per-tab sessions, persistence |
| `Sources/HotKeyMonitor.swift` | right-Option global hotkey + Input Monitoring/TCC recovery |
| `Sources/EnvironmentResolver.swift` | login-shell `PATH` recovery so GUI launches find `pi-web`/`node` |
| `Sources/PortPlanner.swift`, `HTTPProbe.swift`, `RunRecords.swift` | port fallback, health probe, run-record attach contract |
| `Sources/SelfTest.swift` | headless assertions — extend this with every new behaviour |
| `Sources/Preferences.swift` | persisted `UserDefaults` keys |

Read `README.md` (English) / `README.zh-CN.md` (primary, more detailed) and
`CHANGELOG.md` for the user-facing contract; `docs/` holds screenshots.
`README.md` and `README.zh-CN.md` are kept in sync — never update one alone.

## Rules

- **Commit and push after every completed, tested feature.** When a new feature is
  implemented *and* verified (build green + `make verify` or the relevant headless
  flags pass), immediately `git commit` and `git push` before starting anything else.
  Do not batch multiple features into one commit and do not leave verified work
  uncommitted. If the suite fails, do not commit — fix it first.
- Commit subjects follow the existing history: `feat: <what> (vX.Y.Z)`,
  `fix: ...`, `docs: ...`, `ci: ...` — one bounded change per commit.
- Versioning: `VERSION` is the single source of truth for the semantic version;
  the build date is stamped by `build.sh`. Bump `VERSION` for a release, add a
  `CHANGELOG.md` entry, and never hard-code a version in Swift.
- Keep the app zero-dependency: system frameworks only, no SPM/CocoaPods additions.
- All UI text is Simplified Chinese, matching existing menu items.
- Do not weaken the TCC/Input Monitoring handling in `build.sh` or
  `HotKeyMonitor.swift`; the stable signing identity is what keeps the grant alive.
- Never commit secrets, nor build output under `build/` or `.DS_Store`.
- `/Users/xiao` is the user's home directory: never modify or delete unrelated files
  there; confirm high-risk operations first.
