#!/bin/bash
# Start somewm with the upstream binary (no Quickshell, no fork features).
#
# Use this to test against pristine upstream code, e.g. when reproducing
# an issue Jimmy can't reproduce. Assumes /usr/local/bin/somewm is the
# upstream build (install via `sudo ninja -C build-upstream-test install`
# after `git checkout upstream/main && meson setup build-upstream-test`).
#
# Pair with the matching default rc.lua:
#   git show upstream/main:somewmrc.lua > ~/.config/somewm/rc.lua
#
# Restore fork after testing:
#   git checkout main && ~/git/github/somewm/plans/scripts/install-scenefx.sh
#   cp ~/.config/somewm/rc.lua.pre-pr521-test ~/.config/somewm/rc.lua

mkdir -p ~/.local/log
LOG=~/.local/log/somewm-upstream-debug.log

# Rotate previous upstream-test log (last 5 kept).
if [ -f "$LOG" ]; then
    for n in 4 3 2 1; do
        [ -f "$LOG.$n" ] && mv "$LOG.$n" "$LOG.$((n+1))"
    done
    mv "$LOG" "$LOG.1"
fi

# Ensure /usr/local/lib is on the linker path (libscenefx may still live
# there from previous fork installs; harmless even if upstream doesn't use it).
if [[ ":${LD_LIBRARY_PATH:-}:" != *":/usr/local/lib:"* ]]; then
    export LD_LIBRARY_PATH="/usr/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

# Propagate display/session env to the systemd user bus so user services
# (portals, polkit, gnome-keyring) see this session. Same approach as the
# fork's start.sh — explicitly avoiding dbus-run-session to keep the bus
# shared with user@<uid>.service.
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-somewm}"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"

systemctl --user import-environment \
    DISPLAY WAYLAND_DISPLAY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP \
    XDG_RUNTIME_DIR XDG_DATA_DIRS XDG_CONFIG_DIRS PATH \
    SSH_AUTH_SOCK 2>/dev/null || true
dbus-update-activation-environment --all 2>/dev/null || true

echo "starting upstream somewm: $(somewm -v 2>&1 | head -1)"
echo "log: $LOG"

exec somewm -d 2>&1 | tee "$LOG"
