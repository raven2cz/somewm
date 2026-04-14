#!/bin/bash
# check-headers.sh — lint header presence in somewm-one + somewm-shell
#
# Exits non-zero if a required Lua file is missing `@module`.
# Reports (but does not fail on) QML files without a top-of-file comment.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ONE="$REPO/project/somewm-one"
SHELL="$REPO/project/somewm-shell"

FAIL=0
check_module() {
    local f="$1"
    if ! grep -q '^-- @module' "$f"; then
        echo "FAIL: missing @module — $f"
        FAIL=1
    fi
}

echo "── Lua: fishlive/services/*.lua (required @module)"
for f in "$ONE"/fishlive/services/*.lua; do
    check_module "$f"
done

echo "── Lua: fishlive/components/*.lua (required @module)"
for f in "$ONE"/fishlive/components/*.lua; do
    check_module "$f"
done

echo "── Lua: fishlive/config/*.lua (required @module)"
for f in "$ONE"/fishlive/config/*.lua; do
    check_module "$f"
done

echo "── Lua: fishlive/*.lua core (required @module)"
for f in "$ONE"/fishlive/*.lua; do
    check_module "$f"
done

# QML header: `//` comment within the first 5 lines. `pragma Singleton` must
# stay on line 1 (Quickshell requirement), so the header sits below it.
qml_has_header() {
    head -5 "$1" | grep -q '^//'
}

echo "── QML: services/*.qml (report-only, // header in first 5 lines)"
for f in "$SHELL"/services/*.qml; do
    qml_has_header "$f" || echo "  miss: $f"
done

echo "── QML: components/*.qml (report-only, // header in first 5 lines)"
for f in "$SHELL"/components/*.qml; do
    qml_has_header "$f" || echo "  miss: $f"
done

echo
if [ $FAIL -eq 0 ]; then
    echo "OK — all required Lua headers present."
    exit 0
else
    echo "FAIL — fix missing @module lines above."
    exit 1
fi
