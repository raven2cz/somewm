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

exec dbus-run-session somewm -d 2>&1 | tee ~/.local/log/somewm-debug.log
