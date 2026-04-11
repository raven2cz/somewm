#!/bin/bash
# somewm-postmortem.sh — Analyze the most recent crash snapshot
#
# Reads latest ~/.local/log/somewm-crashlogs/*/ and prints a summary
# suitable for pasting into a Claude Code session or bug report.
#
# Usage:
#   somewm-postmortem.sh           # latest snapshot
#   somewm-postmortem.sh <path>    # specific snapshot directory

set -uo pipefail

CRASHLOG_DIR="$HOME/.local/log/somewm-crashlogs"

if [[ -n "${1:-}" ]]; then
    SNAP_DIR="$1"
else
    # Find the most recent snapshot
    if [[ ! -d "$CRASHLOG_DIR" ]]; then
        echo "No crashlog snapshots found in $CRASHLOG_DIR"
        exit 1
    fi
    SNAP_DIR=$(ls -1d "$CRASHLOG_DIR"/*/ 2>/dev/null | sort | tail -1)
    if [[ -z "$SNAP_DIR" ]]; then
        echo "No snapshots found"
        exit 1
    fi
fi

SNAP_NAME=$(basename "$SNAP_DIR")

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  somewm Post-mortem: $SNAP_NAME"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Compositor state
if [[ -f "$SNAP_DIR/compositor.txt" ]]; then
    echo "── Compositor State ──"
    cat "$SNAP_DIR/compositor.txt"
    echo ""
fi

# Critical errors from debug log
if [[ -f "$SNAP_DIR/debug-tail.log" ]]; then
    echo "── Critical Errors (debug log) ──"
    ERRORS=$(grep -iE 'SEGFAULT|SIGSEGV|SIGABRT|FATAL|CRITICAL|panic|assert|abort|error in exit' \
        "$SNAP_DIR/debug-tail.log" 2>/dev/null | tail -20)
    if [[ -n "$ERRORS" ]]; then
        echo "$ERRORS"
    else
        echo "(none found)"
    fi
    echo ""

    # Lua errors
    echo "── Lua Errors (debug log) ──"
    LUA_ERRORS=$(grep -E 'error|traceback|attempt to|stack traceback|bad argument' \
        "$SNAP_DIR/debug-tail.log" 2>/dev/null | grep -iv '\[HOTPLUG\]\|updatemons' | tail -15)
    if [[ -n "$LUA_ERRORS" ]]; then
        echo "$LUA_ERRORS"
    else
        echo "(none found)"
    fi
    echo ""
fi

# Lua error log
if [[ -f "$SNAP_DIR/errors.log" ]]; then
    ERRCOUNT=$(wc -l < "$SNAP_DIR/errors.log")
    if [[ "$ERRCOUNT" -gt 0 ]]; then
        echo "── Lua Error Log ($ERRCOUNT entries) ──"
        tail -20 "$SNAP_DIR/errors.log"
        echo ""
    fi
fi

# GPU/kernel issues
if [[ -f "$SNAP_DIR/dmesg.log" ]]; then
    echo "── GPU/Kernel Issues (dmesg) ──"
    GPU_ISSUES=$(grep -iE 'gpu|drm|nvidia|nouveau|amdgpu|fence|timeout|hung' \
        "$SNAP_DIR/dmesg.log" 2>/dev/null | tail -10)
    if [[ -n "$GPU_ISSUES" ]]; then
        echo "$GPU_ISSUES"
    else
        echo "(none found)"
    fi
    echo ""
fi

# Journal summary
if [[ -f "$SNAP_DIR/journal.log" ]]; then
    echo "── Journal (somewm-related, last 10) ──"
    JOURNAL=$(grep -iE 'somewm|wlroots|wayland|compositor|segfault|killed' \
        "$SNAP_DIR/journal.log" 2>/dev/null | tail -10)
    if [[ -n "$JOURNAL" ]]; then
        echo "$JOURNAL"
    else
        echo "(no somewm entries found)"
    fi
    echo ""
fi

echo "── Snapshot files ──"
ls -lh "$SNAP_DIR/" 2>/dev/null
echo ""
echo "Full snapshot: $SNAP_DIR"
