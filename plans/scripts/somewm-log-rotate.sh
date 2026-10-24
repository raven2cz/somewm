#!/bin/bash
# somewm-log-rotate.sh — Rotate somewm-debug.log (keep last 5 sessions)
#
# Called from start.sh before launching somewm.
# Shifts: .4→.5, .3→.4, .2→.3, .1→.2, current→.1
#
# Also prunes old crashlog snapshots.

set -euo pipefail

LOG="$HOME/.local/log/somewm-debug.log"
MAX_COPIES=5

if [[ ! -f "$LOG" ]]; then
    exit 0
fi

# Shift existing rotated logs
for (( i = MAX_COPIES - 1; i >= 1; i-- )); do
    next=$(( i + 1 ))
    if [[ -f "$LOG.$i" ]]; then
        mv "$LOG.$i" "$LOG.$next"
    fi
done

# Current → .1
mv "$LOG" "$LOG.1"

# Prune old crashlog snapshots while we're at it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "$SCRIPT_DIR/somewm-snapshot.sh" ]]; then
    "$SCRIPT_DIR/somewm-snapshot.sh" --prune-only 2>/dev/null || true
fi
