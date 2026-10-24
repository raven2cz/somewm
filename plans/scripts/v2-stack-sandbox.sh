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
#   4. with --shell: starts its own Quickshell instance against a throwaway
#      HOME (somewm-shell hardcodes $HOME/.config/...), with the sandbox's
#      somewm-client first on PATH. rc.lua's own shell launch stays off
#      (SOMEWM_NO_SHELL=1): it would pkill every `qs -c somewm` and clear
#      /run/user/$UID/quickshell, i.e. take down the host's shell.
#   5. nested: renders with GLES2 (V2_SBX_RENDERER overrides), so the test
#      runs on the real GPU; headless: pixman
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
            for f in qs.pid pid; do
                [ -f "$STATE/$f" ] && kill "$(cat "$STATE/$f")" 2>/dev/null || true
                rm -f "$STATE/$f"
            done
            echo "stopped"; exit 0 ;;
        -h|--help) sed -n 2,30p "$0"; exit 0 ;;
        *) echo "unknown option $a" >&2; exit 1 ;;
    esac
done

# The prefix gets its Lua tree wiped before each install: never let it be a
# system location, a shared prefix or the live install. Canonicalise first,
# and only wipe a prefix this script created (marker file).
PREFIX=$(realpath -m "$PREFIX")
case "$PREFIX" in
    /|/usr|/usr/*|/opt|/opt/*|/etc|/etc/*|"$HOME"|"$HOME/.local"|"$HOME/.local/share")
        echo "refusing prefix '$PREFIX' (system or shared directory)" >&2; exit 1 ;;
esac
MARKER=$PREFIX/.v2-stack-sandbox
if [ -e "$PREFIX/share/somewm" ] && [ ! -e "$MARKER" ]; then
    echo "refusing prefix '$PREFIX': it holds a somewm install this script did not make" >&2
    exit 1
fi

if [ $build = 1 ]; then
    if [ ! -d "$BUILD" ]; then
        meson setup "$BUILD" "$ROOT" --prefix="$PREFIX" -Dsystemd=disabled -Dbuildtype=debugoptimized
    else
        # A build dir set up earlier keeps its prefix; follow V2_SBX_PREFIX.
        meson configure "$BUILD" -Dprefix="$PREFIX" >/dev/null
    fi
    ninja -C "$BUILD"
    mkdir -p "$PREFIX" && touch "$MARKER"
    rm -rf "$PREFIX/share/somewm/lua"
    meson install -C "$BUILD" --skip-subprojects >/dev/null
fi
[ -x "$PREFIX/bin/somewm" ] || { echo "no somewm in $PREFIX/bin; run without --no-build" >&2; exit 1; }

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
    export HOME=$H
fi
export PATH=$PREFIX/bin:$PATH SOMEWM_NO_AUTOSTART=1 SOMEWM_NO_SHELL=1 SOMEWM_SANDBOX_CONFIG_HOME=$CFG
export SOMEWM_SANDBOX_LOG=$STATE/somewm.log
if [ $headless = 0 ]; then
    export WLR_RENDERER=${V2_SBX_RENDERER:-gles2}
fi

args=(--binary "$PREFIX/bin/somewm" --client "$PREFIX/bin/somewm-client")
[ $headless = 1 ] && args=(--headless "${args[@]}")
setsid nohup "$ROOT/plans/scripts/somewm-sandbox.sh" "${args[@]}" > "$STATE/sandbox.out" 2>&1 &
for _ in $(seq 1 150); do
    grep -q '^export WAYLAND_DISPLAY=.' "$STATE/sandbox.out" 2>/dev/null && break
    sleep 0.2
done
grep -q '^export WAYLAND_DISPLAY=.' "$STATE/sandbox.out" || { cat "$STATE/sandbox.out"; exit 1; }
sed -n 's/^nested somewm pid: //p' "$STATE/sandbox.out" > "$STATE/pid"

sock=$(sed -n 's/^export SOMEWM_SOCKET=//p' "$STATE/sandbox.out")
wdisp=$(sed -n 's/^export WAYLAND_DISPLAY=//p' "$STATE/sandbox.out")
# The nested Xwayland's DISPLAY, so X11 test clients (xterm, Wine) land in
# the sandbox and not on the live session.
# Xwayland is lazy; somewm-one's rc.lua kicks it with xprop, so allow ~15 s.
xdisp=
for _ in $(seq 1 150); do
    xdisp=$(SOMEWM_SOCKET=$sock "$PREFIX/bin/somewm-client" eval 'return os.getenv("DISPLAY") or ""' 2>/dev/null | grep -v '^OK$' | grep . | tail -1 || true)
    [ -n "$xdisp" ] && [ "$xdisp" != OK ] && break
    xdisp=; sleep 0.1
done

if [ $shell = 1 ]; then
    (
        export SOMEWM_SOCKET=$sock WAYLAND_DISPLAY=$wdisp XDG_RUNTIME_DIR=$(dirname "$sock") XDG_CONFIG_HOME=$CFG
        # Its X11 children must not open on the host.
        if [ -n "$xdisp" ]; then export DISPLAY=$xdisp; else unset DISPLAY; fi
        "$SHELL_REPO/theme-export.sh" >/dev/null 2>&1 || true
        # No -d: qs would daemonise and $! would be the exiting launcher.
        setsid nohup qs -c somewm -n > "$STATE/qs.log" 2>&1 &
        echo $! > "$STATE/qs.pid"
    )
fi

{
    printf 'export SOMEWM_SOCKET=%q\n' "$sock"
    printf 'export WAYLAND_DISPLAY=%q\n' "$wdisp"
    # --headless runs in its own XDG_RUNTIME_DIR; qs ipc and grim need it.
    printf 'export XDG_RUNTIME_DIR=%q\n' "$(dirname "$sock")"
    printf 'export PATH=%q:"$PATH"\n' "$PREFIX/bin"
    printf 'export XDG_CONFIG_HOME=%q\n' "$CFG"
    if [ -n "$xdisp" ]; then
        printf 'export DISPLAY=%q\n' "$xdisp"
    else
        # Never leave the host's DISPLAY in a sandbox shell.
        echo 'unset DISPLAY'
    fi
    # Absolute paths: with --shell this file also changes HOME.
    printf 'export V2_SBX_STATE=%q\n' "$STATE"
    printf 'export V2_SBX_LOG=%q\n' "$STATE/somewm.log"
    if [ $shell = 1 ]; then printf 'export HOME=%q\n' "$STATE/home"; fi
} > "$STATE/env"

echo "sandbox pid $(cat "$STATE/pid"), log $STATE/somewm.log"
[ $shell = 1 ] && echo "quickshell pid $(cat "$STATE/qs.pid"), log $STATE/qs.log"
[ -n "$xdisp" ] || echo "warning: nested DISPLAY not found; the env file unsets DISPLAY" >&2
echo "source $STATE/env"
