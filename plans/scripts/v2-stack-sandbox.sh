#!/bin/bash
# v2-stack-sandbox.sh - run somewm + somewm-one (+ somewm-shell) from the
# working trees in a throwaway sandbox, without touching the live session,
# /usr/local, ~/.config/somewm or ~/.config/quickshell.
#
#   1. builds this checkout into a private prefix (default ~/.local/somewm-v2)
#      so the binary reads its own Lua tree, not /usr/local/share/somewm
#   2. copies somewm-one (and somewm-shell) into a private config home
#   3. starts a nested (default) or headless compositor via somewm-sandbox.sh
#      with SOMEWM_NO_AUTOSTART=1 (no second kded6/nm-applet/polkit agent)
#   4. with --shell: lets rc.lua launch Quickshell against a throwaway HOME
#      (somewm-shell hardcodes $HOME/.config/...), PATH has the sandbox's
#      somewm-client first
#
# Usage:
#   plans/scripts/v2-stack-sandbox.sh [--headless] [--shell] [--no-build]
#   plans/scripts/v2-stack-sandbox.sh --stop
#
# Afterwards source the env file it prints in a subshell or a separate
# terminal (it may set HOME and XDG_CONFIG_HOME), e.g.
#   source ~/.local/somewm-v2-sbx/env
#   somewm-client eval 'return #client.get()'
#   qs ipc -c somewm call somewm-shell:panels toggle dashboard   # with --shell
#   grim /tmp/shot.png        # or: somewm-client screenshot save /tmp/shot.png
#
# Nested vs headless: a nested window that the parent compositor hides gets
# no frame callbacks, so animations freeze and grim hangs; use --headless for
# anything time-based. Nested on the NVIDIA box renders through the real GPU
# (GLES2), which is what the corner test wants; keep that window visible.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ONE=${SOMEWM_ONE_PATH:-$HOME/git/github/somewm-one}
SHELL_REPO=${SOMEWM_SHELL_PATH:-$HOME/git/github/somewm-shell}
PREFIX=${V2_SBX_PREFIX:-$HOME/.local/somewm-v2}
BUILD=${V2_SBX_BUILD:-$HOME/.cache/somewm-v2-build}
STATE=${V2_SBX_STATE:-$HOME/.local/somewm-v2-sbx}

headless=0 shell=0 build=1
for a in "$@"; do
    case $a in
        --headless) headless=1 ;;
        --shell) shell=1 ;;
        --no-build) build=0 ;;
        --stop)
            # Quickshell started inside exits when its compositor goes away.
            [ -f "$STATE/pid" ] && kill "$(cat "$STATE/pid")" 2>/dev/null || true
            echo "stopped"; exit 0 ;;
        -h|--help) sed -n 2,30p "$0"; exit 0 ;;
        *) echo "unknown option $a" >&2; exit 1 ;;
    esac
done

if [ $build = 1 ]; then
    if [ ! -d "$BUILD" ]; then
        meson setup "$BUILD" "$ROOT" --prefix="$PREFIX" -Dsystemd=disabled -Dbuildtype=debugoptimized
    fi
    ninja -C "$BUILD"
    rm -rf "$PREFIX/share/somewm/lua"
    meson install -C "$BUILD" --skip-subprojects >/dev/null
fi

CFG=$STATE/config
mkdir -p "$CFG/somewm" "$CFG/quickshell"
rsync -a --delete --exclude .git --exclude deploy.sh --exclude CLAUDE.md "$ONE/" "$CFG/somewm/"
if [ $shell = 1 ]; then
    rsync -a --delete --exclude .git --exclude deploy.sh --exclude CLAUDE.md --exclude tests \
        "$SHELL_REPO/" "$CFG/quickshell/somewm/"
    H=$STATE/home
    mkdir -p "$H/git/github" "$H/.local/share"
    ln -sfn "$CFG" "$H/.config"
    for r in somewm somewm-one somewm-shell; do ln -sfn "$HOME/git/github/$r" "$H/git/github/$r"; done
    [ -d "$HOME/.local/share/fonts" ] && ln -sfn "$HOME/.local/share/fonts" "$H/.local/share/fonts"
    export HOME=$H SOMEWM_NO_SHELL=0
else
    export SOMEWM_NO_SHELL=1
fi
export PATH=$PREFIX/bin:$PATH SOMEWM_NO_AUTOSTART=1 SOMEWM_SANDBOX_CONFIG_HOME=$CFG
export SOMEWM_SANDBOX_LOG=$STATE/somewm.log

args=(--binary "$PREFIX/bin/somewm" --client "$PREFIX/bin/somewm-client")
[ $headless = 1 ] && args=(--headless "${args[@]}")
setsid nohup "$ROOT/plans/scripts/somewm-sandbox.sh" "${args[@]}" > "$STATE/sandbox.out" 2>&1 &
for _ in $(seq 1 150); do
    grep -q '^export WAYLAND_DISPLAY=.' "$STATE/sandbox.out" 2>/dev/null && break
    sleep 0.2
done
grep -q '^export WAYLAND_DISPLAY=.' "$STATE/sandbox.out" || { cat "$STATE/sandbox.out"; exit 1; }
sed -n 's/^nested somewm pid: //p' "$STATE/sandbox.out" > "$STATE/pid"

{
    grep '^export' "$STATE/sandbox.out"
    sock=$(sed -n 's/^export SOMEWM_SOCKET=//p' "$STATE/sandbox.out")
    # --headless runs in its own XDG_RUNTIME_DIR; qs ipc and grim need it.
    echo "export XDG_RUNTIME_DIR=$(dirname "$sock")"
    echo "export PATH=$PREFIX/bin:\$PATH"
    echo "export XDG_CONFIG_HOME=$CFG"
    [ $shell = 1 ] && echo "export HOME=$STATE/home"
} > "$STATE/env"

echo "sandbox pid $(cat "$STATE/pid"), log $STATE/somewm.log"
echo "source $STATE/env"
