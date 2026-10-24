# v2 fork line: upstream 2.1 + a thin fork delta

Started: 2026-10-24 on `boxszn` (AMD iGPU, KDE; no NVIDIA).
Status: **built and sandbox-verified; awaiting NVIDIA/DRM validation** with
[`nvidia-test-plan.md`](nvidia-test-plan.md).

## Why

By October 2026 upstream (`trip-zip/somewm`) had shipped 2.0.0, 2.0.1 and
2.1.0: 115 commits and ~720 files (+72k/-24k) after the base the v1 fork was
last synced to (`c7b3208`). 2.1 rebuilt rendering around Clay:

- one Clay layout tree per output; `declare.c` solves it, `render.c`
  reconciles it into wlr_scene. Widgets no longer `fit`/`draw` themselves.
- wlroots 0.20.2 is always built from the wrap with somewm's own
  `wlroots-corners.diff` (GLES2 + pixman); wlroots 0.19 and SceneFX are gone.
- its own animation API (`c.animation`, `beautiful.animation_*`, widget and
  popup animation); `awesome.start_animation` removed.
- the maintainer will not take SceneFX as a dependency (#387, closed
  2026-10-13: "I'll do something similar, but on our own"). No blur exists
  upstream.

The v1 fork (230 commits ahead, SceneFX, wlroots 0.19) could not be synced
into that. Decision (user, 2026-10-24): freeze v1, rebuild `main` from
upstream 2.1, keep the fork thin, port v1 bug fixes only when they still
reproduce, decide features one by one.

## Branches and tags

All three repos (`somewm`, `somewm-one`, `somewm-shell`):

| ref | meaning |
|---|---|
| `legacy/v1`, tag `v1-legacy` | the last v1 state (pushed 2026-10-24) |
| `main` | the v2 line (replaced the v1 main on 2026-10-24) |
| `v2/main` | the branch v2 was built on; identical to `main` at the switch |

No `-v2` repo suffixes: one GitHub account cannot hold two forks of the same
upstream, and branches give the same separation.

## What v2 carries (somewm)

On top of `upstream/main` (6eaa61e, 2.1.0 + 5):

| commit | what | upstream candidate |
|---|---|---|
| chore(fork) | `plans/` tooling, `install.sh`, CLAUDE/INSTALL docs, AGENTS.md pointer | no (fork-only) |
| fix(xwayland) | map a surface whose buffer was committed before associate (Sierra Chart dialogs never appearing); skips a stale buffer left from before an X11 unmap | yes (also wlroots: the gap is in `xwayland_surface_associate`) |
| fix: main() exit code | `awesome.quit(code)` code reaches the caller | yes (2 lines) |
| fix(input) | `screen::focus` when the pointer crosses outputs | yes |
| fix(focus) drag | keep focus on a client dragged across outputs; rebase pointer focus when a grab ends | yes, after NVIDIA verification |
| fix(layer-shell) | focus_restore on unmap only for the surface that held keyboard focus | yes |
| fix(focus) grab end | do the unfocus/restore a grab deferred when it stops | yes (goes with the two above) |
| feat(root) | `root.memory_stats([gc])` | proposal #508 (maintainer may prefer `somewm.memory.stats`) |
| fix(sandbox) | keep a caller-provided sandbox config home | no (fork-only) |

Upstream policy (`AGENTS.md`, `AI_POLICY.md`): issues written by a person,
PRs only for issues the maintainer agreed to, AI use disclosed. Agents never
open issues/PRs; the maintainer (human) submits.

## What v2 changes in somewm-one

- `anim_client.lua` removed; `fishlive/config/animations.lua` maps the v1
  timings onto 2.1 theme keys, corners via `c.shape = 14` (square for
  `steam_app_*`, Wine, `*.exe`, fullscreen), notification popup fade.
- KDE-like tag slide on the 2.1 tag animation: new clients and the tag
  wallpaper come in from the right on a higher tag index, from the left on a
  lower one. A leaving client only animates its frame in 2.1, so the old
  desktop does not visibly slide out. `tag_slide::start/end` are still
  emitted for the shell collage.
