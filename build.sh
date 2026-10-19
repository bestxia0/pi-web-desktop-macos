#!/usr/bin/env bash
#
# Builds PiWeb.app with swiftc only (no SPM / CocoaPods / external packages).
#
#   ./build.sh          compile + assemble build/PiWeb.app + codesign
#   ./build.sh --run    also launch the app
#
# Codesigning uses a stable identity when one is available so the macOS Input
# Monitoring (TCC) grant survives rebuilds: $PI_WEB_SIGN_IDENTITY, else the
# exact certificate name "PiWeb Local Signing", else ad-hoc (see README).
#
# The version shown at the bottom of the menu comes from two places, both
# stamped here:
#   VERSION                     -> semantic version, e.g. 0.5.0
#   date +%Y%m%d                -> build date,     e.g. 20261019
# They are written into Info.plist as CFBundleShortVersionString, CFBundleVersion
# and PiWebVersion ("0.5.0-20261019"). Nothing is hardcoded in Swift, so bumping
# the version is: edit VERSION, rebuild.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/PiWeb.app"
BIN="$APP/Contents/MacOS/PiWeb"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos13.0"

# --- version ---------------------------------------------------------------
VERSION_FILE="$ROOT/VERSION"
SEMANTIC_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE" 2>/dev/null || true)"
if [[ -z "$SEMANTIC_VERSION" ]]; then
  echo "!! VERSION file missing or empty; falling back to 0.0.0" >&2
  SEMANTIC_VERSION="0.0.0"
fi
BUILD_DATE="$(date +%Y%m%d)"
FULL_VERSION="${SEMANTIC_VERSION}-${BUILD_DATE}"

echo "==> Cleaning $APP"
rm -rf "$APP"
mkdir -p "$(dirname "$BIN")" "$APP/Contents/Resources"

echo "==> Compiling with swiftc (target $TARGET)"
swiftc \
  -swift-version 5 \
  -O \
  -target "$TARGET" \
  -framework AppKit \
  -framework WebKit \
  -framework ServiceManagement \
  -framework UniformTypeIdentifiers \
  -o "$BIN" \
  "$ROOT"/Sources/*.swift

# --- app icon --------------------------------------------------------------
# The source is a small (282x267) non-square JPEG, so it is centre-cropped to a
# square first: no stretching, no padding bands. Upscaling past 256px is soft by
# nature of the source; see README.
ICON_SRC="$ROOT/Resources/AppIcon.jpg"
ICON_DEST="$APP/Contents/Resources/PiWeb.icns"
if [[ -f "$ICON_SRC" ]]; then
  echo "==> Generating app icon"
  WORK="$(mktemp -d)"
  SQUARE="$WORK/square.png"
  ICONSET="$WORK/PiWeb.iconset"
  mkdir -p "$ICONSET"

  SRC_W="$(sips -g pixelWidth "$ICON_SRC" | awk '/pixelWidth/ { print $2 }')"
  SRC_H="$(sips -g pixelHeight "$ICON_SRC" | awk '/pixelHeight/ { print $2 }')"
  SIDE="$SRC_W"
  if (( SRC_H < SRC_W )); then SIDE="$SRC_H"; fi

  # -c is "crop to <height> <width>", centred; -s format converts to PNG.
  sips -s format png -c "$SIDE" "$SIDE" "$ICON_SRC" --out "$SQUARE" >/dev/null

  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SQUARE" \
      --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$SQUARE" \
      --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done

  iconutil -c icns "$ICONSET" -o "$ICON_DEST"
  rm -rf "$WORK"
  echo "    icon: $ICON_DEST (source ${SRC_W}x${SRC_H}, cropped to ${SIDE}x${SIDE})"
else
  echo "!! $ICON_SRC not found; building without a custom app icon" >&2
fi

echo "==> Writing Info.plist (version $FULL_VERSION)"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Pi Web</string>
    <key>CFBundleDisplayName</key>
    <string>Pi Web</string>
    <key>CFBundleIdentifier</key>
    <string>com.piweb.desktop</string>
    <key>CFBundleExecutable</key>
    <string>PiWeb</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>PiWeb</string>
    <key>CFBundleShortVersionString</key>
    <string>${SEMANTIC_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_DATE}</string>
    <key>PiWebVersion</key>
    <string>${FULL_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

# --- codesign --------------------------------------------------------------
# A stable signing identity keeps the Input Monitoring (TCC) grant across
# rebuilds: macOS stores the code requirement per signature/cdhash, and an
# ad-hoc signature changes its cdhash on every build. Resolution order:
#   1. $PI_WEB_SIGN_IDENTITY (name or SHA-1), if set and non-empty
#   2. an exact "PiWeb Local Signing" codesigning identity
#   3. none -> ad-hoc fallback (today's behaviour)
# Deliberately no --options runtime and no entitlements: the hardened runtime
# would require WebKit/JIT entitlements and is not needed for TCC here.
echo "==> Codesign"
SIGN_IDENTITY="${PI_WEB_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  # `|| true` keeps `set -e` happy when there are zero valid identities.
  SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | awk -F'"' '/"PiWeb Local Signing"/ { print $2; exit }' || true
  )"
fi

cdhash_of() {
  # `-dv` (verbose=2) omits CDHash on recent macOS; `-dvvv` prints it.
  codesign -dvvv "$APP" 2>&1 | awk -F'=' '/^CDHash=/ { print $2; exit }'
}

if [[ -n "$SIGN_IDENTITY" ]]; then
  if codesign --force --deep --sign "$SIGN_IDENTITY" "$APP" >/dev/null 2>&1; then
    echo "    signed (identity: $SIGN_IDENTITY)"
    echo "    CDHash: $(cdhash_of)"
  else
    echo "!! codesign with identity '$SIGN_IDENTITY' failed; falling back to ad-hoc" >&2
    SIGN_IDENTITY=""
  fi
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  if codesign --force --deep --sign - "$APP" >/dev/null 2>&1; then
    echo "    signed (ad-hoc)"
    echo "    CDHash: $(cdhash_of)"
    echo "!! WARNING: ad-hoc signatures change their cdhash on every build, so macOS" >&2
    echo "!!          drops the Input Monitoring grant and the System Settings" >&2
    echo "!!          checkbox stops matching the new binary." >&2
    echo "!!          Create/select a stable code-signing certificate named" >&2
    echo "!!          'PiWeb Local Signing' (see README → 全局热键与输入监控) or set" >&2
    echo "!!          PI_WEB_SIGN_IDENTITY, then rebuild." >&2
  else
    echo "    codesign failed; continuing (unsigned)"
  fi
fi

echo "==> Built: $APP"
echo "    binary:  $BIN"
echo "    version: V$FULL_VERSION (menu shows this)"

if [[ "${1:-}" == "--run" ]]; then
  echo "==> Launching"
  open "$APP"
fi
