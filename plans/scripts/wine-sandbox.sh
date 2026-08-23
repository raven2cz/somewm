#!/usr/bin/env bash
#
# Run Wine applications inside a nested somewm sandbox.
#
# Wine talks X11, so it needs the DISPLAY of the *nested* Xwayland, not the one
# of the live session. Getting that wrong sends windows (and input grabs) into
# the user's working desktop, which is exactly what this script exists to
# prevent: every subcommand refuses to run unless it is talking to a sandbox.
#
# Subcommands:
#   start [--binary PATH] [--test-config] [--log PATH]
#                        start the nested compositor in the background
#   env                  print the sandbox environment (eval-able)
#   run -- CMD...        run CMD inside the sandbox (nested DISPLAY + WAYLAND_DISPLAY)
#   wine -- ARGS...      run `wine ARGS` inside the sandbox with WINEPREFIX
#   click X Y            real pointer click via zwlr_virtual_pointer (compositor path)
#   move X Y             real pointer motion via zwlr_virtual_pointer
#   census [ARGS...]     dump the X11 window tree of the nested Xwayland
#   ipc 'LUA'            somewm-client eval against the sandbox
#   log [N]              tail the compositor log
#   stop                 kill the nested compositor
#
# Example:
#   plans/scripts/wine-sandbox.sh start
#   plans/scripts/wine-sandbox.sh wine -- notepad
#   plans/scripts/wine-sandbox.sh census
#   plans/scripts/wine-sandbox.sh stop

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
STATE_FILE=${SOMEWM_WINE_SANDBOX_STATE:-"${TMPDIR:-/tmp}/somewm-wine-sandbox.state"}
DEFAULT_LOG="${TMPDIR:-/tmp}/somewm-wine-sandbox.log"
CENSUS_PY="$ROOT_DIR/plans/scripts/x11-census.py"

# Wine prefix for Sierra Chart; override with WINEPREFIX in the environment.
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-sierra}"
export WINEARCH="${WINEARCH:-win64}"
export WINEDEBUG="${WINEDEBUG:-fixme-all,err-all}"

die() { printf '\033[1;31m[wine-sandbox]\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[1;36m[wine-sandbox]\033[0m %s\n' "$*"; }

# --- live-session guards ----------------------------------------------------
#
# LIVE_* are captured from the environment this script was invoked from, i.e.
# the user's real session. Nothing the sandbox reports may match them.
LIVE_DISPLAY=${DISPLAY:-}
LIVE_WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}
LIVE_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/somewm-socket"

assert_not_live() {
    local socket=$1 display=$2 wayland=$3

    [[ "$socket" == *sandbox* ]] \
        || die "refusing: IPC socket '$socket' is not a sandbox socket"
    [[ "$socket" != "$LIVE_SOCKET" ]] \
        || die "refusing: IPC socket is the live session socket"
    [[ -S "$socket" ]] \
        || die "refusing: IPC socket '$socket' does not exist (sandbox not running?)"

    if [[ -n "$display" ]]; then
        [[ "$display" != "$LIVE_DISPLAY" ]] \
            || die "refusing: nested DISPLAY equals the live DISPLAY ($display)"
    fi
    if [[ -n "$wayland" && -n "$LIVE_WAYLAND_DISPLAY" ]]; then
        [[ "$wayland" != "$LIVE_WAYLAND_DISPLAY" ]] \
            || die "refusing: nested WAYLAND_DISPLAY equals the live one ($wayland)"
    fi
}

load_state() {
    [[ -f "$STATE_FILE" ]] || die "no sandbox state at $STATE_FILE — run '$0 start' first"
    # shellcheck disable=SC1090
    source "$STATE_FILE"
    : "${SB_SOCKET:?state file is missing SB_SOCKET}"
    : "${SB_PID:?state file is missing SB_PID}"
    kill -0 "$SB_PID" 2>/dev/null || die "sandbox compositor (pid $SB_PID) is not running"
    assert_not_live "$SB_SOCKET" "${SB_DISPLAY:-}" "${SB_WAYLAND_DISPLAY:-}"
}

pick() {
    local name=$1 candidate
    for candidate in "$ROOT_DIR/build-test/$name" "$ROOT_DIR/build-fx/$name" \
                     "$ROOT_DIR/build/$name" "$ROOT_DIR/$name"; do
        if [[ -x "$candidate" ]]; then printf '%s\n' "$candidate"; return 0; fi
    done
    return 1
}

# --- subcommands ------------------------------------------------------------

