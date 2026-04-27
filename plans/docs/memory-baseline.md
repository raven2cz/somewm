# somewm memory baseline

Snapshot taken 2026-04-24 against a live session on the dev machine
(NVIDIA RTX 5070 Ti, 1 × 4K monitor, 9 tags, 1 XWayland client, idle).

Run `plans/scripts/somewm-memory-snapshot.sh` to reproduce; see
`CLAUDE.md` → "Memory diagnostics" for the toolchain.

## Live numbers

| metric                       | value        |
|------------------------------|--------------|
| RSS total                    | 1316 MiB     |
| PSS (proportional)           | 1129 MiB     |
| private_dirty                | 1012 MiB     |
| rss_anon                     | 640 MiB      |
| rss_file                     | 328 MiB      |
| rss_shmem                    | 348 MiB      |
| Lua heap after double GC     | 7.8 MiB      |
| glibc used / free / releasable | 319 / 117 / 33 MiB |
| drawable SHM (pmap)          | 348 MiB (11 buffers) |
| drawable SHM (API counter)   | 348 MiB (11 buffers) — match |
| wallpaper cache              | 569 MiB (9 entries × 64 MiB) |
| active wallpaper             | 32 MiB       |
| drawable surfaces (titlebar/drawin) | 495 KiB |
| nvidiactl                    | 24 MiB       |

API and pmap-derived counters agree exactly (drawable_shm_count=11
both, 348 MiB both). No counter drift, no leak signal.

## Attribution

Wallpaper cache dominates: 9 cached entries at 3840×2160, each holding
both a cairo image surface (32 MiB) and a drawable-shm buffer (32 MiB)
for fast tag-switch blit. Cache cap is 32 entries; we sit at 9.

    wallpaper cache entries:  569 MiB
    active wallpaper:          32 MiB
    ---------------------------------
    total wallpaper footprint: 601 MiB

RSS minus wallpapers ≈ **714 MiB** — the somewm "baseline" for a
single 4K monitor on NVIDIA.

Of that 714 MiB:

- NVIDIA proprietary driver context mapped into process (~200 MiB of
  anon, ~80 MiB of libnvidia-*.so file-backed)
- Shared libraries (cairo, pango, gdk-pixbuf, glib, luajit, wlroots):
  ~150 MiB file-backed
- glibc heap retention (malloc): 150 MiB of arena pages the allocator
  has retained after `free()`; not returned to kernel due to
  fragmentation. `malloc_releasable_bytes=33 MiB` would be trimmable
  with `malloc_trim(0)` if ever desired.
- Other drawable SHM (titlebars, drawins): 63 MiB
- Lua heap + AwesomeWM framework state: ~10 MiB

## Comparison against sway on the same hardware

Rough estimate, same NVIDIA 4K single-monitor idle:

| compositor            | baseline RSS   | note |
|-----------------------|----------------|------|
| cage / labwc          | ~80 MiB        | minimal wlroots |
| sway                  | ~300–400 MiB   | wlroots + bar, driver context dominates |
| **somewm (no wp cache)** | **~700 MiB** | + Lua + AwesomeWM cairo widgets |
| somewm (with wp cache) | ~1.3 GiB      | + 9-tag wallpaper preload |

**somewm ≈ 2× sway** on matched hardware. The overhead comes from the
AwesomeWM API surface (Lua runtime, signal system, object model) and
the cairo-based widget pipeline — every wibox/drawable is a CPU-side
`cairo_image_surface_t` duplicated as an SHM buffer for wlroots.
sway renders its bar directly through GL without the CPU buffer
round-trip.

This is a conscious design tradeoff, not a leak. The memory pattern is
stable: counter values agree across `/proc`, pmap, and the API, and
`somewm.memory.stats(true)` trend stays flat under idle / tag-switch /
reload workloads (see `plans/scripts/somewm-memory-trend.sh`).

## On Lua GC

Lua has a fully functional incremental GC. `collectgarbage("collect")`
or `somewm.memory.stats(true)` (double pass) reliably drops `lua_bytes`
to the live set (currently ~7.8 MiB).

The GC only reclaims **Lua-allocated** objects: tables, strings,
closures, userdata headers. It does **not** free the heavy C-side
allocations held by Lua objects — cairo surfaces, pango layouts,
pixbufs. Those are released by explicit `:destroy()` paths or
`__gc` metatables, which call back into the C side.

Even when the C-side resource is freed, glibc may keep the pages in
its arena (malloc retention) instead of returning them to the kernel.
PSS drops, RSS often does not — expected behaviour.

Consequence for leak hunting: `lua_bytes` is almost always a small
fraction of RSS. A growing `lua_bytes` is a Lua leak; a growing
`drawable_shm_bytes` / `wibox_surface_bytes` with stable `lua_bytes`
is a C-side leak the GC cannot help with. The counters in
`somewm.memory.stats()` let you tell the two apart.

## Measurement toolchain

Three layers, used together. Each one answers a different question.

### Layer 1 — `somewm.memory.stats()` (Lua-side API, process-local)

Cheapest probe. Runs inside the compositor, returns a table. Pass
`true` to force a double Lua GC before sampling, so the number
reflects the live set, not transient allocations.

```bash
# Lua heap after forced GC
somewm-client eval 'local s = somewm.memory.stats(true); return s.lua_bytes'

# Wallpaper cache summary
somewm-client eval 'local s = somewm.memory.wallpaper_cache(); \
    return s.entries.." entries, "..s.estimated_bytes.." bytes"'

# Per-entry wallpaper breakdown (path, screen, dimensions, bytes)
somewm-client eval 'local s = somewm.memory.wallpaper_cache(true); \
    for i, it in ipairs(s.items) do print(i, it.path, it.screen_index, \
    it.width, it.height, it.cairo_bytes, it.shm_bytes, it.current) end'

# Drawable surface accounting
somewm-client eval 'local s = somewm.memory.drawables(); return s.surface_bytes'
```

