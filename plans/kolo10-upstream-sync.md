# Kolo 10 — Upstream Sync (wlroots 0.20 + SceneFX 0.5)

Date: 2026-08-23
Branch: `sync/upstream-2026-08-23-kolo10` (from `upstream/main` @ `c7b3208`)
Methodology: **branch FROM upstream, re-apply fork features** (kolo8/kolo9 rule)
Status: **Phases 0-4 DONE, sandbox-verified. NOT merged.** Live DRM testing found
a border rendering defect on wlroots 0.20 + SceneFX 0.5 that is not fixed; the
fork runs on 0.19, which is an upstream-supported build option.

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

### Blur: eliminated

The padding-band theory was the last one standing and it is dead too.
`is_scene_blur_enabled()` is `radius > 0 && num_passes > 0`
(`scenefx-0.5/types/fx/blur_data.c:14`), so running with
`SOMEWM_BLUR_PASSES=0 SOMEWM_BLUR_RADIUS=0` switches off every blur path
SceneFX has, padding save/restore included. The border came out pixel for
pixel the same as with blur on.

Note the earlier run that seemed to clear blur did not: setting
`c.backdrop_blur = false` destroys the per-client `wlr_scene_blur` nodes, but
somewm also creates a scene-level `wlr_scene_optimized_blur` layer at startup
(`somewm.c`), and `should_blur_node_extend_damage()` returns true for that node
type whenever it is dirty. The machinery kept running, so the identical A and B
numbers ruled out nothing at the time.

### What the pixels say

Three runs, three restarts, blur on and off -- always the same shape:

| edge | result |
|---|---|
| top, bottom | exact, 1px, full span |
| right | present but **2px** wide, one pixel inboard of where it belongs |
| left | absent; the arc is not drawn either |

Both right corners trace a clean arc into the vertical column. Neither left
corner has an arc at all -- the horizontal edges simply begin at x offset
`corner_radius + border_width`.

For a 1610-wide frame the only border-coloured run across the middle row is at
x offsets 1608 and 1609, where the rect spans 0..1609 and the punch-hole spans
1..1608. So the hole behaves as if it sat **one pixel to the left** of the rect:
on the left it swallows the ring, on the right it uncovers an extra column.
Vertically it is exact, which is why the horizontal edges are perfect.

### What that rules out

- The scene node is right. `root.scene_tree_dump` on the broken session:
  `rect 1703x1435`, `clip 1701x1433+1+1`, radii 15/14, alpha 1.00, for geometry
  1701x1433 with `bw=1`.
- Nothing occludes it. That node's `visible` is the whole rect in **one**
  rectangle.
- The draw call is right. Replaying it outside the compositor -- same
  `FLIPPED_180` projection, same `set_proj_matrix`, same vertex generation as
  `render()`, same uniforms as `fx_render_pass_add_rounded_rect`, same
  frame-shaped pixman region `apply_clip_region` leaves, SceneFX 0.5's own
  shaders concatenated the way `link_quad_program` does -- produces a perfect
  1px ring.

So the scene holds correct values and the shader draws correct values, yet the
screen disagrees. The remaining gap is what the renderer receives at run time.

### Instrumentation

`plans/patches/scenefx-0.5-rect-logging.patch` adds a `[RECT]` line to
`fx_render_pass_add_rounded_rect`, logged on change and gated behind
`SOMEWM_LOG_RECT=1`, reporting the box, the clip box, their deltas, the radii
and the colour alpha. `subprojects/` is gitignored, hence the patch file.

The live session reports `dx=1 dy=1 dw=2 dh=2 r=15.0 cr=14.0 a=1.00` -- the
renderer receives exactly the right boxes, radii and alpha. So that is not it
either.

### Where it stands: partial damage

The same log line reports the region actually rasterised. A typical frame:

    render_region=484x602+318+0 in 1 rect(s)
    rasterised 3 rect(s), box-relative: [318,0 484x5] [796,5 6x591] [318,596 484x6]

`render()` rasterises `visible INTERSECT damage` minus the inner box, so when
damage starts at x offset 318 the border's left strip is not drawn at all that
frame. That is normal and correct: the rest of the framebuffer is supposed to
still hold the previous frame's content, which was right. It works out in the
sandbox.

So the defect is not in what gets drawn but in the left strip never ending up
with valid content on this machine -- i.e. partial damage plus buffer age on
NVIDIA DRM, where the nested backend's full repaints hide it. That also finally
explains why the sandbox has never reproduced anything.

### Status: unresolved

The mechanism is well characterised and the fork's own inputs are proven
correct, but nothing here is fixed. Borders on wlroots 0.20 + SceneFX 0.5
flicker while a window is dragged at any border width, and the fork stays on
0.19. What follows is the evidence, kept so this does not have to be
re-derived.

### Confirmed: partial damage

`WLR_SCENE_DEBUG_DAMAGE=rerender` forces a full repaint every frame
(`scenefx-0.5/types/scene/wlr_scene.c:3146`). Measured on the live session,
same window, same everything else:

| edge | partial damage | full repaint |
|---|---|---|
| top | ok | ok |
| bottom | ok | ok |
| **left** | **absent** | **1598 of 1598 clean** |
| right | 2px, one pixel inboard | pure black, oscillating |

The left edge going from completely absent to perfect settles it: the primary
defect is that the border's left strip never gets repainted into valid content
under partial damage. Nothing about the drawing is wrong -- the scene node, its
visible region, the renderer's boxes, the uniforms and the shaders were each
verified correct in turn.

