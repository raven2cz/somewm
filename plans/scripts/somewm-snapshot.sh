#!/bin/bash
# somewm-snapshot.sh — Capture pre-reload/pre-crash compositor state
#
# Creates a timestamped directory with debug logs, journal, dmesg,
# and compositor state for post-mortem analysis.
#
# Usage:
#   somewm-snapshot.sh              # create snapshot, print path
#   somewm-snapshot.sh --prune-only # just prune old snapshots
#
# Output: ~/.local/log/somewm-crashlogs/YYYYMMDD-HHMMSS/

set -euo pipefail

CRASHLOG_DIR="$HOME/.local/log/somewm-crashlogs"
DEBUG_LOG="$HOME/.local/log/somewm-debug.log"
ERROR_LOG="$HOME/.local/log/somewm-errors.log"
MAX_AGE_DAYS=30

# Prune snapshots older than MAX_AGE_DAYS
prune_old() {
    if [[ -d "$CRASHLOG_DIR" ]]; then
        find "$CRASHLOG_DIR" -maxdepth 1 -type d -mtime +$MAX_AGE_DAYS \
            -not -path "$CRASHLOG_DIR" -exec rm -rf {} + 2>/dev/null || true
    fi
}

# Always prune
prune_old

if [[ "${1:-}" == "--prune-only" ]]; then
    exit 0
fi

# Create timestamped snapshot directory
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SNAP_DIR="$CRASHLOG_DIR/$TIMESTAMP"
mkdir -p "$SNAP_DIR"

# 1. Debug log tail (last 500 lines)
if [[ -f "$DEBUG_LOG" ]]; then
    tail -500 "$DEBUG_LOG" > "$SNAP_DIR/debug-tail.log" 2>/dev/null || true
fi

# 2. Error log (full copy)
if [[ -f "$ERROR_LOG" ]]; then
    cp "$ERROR_LOG" "$SNAP_DIR/errors.log" 2>/dev/null || true
fi

# 3. Journal (user session, last 200 entries)
journalctl --user -n 200 --no-pager > "$SNAP_DIR/journal.log" 2>/dev/null || true

# 4. Kernel/GPU messages (errors and warnings)
dmesg --level=err,warn -T 2>/dev/null | tail -50 > "$SNAP_DIR/dmesg.log" || true

# 5. Compositor state (best-effort — compositor may be dead)
{
    echo "=== somewm snapshot $TIMESTAMP ==="
    echo ""
    if command -v somewm-client &>/dev/null; then
        echo "Version: $(somewm-client eval 'return awesome.version' 2>/dev/null | tail -1 || echo 'N/A')"
        echo "Clients: $(somewm-client eval 'return #client.get()' 2>/dev/null | tail -1 || echo 'N/A')"
        echo "Tags:    $(somewm-client eval 'local s=require("awful").screen.focused(); return s and #s.tags or "N/A"' 2>/dev/null | tail -1 || echo 'N/A')"
        echo "Screen:  $(somewm-client eval 'local s=require("awful").screen.focused(); return s and s.geometry.width.."x"..s.geometry.height or "N/A"' 2>/dev/null | tail -1 || echo 'N/A')"
    else
        echo "somewm-client not found"
    fi
    echo ""
    echo "Uptime: $(uptime)"
    echo "Memory: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
    echo "GPU:    $(nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used --format=csv,noheader 2>/dev/null || echo 'N/A')"
} > "$SNAP_DIR/compositor.txt" 2>/dev/null || true

echo "$SNAP_DIR"
