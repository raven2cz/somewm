#!/usr/bin/env bash
# Integration test for fishlive.autostart lifecycle.
#
# Boots somewm in headless wlroots mode against a custom rc.lua that
# registers two autostart entries (see fixtures/autostart-rc.lua). Asserts
# state transitions and PID liveness via somewm-client eval.
#
# Coverage:
#   * gated -> starting -> running on ready::somewm (cold-boot replay)
#   * status() snapshot exposes correct ready map + entry rows
#   * stop() transitions running -> pending and SIGTERMs the child
#   * restart() of a `failed` entry re-enters the gated cycle
#   * /bin/false oneshot with retries=1 lands in `failed`
#
# Required binaries: somewm + somewm-client. Either build-fx/ or
# build-nofx/ works (no SceneFX needed for headless).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_RC="$ROOT_DIR/plans/tests/fixtures/autostart-rc.lua"

BINARY="${SOMEWM_BINARY:-}"
CLIENT="${SOMEWM_CLIENT:-}"

# build-fx is preferred because it matches the canonical install-scenefx.sh
# workflow (CLAUDE.md "Always use install-scenefx.sh"). Other build dirs are
# fallbacks for environments that don't keep build-fx around. Both picks must
# come from the SAME build dir or the IPC ABI may mismatch -- callers should
# verify that BINARY and CLIENT live next to each other.
pick_binary() {
    local c
    for c in \
        "$ROOT_DIR/build-fx/somewm" \
        "$ROOT_DIR/build/somewm" \
        "$ROOT_DIR/build-test/somewm" \
        "$ROOT_DIR/build-nofx/somewm"; do
        if [ -x "$c" ]; then printf '%s\n' "$c"; return 0; fi
    done
    return 1
}
pick_client() {
    local c
    for c in \
        "$ROOT_DIR/build-fx/somewm-client" \
        "$ROOT_DIR/build/somewm-client" \
        "$ROOT_DIR/build-test/somewm-client" \
        "$ROOT_DIR/build-nofx/somewm-client"; do
        if [ -x "$c" ]; then printf '%s\n' "$c"; return 0; fi
    done
    return 1
}

[ -z "$BINARY" ] && BINARY=$(pick_binary) || true
[ -z "$CLIENT" ] && CLIENT=$(pick_client) || true
if [ ! -x "${BINARY:-}" ]; then
    echo "Error: no somewm binary found. Build first." >&2
    exit 1
fi
if [ ! -x "${CLIENT:-}" ]; then
    echo "Error: no somewm-client binary found. Build first." >&2
    exit 1
fi

TMP_DIR=$(mktemp -d)
LOG="$TMP_DIR/somewm.log"
SOMEWM_PID=
TEST_RUNTIME_DIR="$TMP_DIR/runtime"
TEST_CONFIG_DIR="$TMP_DIR/config/somewm"
mkdir -p "$TEST_RUNTIME_DIR" "$TEST_CONFIG_DIR"
chmod 700 "$TEST_RUNTIME_DIR"
cp "$FIXTURE_RC" "$TEST_CONFIG_DIR/rc.lua"

cleanup() {
    local rc=$?
    # Kill ONLY the compositor we spawned. Never use pkill against the
    # process name -- that would kill the user's live somewm session too.
    # The sleep children spawned by autostart entries are reaped by the
    # SIGTERM cascade because somewm is their parent (the autostart spawn
    # backend uses awful.spawn -> GLib gspawn which keeps the parent
    # relationship intact).
    if [ -n "$SOMEWM_PID" ] && kill -0 "$SOMEWM_PID" 2>/dev/null; then
        kill -TERM "$SOMEWM_PID" 2>/dev/null || true
        sleep 0.3
        kill -KILL "$SOMEWM_PID" 2>/dev/null || true
        wait "$SOMEWM_PID" 2>/dev/null || true
    fi
    if [ "$rc" -ne 0 ] && [ -s "$LOG" ]; then
        echo "--- somewm log (last 80 lines) ---" >&2
        tail -80 "$LOG" >&2
    fi
    rm -rf "$TMP_DIR"
    exit "$rc"
}
trap cleanup EXIT INT TERM

export FISHLIVE_ROOT="$ROOT_DIR/plans/project/somewm-one"
export XDG_CONFIG_HOME="$TMP_DIR/config"
export XDG_RUNTIME_DIR="$TEST_RUNTIME_DIR"
export WLR_BACKENDS=headless
export WLR_RENDERER=pixman
export WLR_WL_OUTPUTS=1
export NO_AT_BRIDGE=1
SOCKET="$XDG_RUNTIME_DIR/somewm-socket"
export SOMEWM_SOCKET="$SOCKET"

rm -f "$SOCKET"
"$BINARY" -d > "$LOG" 2>&1 &
SOMEWM_PID=$!

# Wait for socket + IPC ping.
for _ in $(seq 1 100); do
    if [ -S "$SOCKET" ] && "$CLIENT" ping >/dev/null 2>&1; then
        break
    fi
    if ! kill -0 "$SOMEWM_PID" 2>/dev/null; then
        echo "Error: somewm exited during startup" >&2
        exit 1
    fi
    sleep 0.1
done

if ! "$CLIENT" ping >/dev/null 2>&1; then
    echo "Error: timeout waiting for somewm IPC" >&2
    exit 1
