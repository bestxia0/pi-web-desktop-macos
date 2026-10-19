# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| 0.5.x | Yes |
| < 0.5 | No |

This project is a thin local launcher with no network-facing service of its own.
Only the latest released version is supported; fixes are not backported.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Report it privately through GitHub's
[Security Advisories](https://github.com/bestxia0/pi-web-desktop-macos/security/advisories/new)
form (*Security* → *Report a vulnerability*). That keeps the report private while
a fix is prepared.

Please include:

- the output of `build/PiWeb.app/Contents/MacOS/PiWeb --version`;
- your macOS version;
- which `pi-web` version is installed (`pi-web --version`);
- a description of the impact, and the steps to reproduce;
- any relevant lines from `~/Library/Logs/PiWeb/pi-web.log`.

### What to expect

This is a small volunteer project, so these are intentions rather than a
contract:

| Stage | Target |
| --- | --- |
| Acknowledgement of the report | within 7 days |
| Initial assessment and severity | within 14 days |
| Fix released, or a plan with a timeline | within 90 days |
| Public disclosure | coordinated with you, after a fix is available |

You will be credited in the advisory and the changelog unless you ask not to be.

## Threat model

Understanding what this app does makes it easier to judge whether something is a
vulnerability.

**What it touches**

- It resolves `pi-web` and `node` — first from an explicit path
  (`PiWebExecutablePath` / `PI_WEB_DESKTOP_EXECUTABLE`), then by probing the login
  shell (`/bin/zsh -lic`), then by scanning well-known directories. Whatever it
  resolves, it **executes**.
- It reads run records under `<agentDir>/pi-web-run/` (`PI_CODING_AGENT_DIR` or
  `~/.pi/agent`) and validates them by calling `kill(pid, 0)` and
  `ps -ww -p <pid> -o args=` for the pids found in those files.
- It spawns `pi-web stop --port N` for the destructive attached-instance path,
  and signals the child it owns directly.
- It writes only to UserDefaults (bundle domain `com.piweb.desktop`) and to
  `~/Library/Logs/PiWeb/pi-web.log`.
- It opens URLs in a local browser. The URL always comes from the resolved
  `127.0.0.1:<port>`, never from remote input.

**Trust boundaries**

- Anything already able to write to `~/Library/Logs/PiWeb/`, the agent
  directory, or your UserDefaults is already inside your user account, and can
  do anything this app can do. That is not a privilege boundary.
- The login-shell probe executes your own shell startup files. A hostile
  `.zshrc` is a hostile shell, not an app vulnerability.
- The app is **ad-hoc signed and not notarised**. A copy downloaded from the
  internet triggers Gatekeeper; verify that you built it from this repository if
  that matters to you.
- Run records are treated as untrusted input: a record is only acted upon after
  both the liveness and the ownership checks pass. A record that fails those
  checks is ignored, never deleted.

**Out of scope**

- Vulnerabilities in the upstream [`pi-web`](https://github.com/agegr/pi-web) CLI,
  in `node`, or in Next.js. Report those upstream.
- Anything that requires an attacker to already have code execution or write
  access as your user.
- The app's inability to stop an instance whose port is reachable but whose run
  record has been removed.
