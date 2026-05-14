#!/bin/bash
# Claude Code PreToolUse hook — snapshot before somewm reload/restart/exec
#
# Receives JSON on stdin with tool_input.command.
# Only fires snapshot when command matches somewm-client reload|restart|exec.

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)

if echo "$COMMAND" | grep -qE 'somewm-client\s+(reload|restart|exec)'; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SNAP=$("$SCRIPT_DIR/somewm-snapshot.sh" 2>/dev/null || true)
    if [[ -n "$SNAP" ]]; then
        echo "Pre-reload snapshot: $SNAP" >&2
    fi
fi

exit 0