fi

# eval_lua runs a single-line Lua snippet via IPC and returns the result.
# somewm-client writes "OK\n<result>\n\n" to stdout; we strip the OK header
# and any trailing blank line via `awk 'NF' | tail -1` (last non-empty line).
# Errors come back without the OK prefix, so we still surface them.
eval_lua() {
    "$CLIENT" eval "$1" 2>&1 | awk 'NF' | sed '/^OK$/d' | tail -1
}

# IPC accepts connections before luaA_parserc() finishes, so wait until the
# rc.lua fixture has run autostart.start_all() and the two entries appear
# in the status snapshot.
for _ in $(seq 1 100); do
    n=$(eval_lua "local ok,m=pcall(require,'fishlive.autostart'); if not ok then return '0' end; local s=m.status(); local c=0; for _ in pairs(s.entries) do c=c+1 end; return tostring(c)" || true)
    [ "$n" = "2" ] && break
    sleep 0.1
done
if [ "$n" != "2" ]; then
    echo "Error: timeout waiting for rc.lua to register autostart entries (got n='$n')" >&2
    exit 1
fi

require_eq() {
    local desc="$1" expected="$2" got="$3"
    if [ "$got" != "$expected" ]; then
        echo "FAIL: $desc: expected '$expected', got '$got'" >&2
        return 1
    fi
    echo "  ok  $desc"
}

# Helper: poll status().entries[name].state until it equals $target or timeout.
wait_for_state() {
    local name="$1" target="$2" max="${3:-50}"
    local got=
    for _ in $(seq 1 "$max"); do
        got=$(eval_lua "return (require('fishlive.autostart').status().entries['$name'] or {}).state or 'missing'")
        if [ "${DEBUG_AUTOSTART:-0}" = "1" ]; then
            extra=$(eval_lua "local s=require('fishlive.autostart').status(); return string.format('aw=%s broker=%s', tostring(awesome.somewm_ready), tostring(s.ready['ready::somewm']))")
            echo "  [trace $name] got='$got' target='$target' $extra" >&2
        fi
        if [ "$got" = "$target" ]; then
            printf '%s\n' "$got"
            return 0
        fi
        sleep 0.1
    done
    printf '%s\n' "$got"
    return 0
}

echo "test: lifecycle-sleep enters running"
# This implicitly confirms ready::somewm fired through the broker — without
# the gate, the entry would be stuck in `gated`.
state=$(wait_for_state "lifecycle-sleep" "running" 50)
require_eq "lifecycle-sleep state=running" "running" "$state"

echo "test: ready map exposes ready::somewm = true"
ready_somewm=$(eval_lua 'return tostring(require("fishlive.autostart").status().ready["ready::somewm"])')
require_eq "ready::somewm true" "true" "$ready_somewm"

pid=$(eval_lua "return tostring((require('fishlive.autostart').status().entries['lifecycle-sleep'] or {}).pid or 0)")
if ! [ "$pid" -gt 0 ] 2>/dev/null; then
    echo "FAIL: lifecycle-sleep pid not positive: '$pid'" >&2
    exit 1
fi
if ! kill -0 "$pid" 2>/dev/null; then
    echo "FAIL: lifecycle-sleep pid $pid not alive" >&2
    exit 1
fi
echo "  ok  lifecycle-sleep pid $pid alive"

echo "test: lifecycle-fail reaches failed (oneshot, retries=1)"
state=$(wait_for_state "lifecycle-fail" "failed" 50)
require_eq "lifecycle-fail state=failed" "failed" "$state"

echo "test: stop() transitions running -> pending and SIGTERMs the pid"
eval_lua "require('fishlive.autostart').stop('lifecycle-sleep'); return 'ok'" >/dev/null
state=$(eval_lua "return (require('fishlive.autostart').status().entries['lifecycle-sleep'] or {}).state or 'missing'")
require_eq "lifecycle-sleep state=pending" "pending" "$state"

# Wait for the SIGTERM (queued via awful.spawn.easy_async) to arrive and
# the kernel to reap the child.
for _ in $(seq 1 50); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$pid" 2>/dev/null; then
    echo "FAIL: lifecycle-sleep pid $pid still alive after stop()" >&2
    exit 1
fi
echo "  ok  lifecycle-sleep pid $pid terminated"

echo "test: restart() of failed entry re-enters lifecycle and re-fails"
eval_lua "return tostring(require('fishlive.autostart').restart('lifecycle-fail'))" >/dev/null
# After restart, attempts is reset to 0 and one more spawn happens.
# /bin/false still exits 1, so we end up back in `failed`.
state=$(wait_for_state "lifecycle-fail" "failed" 50)
require_eq "lifecycle-fail restart -> failed" "failed" "$state"

echo "test: status() lists both registered entries"
n=$(eval_lua "local s=require('fishlive.autostart').status(); local n=0; for _ in pairs(s.entries) do n=n+1 end; return tostring(n)")
require_eq "entries count" "2" "$n"

echo "test: list() returns names in registration order"
order=$(eval_lua "return table.concat(require('fishlive.autostart').list(), ',')")
require_eq "registration order" "lifecycle-sleep,lifecycle-fail" "$order"

echo "PASS"
