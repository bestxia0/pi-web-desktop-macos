# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The version shown in the menu is `<semver>-<builddate>`, e.g. `V0.5.0-20261019`.
The semantic part comes from the [`VERSION`](VERSION) file; the build date is
stamped by `build.sh` at build time.

## [Unreleased]

Nothing yet.

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

[Unreleased]: https://github.com/bestxia0/pi-web-desktop-macos/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/bestxia0/pi-web-desktop-macos/releases/tag/v0.5.0