A second artefact survives the full repaint: the right column reads pure black
and `flicker` jumps to 1600 of 6752 ring pixels changed between two captures
0.4s apart, which is almost exactly the 1598 positions of that edge. So the
right column oscillates between states even when every frame is fully
redrawn. That is a separate problem from the left one and is not yet explained.

### Root cause: a one-pixel rounded border ring

SceneFX's own tinywl, on the same machine, same wlroots 0.20, same SceneFX 0.5,
drawing the same construction, renders correctly. It uses `BORDER_THICKNESS 3`
and `corner_radius 20`; somewm uses 1 and 14. That was the difference.

Measured live, one client, changing only these two properties over IPC:

| border_width | corner_radius | result |
|---|---|---|
| 1 | 14 | 56% -- **left edge entirely absent** |
| 2 | 14 | **100%**, all four edges ok |
| 3 | 14 | all four edges present, nothing missing |
| 1 | 0 (flat 4-rect path) | **100%** |

The border is the difference between an SDF rounded rect of radius
`corner_radius + border_width` and a punched-out hole of radius
`corner_radius`. At `border_width = 1` that difference is exactly one pixel
wide, and the half-pixel conventions the two shader evaluations use
(`size - 1.0`, `position + 0.5` in `quad_round.frag`) round the surviving alpha
to zero on one side. At 2px there is enough margin that it always lands. The
flat path has no SDF at all, hence 100%.

This also explains the flicker: a ring balanced on a rounding boundary flips
between drawn and not drawn as sub-pixel positions shift while a window moves.

And it explains the first window always being fine -- it is the one that never
gets re-laid-out, so its ring is rasterised once under conditions that happen to
work and nothing disturbs it.

**Not fixed.** `border_width = 2` removes the statically missing edge and
measures 100.0%, but that measurement is two captures 0.4s apart on a
stationary window -- it never tested dragging. On the live session a 2px border
still flickers while a window is moved. The theme change was made and then
reverted; on 0.19 a 1px border measures 100% anyway.

Everything ruled out along the way -- blur, occlusion, the scene node, the
uniforms, the shaders, mediump precision, the opaque-region change, partial
damage -- was ruled out correctly; none of them was the cause. The damage
observations were real but secondary: forcing a full repaint changes which
side of the ring survives the rounding, which is why it appeared to help.

### Sharpened: it is the rounded path, at any radius

Sweeping corner_radius at border_width 1 on one live client:

| border_width | corner_radius | result |
|---|---|---|
| 1 | 0 | 100%, both vertical edges clean |
| 1 | 1 | right edge one pixel out |
| 1 | 2 | right edge one pixel out |
| 1 | 4 | right edge one pixel out |
| 1 | 14 | right edge one pixel out |

The radius does not matter. What matters is only whether the rounded path runs
at all: `corner_radius = 0` takes the flat four-rect branch and is exact,
anything above zero takes the single frame rect with a `clipped_region` and the
ring lands a pixel off.

It is not a constant offset either. Earlier runs lost the **left** edge; this
sweep shifted the **right** one, same construction, different window position.
So it is a rounding boundary that tips one way or the other depending on where
the window sits -- which is also why it visibly slides and drops out while a
window is dragged, and why a fixed one-pixel compensation in
`client_update_border_for_corners()` would be right only half the time.

The fork's own geometry is provably correct: `clipped_region` is
`{bw, bw, w - 2bw, h - 2bw}`, symmetric, and the renderer receives exactly that
(`dx=1 dy=1 dw=2 dh=2` from the [RECT] instrumentation). The fragility is that
SceneFX forms the ring as the difference of two SDF shapes one pixel apart, and
`quad_round.frag`'s half-pixel conventions (`size - 1.0`, `position + 0.5`)
cannot resolve that reliably.

**wlroots 0.20 stays blocked.** There is no workaround that survives dragging:
`corner_radius = 0` is exact but gives up rounded corners, and a thicker border
only hides the static symptom. The installer default stays on 0.19.

### Reproducer for upstream

`plans/patches/scenefx-0.5-tinywl-1px-border.patch` sets SceneFX's own tinywl
to `BORDER_THICKNESS 1` (it ships with 3). tinywl draws the identical
construction and renders correctly at 3, so if it breaks at 1 the whole report
is one constant in their own example, with no somewm code involved. Built and
ready at `build-fx-0.20/subprojects/scenefx-0.5/tinywl/tinywl`; needs a DRM
session to run.

Both patch files are kept here because `subprojects/` is gitignored. Apply with
`git -C subprojects/scenefx-0.5 apply plans/patches/<file>` after a fresh wrap
checkout.

Not urgent: 0.19 is an upstream-supported configuration and the installer
defaults to it.

## Remaining

1. **Live DRM test** — install and restart, then exercise: tag-slide animation,
   SceneFX effects on the real GPU, Steam/game focus, multi-monitor hotplug,
   hot-reload (upstream's guard replaces the fork's), Sierra Chart popups.
2. Merge to `main` the same way kolo9b was promoted (merge commit, tree taken
   from the sync branch, both histories kept).
3. `plans/done/fix-hot-reload-lgi-closures.md` describes a guard the fork no
   longer has. Re-check the fifth-reload crash on upstream's guard and update
   or archive that doc accordingly.
