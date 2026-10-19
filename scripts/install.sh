#!/usr/bin/env bash
#
# Builds Pi Web Desktop and installs it to /Applications/PiWeb.app.
#
#   ./scripts/install.sh                      build, copy to /Applications, re-register
#   ./scripts/install.sh --no-build           reuse the existing build/
#   ./scripts/install.sh --reset-permissions  also clear the stale Input Monitoring /
#                                             Accessibility TCC grants for the app
#
# --no-build and --reset-permissions may be combined in any order.
#
# SMAppService.mainApp needs a stable bundle location, so "Start at Login" only
# works once the app lives in /Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/PiWeb.app"
DEST="/Applications/PiWeb.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
BUNDLE_ID="com.piweb.desktop"

DO_BUILD=1
RESET_PERMISSIONS=0
for arg in "$@"; do
  case "$arg" in
    --no-build) DO_BUILD=0 ;;
    --reset-permissions) RESET_PERMISSIONS=1 ;;
    *)
      echo "!! Unknown argument: $arg" >&2
      echo "   Usage: $0 [--no-build] [--reset-permissions]" >&2
      exit 1
      ;;
  esac
done

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

# A downloaded build may carry the quarantine flag; clear it to avoid Gatekeeper
# friction on first launch.
xattr -dr com.apple.quarantine "$DEST" >/dev/null 2>&1 || true

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
fi

echo "==> Installed: $DEST"

# Input Monitoring (and Accessibility) grants are bound to the code signature.
# An ad-hoc signed bundle gets a new cdhash on every rebuild, so the grant from
# a previous build silently stops matching. Warn, and point at the fix.
if codesign -dv "$DEST" 2>&1 | grep -q adhoc; then
  echo ""
  echo "!! WARNING: $DEST is ad-hoc signed."
  echo "   macOS TCC binds the Input Monitoring grant to the signature, so it will"
  echo "   stop matching after every rebuild or move of the .app (the System"
  echo "   Settings checkbox can stay on while the hotkey is dead)."
  echo "   Clear the stale grant and re-grant, or create the stable certificate"
  echo "   named 'PiWeb Local Signing' (README → 全局热键与输入监控):"
  echo "     /usr/bin/tccutil reset ListenEvent $BUNDLE_ID"
  echo "     /usr/bin/tccutil reset Accessibility $BUNDLE_ID"
fi

if ((RESET_PERMISSIONS)); then
  echo ""
  echo "==> Resetting TCC permissions for $BUNDLE_ID"
  for service in ListenEvent Accessibility; do
    if /usr/bin/tccutil reset "$service" "$BUNDLE_ID"; then
      echo "    reset $service: OK"
    else
      echo "    reset $service: failed (exit $?)" >&2
    fi
  done
  echo "    Launch the app and enable 输入监控 again (menu bar → ⚠︎ 需要「输入监控」权限——点击授权)."
fi

echo ""
cat <<'EOF'

Next steps
  1. open /Applications/PiWeb.app
  2. Click the menu bar icon, then enable 开机自启 if you want it at login.
     (macOS may ask you to approve the login item in System Settings.)
  3. If the right-Option hotkey dies after a rebuild or a move of the app,
     clear the stale grant and re-grant:
       /usr/bin/tccutil reset ListenEvent com.piweb.desktop
       /usr/bin/tccutil reset Accessibility com.piweb.desktop
     or re-run this script with --reset-permissions. The permanent fix is a
     stable code-signing certificate — see README → 全局热键与输入监控.

To remove it again:  make uninstall
EOF