- layout-machi: function `bgimage` is no longer drawn; `layout-machi/paint.lua`
  paints it into a surface.
- wibar: 2.1 draws a multi-font markup in the first run's font, so icon and
  number/date/time are now separate textboxes (`widget_helper.create_runs`).
- lock screen: `lockscreen_bg_image` -> `lockscreen_wallpaper`.
- `SOMEWM_NO_AUTOSTART=1`, `SOMEWM_NO_SHELL=1` for nested tests.
- menu "Restart" falls back to `awesome.restart()` (no `rebuild_restart`).

## What v2 changes in somewm-shell

- memory panel reads `root.memory_stats` (falls back to the Lua heap).
- CPU panel buttons pass a shell command to `somewm-client exec`.

## v1 features deliberately not carried

| v1 feature | v2 |
|---|---|
| SceneFX corners, shadows, border frame | upstream `client.shape`, nine-patch shadows |
| backdrop blur (clients, lock screen) | **none**. Would need a blur pass in the wlroots diff/render.c; feature request upstream if wanted |
| `anim_client` (fade/maximize/swap/float/layer/minimize) | upstream animations; minimize and layer-surface fades are gone |
| tag slide with sliding wallpaper overlays | the KDE-like slide above |
| wallpaper scene cache (`root.wallpaper_cache_*`, `root.wp_*`) | obsolete under Clay; somewm-one's calls are guarded no-ops |
| `gears.wallpaper` | removed upstream; unused |
| cold/rebuild restart, `somewm-session` loop | `awesome.restart()`; `main()` now returns the quit code, so a session loop can be rebuilt on `awesome.quit(2)` later |
| XWayland override-redirect rewrite (`UnmanagedSurface`) | **not ported**; upstream still makes OR windows Lua clients, stacks them via Clay. Test with Wine first (test plan §6); a minimal port (role flips + focus hold) is ~150 lines |
| `root.scene_tree_dump`, `root.layer_order`, `root.xwayland_unmanaged` | `somewm-client clay tree`, `screen.inspector` |
| v1 debug markers `[FOCUS*]` | gone |

## Verified on boxszn (nested/headless sandbox, AMD)

- upstream integration suite on the v2 fork: 342 pass, 7 fail, 7 skip. The
  7 failures (`test-clay-calendar-presentation`, `-hotkeys-sizing`,
  `-notification`, `-text-scale-change`, `-wallpaper-source`,
  `test-client-subsurface-opacity`, `test-font-resolution`) fail identically
  on pristine upstream on this machine: environment, not the fork.
- XWayland/layer-shell/focus/grab subset (40 tests) + `test-memory-stats`:
  all pass after the review fixes.
- somewm-one boots with no Lua error; windows map with rounded corners;
  layout-machi switcher draws; theme switch keeps animation keys; lock screen
  shows the wallpaper; tag slide direction measured from screenshots.
- somewm-shell (headless): dashboard, memory/cpu/storage panels, wallpaper
  picker render; memory panel shows `root.memory_stats` data.
- somewm-one busted: 225 pass, 7 fail, 1 error, identical to before the
  port (pre-existing `wallpaper_spec` failures).
- Cross-model review (gpt-5.6-sol) of the C delta: 4 findings, all fixed
  (stale re-associate buffer, deferred grab focus work x2, mallinfo2 glibc
  version guard).

Not verifiable here: anything DRM/NVIDIA, Wine (not installed), real
multi-monitor, games, PAM unlock, screen sharing. See the test plan.

## Follow-ups

1. NVIDIA test plan, then decide on the Wine OR port.
2. Upstream submissions (by the maintainer) for the candidate commits above.
3. Blur: decide whether to build it on the wlroots diff (large) or live
   without it.
4. `plans/scripts/somewm-memory-*.sh`: switch their field lists to the v2
   `root.memory_stats` keys (`wallpaper_bytes`, no drawable/wibox fields).
5. busted `wallpaper_spec` failures in somewm-one (pre-existing).
