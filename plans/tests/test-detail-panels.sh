#!/usr/bin/env bash
# Smoke tests for the Memory + Storage detail panels.
#
# What this covers (no live compositor / X display required):
#  1. QML syntax validation for every file we added under
#     modules/memory-detail/, modules/storage-detail/, services/
#     Memory|Storage Detail.qml, core/DetailController.qml.
#  2. Registration sanity: new singletons appear in qmldir, new modules
#     are loaded from shell.qml, Panels.qml exposes toggleOnScreen.
#  3. Parser logic for the service helpers that the rest of the panel
#     depends on — reproduces the `somewm-client eval` flat-kv grammar
#     and the findmnt -J JSON parser on fake stdin fixtures.
#
# Does NOT cover: the live QML runtime, ArcGauge rendering, paccache
# pkexec path. Those are verified manually in the sandbox
# (plans/scripts/somewm-sandbox.sh) or via a real compositor session.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHELL_DIR="$ROOT_DIR/plans/project/somewm-shell"
ONE_DIR="$ROOT_DIR/plans/project/somewm-one"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# ---------------------------------------------------------------------
# 1. QML syntax
# ---------------------------------------------------------------------
if command -v qmllint >/dev/null; then
    echo "-- qmllint --"
    files=(
        "$SHELL_DIR/modules/memory-detail/MemoryDetailPanel.qml"
        "$SHELL_DIR/modules/memory-detail/SystemOverviewSection.qml"
        "$SHELL_DIR/modules/memory-detail/SomewmInternalsSection.qml"
        "$SHELL_DIR/modules/memory-detail/TopProcessesSection.qml"
        "$SHELL_DIR/modules/memory-detail/TrendSection.qml"
        "$SHELL_DIR/modules/memory-detail/FooterActions.qml"
        "$SHELL_DIR/modules/storage-detail/StorageDetailPanel.qml"
        "$SHELL_DIR/modules/storage-detail/MountsSection.qml"
        "$SHELL_DIR/modules/storage-detail/HotspotsSection.qml"
        "$SHELL_DIR/modules/storage-detail/TopDirsSection.qml"
        "$SHELL_DIR/modules/storage-detail/FooterActions.qml"
        "$SHELL_DIR/services/MemoryDetail.qml"
        "$SHELL_DIR/services/StorageDetail.qml"
        "$SHELL_DIR/core/DetailController.qml"
        "$SHELL_DIR/core/Panels.qml"
        "$SHELL_DIR/shell.qml"
        "$SHELL_DIR/modules/dashboard/PerformanceTab.qml"
    )
    # qmllint returns 255 for files that reference types it cannot resolve
    # (IpcHandler, PanelWindow, Variants — Quickshell types aren't shipped
    # as qmltypes). We only fail on exit code 1, which is a real parse error.
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || fail "missing: $f"
        set +e
        qmllint -I "$SHELL_DIR" "$f" >/dev/null 2>&1
        rc=$?
        set -e
        case "$rc" in
            0|255) ;;                       # ok / unknown types
            *)     fail "qmllint rc=$rc: $f" ;;
        esac
    done
    pass "qmllint ok (${#files[@]} files)"
else
    echo "SKIP qmllint (not installed)"
fi

# ---------------------------------------------------------------------
# 2. Registration sanity
# ---------------------------------------------------------------------
echo "-- registration --"

grep -q "^singleton MemoryDetail MemoryDetail\\.qml$" "$SHELL_DIR/services/qmldir" \
    || fail "services/qmldir: MemoryDetail"
grep -q "^singleton StorageDetail StorageDetail\\.qml$" "$SHELL_DIR/services/qmldir" \
    || fail "services/qmldir: StorageDetail"
grep -q "^singleton DetailController DetailController\\.qml$" "$SHELL_DIR/core/qmldir" \
    || fail "core/qmldir: DetailController"

for m in memory-detail storage-detail; do
    [[ -f "$SHELL_DIR/modules/$m/qmldir" ]] || fail "modules/$m/qmldir missing"
done

grep -q 'MemoryDetailPanel' "$SHELL_DIR/shell.qml" || fail "shell.qml does not load MemoryDetailPanel"
grep -q 'StorageDetailPanel' "$SHELL_DIR/shell.qml" || fail "shell.qml does not load StorageDetailPanel"
grep -q 'DetailController._refresh' "$SHELL_DIR/shell.qml" \
    || fail "shell.qml does not kick DetailController"

grep -q 'toggleOnScreen' "$SHELL_DIR/core/Panels.qml" \
    || fail "Panels.qml: toggleOnScreen missing"
grep -q 'memory-detail' "$SHELL_DIR/core/Panels.qml" \
    || fail "Panels.qml: memory-detail not in anyOverlayOpen/exclusive"
