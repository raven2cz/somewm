# Kolo 10 — Upstream Sync (wlroots 0.20 + SceneFX 0.5)

Date: 2026-08-23
Branch: `sync/upstream-2026-08-23-kolo10` (from `upstream/main` @ `c7b3208`)
Methodology: **branch FROM upstream, re-apply fork features** (kolo8/kolo9 rule)
Status: **Phases 0-4 DONE, sandbox-verified. NOT merged — awaiting live DRM test.**

## Starting point

| | |
|---|---|
| upstream commits to take | 66 |
| fork commits on top | 225 |
| merge base | `9721b46` (the base kolo9b branched from — git found it, so the 3-way merge was exact) |
| result | behind 0, ahead 230 |

## The v2 question, answered

Both `upstream/main` and the fork carry `version: '2.0.0-dev'` in `meson.build`,
set by `22b226d chore: prepare main for 2.0 development` back in April. That is
a version string, not the 2.0 rework.

The actual 2.0 work lives in branches that are **not** in upstream/main and are
stale:

| branch | ahead of main | behind | last activity |
|---|---|---|---|
| `feat/2.0-foundation` | 56 | 257 | 2026-04-02 |
| `feat/2.0-event-queue` | 19 | 160 | 2026-04-17 |
| `feat/clay-everywhere` | 19 | 81 | 2026-06-17 |

`feat/2.0-foundation` would be 378 files, +16 617 / −25 685 — that is the "mrak
změn". It is not in this sync and cannot merge as-is.

## Impact on somewm-one / somewm-shell: none

Upstream removed a set of APIs in this window. Cross-referenced against both
dependent projects (23 modules somewm-one requires, 12 of which upstream
touched):

| removed upstream | somewm-one | somewm-shell |
|---|---|---|
| `gears.wallpaper` (module) | 0 | 0 |
| `naughty.notify` | 0 | 0 |
| `awful.util.*` | 0 (comment only) | 0 |
| `gears.filesystem.get_dir` / `.mkdir` | 0 | 0 |
| `theme_assets.recolor_titlebar_focus/_normal` | 0 | 0 |
| `gears.object.add_signal` | 0 | 0 |
| `menubar.get` | 0 | 0 |
| `api_level` | 0 | 0 |

The shell talks to the compositor only through `somewm-client eval`, reaching
`beautiful`, `awful.screen.focused().tags` and somewm-one's own
`fishlive.services.wallpaper`. IPC commands `wallpaper.set` / `wallpaper.color`
keep their names; only their implementation moved to `awful.wallpaper`.

**Neither project needs a change.**

## Phases

### Phase 1 — build files (`df552b7`)

wlroots 0.20 + SceneFX 0.5. Upstream added a `wlroots_version` combo
(`auto|0.19|0.20`) with per-version wraps; SceneFX releases track wlroots
one-to-one, so its version follows that option the same way, with
`subprojects/scenefx-0.4.wrap` and `scenefx-0.5.wrap`.

Arch meets every wlroots-0.20 floor, so `auto` picks 0.20 here.

**Requires `wlroots0.20` installed** (`pacman -S wlroots0.20`; it coexists with
0.19). Without it wlroots builds from source, and SceneFX — which ships its own
copies of some wlroots internals — then collides at link time with a static
wlroots ("multiple definition of `output_pending_resolution`"). meson.build
forces a shared subproject build when SceneFX is enabled to cover that case.

### Phase 2 — mechanical bulk (`d5932ba`)

118 fork-only files. Two exclusions: `tests/test-api-level.lua` (upstream
removed `api_level` in `c41b45e`, so the test is dead by design) and
`__pycache__` (never belonged in git).

### Phase 3 — C reconcile (`b975afe`)

15 conflicting files. Full rationale is in the commit message; the summary:

