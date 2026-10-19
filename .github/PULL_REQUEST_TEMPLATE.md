# Pull Request

## Summary

<!-- What does this PR change and why? Link the issue it closes, if any. -->

## Type of change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds behaviour)
- [ ] Breaking change (existing behaviour changes)
- [ ] Documentation only
- [ ] Build / CI / tooling only
- [ ] Refactor with no behaviour change

## Verification

- [ ] I ran `./build.sh` and it succeeded
- [ ] I ran `build/PiWeb.app/Contents/MacOS/PiWeb --self-test` and it passed
- [ ] I ran `build/PiWeb.app/Contents/MacOS/PiWeb --version` and it printed the expected version
- [ ] I ran `make verify` (or `./scripts/verify.sh`) and the summary was green
- [ ] I updated the docs (`README.md`, `docs/ARCHITECTURE.md`, `CHANGELOG.md`, …) where behaviour changed

## Headless test coverage

Any new user-visible behaviour must come with a matching headless assertion in
`Sources/SelfTest.swift`, so it is covered by `--self-test` and cannot silently
regress. Describe the assertion you added (or explain why this change has no
observable behaviour):

<!-- e.g. "Added testStopMenuItems case for a 3-instance submenu." -->
