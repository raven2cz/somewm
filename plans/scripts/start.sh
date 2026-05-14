#!/bin/bash
# Start somewm with debug logging
mkdir -p ~/.local/log

# Rotate previous session log (keep last 5)
"$(dirname "$0")/somewm-log-rotate.sh" 2>/dev/null || true

# Clean stale Quickshell instance locks from previous sessions.
# Without this, awful.spawn.once() may think QS is already running
# after a compositor crash/restart.
if [ -d /run/user/$(id -u)/quickshell ]; then
    # Kill any orphaned QS processes from previous session
    pkill -u "$(id -un)" -f "qs -c somewm" 2>/dev/null
    # Remove stale runtime dirs so spawn.once doesn't skip launch
    rm -rf /run/user/$(id -u)/quickshell/by-id/* \
           /run/user/$(id -u)/quickshell/by-pid/* \
           /run/user/$(id -u)/quickshell/by-path/* 2>/dev/null
fi

# Clear QML cache to pick up any QS config changes
rm -rf ~/.cache/quickshell/qmlcache 2>/dev/null

# Ensure /usr/local/lib is on library path (scenefx, lgi guard)
# ldconfig should handle this, but LD_LIBRARY_PATH is a safe fallback
if [[ ":${LD_LIBRARY_PATH:-}:" != *":/usr/local/lib:"* ]]; then
    export LD_LIBRARY_PATH="/usr/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

# Lgi closure guard is auto-loaded by somewm's main() via re-exec.
# No manual LD_PRELOAD needed since upstream cherry-picks 67d7899 + ace15ed + b6b2e78.

# Diagnostic watchdog: every 5s append somewm's RSS, CPU%, GPU SM%, open FDs
# to ~/.local/log/somewm-stats.log so we can see leak/hot-loop growth pattern.
# Dies automatically when somewm exits (kill -0 check).
STATS_LOG=~/.local/log/somewm-stats.log
: > "$STATS_LOG"
(
    # Wait for somewm to appear (up to 10s)
    for _ in $(seq 1 20); do
        SOMEWM_PID=$(pgrep -u "$(id -u)" -x 'somewm' | head -1)
        [ -n "$SOMEWM_PID" ] && break
        sleep 0.5
    done
    [ -z "$SOMEWM_PID" ] && exit 0
    echo "# $(date -Iseconds) watchdog attached to pid=$SOMEWM_PID" >> "$STATS_LOG"
    echo "# time_iso  elapsed_s  rss_kb  cpu%  threads  open_fds  gpu_sm%  gpu_mem%" >> "$STATS_LOG"
    START=$(date +%s)
    while kill -0 "$SOMEWM_PID" 2>/dev/null; do
        NOW=$(date -Iseconds)
        ELAPSED=$(( $(date +%s) - START ))
        read -r RSS CPU THREADS < <(ps -o rss=,pcpu=,nlwp= -p "$SOMEWM_PID" 2>/dev/null)
        FDS=$(ls /proc/"$SOMEWM_PID"/fd 2>/dev/null | wc -l)
        GPU=$(nvidia-smi pmon -c 1 -s u 2>/dev/null | awk -v p="$SOMEWM_PID" '$2==p {print $4" "$5; exit}')
        [ -z "$GPU" ] && GPU="- -"
        echo "$NOW  ${ELAPSED}s  $RSS  $CPU  $THREADS  $FDS  $GPU" >> "$STATS_LOG"
        sleep 5
    done
    echo "# $(date -Iseconds) somewm exited" >> "$STATS_LOG"
) &
disown

# Propagate display/session env to the systemd user bus so user services
# (xdg-desktop-portal, gnome-keyring, polkit, gpg-agent, ...) know which
# display to talk to. Mirrors the canonical sequence in
# /usr/local/bin/somewm-session (the systemd-integrated launcher used
# by ~/bin/session-launcher), so manual start.sh and DM/launcher paths
# end up on the same user@1000.service D-Bus.
#
# Do NOT wrap in dbus-run-session: that creates an isolated private bus
# so child apps can no longer reach gnome-keyring / polkit on the
# user@1000.service bus and time out on libsecret/portal calls (~25s
# D-Bus default), surfacing as 20s+ delays before password prompts and
# slow Spotify/Electron startup.
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-somewm}"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"

systemctl --user import-environment \
    DISPLAY WAYLAND_DISPLAY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP \
    XDG_RUNTIME_DIR XDG_DATA_DIRS XDG_CONFIG_DIRS PATH \
    SSH_AUTH_SOCK 2>/dev/null || true
dbus-update-activation-environment --all 2>/dev/null || true

exec somewm -d 2>&1 | tee ~/.local/log/somewm-debug.log
