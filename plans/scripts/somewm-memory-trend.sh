#!/usr/bin/env bash
# somewm-memory-trend.sh — repeated live memory snapshots with optional workload.
#
# Usage:
#   plans/scripts/somewm-memory-trend.sh --idle 60
#   plans/scripts/somewm-memory-trend.sh --tag-switch 500
#   plans/scripts/somewm-memory-trend.sh --reload 5
#   plans/scripts/somewm-memory-trend.sh --all

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOT="$SCRIPT_DIR/somewm-memory-snapshot.sh"
SOMEWM_CLIENT="${SOMEWM_CLIENT:-somewm-client}"
OUT_DIR="${OUT_DIR:-$PWD/tests/bench/results/memory/$(date +%Y%m%d-%H%M%S)}"
INTERVAL="${INTERVAL:-5}"
IDLE_SECONDS=0
TAG_SWITCHES=0
RELOADS=0

usage() {
    sed -n '2,12p' "$0" >&2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --idle) IDLE_SECONDS="$2"; shift 2 ;;
        --tag-switch) TAG_SWITCHES="$2"; shift 2 ;;
        --reload) RELOADS="$2"; shift 2 ;;
        --interval) INTERVAL="$2"; shift 2 ;;
        --out-dir) OUT_DIR="$2"; shift 2 ;;
        --all) IDLE_SECONDS=30; TAG_SWITCHES=500; RELOADS=5; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
done

mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/samples.tsv"
SUMMARY="$OUT_DIR/summary.txt"

snapshot_line() {
    local phase="$1"
    local raw header values
    raw="$("$SNAPSHOT" --tsv)"
    header="$(printf '%s\n' "$raw" | sed -n '1p')"
    values="$(printf '%s\n' "$raw" | sed -n '2p')"
    if [[ ! -f "$OUT" ]]; then
        printf 'phase\t%s\n' "$header" > "$OUT"
    fi
    printf '%s\t%s\n' "$phase" "$values" >> "$OUT"
}

gc_once() {
    "$SOMEWM_CLIENT" eval 'collectgarbage(); collectgarbage(); if root.memory_stats then root.memory_stats(true) end; return "ok"' >/dev/null 2>&1 || true
}

sample_idle() {
    local phase="$1"
    local seconds="$2"
    local elapsed=0
    while [[ "$elapsed" -le "$seconds" ]]; do
        gc_once
        snapshot_line "$phase"
        sleep "$INTERVAL"
        elapsed=$((elapsed + INTERVAL))
    done
}

run_tag_switches() {
    local n="$1"
    snapshot_line "tag_switch_before"
    for i in $(seq 1 "$n"); do
        "$SOMEWM_CLIENT" eval "local s=require('awful').screen.focused(); if s and s.tags and #s.tags > 0 then s.tags[(($i - 1) % #s.tags) + 1]:view_only() end; return 'ok'" >/dev/null 2>&1 || true
        if (( i % 50 == 0 )); then
            gc_once
            snapshot_line "tag_switch_$i"
        fi
    done
    sleep 2
    gc_once
    snapshot_line "tag_switch_after"
}

run_reloads() {
    local n="$1"
    snapshot_line "reload_before"
    for i in $(seq 1 "$n"); do
        "$SOMEWM_CLIENT" reload >/dev/null 2>&1 || true
        sleep 2
        gc_once
        snapshot_line "reload_$i"
    done
    snapshot_line "reload_after"
}

echo "Writing memory trend to $OUT_DIR"
snapshot_line "start"

if [[ "$IDLE_SECONDS" -gt 0 ]]; then
    sample_idle "idle" "$IDLE_SECONDS"
fi

if [[ "$TAG_SWITCHES" -gt 0 ]]; then
    run_tag_switches "$TAG_SWITCHES"
fi

if [[ "$RELOADS" -gt 0 ]]; then
    run_reloads "$RELOADS"
fi

gc_once
snapshot_line "end"

{
    echo "Memory trend: $OUT"
    echo ""
    awk -F'\t' '
        NR == 1 {
            for (i=1; i<=NF; i++) col[$i]=i
            next
        }
        NR == 2 {
            start_rss=$col["rss_kb"]; start_pss=$col["pss_kb"]; start_lua=$col["lua_bytes"];
            start_wp=$col["wallpaper_estimated_bytes"]; start_draw=$col["drawable_shm_kb"];
        }
        {
            phase=$1; rss=$col["rss_kb"]; pss=$col["pss_kb"]; lua=$col["lua_bytes"];
            wp=$col["wallpaper_estimated_bytes"]; draw=$col["drawable_shm_kb"];
        }
        END {
            printf "last_phase=%s\n", phase
            printf "rss_delta=%.1f MiB\n", (rss-start_rss)/1024
            printf "pss_delta=%.1f MiB\n", (pss-start_pss)/1024
            printf "lua_delta=%.1f MiB\n", (lua-start_lua)/1024/1024
            printf "wallpaper_delta=%.1f MiB\n", (wp-start_wp)/1024/1024
            printf "drawable_shm_delta=%.1f MiB\n", (draw-start_draw)/1024
        }' "$OUT"
} | tee "$SUMMARY"
