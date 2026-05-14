# Kolo 8 — Phase 4: Event-Queue Migration Sub-Plan (v3)

Date: 2026-05-14
Sync branch: `sync/upstream-2026-05-13` (Phase 3b done at `d76122b`)
Companion docs: `kolo8-migration-audit.md` (per-function A/B/C/D), `kolo8-integration-plan.md`

**Status: v3 — Codex R1 (3 findings) + Sonnet independent 33-hunk audit + Codex R2
(2 findings) all incorporated. R2 explicitly confirmed the reconciled
objects/client.c table and all conversion rules are correct. One short R3
confirming round on the v2→v3 fixes, then code. Per user instruction 2026-05-14:
Codex is given the fork commit history so it understands the *essence and original
placement* of every fork change.**

v1→v2: Codex R1 — `_scene_layer` explicit KEEP-UPSTREAM, window.c idle-inhibit
explicit DROP, double-emit grep expanded. Sonnet audit — objects/client.c §4
replaced with the reconciled 33-hunk table; hunk 2 corrected; hunk 9 4-way split;
hunk 15 flagged as deliberate fix.
v2→v3: Codex R2 — xwayland.c must RE-APPLY `#include "objects/signal.h"` (the
`xwayland::ready` emit needs it); `0c839f4` corrected — it touches window.c
`commitpopup()` + objects/layer_surface.c, NOT objects/client.c.

This is the hardest phase. Upstream touched `objects/client.c` with 12 commits in
the sync window — the entire event-queue refactor — so the fork's 30+ hunks there
are tightly interleaved feature-vs-signal-vs-content-getter code.

---

## 1. What upstream did — the event-queue model

Upstream replaced synchronous C→Lua signal emission with deferred/queued dispatch
(`event_queue.c`/`event_queue.h`, 16 commits `1b90255`..`4b51122`).

- C code used to call `luaA_object_emit_signal(L, idx, "name", nargs)` inline,
  which crossed into Lua immediately, mid-handler.
- Now C calls `some_event_queue_signal0/signal/global/move/class()` with a `SIG_*`
  enum id. Events accumulate in a buffer and are drained at a frame boundary by
  `some_event_queue_drain()` (Step 0 of `some_refresh()`).
- The `SIG_*` enum (`event_queue.h`) is the **authoritative list of which signals
  were converted**:
  - Property geometry: `SIG_PROPERTY_GEOMETRY/POSITION/SIZE/X/Y/WIDTH/HEIGHT`
  - Focus: `SIG_PROPERTY_ACTIVE` (1 bool arg), `SIG_FOCUS`, `SIG_UNFOCUS`,
    `SIG_CLIENT_FOCUS` (global), `SIG_CLIENT_UNFOCUS` (global)
  - Mouse: `SIG_MOUSE_ENTER`, `SIG_MOUSE_LEAVE`, `SIG_MOUSE_MOVE` (2 args, coalesced)
  - Lifecycle: `SIG_LIST` (class-level), `SIG_SWAPPED` (2 args)
  - Request: `SIG_REQUEST_ACTIVATE`, `SIG_REQUEST_URGENT`, `SIG_REQUEST_TAG`,
    `SIG_REQUEST_SELECT`, `SIG_SYSTRAY_SECONDARY_ACTIVATE`,
    `SIG_SYSTRAY_CONTEXT_MENU`, `SIG_SYSTRAY_SCROLL`
  - Global geometry: `SIG_CLIENT_PROPERTY_GEOMETRY`
- `affdf56` additionally **removed** the bare `manage`/`unmanage` signals (the
  `request::manage`/`request::unmanage` ones are different and were KEPT synchronous).

## 2. Conversion rules — the decision tree for every signal emit

For every `luaA_object_emit_signal` / `luaA_class_emit_signal` /
`luaA_emit_signal_global` the fork carries in a Phase-4 file:

**Rule A — converted signal → DROP fork's synchronous call, TAKE upstream's queued
form.** If the signal name maps to a `SIG_*` enum entry (see §1), upstream already
has the correct `some_event_queue_*` call. The fork's synchronous call is the
pre-refactor original. Discard it; keep upstream's queued line. *Failure mode if
you keep the fork line: double-emit (signal fires once queued, once synchronous).*

