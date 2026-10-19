#!/usr/bin/env bash
#
# Best-effort regeneration of the screenshots used by docs/images/.
#
#   ./scripts/capture-screenshots.sh
#
# This script is a convenience only — the committed screenshots are maintained
# by hand. It tries to capture the real thing and tells you exactly what to do
# by hand when it cannot.
#
# Known constraint: capturing the screen requires the "Screen Recording"
# permission (System Settings > Privacy & Security > Screen Recording) for
# whichever app runs this script. Without it, `screencapture` fails with
# "could not create image from display" and this script falls back to the
# instructions below.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/PiWeb.app"
BIN="$APP/Contents/MacOS/PiWeb"
IMAGES="$ROOT/docs/images"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$IMAGES"

echo "==> Building"
(cd "$ROOT" && ./build.sh) || exit 1

# ---------------------------------------------------------------- icon ----
echo "==> app-icon.png (from the built .icns — no screen recording needed)"
if iconutil -c iconset "$APP/Contents/Resources/PiWeb.icns" -o "$TMP/PiWeb.iconset" 2>/dev/null; then
  sips -z 512 512 "$TMP/PiWeb.iconset/icon_256x256@2x.png" --out "$IMAGES/app-icon.png" >/dev/null
  echo "    wrote $IMAGES/app-icon.png"
else
  echo "    !! could not read PiWeb.icns"
fi

# ------------------------------------------------------ screen capture ----
echo "==> Probing screen capture permission"
if ! screencapture -x "$TMP/probe.png" 2>"$TMP/err.txt"; then
  echo "    !! screencapture is not permitted:"
  sed 's/^/       /' "$TMP/err.txt"
  cat <<'EOF'

    Real screen captures are skipped. To capture them yourself:

      1. System Settings > Privacy & Security > Screen Recording
         -> enable it for your terminal app (Terminal, iTerm, Ghostty, ...)
         -> quit and reopen that app.

      2. Build and launch the app:
             ./build.sh --run

      3. menubar-icon.png — crop the status icon out of the menu bar:
             screencapture -x -R"0,0,1728,48" /tmp/menubar.png
             sips -c 76 160 /tmp/menubar.png --out docs/images/menubar-icon.png

      4. menu-open.png — launch the app a SECOND time; the running instance
         pops its own menu (distributed notification com.piweb.desktop.activate).
         Capture immediately while the menu is still open:
             open build/PiWeb.app
             screencapture -x /tmp/menu.png
         Then crop the menu plus a small margin.

      5. piweb-ui.png — the pi-web UI itself, which needs no screen recording:
             "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
               --headless=new --disable-gpu --hide-scrollbars \
               --user-data-dir=/tmp/chrome-shot --window-size=1440,900 \
               --virtual-time-budget=10000 \
               --screenshot=docs/images/piweb-ui.png http://127.0.0.1:30141
EOF
  exit 0
fi
echo "    permission OK"

# ------------------------------------------------------------- capture ----
BOUNDS="$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null | tr -d '{}')"
WIDTH="$(echo "$BOUNDS" | awk -F',' '{gsub(/ /,"",$3); print $3}')"
[[ -z "${WIDTH:-}" ]] && WIDTH=1728

echo "==> Launching the app"
open "$APP"
sleep 12
pgrep -x PiWeb >/dev/null || echo "    (warning: PiWeb does not appear to be running)"

echo "==> menubar-icon.png"
screencapture -x -R"0,0,${WIDTH},48" "$TMP/menubar.png"
# Centre-crop to a tight strip around the status item; adjust by hand if needed.
sips -c 48 240 "$TMP/menubar.png" --out "$IMAGES/menubar-icon.png" >/dev/null
echo "    wrote $IMAGES/menubar-icon.png (crop by hand for a tighter frame)"

echo "==> menu-open.png"
open "$APP" # second launch pops the running instance's menu
sleep 3
screencapture -x "$TMP/menu-full.png" && echo "    raw capture: $TMP/menu-full.png"
cp "$TMP/menu-full.png" "$IMAGES/menu-open.png" 2>/dev/null || true
echo "    wrote $IMAGES/menu-open.png (full screen — crop to the menu by hand)"

echo "==> Done. Review docs/images/ and re-crop anything that looks off."
echo "    The app was left running; use the menu to quit it, or: pkill -x PiWeb"
