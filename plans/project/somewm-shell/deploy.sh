#!/bin/bash
# Deploy somewm-shell to ~/.config/quickshell/somewm/
# Usage: ./deploy.sh [--dry-run]
#
# Copies the somewm-shell project from the repo to the Quickshell config dir.
# Copies config.default.json → config.json only if config.json doesn't exist.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.config/quickshell/somewm"

if [[ "${1:-}" == "--dry-run" ]]; then
    echo "Dry run — would sync:"
    rsync -av --exclude 'deploy.sh' --exclude 'config.default.json' --dry-run "$SCRIPT_DIR/" "$TARGET/"
    exit 0
fi

# Create target directory
mkdir -p "$TARGET"

# Sync (exclude deploy.sh and *.default.json)
rsync -av --exclude 'deploy.sh' --exclude 'config.default.json' "$SCRIPT_DIR/" "$TARGET/"

# Copy config.default.json → config.json only if not exists (preserve user edits)
if [[ ! -f "$TARGET/config.json" ]]; then
    cp "$SCRIPT_DIR/config.default.json" "$TARGET/config.json"
    echo "Created config.json from defaults"
fi

# Seed theme.json if not exists (ensures QS Theme singleton loads real colors)
THEME_JSON="$HOME/.config/somewm/themes/default/theme.json"
if [[ ! -f "$THEME_JSON" ]]; then
    mkdir -p "$(dirname "$THEME_JSON")"
    bash "$TARGET/theme-export.sh" 2>/dev/null || \
        cp "$TARGET/theme.default.json" "$THEME_JSON" 2>/dev/null || true
    echo "Seeded theme.json"
fi

echo ""
echo "Deployed somewm-shell to $TARGET"
echo "Launch: qs -c somewm"
