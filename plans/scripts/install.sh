#!/bin/bash
# Build and install somewm (v2 line: upstream 2.x + thin fork delta).
#
# What this does:
#   1. Builds the release tree in build/ (`make`); wlroots 0.20.2 is built
#      from the wrap with somewm's corner diff and linked in
#   2. Removes leftovers of the v1 (legacy/v1) SceneFX install from
#      /usr/local that the new build never overwrites
#   3. Installs to /usr/local with `sudo make install` (which also wipes the
#      installed Lua tree first, so no stale v1 Lua module can shadow v2)
#   4. Verifies the binary links and reports its version
#
# Usage:
#   ./plans/scripts/install.sh          # build + install
#   ./plans/scripts/install.sh --check  # only verify the current install
#
# Replaces install-scenefx.sh from the v1 line: v2 has no SceneFX build.
set -euo pipefail

SRCDIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILDDIR="$SRCDIR/build"
PREFIX=/usr/local

red()    { printf '\033[1;31m%s\033[0m\n' "$*"; }
green()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[1;33m%s\033[0m\n' "$*"; }

# Files the v1 SceneFX install left in /usr/local. v2 neither builds nor links
# them, and the Lua modules would shadow nothing (make install wipes the Lua
# tree), but a stale libscenefx confuses ldd checks and future debugging.
legacy_leftovers() {
    compgen -G "$PREFIX/lib/libscenefx-*" || true
    compgen -G "$PREFIX/lib/pkgconfig/scenefx-*.pc" || true
    [[ -d "$PREFIX/include/scenefx-0.4" ]] && echo "$PREFIX/include/scenefx-0.4"
    [[ -d "$PREFIX/include/scenefx-0.5" ]] && echo "$PREFIX/include/scenefx-0.5"
    return 0
}

check() {
    local ok=true bin="$PREFIX/bin/somewm"
    if [[ -x "$bin" ]]; then
        green "  somewm binary: $bin"
        green "  version: $("$bin" --version 2>&1 | head -1)"
    else
        red "  somewm binary: NOT FOUND at $bin"; ok=false
    fi
    if [[ -x "$PREFIX/bin/somewm-client" ]]; then
        green "  somewm-client: $PREFIX/bin/somewm-client"
    else
        red "  somewm-client: NOT FOUND"; ok=false
    fi
    local missing
    missing=$(ldd "$bin" 2>&1 | grep "not found" || true)
    if [[ -n "$missing" ]]; then
        red "  missing libraries:"; echo "$missing"; ok=false
    else
        green "  ldd: all libraries resolve"
    fi
    if ldd "$bin" 2>/dev/null | grep -q scenefx; then
        red "  binary links libscenefx: this is a v1 build, not v2"; ok=false
    fi
    local left
    left=$(legacy_leftovers)
    [[ -n "$left" ]] && yellow "  v1 leftovers still present:" && echo "$left"
    $ok && green "All good." || { red "Issues found."; return 1; }
}

if [[ "${1:-}" == "--check" ]]; then
    check
    exit $?
fi

# A previous `sudo ninja install` can leave root-owned objects in build/.
if [[ -d "$BUILDDIR" ]] && find "$BUILDDIR" -not -user "$USER" -print -quit 2>/dev/null | grep -q .; then
    echo "==> Reclaiming root-owned files in $BUILDDIR (sudo)..."
    sudo chown -R "$USER:$(id -gn)" "$BUILDDIR"
fi

# A build/ configured by the v1 line carries options v2 no longer has
# (scenefx, wlroots_version, xwayland); meson refuses those, so start clean.
if [[ -f "$BUILDDIR/meson-info/intro-buildoptions.json" ]] &&
   grep -q '"name": "scenefx"' "$BUILDDIR/meson-info/intro-buildoptions.json"; then
    yellow "==> build/ was configured by the v1 line; removing it"
    rm -rf "$BUILDDIR"
fi

echo "==> Building (make)..."
make -C "$SRCDIR"

left=$(legacy_leftovers)
if [[ -n "$left" ]]; then
    echo "==> Removing v1 SceneFX leftovers (sudo):"
    echo "$left"
    echo "$left" | xargs sudo rm -rf
fi

echo "==> Installing to $PREFIX (sudo)..."
sudo make -C "$SRCDIR" install
sudo ldconfig

echo "==> Verifying..."
check

echo
echo "Next: switch to a TTY and run ~/git/github/somewm/plans/scripts/start.sh"
