# AGENTS.md

Objective: a zero-dependency Swift + AppKit macOS menu-bar launcher for the upstream
`pi-web` CLI. It owns a native single window with multiple `WKWebView` tabs and never
bundles Node or `pi-web`. Built directly with `swiftc`; no SPM, no third-party packages.

This file is version controlled on purpose: it is part of the repository contract,
not local scratch. Changing it is a normal, reviewable commit.

## Commands

```sh
./build.sh              # swiftc + assemble build/PiWeb.app + code-sign (the only build path)
./build.sh --run        # build and launch
PI_WEB_ARCHS=arm64 ./build.sh  # single-slice build for a faster local loop
make verify             # headless suite + docs check + universal-binary assertion
make check-docs         # version / changelog / README consistency (docs drift gate)
make release            # verify, then tag + push VERSION (GitHub Actions publishes)
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
| `scripts/verify.sh` | headless verification suite (`make verify`) |
| `scripts/check-docs.sh` | documentation drift gate (`make check-docs`) |
| `scripts/release.sh` | tag + push, which is what actually publishes (`make release`) |
| `build.sh` | the build path: per-arch `swiftc`, `lipo`, icon, Info.plist, codesign |
| `.github/workflows/ci.yml`, `release.yml` | CI matrix (macos-15-intel + macos-15 arm64) and tag-driven publishing |

Read `README.md` (English) / `README.zh-CN.md` (primary, more detailed) and
`CHANGELOG.md` for the user-facing contract; `docs/` holds screenshots and design notes.
`README.md` and `README.zh-CN.md` are kept in sync — never update one alone.
`make check-docs` enforces that (same screenshots, same flags, same keys, matching versions).

## Rules

- **Commit and push after every completed, tested feature.** When a new feature is
  implemented *and* verified (build green + `make verify` or the relevant headless
  flags pass), immediately `git commit` and `git push` before starting anything else.
  Do not batch multiple features into one commit and do not leave verified work
  uncommitted. If the suite fails, do not commit — fix it first.
- **A version bump is not released until it is tagged.** Committing and pushing is
  not enough: only a pushed `v<VERSION>` tag triggers the release workflow. Bump
  `VERSION`, add the `CHANGELOG.md` section **and** its `v<VERSION>` link, make sure
  both READMEs match (`make check-docs` proves it), then run `make release`
  (verify → tag → push). Never publish a build from a laptop.
- Commit subjects follow the existing history: `feat: <what> (vX.Y.Z)`,
  `fix: ...`, `docs: ...`, `ci: ...` — one bounded change per commit.
- Versioning: `VERSION` is the single source of truth for the semantic version;
  the build date is stamped by `build.sh`. Never hard-code a version in Swift, in
  the docs or in CI.
- **Always build universal.** `build.sh` compiles `arm64` + `x86_64` and `lipo`s
  them; the app claims macOS 13+ and an arm64-only bundle will not launch on an
  Intel Mac. `make verify`, CI and the release workflow all fail on a missing
  slice — never work around that.
- Keep the app zero-dependency: system frameworks only, no SPM/CocoaPods additions,
  and no new build steps beyond `swiftc`/`lipo`/`sips`/`iconutil`.
- All UI text is Simplified Chinese, matching existing menu items.
- Do not weaken the TCC/Input Monitoring handling in `build.sh` or
  `HotKeyMonitor.swift`; the stable signing identity is what keeps the grant alive.
- Never commit secrets, nor build output under `build/` or `.DS_Store`.
- `/Users/xiao` is the user's home directory: never modify or delete unrelated files
  there; confirm high-risk operations first.
- Leave no residue behind: no stray `pi-web`/`PiWeb` processes, temp files or test
  instances after a work session, and nothing installed to `/Applications` unless
  the user asked for it.