cmd_start() {
    local binary="" client="" log="$DEFAULT_LOG" config_home=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --binary) binary=$2; shift 2 ;;
            --client) client=$2; shift 2 ;;
            --log)    log=$2; shift 2 ;;
            --test-config)
                config_home=$(mktemp -d)
                mkdir -p "$config_home/somewm"
                cp "$ROOT_DIR/tests/rc.lua" "$config_home/somewm/rc.lua"
                shift ;;
            *) die "unknown option for start: $1" ;;
        esac
    done

    if [[ -f "$STATE_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$STATE_FILE"
        if [[ -n "${SB_PID:-}" ]] && kill -0 "$SB_PID" 2>/dev/null; then
            die "a sandbox is already running (pid $SB_PID) — run '$0 stop' first"
        fi
    fi

    [[ -n "$binary" ]] || binary=$(pick somewm) || die "no somewm binary; run 'make build-test'"
    [[ -n "$client" ]] || client=$(pick somewm-client) || die "no somewm-client binary"
    [[ -n "${XDG_RUNTIME_DIR:-}" ]] || die "XDG_RUNTIME_DIR is not set"
    [[ -n "$LIVE_WAYLAND_DISPLAY" ]] || die "WAYLAND_DISPLAY is not set; need a parent compositor"

    local socket="$XDG_RUNTIME_DIR/somewm-sandbox-wine-$$.sock"
    rm -f "$socket"

    info "starting nested somewm ($binary)"
    (
        export SOMEWM_SOCKET="$socket"
        export WLR_BACKENDS=wayland
        export WLR_WL_OUTPUTS="${WLR_WL_OUTPUTS:-1}"
        export NO_AT_BRIDGE=1
        [[ -n "$config_home" ]] && export XDG_CONFIG_HOME="$config_home"
        exec "$binary" -d >"$log" 2>&1
    ) &
    local pid=$!

    local i
    for i in $(seq 1 100); do
        if [[ -S "$socket" ]] && SOMEWM_SOCKET="$socket" "$client" ping >/dev/null 2>&1; then
            break
        fi
        kill -0 "$pid" 2>/dev/null || { tail -40 "$log" >&2; die "nested somewm exited during startup (log: $log)"; }
        sleep 0.1
    done
    SOMEWM_SOCKET="$socket" "$client" ping >/dev/null 2>&1 \
        || { tail -40 "$log" >&2; die "timeout waiting for nested IPC (log: $log)"; }

    # Both displays are exported by the compositor after startup: WAYLAND_DISPLAY
    # by run(), DISPLAY by the Xwayland ready handler. Xwayland is lazy, so poll.
    local wayland="" display="" raw
    for i in $(seq 1 100); do
        # eval prints an "OK" status line, the result, then a trailing blank
        # line; keep the last non-empty line that is not the status.
        raw=$(SOMEWM_SOCKET="$socket" "$client" eval 'return (os.getenv("WAYLAND_DISPLAY") or "").."|"..(os.getenv("DISPLAY") or "")' 2>/dev/null \
              | awk 'NF && $0 != "OK"' | tail -1)
        wayland=${raw%%|*}
        display=${raw##*|}
        [[ -n "$wayland" && -n "$display" && "$raw" != "OK" ]] && break
        wayland=""; display=""
        sleep 0.1
    done
    [[ -n "$wayland" ]] || die "nested WAYLAND_DISPLAY never appeared (log: $log)"
    [[ -n "$display" ]] || die "nested DISPLAY never appeared — is this build XWayland-enabled? (log: $log)"

    assert_not_live "$socket" "$display" "$wayland"

    cat >"$STATE_FILE" <<EOF
SB_PID=$pid
SB_SOCKET=$socket
SB_CLIENT=$client
SB_BINARY=$binary
SB_DISPLAY=$display
SB_WAYLAND_DISPLAY=$wayland
SB_LOG=$log
SB_CONFIG_HOME=$config_home
EOF

    info "pid=$pid  DISPLAY=$display  WAYLAND_DISPLAY=$wayland"
    info "log: $log"
    info "state: $STATE_FILE"
}

cmd_env() {
    load_state
    echo "export SOMEWM_SOCKET=$SB_SOCKET"
    echo "export DISPLAY=$SB_DISPLAY"
    echo "export WAYLAND_DISPLAY=$SB_WAYLAND_DISPLAY"
    echo "export WINEPREFIX=$WINEPREFIX"
}

cmd_run() {
    load_state
    [[ "${1:-}" == "--" ]] && shift
    [[ $# -gt 0 ]] || die "run needs a command"
    DISPLAY="$SB_DISPLAY" \
    WAYLAND_DISPLAY="$SB_WAYLAND_DISPLAY" \
    SOMEWM_SOCKET="$SB_SOCKET" \
        "$@"
}

cmd_wine() {
    load_state
    [[ "${1:-}" == "--" ]] && shift
    command -v wine >/dev/null || die "wine not found on PATH"
    info "wine $* (DISPLAY=$SB_DISPLAY WINEPREFIX=$WINEPREFIX)"
    DISPLAY="$SB_DISPLAY" \
    WAYLAND_DISPLAY="$SB_WAYLAND_DISPLAY" \
    SOMEWM_SOCKET="$SB_SOCKET" \
    WINEPREFIX="$WINEPREFIX" \
    WINEARCH="$WINEARCH" \
    WINEDEBUG="$WINEDEBUG" \
        wine "$@"
}

cmd_click() {
    # Inject a real pointer event through zwlr_virtual_pointer_v1 so it takes
    # the compositor's buttonpress()/motionnotify() path. xdotool would go
    # through XTEST inside Xwayland instead, bypassing somewm entirely -- which
    # is a different code path and useless for reproducing compositor bugs.
    load_state
    local action=$1 x=$2 y=$3
    local vpointer="$ROOT_DIR/build-test/test-virtual-pointer-client"
    [[ -x "$vpointer" ]] || die "missing $vpointer (run 'make build-test')"

    local extent
    extent=$(SOMEWM_SOCKET="$SB_SOCKET" "$SB_CLIENT" eval \
        'local g=screen[1].geometry; return g.width.."x"..g.height' \
        | awk 'NF && $0 != "OK"' | tail -1)
    local ex=${extent%%x*} ey=${extent##*x}
    [[ -n "$ex" && -n "$ey" ]] || die "could not read screen geometry"

    WAYLAND_DISPLAY="$SB_WAYLAND_DISPLAY" "$vpointer" "$action" "$x" "$y" "$ex" "$ey"
}

cmd_census() {
    load_state
    [[ -f "$CENSUS_PY" ]] || die "census helper not found: $CENSUS_PY"
    DISPLAY="$SB_DISPLAY" SOMEWM_SOCKET="$SB_SOCKET" SOMEWM_CLIENT_BIN="$SB_CLIENT" \
        python3 "$CENSUS_PY" "$@"
}

cmd_ipc() {
    load_state
    [[ $# -gt 0 ]] || die "ipc needs a Lua expression"
    # Drop the "OK" status line and the trailing blank line so the output can
    # be piped straight into other tools.
    SOMEWM_SOCKET="$SB_SOCKET" "$SB_CLIENT" eval "$*" | awk 'NF && $0 != "OK"'
}

cmd_log() {
    load_state
    tail -n "${1:-60}" "$SB_LOG"
}

cmd_stop() {
    [[ -f "$STATE_FILE" ]] || { info "no sandbox state; nothing to stop"; return 0; }
    # shellcheck disable=SC1090
    source "$STATE_FILE"
    if [[ -n "${SB_PID:-}" ]] && kill -0 "$SB_PID" 2>/dev/null; then
        assert_not_live "${SB_SOCKET:-}" "${SB_DISPLAY:-}" "${SB_WAYLAND_DISPLAY:-}"
        info "stopping nested somewm (pid $SB_PID)"
        kill "$SB_PID" 2>/dev/null || true
        for _ in $(seq 1 50); do
            kill -0 "$SB_PID" 2>/dev/null || break
            sleep 0.1
        done
        kill -9 "$SB_PID" 2>/dev/null || true
    fi
    rm -f "${SB_SOCKET:-}"
    [[ -n "${SB_CONFIG_HOME:-}" && "${SB_CONFIG_HOME}" == /tmp/* ]] && rm -rf "$SB_CONFIG_HOME"
    rm -f "$STATE_FILE"
}

case "${1:-}" in
    start)  shift; cmd_start "$@" ;;
    env)    shift; cmd_env ;;
    run)    shift; cmd_run "$@" ;;
    wine)   shift; cmd_wine "$@" ;;
    census) shift; cmd_census "$@" ;;
    click)  shift; cmd_click click "$@" ;;
    move)   shift; cmd_click move "$@" ;;
    ipc)    shift; cmd_ipc "$@" ;;
    log)    shift; cmd_log "$@" ;;
    stop)   shift; cmd_stop ;;
    -h|--help|"") sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^# \?//' ;;
    *) die "unknown subcommand: $1 (try --help)" ;;
esac