**Rule B — KEPT-synchronous signal → leave untouched.** `request::manage`,
`request::unmanage`, `request::geometry`, layer `request::keyboard` are NOT in the
`SIG_*` enum — upstream deliberately keeps them synchronous (verified
`upstream/main:objects/client.c`, `objects/layer_surface.c`). Leave as
`luaA_object_emit_signal`. NOTE: the *bare* `manage`/`unmanage` (no `request::`
prefix) were removed by `affdf56` — every fork emit of those IS dropped.

**Rule C — fork-new signal → RE-APPLY as synchronous, do NOT drop.** Signals
upstream never had and that are NOT in the enum: `screen::focus` (input.c
motionnotify hover crossing — fork commit `edc5605`), `somewm::ready` (done in
Phase 2), `xwayland::ready` (fork commit `85c227f`), and fork property setters
(`property::_c_floating`, `property::corner_radius`, `property::backdrop_blur`,
layer `property::opacity`). These stay `luaA_emit_signal_global` /
`luaA_object_emit_signal`. Verified: no must-add `SIG_*` case; upstream still
emits `screen::focus` synchronously at `input.c:567`.

**Rule D — fork removal of upstream queue lifecycle → REJECT.** Any place the fork
diff *deletes* `some_event_queue_*` calls or `#include "event_queue.h"`: do NOT
carry the deletion. The fork removed those only because fork `main` predates the
queue.

**Rule E — fork feature interleaved with a converted emit → re-express onto the
queued form.** Do not paste the fork feature *around* a synchronous call. Apply it
relative to upstream's queued line.

## 3. Fork commit context — essence & original placement

The 37 fork commits touching Phase-4 files (`git log <merge-base>..main -- <files>`).
Codex MUST read these — `git log -p` for the diffs and intent. Key groups:

### 3a. kolo6/kolo7 — prior-sync reintegration (HOW fork code was placed last time)
- `77d7494` refactor(kolo6): port fork infrastructure onto refactored tree (Group A)
- `30c1898` fix(kolo6): de-duplicate SOMEWM_BENCH impl in somewm.c
- `4a810cb` feat(kolo6): port NVIDIA/SceneFX/bench deltas to refactored modules
- `6a6aef5` fix(kolo6): address Codex Round 5 findings on Groups F/G/H port
- `a109dc4` fix(kolo6): restore Lgi guard ordering + pointer-constraint on Lua focus
- `f464860` fix(kolo6): route refactored modules through scenefx_compat.h
- `2bffa5b` fix(kolo6): restore fork pointer/layer deltas dropped by refactor
- `18cc414` fix(kolo6): split LISTEN order to avoid layer-surface destroy SIGSEGV
- `f5c6753` protocols: Simplify code of unmaplayersurfacenotify()  [== upstream `64fe6a7`]
- `7a3e449` fix: Use-after-free of wlr_scene_tree  [== upstream `bad997d`]
- `46703ad` fix(kolo7): preserve titlebar/border clearing after upstream UAF fix
- `622cde3` fix: Use static inline for scene-tree surface helpers  [== upstream `d27fa2b`]
- `ddd921a` fix(kolo7): remove XDG commit listener in !globalconf_L unmap path
- `3042fd5` fix(kolo7): fire motionnotify on monitor-hotplug banning
- `ce1a98c` fix(kolo6): stop key repeat when a keygrabber starts mid-binding  [== upstream `cb6c2c1`]
**These tell us where fork deltas landed in the LAST refactored tree** — the same
placement logic applies again. Several (`f5c6753`, `7a3e449`, `622cde3`, `ce1a98c`)
are fork ports of commits upstream ALSO has — those are DUP, take upstream.

### 3b. Fork features touching Phase-4 files (the work to re-integrate)
- `f756ead` fix(focus): preserve focus during cross-monitor mouse-drag —
  THREE coordinated changes: `client_ban_unfocus` mousegrabber early-return
  (objects/client.c), `unmaplayersurfacenotify` exclusive_focus + mousegrabber
  guard (protocols.c), `motionnotify(0,...)` rebase after grabber returns false
  (input.c). PR #521.
- `ed894df` fix(window): defer wl_display_flush_clients out of mapnotify —
  `schedule_flush_clients` (DONE Phase 2) + the mapnotify call site change. #530.
- `85c227f` feat(api): emit xwayland::ready after EWMH init — xwayland.c (Rule C).
- `4c5b23e` fix(input): gate motionnotify pin on seat button_count not cursor_mode —
  the `cursor_mode == CurPressed` → `button_count > 0` change in input.c.
