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
# 4. Round-2 review fixes: guard against regression
# ---------------------------------------------------------------------
echo "-- round-2 fix guards --"

# 4a. procsProc must use single gawk over all smaps_rollup, NOT a fork-per-pid
# loop. If someone re-introduces `for d in /proc/[0-9]*; do ... awk ...; done`
# that's a perf regression (~1k forks/5s on a busy desktop).
if grep -Eq 'for d in /proc/\[0-9\]\*; do.*awk' "$SHELL_DIR/services/MemoryDetail.qml"; then
    fail "MemoryDetail.procsProc: fork-per-pid awk loop re-introduced"
fi
grep -q "BEGINFILE" "$SHELL_DIR/services/MemoryDetail.qml" \
    || fail "MemoryDetail.procsProc: missing BEGINFILE/ERRNO guard"

# Smoke-exec the gawk pipeline if gawk is available, so a syntax regression
# surfaces here instead of silently at runtime.
if command -v gawk >/dev/null; then
    gawk_out="$(timeout 6 gawk '
        BEGINFILE{if (ERRNO) { nextfile } pid=FILENAME; sub(/^\/proc\//, "", pid); sub(/\/smaps_rollup$/, "", pid); p=0; r=0}
        /^Pss:/{p+=$2}
        /^Rss:/{r+=$2}
        ENDFILE{if (r > 0) printf "%d\t%d\t%s\n", p+0, r+0, pid}
    ' /proc/[0-9]*/smaps_rollup 2>/dev/null | wc -l)"
    [[ "$gawk_out" -gt 0 ]] || fail "procsProc gawk pipeline: produced 0 rows"
    pass "procsProc gawk pipeline runs (${gawk_out} rows)"
fi

# 4b. Schema-drift detector must bail on empty parse (no IPC response)
grep -q "gotAnyKey" "$SHELL_DIR/services/MemoryDetail.qml" \
    || fail "schema-drift: missing empty-parse bail (gotAnyKey)"
pass "schema-drift empty-parse guard present"

# 4c. paccacheDryProc must have empty initial command (rebuilt by function)
# Check the declared command in the Process block is `command: []`.
awk '
    /id: paccacheDryProc/{in_block=1}
    in_block && /command:/{print; exit}
' "$SHELL_DIR/services/StorageDetail.qml" | grep -q 'command: *\[\]' \
    || fail "paccacheDryProc: must declare command: [] (not static)"
pass "paccacheDryProc static command removed"

# 4d. paccacheRunProc must read exitCode in onExited, not StdioCollector
grep -q "onExited:" "$SHELL_DIR/services/StorageDetail.qml" \
    || fail "paccacheRunProc: missing onExited handler (exitCode race fix)"
if awk '/id: paccacheRunProc/,/^    }/' \
       "$SHELL_DIR/services/StorageDetail.qml" | \
   grep -q "paccacheRunProc\.exitCode"; then
    fail "paccacheRunProc: exitCode still read from StdioCollector (race)"
fi
pass "paccacheRunProc exitCode via onExited"

# 4e. topDirsProc must use du --max-depth=1, NOT shell glob
if grep -q 'du -sxb -- \* \.' "$SHELL_DIR/services/StorageDetail.qml"; then
    fail "topDirsProc: shell glob E2BIG regression"
fi
grep -q 'du -xb --max-depth=1' "$SHELL_DIR/services/StorageDetail.qml" \
    || fail "topDirsProc: must use du -xb --max-depth=1"
pass "topDirsProc uses du --max-depth=1"

# Smoke-exec the du command so a flag-removal regression is caught.
du_lines="$(timeout 15 du -xb --max-depth=1 "$HOME" 2>/dev/null | wc -l)"
[[ "$du_lines" -gt 0 ]] || fail "topDirs du pipeline: zero output"
pass "topDirs du pipeline runs (${du_lines} rows)"

# 4f. paccache unit regex must normalise to upper-case before lookup
grep -q 'toUpperCase' "$SHELL_DIR/services/StorageDetail.qml" \
    || fail "paccache unit: must normalise via toUpperCase"
pass "paccache unit regex case-normalised"

# 4g. Panels.toggleOnScreen pin ordering — _setPin must precede toggle()
awk '/function toggleOnScreen/,/^    }/' \
    "$SHELL_DIR/core/Panels.qml" \
  | awk '/_setPin/{ sp=NR } /toggle\(name\)/{ t=NR } END{ if (!(sp < t)) exit 1 }' \
    || fail "Panels.toggleOnScreen: _setPin must be called before toggle(name)"
pass "Panels.toggleOnScreen ordering correct"

# ---------------------------------------------------------------------
# 4½. Round-3 review fixes: guard against regression
# ---------------------------------------------------------------------
echo "-- round-3 fix guards --"

# 4h. procsProc MUST call `gawk`, never `awk`. On systems where /usr/bin/awk
# resolves to mawk/bwk, BEGINFILE/ENDFILE/ERRNO are no-ops and the scanner
# silently yields nothing (review round 3, sonnet).
if awk '/id: procsProc/,/^    }/' "$SHELL_DIR/services/MemoryDetail.qml" \
    | grep -Eq '^\s*"awk ' ; then
    fail "procsProc: must invoke gawk explicitly, not awk (portability)"
fi
awk '/id: procsProc/,/^    }/' "$SHELL_DIR/services/MemoryDetail.qml" \
    | grep -q '"gawk ' \
    || fail "procsProc: expected explicit gawk invocation"
pass "procsProc uses explicit gawk"

# 4i. Unread counter MUST be incremented inside BEGINFILE (same awk pass);
# a late `for d in /proc/[0-9]*` fallback would re-introduce the TOCTOU race
# between the glob and the scan (review round 3, sonnet).
awk '/id: procsProc/,/^    }/' "$SHELL_DIR/services/MemoryDetail.qml" \
    | grep -q 'BEGINFILE{if (ERRNO) { unread++' \
    || fail "procsProc: unread counter must live inside BEGINFILE"
if awk '/id: procsProc/,/^    }/' "$SHELL_DIR/services/MemoryDetail.qml" \
    | grep -Eq 'for d in /proc/\[0-9\]\*' ; then
    fail "procsProc: glob-based unread counter re-introduced (TOCTOU race)"
fi
pass "procsProc unread counter inside BEGINFILE"

# 4j. Unread stderr temp file must live under XDG_RUNTIME_DIR with a per-PID
# suffix. A shared /tmp path would race between concurrent panels.
awk '/id: procsProc/,/^    }/' "$SHELL_DIR/services/MemoryDetail.qml" \
    | grep -q 'XDG_RUNTIME_DIR' \
    || fail "procsProc: unread temp file must use XDG_RUNTIME_DIR"
awk '/id: procsProc/,/^    }/' "$SHELL_DIR/services/MemoryDetail.qml" \
    | grep -q 'somewm-procs-unread\.\$\$' \
    || fail "procsProc: unread temp file must include \$\$ (per-PID unique)"
pass "procsProc unread temp file is per-PID"

# 4k. topDirs pipeline must strip du rollup BEFORE sort, via `head -n -1`.
# Equality-based filtering in _parseTopDirs is unreliable when $HOME is a
# symlink (du resolves, $HOME doesn't) (review round 3, sonnet).
grep -qF 'head -n -1 | sort' "$SHELL_DIR/services/StorageDetail.qml" \
    || fail "topDirsProc: must pipe through head -n -1 before sort"
pass "topDirsProc strips du rollup before sort"

# Smoke-exec the full round-3 pipeline to verify `head -n -1` is supported
# by the local coreutils and the rollup is actually stripped.
if du_full="$(timeout 15 du -xb --max-depth=1 "$HOME" 2>/dev/null | head -n -1 | wc -l)"; then
    du_rollup="$(timeout 15 du -xb --max-depth=1 "$HOME" 2>/dev/null | wc -l)"
    [[ "$du_full" -eq "$((du_rollup - 1))" ]] \
        || fail "topDirs: head -n -1 did not strip exactly one row"
    pass "topDirs rollup-strip pipeline runs (${du_full} rows, stripped 1)"
fi

# ---------------------------------------------------------------------
# 5. Schema-drift: ALL documented keys must match MemoryDetail parser
# ---------------------------------------------------------------------
echo "-- schema-drift parser cross-check --"

# Extract the _expectedStatKeys list from MemoryDetail.qml
exp_keys=$(awk '
    /_expectedStatKeys: \[/{in_list=1; next}
    in_list && /\]/{exit}
    in_list { print }
' "$SHELL_DIR/services/MemoryDetail.qml" | \
  grep -oE '"[a-z_]+"' | tr -d '"' | sort)

# Compare against the handwritten test list. Delta = regression.
test_keys=$(printf '%s\n' "${expected_keys[@]}" | sort)
if [[ "$exp_keys" != "$test_keys" ]]; then
    diff <(echo "$exp_keys") <(echo "$test_keys") | head -20
    fail "schema-drift: _expectedStatKeys in MemoryDetail.qml diverged from test expected_keys"
fi
pass "MemoryDetail._expectedStatKeys matches test contract"

# ---------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------
echo "-- all detail-panel smoke checks passed --"
