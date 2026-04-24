#!/usr/bin/env bash
#
# Start somewm as a nested Wayland compositor for local debugging.
#
# The script prints two different environment values:
#   SOMEWM_SOCKET    IPC socket for somewm-client
#   WAYLAND_DISPLAY  Wayland display for apps launched inside the nested session

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
BACKEND=wayland
BINARY=${SOMEWM_BINARY:-}
CLIENT=${SOMEWM_CLIENT:-}
LOG=${SOMEWM_SANDBOX_LOG:-"${TMPDIR:-/tmp}/somewm-sandbox.log"}
CONFIG_HOME=${SOMEWM_SANDBOX_CONFIG_HOME:-}
SANDBOX_RUNTIME_DIR=
CLIENT_CMD=()

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [-- CLIENT_CMD...]

Options:
  --binary PATH       somewm binary to run
  --client PATH       somewm-client binary to use
  --log PATH          log file (default: /tmp/somewm-sandbox.log)
  --test-config       use tests/rc.lua in an isolated XDG_CONFIG_HOME
  --headless          use wlroots headless backend instead of nested Wayland
  -h, --help          show this help

Examples:
  $0
  $0 -- mpv --no-terminal /path/to/video.mp4
  $0 --test-config -- alacritty

After startup, use the printed SOMEWM_SOCKET for IPC commands and the printed
WAYLAND_DISPLAY for client applications.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --binary)
            BINARY=$2
            shift 2
            ;;
        --client)
            CLIENT=$2
            shift 2
            ;;
        --log)
            LOG=$2
            shift 2
            ;;
        --test-config)
            CONFIG_HOME=$(mktemp -d)
            mkdir -p "$CONFIG_HOME/somewm"
            cp "$ROOT_DIR/tests/rc.lua" "$CONFIG_HOME/somewm/rc.lua"
            shift
            ;;
        --headless)
            BACKEND=headless
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            CLIENT_CMD=("$@")
            break
            ;;
        *)
            CLIENT_CMD=("$@")
            break
            ;;
    esac
done

pick_binary() {
    local candidate
    if [ "$BACKEND" = "headless" ]; then
        for candidate in \
            "$ROOT_DIR/build-nofx/somewm" \
            "$ROOT_DIR/build-test/somewm" \
            "$ROOT_DIR/build/somewm" \
            "$ROOT_DIR/somewm"; do
            if [ -x "$candidate" ]; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done
    else
        for candidate in \
            "$ROOT_DIR/build-fx/somewm" \
            "$ROOT_DIR/build/somewm" \
            "$ROOT_DIR/build-test/somewm" \
            "$ROOT_DIR/somewm"; do
            if [ -x "$candidate" ]; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done
    fi
    return 1
}

