# Contributing

Thanks for taking a look at Pi Web Desktop. This is a small, deliberately
dependency-free project; the bar for changes is "keeps the build a single
`swiftc` invocation and keeps the headless self-test honest".

## Getting set up

```sh
git clone https://github.com/bestxia0/pi-web-desktop-macos.git
cd pi-web-desktop-macos
./build.sh --run
```

You need macOS 13+ and the Xcode Command Line Tools (`swiftc`). To exercise the
launcher for real you also need a globally installed `pi-web` CLI and `node`:

```sh
npm install -g @agegr/pi-web
```

## Running the checks

```sh
make verify          # builds, then runs the headless verification suite
./scripts/verify.sh --no-build   # the same suite against the existing build
VERIFY_FULL=1 ./scripts/verify.sh   # also runs the end-to-end start/stop cycles
```

`scripts/verify.sh` only ever uses the throwaway port `30199`, never `30141`, and
stops anything it started. Individual checks map directly to the binary's
headless flags, which are documented in the [README](README.md#headless-and-verification-flags).

Useful when debugging:

```sh
BIN=build/PiWeb.app/Contents/MacOS/PiWeb
$BIN --probe                 # what does detection see right now?
$BIN --resolve               # which pi-web / node does the app find, and how?
tail -f ~/Library/Logs/PiWeb/pi-web.log
```

## Coding style

- **Swift 5 + AppKit only.** No SPM, no CocoaPods, no third-party packages, no
  new build steps. If a change needs a dependency, it probably belongs upstream
  in `pi-web` instead.
- **Keep `Sources/` flat.** `build.sh` compiles the directory with
  `"$ROOT"/Sources/*.swift`, so the sources are a single flat directory by
  design. Adding a subdirectory silently drops files from the build.
- **No hardcoded versions.** The version flows from the `VERSION` file and the
  build date through `Info.plist`. Never inline a version string in Swift.
- **Blocking work belongs on `StatusController.work`**, and UI state is published
  on the main queue through `publish(_:)`. Do not touch AppKit off the main
  thread.
- **Detection stays read-only.** It must never delete run records. Cleanup is
  upstream `pi-web`'s job.
- Match the surrounding style: small types, `final class` where possible, doc
  comments that explain *why* rather than restating the signature.
- Shell scripts use `#!/usr/bin/env bash` with `set -euo pipefail`, and must pass
  `bash -n`.

## Tests

There is no XCTest target — the test suite is `Sources/SelfTest.swift`, run via
`--self-test`, plus the headless modes the verification script drives.

**Any new user-visible behaviour needs a matching assertion in
`Sources/SelfTest.swift`, or a new headless flag the verification script can
drive.** A pull request that changes behaviour without extending the self-test
will be asked to add it. This is the main thing that keeps a no-dependency,
no-CI-history project trustworthy.

## Commit messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(menu): add a per-instance stop submenu
fix(ports): fall back to an ephemeral port when 30151+ is exhausted
docs: document the login-shell PATH probe
chore(ci): cache the swiftc build
```

Types in use: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`,
`chore`. Keep the subject in the imperative mood and under ~72 characters.

## Pull requests

1. Branch off `main` (`feat/...`, `fix/...`, `docs/...`).
2. Make the change, keeping it focused. Unrelated cleanups go in their own PR.
3. Run `make verify` and make sure the summary is green.
4. Update the docs when behaviour changes: `README.md`, `README.zh-CN.md` (keep
   the two in sync), `docs/ARCHITECTURE.md`, and `CHANGELOG.md` under
   `## [Unreleased]`.
5. If the UI changed, refresh the affected images in `docs/images/` in the same
   PR — see [docs/images/README.md](docs/images/README.md).
6. Fill in the pull request template.

Every pull request runs the [CI workflow](.github/workflows/ci.yml) on a macOS
runner. Note that CI has no `pi-web` installed, so it only builds the app and
runs the checks that do not need a server.

## Reporting bugs and requesting features

Use the issue templates. For a bug, the two most useful attachments are the
output of `--version` and the tail of `~/Library/Logs/PiWeb/pi-web.log`.

Security issues should not be filed publicly — see [SECURITY.md](SECURITY.md).

## Code of conduct

Participation is covered by the [Contributor Covenant](CODE_OF_CONDUCT.md).
