#!/usr/bin/env bash
# Smoke tests for fork-local memory diagnostic scripts.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SNAPSHOT="$ROOT_DIR/plans/scripts/somewm-memory-snapshot.sh"
TREND="$ROOT_DIR/plans/scripts/somewm-memory-trend.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_CLIENT="$TMP_DIR/somewm-client"
cat > "$FAKE_CLIENT" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "reload" ]]; then
    exit 0
fi
if [[ "${1:-}" == "eval" ]]; then
    printf 'OK\n'
    printf 'lua_bytes=4242 clients=3 screens=1 tags=9 drawins=2 drawable_shm_count_api=5 drawable_shm_bytes_api=8192 wibox_count=1 wibox_surface_bytes=4096 wallpaper_entries=2 wallpaper_estimated_bytes=16384 wallpaper_cairo_bytes=8192 wallpaper_shm_bytes=8192 drawable_surface_bytes=2048 malloc_used_bytes=1024 malloc_free_bytes=2048 malloc_releasable_bytes=512\n'
    exit 0
fi
exit 0
EOF
chmod +x "$FAKE_CLIENT"

echo "syntax: snapshot"
bash -n "$SNAPSHOT"

echo "syntax: trend"
bash -n "$TREND"

echo "usage: snapshot text"
text="$(
    SOMEWM_PID="$$" SOMEWM_CLIENT="$FAKE_CLIENT" "$SNAPSHOT"
)"
grep -q "somewm memory snapshot" <<<"$text"
grep -q "lua_bytes" <<<"$text"
grep -q "wallpaper_estimated_bytes" <<<"$text"

echo "usage: snapshot tsv"
tsv="$(
    SOMEWM_PID="$$" SOMEWM_CLIENT="$FAKE_CLIENT" "$SNAPSHOT" --tsv
)"
header="$(sed -n '1p' <<<"$tsv")"
values="$(sed -n '2p' <<<"$tsv")"
grep -q "lua_bytes" <<<"$header"
grep -q "wallpaper_estimated_bytes" <<<"$header"
grep -q "4242" <<<"$values"

echo "usage: trend"
out_dir="$TMP_DIR/memory-trend"
SOMEWM_PID="$$" SOMEWM_CLIENT="$FAKE_CLIENT" \
    "$TREND" --idle 0 --interval 1 --out-dir "$out_dir" >/dev/null
test -s "$out_dir/samples.tsv"
test -s "$out_dir/summary.txt"
grep -q "Memory trend:" "$out_dir/summary.txt"
grep -q "lua_delta=" "$out_dir/summary.txt"

echo "ok"
