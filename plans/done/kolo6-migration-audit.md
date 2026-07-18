# Kolo 6 — Migration Audit: Fork Deltas Lost in Upstream Refactor

Base: merge-base `cb0b8e4` ↔ our main `445905a` ↔ kolo6 HEAD `2e01936`.
Upstream refactor split `somewm.c` into `input.c`, `focus.c`, `window.c`,
`monitor.c`, `protocols.c`, `xwayland.c`.

Method: per-function extract from `main:somewm.c` and kolo6 refactored files,
then unified diff.

## Legend

- **A** = fork delta (our change on top of upstream monolith)
- **B** = original context in `main:somewm.c`
- **C** = expected location in kolo6 (post-refactor)
- **D** = actual state in kolo6

---

## CRITICAL — functional regressions

### 1. `deferred_pointer_enter` + `pointer_enter_deferred_pending` LOST

- **A**: Idle-callback deferred re-delivery of `wl_pointer.enter` when the
  client has not yet bound `wl_pointer` at time of initial focus.
  Origin: commit `acca650` — "scroll not working on first mouse entry into
  new window".
- **B**: `main:somewm.c` lines 4512–4520 (static + helper), 4564–4568 (the
  scheduling block inside `pointerfocus`).
- **C**: should live in `input.c` near `pointerfocus()`.
- **D**: ❌ **completely missing**. `input.c:1037-1045` keeps the
  `POINTER-REENTER` clearing branch but drops the deferred scheduling.
  Result: first-entry hover/scroll on brand-new windows is flaky.

### 2. `commitlayersurfacenotify` cursor-rebase + opacity re-apply LOST

- **A**: When a layer surface transitions unmapped → mapped, call
  `motionnotify(0, NULL, 0, 0, 0, 0)` so `xytonode`+`pointerfocus` re-run
  without emitting Lua mouse signals (time=0 gate). Also re-apply layer
  surface opacity after `wlr_scene_layer_surface_v1` resets buffer opacity.
  Sway parallel: `cursor_rebase_all()` in `handle_map()`.
- **B**: `main:somewm.c` commitlayersurfacenotify — block around mapped
  transition + opacity loop.
- **C**: `protocols.c:commitlayersurfacenotify`.
- **D**: ❌ block removed. Without it, hover over newly-mapped panels/wibox
  does not wake until user jiggles the mouse.

### 3. `createlayersurface` listener registration order REGRESSED

- **A**: Register `commit`/`unmap`/`destroy` listeners **AFTER**
  `wlr_scene_layer_surface_v1_create()` so our opacity re-apply runs after
  wlroots' internal `surface_reconfigure()` resets buffer opacity.
- **B**: explicit ordering + comment in `main:somewm.c`.
- **C**: `protocols.c:createlayersurface`.
- **D**: ❌ LISTEN block moved **BEFORE** the scene create call. Silent
  ordering bug — opacity may be clobbered after our handler runs.

### 4. `rendermon` pre-commit opacity re-apply LOST

- **A**: Before `wlr_scene_output_commit`, iterate `m->layers[0..3]` and
  re-apply `layer_surface_apply_opacity_to_scene` for any layer with
  `opacity >= 0 && opacity < 1.0`. Catches buffer nodes created by wlroots
  after our commit handler.
- **B**: `main:somewm.c` rendermon — loop right before commit.
- **C**: `monitor.c:rendermon`.
- **D**: ❌ loop removed. Bench instrumentation reshuffled separately
  (cosmetic).

---

## Cosmetic / intentional — no action needed

- `setup()`: debug banner + comment drift; XWayland block extracted into
  `xwayland_setup()` in `xwayland.c:275-289` (semantically equivalent —
  same `wlr_xwayland_create` + signal wiring + `setenv DISPLAY`).
- `motionnotify`: `is_client_valid()` helper inlined as `foreach` loop
  (same behavior); SOMEWM_BENCH hook position.
- `buttonpress`: SOMEWM_BENCH reshuffled; one brace indentation change.
- `mapnotify`: SOMEWM_BENCH reorder.
- `focusclient`: brace formatting only.
- `objects/client.c::client_update_border_for_corners`: refactored `#ifdef
  HAVE_SCENEFX` split to keep flat 4-rect mode available on non-scenefx
  builds; redundant `if (bw > 0)` guard removed (early-return on `bw==0`
  already covers it). **Improvement, not regression.**

---

## Confirmed zero-diff (verified identical)

`xytonode`, `pointerfocus` (apart from lost scheduling above),
`mouse_emit_{leave,client_enter,drawin_enter}`, `arrange` (moved to
`window.c:166`), `arrangeclient`, `createnotify`, `createpointer`,
`createkeyboard`, `createpointerconstraint`, `destroypointerconstraint`,
`cursorconstrain`, `cursorwarptohint`, `motionabsolute`, `motionrelative`,
`axisnotify`, `keypressmod`, `keyrepeat`, `keypress`, `keybinding`,
`startdrag`, `destroydrag`, `focusmon`, `focustop`, `fullscreennotify`,
`locksession`, `destroylock`, `destroylocksurface`, `outputmgrapply`,
`outputmgrtest`, `gpureset`, `requeststartdrag`, `commitnotify`,
`commitpopup`, `initialcommitnotify`, `unmapnotify`, `destroynotify`,
`closemon`, `inputdevice`.

---

## Fix order

1. Restore `deferred_pointer_enter` + scheduling block in
   `input.c::pointerfocus`. Sandbox microtest: alacritty first-entry scroll.
2. Restore `commitlayersurfacenotify` cursor-rebase + opacity re-apply in
   `protocols.c`. Sandbox microtest: wibox hover without jiggle.
3. Move LISTEN registration **after** `wlr_scene_layer_surface_v1_create`
   in `createlayersurface`. Sandbox microtest: wibox opacity stays set.
4. Restore `rendermon` opacity re-apply loop. Sandbox microtest: transparent
   panel stays transparent across redraws.

Each fix independent — apply + rebuild + sandbox test before moving to
next. Do **not** merge kolo6 → main until user live-session validation.
