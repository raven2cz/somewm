#!/usr/bin/env bash
# somewm-memory-snapshot.sh — live memory attribution for the running compositor.
#
# Usage:
#   plans/scripts/somewm-memory-snapshot.sh
#   plans/scripts/somewm-memory-snapshot.sh --tsv
#   SOMEWM_CLIENT=./build/somewm-client plans/scripts/somewm-memory-snapshot.sh

set -euo pipefail

MODE="text"
if [[ "${1:-}" == "--tsv" ]]; then
    MODE="tsv"
fi

SOMEWM_CLIENT="${SOMEWM_CLIENT:-somewm-client}"
PID="${SOMEWM_PID:-}"
if [[ -z "$PID" ]]; then
    PID="$(pidof somewm 2>/dev/null | awk '{print $1}')"
fi

if [[ -z "$PID" || ! -r "/proc/$PID/status" ]]; then
    echo "somewm-memory-snapshot: somewm process not found" >&2
    exit 1
fi

kv_status() {
    awk '
        /^VmRSS:/    { printf "rss_kb=%s ", $2 }
        /^RssAnon:/  { printf "rss_anon_kb=%s ", $2 }
        /^RssFile:/  { printf "rss_file_kb=%s ", $2 }
        /^RssShmem:/ { printf "rss_shmem_kb=%s ", $2 }
        /^VmData:/   { printf "vm_data_kb=%s ", $2 }
        /^VmSwap:/   { printf "swap_kb=%s ", $2 }
        /^Threads:/  { printf "threads=%s ", $2 }
    ' "/proc/$PID/status"
}

kv_smaps() {
    if [[ ! -r "/proc/$PID/smaps_rollup" ]]; then
        return
    fi
    awk '
        /^Pss:/             { printf "pss_kb=%s ", $2 }
        /^Private_Dirty:/   { printf "private_dirty_kb=%s ", $2 }
        /^Private_Clean:/   { printf "private_clean_kb=%s ", $2 }
        /^Anonymous:/       { printf "anonymous_kb=%s ", $2 }
        /^ShmemPmdMapped:/  { printf "shmem_pmd_mapped_kb=%s ", $2 }
        /^FilePmdMapped:/   { printf "file_pmd_mapped_kb=%s ", $2 }
    ' "/proc/$PID/smaps_rollup"
}

kv_maps() {
    pmap -x "$PID" 2>/dev/null | awk '
        /rw---[[:space:]]+\[ anon \]$/ { anon += $3 }
        /memfd:drawable-shm/ { drawable_count++; drawable += $3 }
        /memfd:wayland-shm/ { wayland += $3 }
        /memfd:gdk-wayland/ { gdk += $3 }
        /nvidiactl/ { nvidiactl += $3 }
        END {
            printf "anon_maps_kb=%d drawable_shm_count=%d drawable_shm_kb=%d wayland_shm_kb=%d gdk_wayland_kb=%d nvidiactl_kb=%d ",
                anon, drawable_count, drawable, wayland, gdk, nvidiactl
        }
    '
}

kv_lua() {
    local lua='local ok,s=pcall(function() return somewm.memory.stats(true) end); if not ok then collectgarbage(); collectgarbage(); return string.format("lua_bytes=%d clients=%d screens=0 tags=0 drawins=0", math.floor(collectgarbage("count")*1024), #client.get()) end; return string.format("lua_bytes=%d clients=%d screens=%d tags=%d drawins=%d drawable_shm_count_api=%d drawable_shm_bytes_api=%d wibox_count=%d wibox_surface_bytes=%d wallpaper_entries=%d wallpaper_estimated_bytes=%d wallpaper_cairo_bytes=%d wallpaper_shm_bytes=%d drawable_surface_bytes=%d malloc_used_bytes=%d malloc_free_bytes=%d malloc_releasable_bytes=%d", s.lua_bytes or 0, s.clients or 0, s.screens or 0, s.tags or 0, s.drawins or 0, s.drawable_shm_count or 0, s.drawable_shm_bytes or 0, s.wibox_count or 0, s.wibox_surface_bytes or 0, s.wallpaper and s.wallpaper.entries or 0, s.wallpaper and s.wallpaper.estimated_bytes or 0, s.wallpaper and s.wallpaper.cairo_bytes or 0, s.wallpaper and s.wallpaper.shm_bytes or 0, s.drawables and s.drawables.surface_bytes or 0, s.malloc_used_bytes or 0, s.malloc_free_bytes or 0, s.malloc_releasable_bytes or 0)'
    local out
    out="$("$SOMEWM_CLIENT" eval "$lua" 2>/dev/null || true)"
    printf '%s\n' "$out" | tail -1
}

KV="timestamp=$(date +%s) pid=$PID $(kv_status)$(kv_smaps)$(kv_maps)$(kv_lua)"

if [[ "$MODE" == "tsv" ]]; then
    echo "$KV" | tr ' ' '\n' | awk -F= '
        NF == 2 { keys[++n]=$1; vals[$1]=$2 }
        END {
            for (i=1; i<=n; i++) {
                printf "%s%s", keys[i], i<n ? "\t" : "\n"
            }
            for (i=1; i<=n; i++) {
                printf "%s%s", vals[keys[i]], i<n ? "\t" : "\n"
            }
        }'
    exit 0
fi

echo "somewm memory snapshot"
echo "$KV" | tr ' ' '\n' | awk -F= 'NF == 2 { printf "  %-30s %s\n", $1, $2 }'