- `edc5605` fix(input): emit screen::focus on monitor-boundary cross — input.c
  motionnotify (Rule C, synchronous global).
- `06ca83e` docs: sonnet review nits — comments only.
- `4dc0fbf` fix(tag_slide): strict_clip per-client flag — objects/client.h (DONE
  Phase 2: the field), objects/client.c, window.c apply_geometry_to_wlroots,
  luaa.c `_client_scene_set_strict_clip`, lua/somewm/tag_slide.lua.
- `1809506` fix(client): keep border hidden for fullscreen during refresh —
  `client_border_refresh` c->fullscreen guard.
- `84aa3cb`, `36e939f`, `b1cded2` — CSD-DIAG instrumentation add+revert, net zero.
- `387e26a` fix(csd): stop poisoning c->prev from setmon + skip no-op unfullscreen —
  window.c `setmon`, `setfullscreen`.
- `f842847` fix(csd): remove xdg state driving from client_set_minimized —
  objects/client.c `client_set_minimized`.
- `8a42b35` fix(csd): reorder maximize ack + refresh configure on unminimize —
  window.c `maximizenotify`, objects/client.c.
- `748070e` feat: wire CSD maximize/minimize buttons — window.c `maximizenotify` +
  new `minimizenotify` + listener lifecycle in `createnotify`/hot-reload/destroy,
  `initialcommitnotify` capability bits, objects/client.c `client_set_maximized_common`.
- `6fb4db8` fix(fullscreen): emit per-client property::geometry in setfullscreen —
  ⚠ window.c. **This is fork PR #478 — CLOSED. Upstream reimplemented it as
  `58915a2` (queues per-client geometry from `resize()`). DROP the fork's
  setfullscreen geometry emit; take upstream `58915a2`.** (triage)
- `f5164d2` fix(scenefx): disable optimized backdrop blur on client buffers —
  objects/client.c scenefx.
- `25a1708`, `e7eb6c5`, `8eef823` fullscreen geometry preservation — window.c
  `setfullscreen` reentrance/no-op guards + max→fs→unfull memento.
- `0c839f4` perf(opacity): skip no-op opacity re-apply at 1.0 — touches
  **window.c `commitpopup()`** (popup opacity inheritance with `opacity >= 0 &&
  opacity < 1.0f`) and **objects/layer_surface.c**. (Corrected per Codex R2 — NOT
  objects/client.c.)
- `867ba20` fix(stack): skip unmanaged clients in stack_refresh — == upstream `07ac746`
  (DUP, take upstream; stack.c already done Phase 3b).

---

## 4. Per-file execution plan

Files with NO fork features — take upstream verbatim, drop the entire fork delta:

### event.c — take upstream verbatim
Fork delta is only the pre-refactor synchronous `mouse::enter/leave` + removed
`event_queue.h` include. Rule A + Rule D. **No edit needed — the branch already
has upstream's `event.c`.** Confirm `git diff upstream/main..HEAD -- event.c` is
empty at the end.

### common/luaclass.c — take upstream verbatim
The ~20 added lines are upstream's `client.manage/unmanage` deprecation shim. Fork
has no delta of its own. **No edit needed.** Confirm empty diff.

### ewmh.c — take upstream verbatim
Fork delta is pre-refactor synchronous `request::urgent/tag/select/activate` +
removed `event_queue.h`. Upstream `c2d4700` converted them to
`some_event_queue_signal(SIG_REQUEST_*)`. `request::geometry` stays synchronous
(Rule B). No fork feature. **No edit needed.** Confirm empty diff.

### objects/systray.c — take upstream verbatim
Fork delta is pre-refactor synchronous `request::*` emits + removed `event_queue.h`.
Upstream uses `some_event_queue_signal(SIG_REQUEST_ACTIVATE / SIG_SYSTRAY_*)`. No
fork feature. **No edit needed.** Confirm empty diff.

### xwayland.c — minimal
- RE-APPLY (Rule C): the `xwaylandready()` tail — `globalconf.xwayland_ready_seen =
  true; luaA_emit_signal_global("xwayland::ready");` + the explanatory comment
  (fork commit `85c227f`). Upstream restructured xwayland-ready into a
  `xwayland_ready_listener`; the flag still slots into `xwaylandready()`'s body.