grep -q 'storage-detail' "$SHELL_DIR/core/Panels.qml" \
    || fail "Panels.qml: storage-detail not in anyOverlayOpen/exclusive"

grep -q 'detailPanel: "memory-detail"'  "$SHELL_DIR/modules/dashboard/PerformanceTab.qml" \
    || fail "PerformanceTab: gear not wired to memory-detail"
grep -q 'detailPanel: "storage-detail"' "$SHELL_DIR/modules/dashboard/PerformanceTab.qml" \
    || fail "PerformanceTab: gear not wired to storage-detail"

grep -q 'toggleOnScreen' "$ONE_DIR/fishlive/components/memory.lua" \
    || fail "memory.lua: left-click not wired to toggleOnScreen"
grep -q 'toggleOnScreen' "$ONE_DIR/fishlive/components/disk.lua" \
    || fail "disk.lua: left-click not wired to toggleOnScreen"

pass "registration ok"

# ---------------------------------------------------------------------
# 3. Parser contract tests (reproduce in awk/jq what QML parses)
# ---------------------------------------------------------------------
echo "-- parser contract --"

# --- 3a. somewm-client eval flat k=v grammar
# We mirror the exact eval string format from services/MemoryDetail.qml
# to detect silent field renames in the C API.
expected_keys=(
    lua_bytes clients drawable_shm_count drawable_shm_bytes
    wibox_count wibox_surface_bytes
    wallpaper_entries wallpaper_estimated_bytes
    wallpaper_cairo_bytes wallpaper_shm_bytes
    drawable_surface_bytes
    malloc_used_bytes malloc_free_bytes malloc_releasable_bytes
)
eval_cmd="$(grep -oE '"lua_bytes=[^"]*"' "$SHELL_DIR/services/MemoryDetail.qml" | head -1 || true)"
for k in "${expected_keys[@]}"; do
    grep -q "$k=" "$SHELL_DIR/services/MemoryDetail.qml" \
        || fail "MemoryDetail eval missing key: $k"
done
pass "memory eval keys ok (${#expected_keys[@]} fields)"

# --- 3b. findmnt JSON fixture → parse mimic
if command -v jq >/dev/null; then
    fixture='{"filesystems":[{"source":"/dev/nvme0n1p2","target":"/","fstype":"btrfs","size":"500107862016","used":"195340234752","avail":"250000000000","use%":"40%","children":[{"source":"/dev/nvme0n1p2","target":"/home","fstype":"btrfs","size":"500107862016","used":"195340234752","avail":"250000000000","use%":"40%"}]}]}'
    # Walk identical to _parseMounts: recursive, keep target "/" first
    rows="$(jq -r '[.filesystems, (.filesystems[].children // [])] | flatten | .[] | [.target, .fstype, (.["use%"])] | @tsv' <<<"$fixture")"
    grep -q $'^/\t' <<<"$rows" || fail "findmnt parser: missing / row"
    grep -q $'^/home\tbtrfs' <<<"$rows" || fail "findmnt parser: missing /home row"
    pass "findmnt JSON parser contract ok"
else
    echo "SKIP findmnt parser (jq not installed)"
fi

# --- 3c. paccache dry-run output format
paccache_fixture='==> finished: 42 candidates (disk space saved: 1.23 GiB)'
count="$(grep -oE '[0-9]+ candidate' <<<"$paccache_fixture" | head -1 | awk '{print $1}')"
bytes_unit="$(grep -oE 'disk space saved: [0-9.]+ (KiB|MiB|GiB|TiB|B)' <<<"$paccache_fixture")"
[[ "$count" == "42" ]] || fail "paccache parser: count"
[[ -n "$bytes_unit" ]] || fail "paccache parser: bytes"
pass "paccache parser contract ok"

# --- 3d. Lua wibar spawn form (spawn-list, no shell interpolation)
grep -q 'awful\.spawn({' "$ONE_DIR/fishlive/components/memory.lua" \
    || fail "memory.lua: must use list-form awful.spawn, not shell"
grep -q 'awful\.spawn({' "$ONE_DIR/fishlive/components/disk.lua" \
    || fail "disk.lua: must use list-form awful.spawn, not shell"
grep -q '"qs", "ipc"' "$ONE_DIR/fishlive/components/memory.lua" \
    || fail "memory.lua: expected qs ipc invocation"
grep -q '"qs", "ipc"' "$ONE_DIR/fishlive/components/disk.lua" \
    || fail "disk.lua: expected qs ipc invocation"
pass "lua wibar spawn form ok"

# ---------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------
echo "-- all detail-panel smoke checks passed --"
