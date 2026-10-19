#!/usr/bin/env bash
#
# Builds Pi Web Desktop and installs it to /Applications/PiWeb.app.
#
#   ./scripts/install.sh            build, copy to /Applications, re-register
#   ./scripts/install.sh --no-build reuse the existing build/
#
# SMAppService.mainApp needs a stable bundle location, so "Start at Login" only
# works once the app lives in /Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/PiWeb.app"
DEST="/Applications/PiWeb.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

DO_BUILD=1
[[ "${1:-}" == "--no-build" ]] && DO_BUILD=0

if ((DO_BUILD)); then
  echo "==> Building"
  (cd "$ROOT" && ./build.sh)
fi

if [[ ! -d "$APP" ]]; then
  echo "!! $APP not found. Run ./build.sh first (or drop --no-build)." >&2
  exit 1
fi

echo "==> Quitting a running instance"
osascript -e 'tell application "Pi Web" to quit' >/dev/null 2>&1 || true
pkill -x PiWeb >/dev/null 2>&1 || true
sleep 1

if [[ ! -w /Applications ]]; then
  echo "!! /Applications is not writable by $(whoami)." >&2
  echo "   Either run this script with sudo, or copy the bundle manually:" >&2
  echo "     sudo ditto '$APP' '$DEST'" >&2
  exit 1
fi

echo "==> Installing to $DEST"
rm -rf "$DEST"
ditto "$APP" "$DEST"

# A downloaded build may carry the quarantine flag; the app is ad-hoc signed,
# so clear it to avoid Gatekeeper friction on first launch.
xattr -dr com.apple.quarantine "$DEST" >/dev/null 2>&1 || true

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
fi

echo "==> Installed: $DEST"
cat <<'EOF'

Next steps
  1. open /Applications/PiWeb.app
  2. Click the menu bar icon, then enable 开机自启 if you want it at login.
     (macOS may ask you to approve the login item in System Settings.)

To remove it again:  make uninstall
EOF