Read-only. Counter values come from structs updated at create/destroy
time — they cannot drift against reality as long as those code paths
are correct. Cross-verify with pmap to prove there is no drift
(see Layer 2).

### Layer 2 — `plans/scripts/somewm-memory-snapshot.sh` (one-shot snapshot)

Glue layer that combines `/proc/PID/status`, `/proc/PID/smaps_rollup`,
`pmap -x PID`, and the Lua-side API into one aggregated report.

```bash
# Human-readable
plans/scripts/somewm-memory-snapshot.sh

# TSV for spreadsheets / diff across snapshots
plans/scripts/somewm-memory-snapshot.sh --tsv > /tmp/mem-before.tsv
# ... do something ...
plans/scripts/somewm-memory-snapshot.sh --tsv > /tmp/mem-after.tsv
diff /tmp/mem-before.tsv /tmp/mem-after.tsv
```

Key fields and what they mean:

- `rss_kb`, `pss_kb`, `private_dirty_kb` — kernel-side process
  memory, ground truth for total footprint.
- `anonymous_kb` — pure anonymous maps (heap + driver state).
- `drawable_shm_kb` / `drawable_shm_count` — pmap-derived count of
  live `memfd:drawable-shm` maps. Should match `drawable_shm_count_api`
  and `drawable_shm_bytes_api` from the Lua API. A mismatch means
  either a counter drift bug or a buffer that bypassed our
  create/destroy helpers.
- `wallpaper_estimated_bytes` — somewm-owned wallpaper cache.
- `drawable_surface_bytes`, `wibox_surface_bytes` — Cairo surfaces.
- `malloc_*_bytes` — glibc allocator internal view (used / free /
  releasable), useful for spotting heap fragmentation.

### Layer 3 — `plans/scripts/somewm-memory-trend.sh` (over time, under workload)

Runs snapshots at intervals while optionally driving a workload.
Writes `samples.tsv` + `summary.txt` under
`tests/bench/results/memory/YYYYMMDD-HHMMSS/`.

Use one flag per phase, or `--all` to combine:

```bash
# Phase A — idle stability: is RSS stable without user action?
plans/scripts/somewm-memory-trend.sh --idle 60

# Phase B — workload: does tag switching leak anything?
plans/scripts/somewm-memory-trend.sh --tag-switch 500

# Phase C — lifecycle: does config reload leak C state?
plans/scripts/somewm-memory-trend.sh --reload 5

# Combined smoke run (short idle + tag switches + reloads)
plans/scripts/somewm-memory-trend.sh --all
```

The script calls `collectgarbage(); collectgarbage(); somewm.memory.stats(true)`
between samples so growth is not confused with transient allocations.
`summary.txt` reports deltas in MiB for RSS, PSS, Lua, wallpaper, and
drawable-shm.

## Three-phase workflow for progressive measurement

Use this as a template whenever you want to measure a change
(new feature, refactor, upstream merge, suspected leak):

**Phase A — Baseline capture.** With the compositor in a known-clean
idle state (no user interaction, after a couple of minutes to settle):

```bash
plans/scripts/somewm-memory-snapshot.sh --tsv > /tmp/mem-baseline.tsv
```

Record the git SHA and any environment notes alongside the TSV.

**Phase B — Workload.** Drive the scenario you want to test. For
leak hunting that is usually repeated operations — tag switching,
reloads, client open/close cycles. For UX footprint questions it can
be simply "open Firefox and browse for 10 minutes".

For automated repeatable workloads use the trend script:

```bash
plans/scripts/somewm-memory-trend.sh --tag-switch 500 \
    --out-dir tests/bench/results/memory/$(date +%Y%m%d-%H%M%S)
```

**Phase C — Post-workload capture.** After the workload, and after a
few seconds of idle to let Lua GC and wlroots buffer pools settle:

```bash
# Force a GC to remove any Lua transient
somewm-client eval 'collectgarbage(); collectgarbage(); return "ok"'
plans/scripts/somewm-memory-snapshot.sh --tsv > /tmp/mem-after.tsv
diff /tmp/mem-baseline.tsv /tmp/mem-after.tsv
```

**Interpretation:**

- **Flat RSS and flat counters → no leak.** glibc retention may rise
  (`malloc_free_bytes`), that is fragmentation, not a leak.
- **`lua_bytes` grew, the rest flat → Lua leak.** Something keeps a
  reference to an object (signal handler holding a widget, closure
  capturing a client, etc). Hunt in Lua code.
- **`drawable_shm_bytes_api` or `wibox_surface_bytes` grew → C-side
  leak.** A `create_*` without a matching `destroy_*`. Check
  `objects/drawable.c` and `objects/wibox.c` counter paths.
- **`wallpaper_estimated_bytes` grew but entries look correct →
  cache growth, not a leak.** Cap is 32 entries in
  `WALLPAPER_CACHE_MAX`.
- **pmap `drawable_shm_kb` ≠ API `drawable_shm_bytes_api` → counter
  drift.** The counter path is wrong; pmap is ground truth. Fix the
  create/destroy bookkeeping.
- **RSS grew, no counter grew, `lua_bytes` flat → look outside
  somewm.** Most likely the NVIDIA driver or a wlroots buffer pool;
  not a somewm-owned allocation.

This gives you a repeatable, interpretable measurement. Keep the
baseline TSV in the PR/issue that introduced the change so future
comparisons have a reference point.
