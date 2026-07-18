#!/usr/bin/env bash
# Live-sandbox smoke: launch nested somewm + qs, exercise the new IPC,
# verify panels open/close. Manual-only — run when iterating on the
# panel behaviour. Needs an active Wayland session (nested backend).
#
# Usage:
#   plans/tests/test-detail-panels-live.sh
#
# Cleans up (pkill + socket) after each step. Takes ~15 s.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SANDBOX="$ROOT_DIR/plans/scripts/somewm-sandbox.sh"
SOCKET="$XDG_RUNTIME_DIR/somewm-detail-test-$$.sock"

cleanup() {
    pkill -f "somewm .* -S $SOCKET" 2>/dev/null || true
    pkill -f "qs -c somewm" 2>/dev/null || true
    rm -f "$SOCKET"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ "${WAYLAND_DISPLAY:-}" ]] || fail "Not in a Wayland session; skip this test or run from TTY+somewm"

echo "-- starting nested somewm --"
WLR_BACKENDS=wayland \
SOMEWM_SOCKET="$SOCKET" \
    "$ROOT_DIR/build-fx/somewm" -d >/tmp/somewm-detail-test.log 2>&1 &
NESTED_PID=$!

# Wait for IPC socket
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -S "$SOCKET" ]] && break
    sleep 0.5
done
[[ -S "$SOCKET" ]] || fail "IPC socket not created"

DISPLAY_NAME="$(SOMEWM_SOCKET="$SOCKET" somewm-client eval 'return os.getenv("WAYLAND_DISPLAY")' | tail -1)"
[[ -n "$DISPLAY_NAME" ]] || fail "No WAYLAND_DISPLAY from nested somewm"
pass "nested somewm up: $DISPLAY_NAME (socket=$SOCKET)"

echo "-- starting qs (somewm-shell) --"
WAYLAND_DISPLAY="$DISPLAY_NAME" qs -c somewm >/tmp/qs-detail-test.log 2>&1 &
QS_PID=$!
sleep 3
kill -0 "$QS_PID" 2>/dev/null || fail "qs exited — check /tmp/qs-detail-test.log"
pass "qs running"

echo "-- toggle memory-detail via IPC --"
WAYLAND_DISPLAY="$DISPLAY_NAME" qs -c somewm ipc call \
    somewm-shell:panels toggle memory-detail >/dev/null 2>&1 \
    || fail "panels.toggle memory-detail failed"
sleep 0.5
pass "memory-detail toggle ok"

echo "-- toggle storage-detail via IPC --"
WAYLAND_DISPLAY="$DISPLAY_NAME" qs -c somewm ipc call \
    somewm-shell:panels toggle storage-detail >/dev/null 2>&1 \
    || fail "panels.toggle storage-detail failed"
sleep 0.5
pass "storage-detail toggle ok"

echo "-- toggleOnScreen form --"
SCREEN_NAME="$(WAYLAND_DISPLAY="$DISPLAY_NAME" qs -c somewm ipc \
    eval 'return Quickshell.screens[0].name' 2>/dev/null || echo "")"
if [[ -n "$SCREEN_NAME" ]]; then
    WAYLAND_DISPLAY="$DISPLAY_NAME" qs -c somewm ipc call \
        somewm-shell:panels toggleOnScreen memory-detail "$SCREEN_NAME" >/dev/null 2>&1 \
        || fail "panels.toggleOnScreen failed"
    pass "toggleOnScreen memory-detail ok (screen=$SCREEN_NAME)"
else
    echo "SKIP toggleOnScreen (no screen name available)"
fi

echo "-- closeAll --"
WAYLAND_DISPLAY="$DISPLAY_NAME" qs -c somewm ipc call \
    somewm-shell:panels closeAll >/dev/null 2>&1 \
    || fail "closeAll failed"
pass "closeAll ok"

echo "-- all live checks passed --"