- ⚠ RE-APPLY (Codex R2): `#include "objects/signal.h"` — `luaA_emit_signal_global`
  needs its declaration; if upstream's xwayland.c no longer includes it, the
  `xwayland::ready` emit won't compile. Re-apply this include WITH the feature.
- DROP (Rule A): the `request::activate`/`request::urgent` emit-call conversions,
  the `client::list` emit — take upstream's queued forms. Keep upstream's
  `#include "event_queue.h"` (Rule D — the queued calls need it).
- RE-APPLY: `scenefx_compat.h` include swap.

### protocols.c — surgical
- RE-APPLY fork features:
  1. `commitlayersurfacenotify`: `[LS-COMMIT]` debug log + opacity re-apply block
     (`layer_surface_apply_opacity_to_scene` when `0 <= opacity < 1.0`).
  2. `createlayersurface`: reordered listener registration + opacity-timing comment
     (fork commit `18cc414` — split LISTEN order to avoid destroy SIGSEGV).
  3. `unmaplayersurfacenotify`: **PR #521 focus guard** (fork commit `f756ead`) —
     capture `had_exclusive_focus = (l == exclusive_focus)` early; gate
     `focus_restore` with `if (had_exclusive_focus && !mousegrabber_isrunning())`.
     Re-applies cleanly on top of upstream `64fe6a7`'s simplified body — `64fe6a7`
     only touched the `send_leave`/`arrangelayers` block, not the focus lines.
- DROP: the `some_is_idle_inhibited`/`createidleinhibitor`/`destroyidleinhibitor`/
  `some_recompute_idle_inhibit` changes — fork has the stale pre-`7aa9351`
  `exclude`-param form; take upstream's no-arg form (consistent with Phase 2).
- RE-APPLY: `scenefx_compat.h` include swap. Re-add `#include "event_queue.h"` if
  the fork removed it (Rule D).

### focus.c — surgical
- DROP (Rule A): `focusclient()` unfocus + focus signal blocks — fork's synchronous
  `property::active`/`unfocus`/`focus` + global `client::unfocus`/`client::focus`.
  Take upstream's `some_event_queue_signal(SIG_PROPERTY_ACTIVE)`,
  `..signal0(SIG_UNFOCUS/SIG_FOCUS)`, `..global(SIG_CLIENT_UNFOCUS/SIG_CLIENT_FOCUS)`.
- RE-APPLY: `scenefx_compat.h` include swap. Re-add `#include "event_queue.h"`.
- No fork feature logic in focus.c's signal hunks (verified Group 1 audit).

### mouse.c — minimal
- DROP the fork's deletion of `luaA_mouse_fake_motion` + the `_fake_motion` method
  registration (Rule D — fork is behind; `some_fake_motion` still exists upstream).
  **Take upstream verbatim — confirm empty diff at the end.**

