# Fork Status: raven2cz/somewm vs trip-zip/somewm

Last sync with upstream: **2026-03-30** (8 commits: fullscreen fixes, systemd, shadow optimization)
Last fork-status update: **2026-04-08**

## Upstream sync gap

We are **~20 commits behind upstream/main**. Notable upstream changes since last sync:
- `focus_restore()` consolidation refactor
- per-device input rules (`awful.input.rules`)
- keygrabber key release routing
- null pointer fix in `wlr_xdg_surface`
- stack refresh for `ewmh_update_net_client_list_stacking()`
- `root._remove_key()` for immediate keybinding removal
- benchmark instrumentation for signal dispatch
- `screen.fake_add()` SEGV fix

## What's in main

### Our unique features (not in upstream)

| # | Feature | Key files | Issue |
|---|---------|-----------|-------|
| 1 | NVIDIA crash guard — `xdg->initialized` check | `somewm.c` | [#216](https://github.com/trip-zip/somewm/issues/216) |
| 2 | Cold restart / session management | `somewm.c`, `luaa.c`, `somewm-session` | [#232](https://github.com/trip-zip/somewm/issues/232) |
| 3 | NumLock on startup (`awesome.set_numlock`) | `luaa.c` | [#238](https://github.com/trip-zip/somewm/issues/238) |
| 4 | Pointer constraint in Lua focus path | `somewm_api.c` | — |
| 5 | `[SOMEWM-DEBUG]` startup markers | `somewm.c` | — |
| 6 | Client animation framework (9 types) | `lua/awful/anim_client.lua` + C changes | [#381](https://github.com/trip-zip/somewm/issues/381) |
| 7 | SceneFX visual effects (optional) | 28 files, `scenefx_compat.h` | [#387](https://github.com/trip-zip/somewm/issues/387) |
| 8 | Layoutlist hotplug crash fix | `lua/awful/widget/layoutlist.lua` | [#390](https://github.com/trip-zip/somewm/issues/390) |
| 9 | Override-redirect XWayland overlay stacking | `somewm.c` | [PR #427](https://github.com/trip-zip/somewm/pull/427) |
| 10 | Pointer enter for newly mapped layer surfaces | `somewm.c` | [PR #421](https://github.com/trip-zip/somewm/pull/421) |
| 11 | Wibox opacity/border propagation to C drawin | `objects/drawin.c` | [PR #407](https://github.com/trip-zip/somewm/pull/407) |
| 12 | Notification FX (fadeIn, shadow, visual refresh) | `lua/naughty/`, `objects/drawin.c` | — |
| 13 | somewm-shell (Quickshell desktop shell) | `plans/project/somewm-shell/` | — |
| 14 | somewm-one config project | `plans/project/somewm-one/` | — |

### SceneFX integration (merged 2026-03-30)

Optional compile-time extension (`-Dscenefx=auto`). See `plans/done/scenefx-integration.md`.
- Rounded corners (`c.corner_radius`)
- GPU shadows (dual-path: scenefx native or 9-slice fallback)
- Backdrop blur (`c.backdrop_blur`)
- Rounded border frame (single rect + clipped_region)
- Titlebar rounded corners
- Fade animation + decoration interaction

## Our upstream PRs

### Open

| PR | Title | Branch | Created |
|----|-------|--------|---------|
| [#427](https://github.com/trip-zip/somewm/pull/427) | fix(stack): place override_redirect XWayland surfaces in overlay layer | `fix/xwayland-override-redirect-stacking-upstream` | 2026-04-07 |
| [#421](https://github.com/trip-zip/somewm/pull/421) | fix: deliver pointer enter to newly mapped layer surfaces | `fix/pointer-enter-layer-surfaces-upstream` | 2026-04-07 |
| [#407](https://github.com/trip-zip/somewm/pull/407) | fix(wibox): propagate opacity/border to underlying C drawin | `fix/wibox-opacity-propagation` | 2026-04-03 |

### Merged

| PR | Title | Merged |
|----|-------|--------|
| [#400](https://github.com/trip-zip/somewm/pull/400) | fix(drawin): shadow and border not refreshed on resize | 2026-04-03 |
| [#391](https://github.com/trip-zip/somewm/pull/391) | fix: layoutlist assertion crash on monitor hotplug | 2026-03-30 |
| [#384](https://github.com/trip-zip/somewm/pull/384) | feat: retroactive added::connected signal for output class | 2026-03-27 |
| [#382](https://github.com/trip-zip/somewm/pull/382) | fix: use set_bounds instead of set_size for initial XDG configure | 2026-03-27 |

### Closed (superseded/rejected)

| PR | Title | Reason |
|----|-------|--------|
| [#420](https://github.com/trip-zip/somewm/pull/420) | fix: deliver pointer enter to newly mapped layer surfaces | Replaced by #421 |
| [#394](https://github.com/trip-zip/somewm/pull/394) | fix: guard XDG surface operations against uninitialized state | Closed |

## Our contributions accepted upstream

16 commits cherry-picked (11 exact, 5 modified). Maintainer picked directly from our fork.

| Our fix | Upstream issue | Status |
|---------|---------------|--------|
| XWayland keyboard focus (Lua path) | #137, #135, #133 | Cherry-picked + improved |
| XWayland ICCCM focusable detection | #137 | Cherry-picked exact |
| awesome.exec() use-after-free | — | Cherry-picked exact |
| Titlebar geometry/clipping (4 commits) | #230 | Cherry-picked exact |
| XWayland position sync for popups | #231 | Cherry-picked exact |
| Minimized clients + tag switch | #217 | Cherry-picked exact |
| Selmon mouse motion update | #245 | Cherry-picked exact |
| XKB layout widget fix | #233 | Cherry-picked exact |
| Multi-monitor hotplug (6 bugs) | #216 | Cherry-picked modified |
| Keyboard focus desync (sloppy) | #237 | Cherry-picked modified |
| NumLock wibar scroll + UBSan | #239 | Cherry-picked modified |
| Layoutlist hotplug crash | #390 | PR #391 merged |
| Output added::connected signal | — | PR #384 merged |
| Floating layout set_bounds | — | PR #382 merged |
| Drawin shadow/border refresh | — | PR #400 merged |

## Open issues on upstream (ours)

| # | Title | Status |
|---|-------|--------|
| [#408](https://github.com/trip-zip/somewm/issues/408) | wibox.opacity has no visual effect on Wayland | OPEN — our PR #407 addresses this |
| [#401](https://github.com/trip-zip/somewm/issues/401) | lockscreen: add background image support | OPEN — done in our fork |
| [#393](https://github.com/trip-zip/somewm/issues/393) | feat: KDE-style tag slide animation | OPEN — tagged 2.x |
| [#387](https://github.com/trip-zip/somewm/issues/387) | SceneFX visual effects | OPEN — tagged 2.x |
| [#381](https://github.com/trip-zip/somewm/issues/381) | Client animation system | OPEN — tagged 2.x |
| [#249](https://github.com/trip-zip/somewm/issues/249) | Tag state lost on hotplug | OPEN — upstream has #312 (tag persistence) |
| [#238](https://github.com/trip-zip/somewm/issues/238) | NumLock on startup | OPEN — in our fork |
| [#232](https://github.com/trip-zip/somewm/issues/232) | awesome.restart() SIGSEGV | OPEN — cold restart workaround in our fork |

## Branch status

### Active (kept intentionally)

| Branch | Purpose | Status |
|--------|---------|--------|
| `feat/scenefx-integration` | SceneFX visual effects PoC | **Merged to main**. Preserved — referenced by upstream #387 |
| `feat/unified-animations` | Client animation system | **Merged to main**. Preserved — referenced by upstream #381 |
| `backup/scenefx-integration` | Pre-squash backup (25 commits) | Safety backup |
| `fix/xwayland-override-redirect-stacking-upstream` | Upstream PR #427 | OPEN |
| `fix/pointer-enter-layer-surfaces-upstream` | Upstream PR #421 | OPEN |
| `fix/wibox-opacity-propagation` | Upstream PR #407 | OPEN |
| `fix/stale-border-color-on-unfocus` | Yellow border bug investigation | WIP |

### Stale (already in main, can be deleted)

| Branch | Why stale |
|--------|-----------|
| `feat/cold-restart` | Merged to main |
| `feat/numlock-on-startup` | Merged to main |
| `feat/output-added-connected` | PR #384 merged upstream |
| `feat/lockscreen-bg-image` | Merged to main |
| `feat/quickshell-caelestia-dashboard` | Superseded by somewm-shell |
| `feat/somewm-one-components` | Archived, superseded by somewm-shell |
| `feat/tag-slide-animation` | Architecture documented, archived |
| `feat/wibar-fx-shadows` | PR #400 merged upstream |
| `feature/native-screenrecord` | Merged to main |
| `fix/floating-layout-initial-size` | PR #382 merged upstream |
| `fix/hot-reload-lgi-crash` | Merged to main |
| `fix/keyboard-focus-desync` | Cherry-picked upstream, in main |
| `fix/layoutlist-hotplug-upstream` | PR #391 merged upstream |
| `fix/minimized-clients-reappear-tag-switch` | Cherry-picked upstream |
| `fix/multi-monitor-hotplug` | Cherry-picked upstream |
| `fix/pointer-enter-layer-surfaces` | Replaced by -upstream branch |
| `fix/scroll-wibar-numlock` | Merged to main |
| `fix/selmon-not-updated-on-mouse-motion` | Cherry-picked upstream |
| `fix/shadow-resize-perf` | Merged to main |
| `fix/steam-menu-popup-positioning` | Cherry-picked upstream |
| `fix/tile-resize-flicker` | Investigation branch |
| `fix/titlebar-geometry-clipping-and-pointer-focus` | Cherry-picked upstream |
| `fix/xdg-activate-uninitialized-crash` | PR #394 closed |
| `fix/xkb-keyboard-layout-switching` | Cherry-picked upstream |
| `fix/xwayland-keyboard-focus` | Cherry-picked upstream |
| `experiment/scenefx-poc` | Superseded by feat/scenefx-integration |
| `sync/upstream-main` | Merge branch, completed |

### Upstream branches (Jimmy's, on our remote)

| Branch | Notes |
|--------|-------|
| `a11y_module` | WIP accessibility module |
| `feat/lockscreen` | Lock screen implementation |
| `feat/wallpaper_caching` | Wallpaper cache optimization |
| `fix/firefox-tiling-regression` | Stack refactor regression |
| `fix/shadow-beautiful-lookup` | Beautiful module require fix |
| `fix/silent_exit` | Error visibility improvement |

## Maintenance checklist

When syncing with upstream or merging branches:
1. Update this file with new branch status
2. Update "What's in main" section
3. Move merged branches to "Stale" section
4. Check if upstream adopted any of our commits
5. Update open issues status
6. Consider deleting stale branches (`git push origin --delete <branch>`)
