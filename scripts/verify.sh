#!/usr/bin/env bash
#
# Headless verification suite for Pi Web Desktop.
#
#   ./scripts/verify.sh              build if needed, then run every check
#   ./scripts/verify.sh --no-build   skip the build step
#
# Every check runs against a throwaway port (30199 by default, override with
# PI_WEB_DESKTOP_TEST_PORT). The suite never touches an instance running on the
# preferred port 30141, and it cleans up any instance it starts.
#
# Set VERIFY_FULL=1 to also run the heavier end-to-end cycles.
# Set VERBOSE=1 to print the output of passing checks too.
#
# Exit status: 0 when nothing failed, 1 otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/PiWeb.app"
BIN="$APP/Contents/MacOS/PiWeb"
TEST_PORT="${PI_WEB_DESKTOP_TEST_PORT:-30199}"
LIMIT="${VERIFY_TIMEOUT:-180}"

DO_BUILD=1
[[ "${1:-}" == "--no-build" ]] && DO_BUILD=0

pass=0
fail=0
skip=0

# The build is chatty, so its output is buffered to a scratch file and only
# echoed when it fails. Keep it out of a fixed /tmp path (which would outlive
# the run) and remove it on the way out, however the suite exits.
BUILD_LOG="$(mktemp "${TMPDIR:-/tmp}/piweb-verify-build.XXXXXX")"

ok() { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
no() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }
sk() { printf '  \033[33mSKIP\033[0m %s\n' "$1"; skip=$((skip + 1)); }

# Portable wall-clock timeout: no dependency on GNU `timeout`/coreutils.
# Runs "$@" in the background, kills it after $1 seconds, returns 124 on timeout.
timeout_run() {
  local limit="$1"
  shift
  local pid waited=0
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if ((waited >= limit)); then
      kill -TERM "$pid" 2>/dev/null
      sleep 1
      kill -KILL "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
}

# check <name> <timeout-seconds> <command...>
check() {
  local name="$1" limit="$2"
  shift 2
  local out rc
  out="$(timeout_run "$limit" "$@" 2>&1)"
  rc=$?
  if ((rc == 0)); then
    ok "$name"
    [[ -n "${VERBOSE:-}" ]] && printf '%s\n' "$out" | sed 's/^/       /'
  else
    if ((rc == 124)); then
      no "$name (timed out after ${limit}s)"
    else
      no "$name (exit $rc)"
    fi
    printf '%s\n' "$out" | sed 's/^/       /'
  fi
  return 0
}

cleanup() {
  # Only ever touch the throwaway test port.
  if [[ -x "$BIN" ]]; then
    "$BIN" --stop-port "$TEST_PORT" >/dev/null 2>&1 || true
  fi
  # Never leave the buffered build log behind.
  rm -f "$BUILD_LOG"
}
trap cleanup EXIT

echo "Pi Web Desktop — headless verification"
echo "  repo:      $ROOT"
echo "  binary:    $BIN"
echo "  test port: $TEST_PORT"
echo

# ---------------------------------------------------------------- build ----
if ((DO_BUILD)); then
  echo "Build"
  if (cd "$ROOT" && ./build.sh) >"$BUILD_LOG" 2>&1; then
    ok "./build.sh"
  else
    no "./build.sh"
    sed 's/^/       /' "$BUILD_LOG" | tail -30
  fi
  echo
fi

if [[ ! -x "$BIN" ]]; then
  no "binary exists at $BIN"
  echo
  echo "Summary: ${pass} passed, ${fail} failed, ${skip} skipped"
  exit 1
fi
ok "binary exists"

# The shipped bundle must run on both Apple silicon and Intel: an arm64-only
# binary refuses to launch on Intel Macs. `lipo` ships with the same toolchain.
ARCH_LIST="$(lipo -archs "$BIN" 2>/dev/null || echo unknown)"
if [[ "$ARCH_LIST" == *arm64* && "$ARCH_LIST" == *x86_64* ]]; then
  ok "binary is universal ($ARCH_LIST)"
else
  no "binary is not universal (archs: $ARCH_LIST); build without PI_WEB_ARCHS"
fi

# -------------------------------------------------------------- core ----
echo
echo "Core"

VERSION_OUT="$(timeout_run 30 "$BIN" --version 2>&1)"
if [[ "$VERSION_OUT" =~ ^V[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  ok "--version prints a version ($VERSION_OUT)"
else
  no "--version prints a version (got: ${VERSION_OUT:-<empty>})"
fi

check "--self-test" "$LIMIT" "$BIN" --self-test
check "--log-path" 30 "$BIN" --log-path

# ------------------------------------------------------- environment ----
echo
echo "Environment resolution"

check "--resolve" "$LIMIT" "$BIN" --resolve
check "--probe" "$LIMIT" "$BIN" --probe

# --gui-path bypasses every cache and forces a login-shell probe, which is the
# code path a Finder / LaunchServices launch takes.
check "--resolve --gui-path" "$LIMIT" "$BIN" --resolve --gui-path

RESOLVE_OUT="$(timeout_run "$LIMIT" "$BIN" --resolve 2>&1)"
if grep -q "NOT FOUND" <<<"$RESOLVE_OUT"; then
  PI_WEB_FOUND=0
  sk "pi-web resolved (pi-web not installed; server-dependent checks skipped)"
else
  PI_WEB_FOUND=1
  ok "pi-web resolved from the login shell"
fi

# ------------------------------------------------------------ ports ----
echo
echo "Port selection"

if ((PI_WEB_FOUND)); then
  check "--test-fallback --port $TEST_PORT" "$LIMIT" "$BIN" --test-fallback --port "$TEST_PORT"
else
  sk "--test-fallback (needs pi-web)"
fi

# ------------------------------------------------ end-to-end cycles ----
if ((PI_WEB_FOUND)); then
  echo
  echo "End-to-end cycles"
  if [[ -n "${VERIFY_FULL:-}" ]]; then
    check "--test-cycle --port $TEST_PORT" "$LIMIT" "$BIN" --test-cycle --port "$TEST_PORT"
    check "--test-cycle --occupy --port $TEST_PORT" "$LIMIT" "$BIN" --test-cycle --occupy --port "$TEST_PORT"
    check "--test-cycle --gui-path --port $TEST_PORT" "$LIMIT" "$BIN" --test-cycle --gui-path --port "$TEST_PORT"
    check "--test-quit --port $TEST_PORT" "$LIMIT" "$BIN" --test-quit --port "$TEST_PORT"
  else
    sk "end-to-end cycles (set VERIFY_FULL=1 to enable; they start a real pi-web)"
  fi
fi

# -------------------------------------------------------------- docs ----
echo
echo "Documentation"
check "scripts/check-docs.sh" 60 "$ROOT/scripts/check-docs.sh"

# ----------------------------------------------------------- summary ----
echo
if ((fail == 0)); then
  printf '\033[32mSummary: %d passed, %d failed, %d skipped\033[0m\n' "$pass" "$fail" "$skip"
  exit 0
fi
printf '\033[31mSummary: %d passed, %d failed, %d skipped\033[0m\n' "$pass" "$fail" "$skip"
exit 1
