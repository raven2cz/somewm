#!/bin/bash
# Start somewm with debug logging
mkdir -p ~/.local/log

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

# Lgi closure guard for safe hot-reload
# somewm clears LD_PRELOAD in main() so children don't inherit it
LGI_GUARD=/usr/local/lib/liblgi_closure_guard.so
if [ -f "$LGI_GUARD" ]; then
    export LD_PRELOAD="${LGI_GUARD}${LD_PRELOAD:+:$LD_PRELOAD}"
    export ASAN_OPTIONS="${ASAN_OPTIONS:+$ASAN_OPTIONS:}verify_asan_link_order=0"
fi

exec dbus-run-session somewm -d 2>&1 | tee ~/.local/log/somewm-debug.log