- **Upstream won** where it reworked what the fork had: the Lgi closure guard
  and hot-reload teardown (`b43b26f`, `c351ac4` — and `plans/done` records the
  fork's guard still crashing on the fifth reload), the CSD/fullscreen memento
  handling (`d56053c`, `cac3fcb`, `a6fe4b5`, `ab4e051`), the mousegrabber
  helper.
- **Fork won** where upstream removed something still in use: the wallpaper
  cache and `root.wp_*` overlays in `root.c` (rebuilt as the fork file plus the
  four upstream commits that touch it for other reasons), the matching
  `globalconf.h` fields, and the focus path in `somewm_api.c` (upstream still
  calls `client_wants_focus()`, which the override-redirect rewrite deleted).
- **Both merged** for `objects/client.{c,h}`, `window.c`, `protocols.c`,
  `input.c` — upstream's popups tree and refactors alongside the fork's SceneFX
  border frame, opacity re-apply and post-grab `motionnotify` (#521).

### SceneFX 0.4 → 0.5 API migration

Two breaking changes, both hidden behind `scenefx_compat.h` so the tree builds
against either version:

| | 0.4 | 0.5 |
|---|---|---|
| corners | one radius + `enum corner_location` bitmask | per-corner `struct fx_corner_radii` |
| per-client blur | a flag on every buffer in the client's tree | its own scene node |

`somewm_corners_t` + `somewm_scene_*_set_corners()` express the fork's intent
(all / top / bottom / none) either way. The blur node is created per client,
sized to the content area and lowered behind it, with
`should_only_blur_bottom_layer` false for the same reason the 0.4 path passed
`optimized=false`: the bottom layer is only the wallpaper, so overlapping
windows would show through as wallpaper instead of their live content.

### Phase 4 — verification

- Full suite: **151 tests**, one failure — `test-floating-layout`, flaky under
  load, 3/3 and 8/8 when run alone, and equally flaky on `main`.
- Fork feature tests pass: tag-slide, SceneFX corner radius / shadow / blur,
  memory stats, the whole XWayland set.
- Visual check in the sandbox: rounded corners, shadow, focus border and
  **backdrop blur** all render (blur confirmed against a translucent terminal —
  wallpaper blurred inside the window, sharp outside).

**One real regression caught here, and only by exercising the feature**
(`e177be1`): `somewm.c` lost its `wallpaper_cache_init()` call. There was no
conflict — upstream simply has no such call, since it deleted the cache — so
the merge took upstream's file and the list head stayed NULL. Every cache
insert then no-opped while still reporting success. The symptom was
`wallpaper_cache_stats().entries == 0` where the pre-sync binary reported 9,
which is what tag-slide animates through. A build-only check would have missed
it entirely.

Also strengthened: `test-scenefx-backdrop-blur` asserted only that Lua stored
the flag, so it would have passed through the whole 0.5 rewrite. It now asserts
`client._has_blur_node`, i.e. that the effect is attached (verified by
inverting the assertion).

## Known / not regressions

- `root.wp_snapshot()` returns nil in the nested sandbox. **Not a regression** —
  A/B tested against the pre-sync binary, which does the same. The cache fills
  (9 entries) but no entry is marked current in the sandbox, and the fallback
  path's overlay creation does not take. Tag-slide works on the live session;
  worth re-checking there.
- `gears.wallpaper` is no longer registered on the `gears` table (upstream
  dropped that line). `require("gears.wallpaper")` still works, which is how the
  fork uses it.
- `awful/ipc.lua` now uses `awful.wallpaper` for its wallpaper commands. The
  fork's cache-aware path is not in it; `fishlive.services.wallpaper` fills the
  cache itself via `root.wallpaper_cache_preload`.
- `make test` aborted at its first target because upstream added
  `tests/check-lua-compat.sh` and the fork-only `lua/awful/anim_client.lua` used
  `goto continue`, which Lua 5.1 cannot parse. Fixed in `43d0bd9`; nothing else
  in the suite had been running until then.

## Verified on both graphics stacks

Full suite, `build-test` reconfigured per stack:

| stack | result |
|---|---|
| wlroots 0.20 + SceneFX 0.5 | 151 tests, only `test-floating-layout` failing |
| wlroots 0.19 + SceneFX 0.4 | 151 tests, only `test-floating-layout` failing |

`test-floating-layout` is flaky under load and fails the same way on `main`.
The sync is therefore green on either stack, and pinning to 0.19 costs nothing
in coverage.

## Known defect: wlroots 0.20 + SceneFX 0.5 corrupts borders on NVIDIA

Confirmed by A/B on the live session, same commit both times:

| graphics stack | client borders |
|---|---|
| wlroots 0.19 + SceneFX 0.4 | correct |
| wlroots 0.20 + SceneFX 0.5 | first window correct, every later window corrupted; dragging flickers |

Since the compositor code is identical, the fault is in the new graphics stack
or in how this fork drives it -- not in the sync reconcile.

Ruled out along the way:
- **Blur.** `SOMEWM_BLUR_BOTTOM_ONLY=1` (cached bottom layer instead of the
  live framebuffer, i.e. SceneFX's own example configuration) does not help,
  which also rules out the partial-damage save/restore path a gpt-5.6-sol
  audit had proposed as the likely cause.
- **Scene reordering.** `root.layer_order()` shows the paint order inside
  LyrFloat stable across refreshes and matching the intended stack.
- **Border visibility churn.** Fixed in 5dcb798 (the refresh path no longer
  enables border nodes that the visibility block then disables), which did not
  cure it either.
- **Install/deploy.** Binary, libscenefx-0.5.so link and the somewm-one deploy
  all verified correct.
- **The nested sandbox does not reproduce it at all** -- three windows, blur on
  and off, static and dragging, frame-diffed: nothing above noise. Sandbox runs
  the nested Wayland backend on GLES2; the live session is NVIDIA DRM. A Fable
  agent trying to instrument it hit Mesa GBM clashing with the NVIDIA device,
  which points the same way.

### Hypotheses tested and refuted

- **Opaque-region regression** (gpt-5.6-sol, round 1). SceneFX 0.4 bailed out of
  `scene_node_opaque_region()` for any rect with a corner radius, with the
  comment `TODO: this is incorrect`; 0.5 removed that guard. The change is real
  but does not explain this. Reading `quad_round.frag` / `corner_alpha.frag`:
  along the straight edges `corner_alpha()` returns exactly 1.0, feathering only
  happens inside the corner squares, and 0.5 conservatively subtracts the full
  radius x radius corner squares plus the whole clip rect. The 1 px straight
  bands really are opaque, so declaring them so is correct.
- **Shader divergence.** Derived that 0.4's and 0.5's SDF maths are functionally
  equivalent; 0.5 only adds fast paths (`discard` instead of writing alpha 0)
  and an `is_cutout` flag, all of which reduce to the same values.
- **mediump precision** (gpt-5.6-sol, round 2). 0.5 did drop 0.4's separate
  GLES3 shader tree, and `corner_alpha.frag` -- which holds all the SDF maths --
  declares no precision qualifier of its own. At 3840x2160 a mediump float
  cannot resolve a 1 px ring past x = 2048, which would have fit every symptom
  including the clean first window and the clean small-output sandbox. Refuted
  by reading `render/fx_renderer/shaders.c:119`: `link_quad_program()`
  concatenates `quad_frag_src` and `corner_alpha_frag_src` into a single source
  string, so the `precision highp float` at the top of the quad shader covers
  the SDF. (Mesa rejecting `corner_alpha.frag` on its own -- "No precision
  specified in this scope" -- confirms the concatenation is mandatory.)

### Surviving hypothesis: the blur padding band roughly doubled in 0.5

SceneFX saves the framebuffer pixels around a blur node before rendering and
pastes them back afterwards, so that newly drawn content above a blurred window
does not bleed into its blur. Both versions do this; 0.5 changed how wide the
band is and when it triggers.

| | 0.4 (`wlr_scene.c:2957`) | 0.5 (`wlr_scene.c:2896`, `apply_blur_region`) |
|---|---|---|
| region | `expand(damage INTERSECT blur_region, S)` | `expand(expand(damage, S) INTERSECT node_visible, S)` |
| reach beyond damage | `S` | `2 * S` |
| triggers when | damage **overlaps** a blurred node | damage comes **within S** of a blurred node |

The fork sets `num_passes = 3, radius = 5` (`somewm.c:1203`), and
`blur_data_calc_size()` is `2^(passes+1) * radius`, so **S = 80 px**. The band
therefore grew from 80 px to 160 px, and now fires for any damage within 80 px
of a blur node. With `useless_gap = 3` two tiled windows sit ~6 px apart, so a
blinking cursor in one terminal drags a 160 px stale-pixel restore band across
its neighbour's border.

That is the only hypothesis left that explains the first window being clean:
with a single window the band lands on the static wallpaper, where pasting back
pre-render pixels is invisible. With a second window it lands on live content
and on the 1 px border.

Two secondary defects found in the same code, worth reporting regardless:

- `apply_blur_region()` tests the return value of `pixman_region32_intersect()`,
  which reports allocation success, not whether the result is non-empty. The
  compensation path is therefore entered for every blur node in the scene.
- `full_damage` is computed from `original_damage.extents`, so a damage region
  whose bounding box spans the output but which is mostly empty is mistaken for
  a full repaint and skips compensation entirely.

Next step, in order:

1. `sfx.blur_enabled = false` in somewm-one on the 0.20 stack. Clean borders
   confirm it.
2. Keep blur but drop `num_passes` to 1 and `radius` to 3 (S = 12 px). If the
   corrupted band shrinks with S, that is proof rather than inference.
3. If confirmed, report to wlrfx/scenefx and carry a `diff_files` patch on
   `subprojects/scenefx-0.5.wrap` until it lands.

`plans/scripts/install-scenefx.sh` therefore defaults to `SOMEWM_WLROOTS=0.19`
until this is resolved. `SOMEWM_WLROOTS=0.20` opts back in.

## Remaining

1. **Live DRM test** — install and restart, then exercise: tag-slide animation,
   SceneFX effects on the real GPU, Steam/game focus, multi-monitor hotplug,
   hot-reload (upstream's guard replaces the fork's), Sierra Chart popups.
2. Merge to `main` the same way kolo9b was promoted (merge commit, tree taken
   from the sync branch, both histories kept).
3. `plans/done/fix-hot-reload-lgi-closures.md` describes a guard the fork no
   longer has. Re-check the fifth-reload crash on upstream's guard and update
   or archive that doc accordingly.