pick_client() {
    local candidate
    for candidate in \
        "$ROOT_DIR/build-fx/somewm-client" \
        "$ROOT_DIR/build/somewm-client" \
        "$ROOT_DIR/build-test/somewm-client" \
        "$ROOT_DIR/somewm-client"; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

if [ -z "$BINARY" ]; then
    BINARY=$(pick_binary) || {
        echo "Error: no somewm binary found. Build first or pass --binary PATH." >&2
        exit 1
    }
fi

if [ -z "$CLIENT" ]; then
    CLIENT=$(pick_client) || {
        echo "Error: no somewm-client binary found. Build first or pass --client PATH." >&2
        exit 1
    }
fi

if [ ! -x "$BINARY" ]; then
    echo "Error: somewm binary is not executable: $BINARY" >&2
    exit 1
fi

if [ ! -x "$CLIENT" ]; then
    echo "Error: somewm-client is not executable: $CLIENT" >&2
    exit 1
fi

if [ "$BACKEND" = "headless" ]; then
    SANDBOX_RUNTIME_DIR=$(mktemp -d)
    chmod 700 "$SANDBOX_RUNTIME_DIR"
    export XDG_RUNTIME_DIR="$SANDBOX_RUNTIME_DIR"
fi

if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    echo "Error: XDG_RUNTIME_DIR is not set." >&2
    exit 1
fi

if [ "$BACKEND" = "wayland" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "Error: WAYLAND_DISPLAY is not set; nested Wayland backend needs a parent compositor." >&2
    exit 1
fi

mkdir -p "$(dirname "$LOG")"

SOCKET="$XDG_RUNTIME_DIR/somewm-sandbox-$$.sock"
rm -f "$SOCKET"

cleanup() {
    local code=$?
    if [ -n "${SOMEWM_PID:-}" ] && kill -0 "$SOMEWM_PID" 2>/dev/null; then
        kill "$SOMEWM_PID" 2>/dev/null || true
        wait "$SOMEWM_PID" 2>/dev/null || true
    fi
    rm -f "$SOCKET"
    if [ -n "$SANDBOX_RUNTIME_DIR" ] && [[ "$SANDBOX_RUNTIME_DIR" == /tmp/* ]]; then
        rm -rf "$SANDBOX_RUNTIME_DIR"
    fi
    if [ -n "$CONFIG_HOME" ] && [[ "$CONFIG_HOME" == /tmp/* ]]; then
        rm -rf "$CONFIG_HOME"
    fi
    exit "$code"
}
trap cleanup EXIT INT TERM

export SOMEWM_SOCKET="$SOCKET"
export WLR_BACKENDS="$BACKEND"
export WLR_WL_OUTPUTS="${WLR_WL_OUTPUTS:-1}"
export NO_AT_BRIDGE=1

if [ "$BACKEND" = "headless" ]; then
    export WLR_RENDERER="${WLR_RENDERER:-pixman}"
fi

if [ -n "$CONFIG_HOME" ]; then
    export XDG_CONFIG_HOME="$CONFIG_HOME"
fi

"$BINARY" -d >"$LOG" 2>&1 &
SOMEWM_PID=$!

for _ in $(seq 1 100); do
    if [ -S "$SOCKET" ] && SOMEWM_SOCKET="$SOCKET" "$CLIENT" ping >/dev/null 2>&1; then
        break
    fi
    if ! kill -0 "$SOMEWM_PID" 2>/dev/null; then
        echo "Error: nested somewm exited during startup. Log: $LOG" >&2
        tail -80 "$LOG" >&2 || true
        exit 1
    fi
    sleep 0.1
done

if ! SOMEWM_SOCKET="$SOCKET" "$CLIENT" ping >/dev/null 2>&1; then
    echo "Error: timeout waiting for nested somewm IPC. Log: $LOG" >&2
    tail -80 "$LOG" >&2 || true
    exit 1
fi

# WAYLAND_DISPLAY is exported by somewm's run() after IPC ping works,
# so poll briefly until it appears before reporting to the user.
DISPLAY_NAME=""
for _ in $(seq 1 50); do
    raw=$(SOMEWM_SOCKET="$SOCKET" "$CLIENT" eval 'return os.getenv("WAYLAND_DISPLAY") or ""' 2>/dev/null || true)
    DISPLAY_NAME=$(printf '%s\n' "$raw" | tail -1)
    if [ -n "$DISPLAY_NAME" ] && [ "$DISPLAY_NAME" != "OK" ]; then
        break
    fi
    DISPLAY_NAME=""
    sleep 0.1
done

echo "nested somewm pid: $SOMEWM_PID"
echo "log: $LOG"
echo "export SOMEWM_SOCKET=$SOCKET"
echo "export WAYLAND_DISPLAY=$DISPLAY_NAME"
echo
echo "IPC example:"
echo "  SOMEWM_SOCKET=$SOCKET $CLIENT eval 'return #client.get()'"
if [ "$BACKEND" = "wayland" ]; then
    echo "Client example:"
    echo "  WAYLAND_DISPLAY=$DISPLAY_NAME alacritty &"
fi
echo

if [ "${#CLIENT_CMD[@]}" -gt 0 ]; then
    WAYLAND_DISPLAY="$DISPLAY_NAME" SOMEWM_SOCKET="$SOCKET" "${CLIENT_CMD[@]}" &
fi

wait "$SOMEWM_PID"