### input.c — surgical (partly done in Phase 3b)
Already done in Phase 3b: `some_update_pointer_constraint` definition.
Remaining:
- RE-APPLY fork features:
  - `buttonpress()`/`keypress()` bench gating on `state == PRESSED` (move
    `bench_input_event_record()` after struct decls, gate it).
  - `motionnotify()` bench removal (fork deletes `bench_input_event_record()` from
    motionnotify — motion isn't a latency start).
  - `motionnotify()` `cursor_mode == CurPressed` → `seat->pointer_state.button_count
    > 0` (fork commit `4c5b23e` — the pointer-focus-stuck fix).
  - `motionnotify()` `screen::focus` on hover crossing (fork commit `edc5605` —
    Rule C, synchronous `luaA_emit_signal_global("screen::focus")` when
    `mon != selmon`). The button-press path's `screen::focus` (input.c:567) is
    ALSO synchronous upstream — so synchronous is the right form.
  - `motionnotify()` grab-end re-entry: `motionnotify(0,NULL,0,0,0,0)` after
    `luaA_mousegrabber_stop()` (fork commit `f756ead` — the PR #521 rebase).
  - `deferred_pointer_enter()` + `pointerfocus()` idle re-delivery (fork's
    `pointer_enter_deferred_pending` static + idle callback).
- DROP (Rule A): `mouse_emit_leave/enter` synchronous calls + `motionnotify()`
  manual `mouse::move` push/emit — take upstream's `some_event_queue_signal0(
  SIG_MOUSE_LEAVE/ENTER)` and `some_event_queue_move()`.
- DROP: `createkeyboardgroup()` xkb `rules.rules = NULL; rules.model = NULL;` — the
  fork NULLs them; upstream `48e19a0` sets them from `globalconf.keyboard.*`. Take
  upstream (consistent with Phase 2/3 — fork's NULLing is pre-`48e19a0`).
- ⚠ DO NOT re-apply the `keyrepeat()` `!locked` guard removal — D5 RESOLVED: keep
  upstream's `!locked` session-lock guard.
- RE-APPLY: `scenefx_compat.h` include swap. Re-add `#include "event_queue.h"`.

### window.c — surgical (schedule_flush_clients done in Phase 2)
- DROP (Rule A): all `manage`/`unmanage` bare-signal emits in `mapnotify()` (×2);
  the synchronous `property::x/y/width/height/geometry` emits in `mapnotify()`;
  the `createnotify()` `client::list` emit; `swapstack()` SIG_LIST/SIG_SWAPPED;
  `request::activate`. Take upstream's queued forms.
- DROP (triage): the fork's PR #478 `setfullscreen()` per-client
  `property::geometry` emit (fork commit `6fb4db8`) — upstream `58915a2`
  reimplemented it in `resize()`. Also drop the fork's `resize()` signal block
  (keep only the fork's aspect-ratio content-area math). Drop the fork's
  `fullscreennotify()` rework's extra `property::fullscreen` emit (upstream's
  `setfullscreen` already emits it — double-emit).
- DROP: the ~25 re-added forward declarations — header-dedup `ed4b4cf` moved them
  to `window.h`.
- DROP (Codex R1): the fork's stale `some_recompute_idle_inhibit(...)` param-form
  hunk in `window.c` (line ~230) — `7aa9351` removed the `exclude` param; keep
  upstream's no-arg `some_recompute_idle_inhibit()` (consistent with Phase 2/3).
- RE-APPLY fork features (NOT signal-related — clean adds):
  - `client_clear_scene_child_pointers()` + calls from both unmap paths.
  - `mapnotify()` call-site change for `schedule_flush_clients` (fork commit
    `ed894df` — the helper itself is already in Phase 2; here only the call site).
  - `commitpopup()` popup opacity inheritance — `opacity >= 0 && opacity < 1.0f`
    (fork commit `0c839f4`, Codex R2 correction — this is window.c, not client.c).
  - `commitnotify()` bench-ordering + `client_apply_corner_radius/backdrop_blur`.
  - `maximizenotify()` + new `minimizenotify()` Lua-routing rework + listener
    lifecycle (fork commits `748070e`, `8a42b35`, `f842847`) — upstream still has
    `maximizenotify` as a near-stub; large but no queue API in the rework.
  - `initialcommitnotify` maximize/minimize capability bits.
  - `setmon()` `c->prev` ownership fix (fork commit `387e26a` — stop poisoning the
    memento).
  - `setfullscreen()` reentrance + no-op transition guards + max→fs→unfull memento
    (fork commits `e7eb6c5`, `25a1708`, `8eef823`, `387e26a`).
  - `apply_geometry_to_wlroots()` `strict_clip` decoration-hiding branch (fork
    commit `4dc0fbf`).
  - `unmapnotify()` early-exit `commit.link` removal (fork commit `ddd921a`).
  - `scenefx_compat.h` include swap.
  ⚠ OVERLAP: the fork's offscreen-rendering changes in `apply_geometry_to_wlroots()`
  partially duplicate upstream `e7c14e6`/`2b6413c`/`9774101` — reconcile per the
  audit; do not double-apply.

### objects/client.c — the hardest file, reconciled 33-hunk plan
The full delta (`git diff upstream/main..main -- objects/client.c`, ~953 lines, 33
hunks) was independently audited by a fresh Sonnet agent AND cross-checked against
Codex R1. The reconciled per-hunk classification below is authoritative. Upstream's
current queued signal sites — TAKE these, drop the fork's synchronous twins:
`client_unfocus_internal` 1921-1922, `client_focus_update` 2048-2049,
`client_manage` 2419-2424 + 2469, `client_resize_do` 2695-2710, `client_unmanage`
3191 + 3233, `luaA_client_swap` 3594-3603.

| # | hunk / fn | verdict | notes |
|---|-----------|---------|-------|
| 1 | @92 includes | RE-APPLY | add `#include "objects/mousegrabber.h"` (needed by hunk 7) |
| 2 | @101 includes | **KEEP UPSTREAM** | ⚠ Sonnet said "apply fork's `event_queue.h` removal" — WRONG for the migrated file. After migration objects/client.c USES the queue (we take upstream's `some_event_queue_*` sites). `#include "../event_queue.h"` MUST stay (Rule D). |
| 3 | @110 includes | KEEP UPSTREAM | DROP the fork's `screenshot_compose.h` removal — paired with hunk 29; upstream's content getter needs it. |
| 4 | @120 includes | RE-APPLY | `scenefx_compat.h` swap (SceneFX core) |
| 5 | @133 globals | KEEP UPSTREAM | DROP the fork's `extern layers[NUM_LAYERS]` removal — upstream's `_scene_layer` (hunk 22/33) needs it. |
| 6 | @1918 `client_unfocus_internal` | DROP-SIGNAL | take upstream `SIG_PROPERTY_ACTIVE`/`SIG_UNFOCUS` |
| 7 | @1954 `client_ban_unfocus` | RE-APPLY | mousegrabber early-return (`f756ead`, PR #521) |
| 8 | @2045 `client_focus_update` | DROP-SIGNAL | take upstream `SIG_PROPERTY_ACTIVE`/`SIG_FOCUS` |
| 9 | @2141 `client_border_refresh` | **MIXED — split 4 ways** | RE-APPLY all four interleaved fork sub-features: (a) `c->bw = c->fullscreen ? 0 : c->border_width` fullscreen guard (`1809506`); (b) `client_update_border_for_corners(c)` dispatch instead of 4-rect resize (SceneFX corner-radius); (c) opacity-alpha preservation in border color (SceneFX opacity); (d) `#ifdef HAVE_SCENEFX … border_frame` color update. Do NOT treat as one block. |
| 10 | @2416 `client_manage` | DROP-SIGNAL | take upstream `SIG_PROPERTY_X/Y/WIDTH/HEIGHT/GEOMETRY` |
| 11 | @2466 `client_manage` | DROP-SIGNAL | take upstream `some_event_queue_class(SIG_LIST)` |
| 12 | @2480 `client_manage` | DROP-SIGNAL | the fork's `/*TODO v6*/ "manage"` bare emit — `affdf56` removed it; no fork Lua connects to bare `manage` (verified). Discard. |
| 13 | @2692 `client_resize_do` | DROP-SIGNAL | take upstream's 7 `some_event_queue_signal0(SIG_PROPERTY_*)` sites |
| 14 | @2768 `client_resize` | RE-APPLY | aspect-ratio reworked to operate on **content area** (excl. borders/titlebars) — semantics fix; upstream applies ratio to full geometry (wrong with titlebars) |
| 15 | @2824 `client_set_minimized` | RE-APPLY | ⚠ NOT fork-behind — the fork DELIBERATELY removed `wlr_xdg_toplevel_set_suspended()` here (`f842847`, KWin-aligned single-configure fix for Firefox/Chrome CSD stale hit regions). Upstream still has the call; re-applying the fork = removing it. |
| 16 | @2942 `client_set_fullscreen` | KEEP UPSTREAM | fork delta is comment-only; upstream's comment is fine |
| 17 | @2991 `client_set_maximized_common` | KEEP UPSTREAM | fork delta is comment truncation only |
| 18 | @3007 `client_set_maximized_common` | RE-APPLY | `wlr_xdg_toplevel_set_maximized(...)` CSD sync (`748070e`) |
| 19 | @3188 `client_unmanage` | DROP-SIGNAL | take upstream `some_event_queue_signal0(SIG_MOUSE_LEAVE)` |
| 20 | @3228 `client_unmanage` | DROP-SIGNAL ×2 | (a) bare `unmanage` emit → discard (`affdf56`); (b) `list` → take upstream `SIG_LIST`. Both drop-signal. |
| 21 | @3591 `luaA_client_swap` | DROP-SIGNAL | take upstream `SIG_LIST` + 2× `SIG_SWAPPED` |
| 22 | @3685 `luaA_client_get__scene_layer` | KEEP UPSTREAM | DROP the fork's deletion — upstream's `_scene_layer` getter is from `07ac746` (override-redirect stacking tests); fork commit `867ba20` solved stacking differently and never removed it. |
| 23 | @3953 `titlebar_get_drawable` | RE-APPLY | `#ifdef HAVE_SCENEFX` immediate `wlr_scene_buffer_set_corner_radius` on new titlebars |
| 24 | @4023 `titlebar_resize` | RE-APPLY | `client_apply_corner_radius(c)` after titlebar resize |
| 25 | @4305 `luaA_client_set_floating` (new fn) | RE-APPLY | `_c_floating` property setter — required by stack.c |
| 26 | @4365 `client_apply_opacity_to_scene` | RE-APPLY | extend opacity to shadow tree + 4 border rects + `#ifdef HAVE_SCENEFX` border_frame. (NOT the `0c839f4` no-op skip — that's window.c/layer_surface.c, see Codex R2 correction.) |
| 27 | @4407 (+285 lines, new fns) | RE-APPLY | the big SceneFX block: `apply_corner_radius_to_tree`, `client_apply_corner_radius`, `client_update_border_for_corners`, `luaA_client_get/set_corner_radius`, `apply_backdrop_blur_to_tree`, `client_apply_backdrop_blur`, `luaA_client_get/set_backdrop_blur` (incl. `f5164d2` `backdrop_blur_optimized=false` fix). No upstream equivalent — easy to omit; do NOT. |
| 28 | @4552 export macro | RE-APPLY | `LUA_OBJECT_EXPORT_PROPERTY(client, client_t, floating, lua_pushboolean)` — pairs with hunk 25 |
| 29 | @4638 `luaA_client_get_content` | DROP-TRIAGE | take upstream's `5f3c4ef` scene-walk getter; fork's is the pre-`5f3c4ef` direct-readback (Firefox-blank #539 = Jimmy's issue, `5f3c4ef` his fix). Paired with hunk 3. |
| 30 | @5224 `luaA_client_border_is_focus_color` | RE-APPLY | check `border_frame` before `border[0]` (rounded-corner aware) |
| 31 | @5248 `luaA_client_border_is_normal_color` | RE-APPLY | same as 30 for unfocused color |
| 32 | @5316 `client_class_setup` | RE-APPLY | register `backdrop_blur` + `corner_radius` properties |
| 33 | @5336 `client_class_setup` | **MIXED** | RE-APPLY the `_c_floating` registration; KEEP UPSTREAM's `_scene_layer` registration (DROP the fork's removal of it). |

Cross-cutting: DROP throughout any PR #394 `initialized`-guard leftovers (client.h
guards already dropped Phase 2). The `client_clear_scene_child_pointers` calls the
audit mentioned are in **window.c**, not objects/client.c — see the window.c section.

At-risk features (Sonnet flagged — extra care): hunk 9 (4-way split), hunk 15
(deliberate fix, not fork-behind), hunk 27 (285-line block, no upstream context),
hunk 33 (add `_c_floating` while keeping `_scene_layer`).

### objects/layer_surface.c — surgical
- DROP (Rule A): `layer_surface_manage` / `layer_surface_emit_unmanage` synchronous
  `luaA_class_emit_signal("list")` — take upstream's `some_event_queue_class(
  &layer_surface_class, SIG_LIST)`. `request::manage`/`request::unmanage`/
  `request::keyboard` stay synchronous (Rule B).
- RE-APPLY: the fork opacity subsystem — `ls_apply_opacity_to_tree`,
  `layer_surface_apply_opacity_to_scene`, `luaA_layer_surface_{get,set}_opacity`,
  the `opacity` class property, the no-op-at-1.0 skip (fork commit `0c839f4`),
  includes. `property::opacity` stays synchronous (Rule C — fork property setter).
- RE-APPLY: re-add `#include "../event_queue.h"`. `scenefx_compat.h` swap.
- Downgrade the `[LS-OPACITY] SKIP` `wlr_log(WLR_ERROR,...)` to `WLR_DEBUG`.

### luaa.c — tag-slide helpers (deferred from Phase 2)
RE-APPLY `luaA_awesome_client_scene_set_enabled` + `luaA_awesome_client_scene_set_
strict_clip` (fork commit `4dc0fbf`) + their `awesome_methods[]` table entries.
They depend on `client_update_border_for_corners` (objects/client.c, this phase).

### lua/somewm/tag_slide.lua
Already fork-only, brought in Phase 1. Verify it feature-detects `strict_clip` and
the `_client_scene_set_*` methods (fork commit `4dc0fbf`). No edit expected.

---

## 5. Execution order

1. Trivial / take-upstream-verbatim: confirm `event.c`, `common/luaclass.c`,
   `ewmh.c`, `objects/systray.c`, `mouse.c` have empty diff vs `upstream/main`
   (no edits — they should already be upstream).
2. `xwayland.c` — small, RE-APPLY `xwayland::ready` only.
3. `protocols.c` — surgical, the PR #521 guard + layer-surface opacity.
4. `focus.c` — drop synchronous emits, include swaps.
5. `input.c` — the fork input features (bench, button_count, screen::focus,
   grab-end rebase, deferred_pointer_enter).
6. `objects/layer_surface.c` — opacity subsystem + SIG_LIST conversion.
7. `objects/client.c` — the big one, per-function per §4. Do it in sub-batches
   (signal-emit functions first to establish "take upstream", then the feature
   subsystem blocks). Codex review after this file specifically.
8. `window.c` — the CSD/maximize/minimize rework + drops.
9. `luaa.c` tag-slide helpers + `awesome_methods` entries.
10. Build (scenefx on + off) after each of 7, 8; full build at the end.

## 6. Test plan

- Build clean scenefx ON + OFF after `objects/client.c` and after `window.c`.
- `somewm --check` 30/30.
- The 4 upstream `tests/test-event-queue-*.lua` MUST pass.
- focus / mouse / xwayland regression test suites.
- **Double-emit grep (expanded, Codex R1):** after the phase, grep all Phase-4
  files for any surviving stale converted-signal emit — must be zero (except the
  Rule-B kept-synchronous `request::manage/unmanage/geometry/keyboard` and the
  Rule-C fork-new signals). Cover ALL three emit helpers:
  - `luaA_object_emit_signal(...)` of `property::geometry/position/size/x/y/width/
    height`, `property::active`, `focus`, `unfocus`, `mouse::enter/leave/move`,
    `request::activate/urgent/tag/select`.
  - `luaA_class_emit_signal(..., "list")` / `"swapped"`.
  - `luaA_emit_signal_global("client::focus")` / `"client::unfocus"` /
    `"client::property::geometry"`.
- Sandbox (headless, lgi guard LD_PRELOADed):
  - startup, hot-reload, client map/unmap, focus changes.
  - mouse hover across monitors (screen::focus), drag (PR #521 cross-monitor).
  - layer-surface map/unmap (PR #521 exclusive_focus guard).
  - CSD maximize/minimize via a GTK client if available.
- THEN the user live DRM-session test gate (per kolo6 methodology — no merge to
  `main` until that passes).

## 7. Codex review instructions (per user 2026-05-14)

Codex must be run MULTIPLE rounds, plus a fresh audit, and must be **given the fork
commit history** so it understands the essence and original placement of every
fork change — not just the raw diff. Concretely, the Codex prompt must instruct it
to:
- `git log -p <merge-base>..main -- focus.c input.c mouse.c window.c
  objects/client.c objects/layer_surface.c ewmh.c protocols.c xwayland.c
  objects/systray.c event.c common/luaclass.c` — read the commit messages AND
  diffs to understand WHY each fork change exists and WHERE it originally lived.
- Cross-check this sub-plan's per-function classification against (a) that fork
  history, (b) upstream's current queued-signal sites, (c) the `SIG_*` enum.
- Specifically validate: every Rule-A drop is genuinely a converted signal; every
  Rule-C keep is genuinely fork-new and absent from the enum; the
  `screenshot_compose.h` / content-getter decision; the PR #478 / `6fb4db8` drop;
  the `objects/client.c` per-hunk feature-vs-signal split.
- A SEPARATE round: a fresh audit agent re-derives the objects/client.c hunk
  classification independently and the two are reconciled.
- Iterate to GREEN before any code is written.

## 8. Open items carried in

- `wallpaper_cache_lookup` — DONE (Phase 3b).
- busted test environment is broken (lua 5.3→5.5 system update) — pre-existing,
  not a sync regression; flagged to user, does not block C work but DOES block the
  `tests/test-event-queue-*.lua` gate in §6 until the user fixes the rocks stack.
