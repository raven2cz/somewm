# Goal: rewrite XWayland unmanaged (override-redirect) handling

Status: **PLAN — not started**
Owner: raven2cz fork (`raven2cz/somewm`), upstream candidate for `trip-zip/somewm`
Created: 2026-08-23
Base branch: `sync/upstream-2026-07-18b` (NOT yet merged to `main`)
Work branch (to create): `fix/xwayland-unmanaged-rewrite`
Trigger: Sierra Chart under Wine — menus/popups often do not appear, or appear with
wrong z-order. Behaviour is correct under KDE/KWin.

---

## 1. Decision

The current handling of X11 override-redirect (OR) surfaces is structurally wrong,
not just missing a few listeners. **Rip it out and rebuild it** the way sway and KWin
do it: OR surfaces are *not* window-manager clients, they are compositor-owned
surfaces with their own lifecycle, their own scene layer, and no presence in the Lua
client model.

Today somewm creates a full Lua `client` object for every OR surface (Wine menu, Qt
tooltip, Steam popup), refs it into `globalconf.clients` and `globalconf.stack`, and
then spends ~20 `client_is_unmanaged()` branches across 8 files trying to undo the
consequences. Every one of those branches is a symptom of the wrong model. The goal
is to delete them, not to add a 21st.

Non-negotiable outcome: after this work, `client_is_unmanaged()` no longer exists,
and OR surfaces never reach the Lua client model, EWMH client lists, focus history,
tasklists, rules, or `mouse::enter`.

---

## 2. Environment facts (verified 2026-08-23)

| Item | Value |
|---|---|
| Wine | 11.15, prefix `~/.wine-sierra`, no `Graphics` registry key → **x11 driver → XWayland** |
| Sierra Chart | `~/.wine-sierra/drive_c/SierraChart/SierraChart.exe` |
| Launcher | `~/git/fishlive/scripts/sierrachart/run-sierrachart.sh` (+ `env.sh`) |
| Installed somewm | `/usr/local/bin/somewm`, built 2026-07-18 from `build-fx/` (SceneFX) |
| wlroots | system `wlroots-0.19.3`; `subprojects/wlroots.wrap` pinned to 0.19.3 |
| Live session | somewm PID 1419 on tty1 + `qs -c somewm` — **must not be touched** |

`wlr_xwayland_surface_restack()` and the `set_geometry` / `set_override_redirect`
signals all exist in wlroots 0.19.3 (`/usr/include/wlroots-0.19/wlr/xwayland/xwayland.h:222,223,293`),
so nothing here needs the 0.20 upgrade.

---

## 3. Upstream status (answers "how far behind are we?")

Measured after `git fetch upstream` on 2026-08-23:

| Comparison | Behind | Ahead |
|---|---|---|
| `sync/upstream-2026-07-18b` (HEAD) | **66** | 7 |
| `origin/main` (fork main) | **110** | 202 |

Of the 66, these touch the same code paths:

- `07feca2` fix(focus): keep X11 pointer grabs across same-surface refocus
  (+ `tests/test-x11-grab-client.c`, `tests/test-virtual-pointer-client.c`,
  vendored `wlr-virtual-pointer-unstable-v1` — reusable test infra we want)
- `c4c2d3a` fix(focus): activate XDG toplevels before keyboard enter in Lua path
- `8fcb55b` refactor(focus): mirror focusclient old-surface handling in Lua path
- `298e3d4` / `c7b3208` fix(popup): xdg-popup scene parenting and z-order
- `d0d7d3a` / `1c417d2` wlroots 0.20 switch, 0.19 still supported
- larger refactors not needed here: border-exclusive geometry, CSD buttons,
  carousel feature set, `api_level` removal

**Scope decision:** cherry-pick only `07feca2`, `c4c2d3a`, `8fcb55b` (focus paths we
rewrite anyway; `07feca2` also brings the X11 grab test client). The two xdg-popup
commits are Wayland-side and unrelated to OR surfaces — take them with the next full
sync. A full "kolo10" sync incl. wlroots 0.20 is a **separate goal**; do not bundle it.

`sync/upstream-2026-07-18b` is still awaiting the live DRM test — do not merge it to
`main` as a side effect of this work.

---

## 4. Inventory: how an OR surface flows through the code today

Line references on `sync/upstream-2026-07-18b`. This is the surface area to be removed
or rewritten.

**Creation** — `xwayland.c:122-174` `createnotifyx11()`
No OR branch at all. Creates a Lua client (`client_new`), assigns `c->id`,
`xsurface->data = c`, `c->window`, `c->bw = 0` for OR (`:145`), registers 8 listeners,
pushes into `globalconf.clients` (`:163-164`) and `globalconf.stack` (`:167`), emits
`client::list` (`:170`).

**Listeners registered** — `xwayland.c:153-160`: associate, destroy, dissociate,
request_activate, request_configure, request_fullscreen, set_hints, set_title.
**Missing: `set_geometry`, `set_override_redirect`.**

**Map** — `window.c:851-923` `mapnotify()`
Creates `c->scene` under `layers[LyrTile]`, then for OR: reparent to `LyrOverlay`
(`:916`), set node position from `c->geometry` (`:917`), `client_set_size()`,
and if `client_wants_focus(c)` → `focusclient(c, 1)` + `exclusive_focus = c`
(`:919-922`), then `goto unset_fullscreen` — skipping borders, shadow, foreign
toplevel handle, tags/monitor, rules and `request::manage`.

**Configure** — `xwayland.c:94-119` `configurex11()`
OR branch sets scene node position and acks the configure (`:106-111`).
`event->mask` (including `XCB_CONFIG_WINDOW_STACK_MODE` and sibling) is ignored for
every X11 client, managed or not.

**Stacking** — `stack.c:242-273` `stack_refresh()`
Skips OR clients entirely (`:253-257`, fix for issue #415) so they stay in
`LyrOverlay` — but then unconditionally raises **every drawin** to the top of its
layer (`:281-315`), and ontop clients also map to `LyrOverlay` (`:160-161`).
Net effect: wibar, naughty notifications and any `ontop` client get raised above an
open Wine menu on the next focus change.

**Focus** — `focus.c`
`:56-61` raise-to-top for OR instead of `stack_client_append()`;
`:73` skip focus-stack/monitor/border for OR;
`:105-106` early **return** when the old client is `exclusive_focus` and wants focus
— this aborts `focusclient()` before the new client gets keyboard enter;
`:107-114` skip protocol deactivation for OR, plus a winecfg-specific carve-out;
`:119-120` skip unfocus signalling;
`:204` skip focus signals.
Mirror logic in the Lua focus path: `somewm_api.c:455-472`.

**Input** — `input.c`
`:407` and `:554`: clicks/scroll are delivered to OR clients only when
`client_wants_focus(c)`;
`:955-975` + `mouse_emit_client_enter()` (`:762-771`): `mouse::enter` is emitted for
**any** client under the pointer, OR included, with no unmanaged check;
`:2073` drag-end border colour guard.

**Unmap** — `window.c:1993-2006`
Clears `globalconf.focus.client`, clears `exclusive_focus`, calls `focus_restore()`
— which emits `request::focus_restore` through the **event queue** (deferred).

**Destroy** — `window.c:679-728` `destroynotify()`
Does **not** clear `exclusive_focus` (the layer-surface path does exactly that,
`protocols.c:317-320`) → dangling pointer after a destroy-without-unmap, and
`focus.c:105`'s early return then blocks all further keyboard focus changes.

**Lua exposure**
`luaA_client_get()` (`objects/client.c:~3435`) does not filter OR clients → they show
up in `client.get()`, tasklists, focus-history helpers, `_NET_CLIENT_LIST` via
`globalconf.clients`. The user's `rc.lua` sloppy focus
(`somewm-one/rc.lua:229-232`: `c:activate{context="mouse_enter", raise=false}`)
therefore fires on Wine menus and on whatever the pointer crosses while a menu is
open → FocusOut in Wine → the menu closes. KDE defaults to click-to-focus, which is
why the problem does not appear there.

**Other `client_is_unmanaged()` sites to retire:** `client.h:306` (definition),
`client.h:447` (`client_wants_focus`), `xwayland.c:53,106,145`,
`window.c:288,868,901,910,1511,1993`, `focus.c:57,73,107,120,204`,
`somewm_api.c:469`, `input.c:407,554,2073`, `stack.c:253-257`.

---

## 5. Target design

### 5.1 `UnmanagedSurface` type

New struct in `somewm_types.h`, modelled on `LayerSurface` (type tag first field):

```c
enum { XDGShell, LayerShell, X11, X11Unmanaged };  /* extend client types */

typedef struct UnmanagedSurface {
	unsigned int type;                    /* X11Unmanaged — keep first */
	struct wlr_xwayland_surface *xsurface;
	struct wlr_scene_tree *scene;         /* parented to layers[LyrUnmanaged] */
	struct wlr_scene_surface *scene_surface;
	struct wl_list link;                  /* globalconf/somewm.c: unmanaged_surfaces */
	int mapped;

	struct wl_listener associate, dissociate;
	struct wl_listener map, unmap, destroy;
	struct wl_listener set_geometry;      /* NEW — H1 */
	struct wl_listener override_redirect; /* NEW — H2 */
	struct wl_listener request_configure;
	struct wl_listener request_activate;
} UnmanagedSurface;
```

No Lua object, no ref counting, no `client_t`. Lives in a plain `wl_list` owned by
the compositor. Implementation goes in `xwayland.c` (currently only 312 lines) —
keep it in one file so upstream review is easy.

**Discriminator:** `xsurface->override_redirect` is authoritative. `xsurface->data`
points to `Client *` when false, `UnmanagedSurface *` when true, and the
`set_override_redirect` handler is the single place that switches both together.
Do not rely on the `*((unsigned int *)c) == LayerShell` type-punning trick that
`xytonode()` uses today (`input.c:~1950`); check `override_redirect` first.

### 5.2 Lifecycle (sway parity — `sway/desktop/xwayland.c:36-215`)

- `createnotifyx11()`: if `xsurface->override_redirect` → `unmanaged_create()`,
  return. No Lua client, no `globalconf.clients`, no `client::list`.
- `associate` → attach map/unmap; `dissociate` → detach.
- `map` → create `wlr_scene_surface` under `layers[LyrUnmanaged]`, position from
  `xsurface->x/y`, attach `set_geometry`, and if
  `wlr_xwayland_surface_override_redirect_wants_focus()` →
  `wlr_xwayland_set_seat()` + keyboard focus to the surface (see 5.4).
- `set_geometry` → reposition the scene node. **(fixes H1: menus that move after map,
  submenus, screen-edge flips)**
- `request_configure` → ack with `wlr_xwayland_surface_configure()`.
- `unmap` → destroy scene node, synchronous focus handoff (5.4).
- `destroy` → remove from list, clear any focus/grab state, free.
- `set_override_redirect` → tear down and re-create on the other path
  (unmanaged ↔ managed). **(fixes H2)**

### 5.3 Scene layer

Add `LyrUnmanaged` to `somewm_types.h:32` between `LyrOverlay` and `LyrBlock`:

```
LyrBg, LyrBottom, LyrTile, LyrFloat, LyrWibox, LyrTop, LyrFS, LyrOverlay,
LyrUnmanaged, LyrBlock
```

Rationale: OR surfaces must sit above ontop clients, the wibar and notifications
(matching X11 semantics and KDE behaviour), and below the session lock. Nothing else
is ever parented into this layer, so `stack_refresh()`'s drawin raise loop can no
longer cover a menu. **(fixes H3)**

Relative order inside the layer follows map order (new node on top), with
`wlr_scene_node_raise_to_top()` on focus, so menu → submenu → tooltip stack
correctly.

Touch points: `somewm.c:135 layermap[]`, `objects/client.c:3739-3757`
(`_scene_layer` name table), `some_promote_lock_cover()` / session-lock code,
and any `NUM_LAYERS` loop.

### 5.4 Focus model

- `exclusive_focus` (`somewm.c:123`, `void *`) goes back to meaning **layer surfaces
  only**. OR focus gets its own typed state: `static UnmanagedSurface *unmanaged_focus`
  in `xwayland.c`, exposed through small accessors. This kills the untyped
  `void *`-compared-against-two-types hazard and the `focus.c:105` early return.
- On OR map with `wants_focus`: set keyboard focus to the surface directly
  (no `focusclient()`, no Lua signals, no focus-history entry).
- On OR unmap/destroy: **synchronous** handoff, sway order —
  1. if the OR surface's `xsurface->parent` is itself an OR surface that wants focus →
     focus it (menu → submenu chains);
  2. otherwise restore the previously focused client directly, without going through
     the deferred `request::focus_restore` event-queue round trip. **(fixes H6)**
- `destroy` clears `unmanaged_focus` unconditionally. **(fixes H7)**
- Keep the upstream `07feca2` behaviour: do not run the same-surface re-delivery cycle
  while a pointer constraint/grab is held. **(H8)**

### 5.5 Input

- `xytonode()` gains an `UnmanagedSurface **pu` out-parameter; the surface lookup
  returns the OR surface instead of a bogus `Client *`. The `globalconf.clients`
  validity walk (`input.c:~1960`) stops being the OR safety net.
- `buttonpress` (`input.c:520-600`): click on an OR surface → focus it if it wants
  focus, never emit Lua client button signals (sway: `seatop_default.c:517`).
- `motionnotify`: OR surfaces get pointer enter/motion at the wlroots seat level, but
  **no `mouse::enter` / `mouse::move` Lua signals**. **(fixes H5 — sloppy focus can no
  longer close a Wine menu)**
- `toplevel_from_wlr_surface()` (`client.h:48`) returns `X11Unmanaged` with `*pu` set;
  all 8 call sites reviewed for the new case.

### 5.6 X11 stacking feedback (H4)

Verify first from the wlroots 0.19.3 source whether the automatic Xwayland restack
documented on `wlr_scene_surface_create()` (`wlr_scene.h:382`) also applies to
`wlr_scene_subsurface_tree_create()`, which is what managed X11 clients use
(`window.c:869-871`). If it does not, `stack_refresh()` must call
`wlr_xwayland_surface_restack()` so the X server's stacking order matches what is
rendered — Wine drives z-order through `SetWindowPos` → `XConfigureWindow(stack_mode)`
and reads the tree back. Also honour `XCB_CONFIG_WINDOW_STACK_MODE` in
`configurex11()` instead of dropping `event->mask` on the floor.

### 5.7 Test introspection

OR surfaces disappear from `client.get()`, so tests need a replacement. Add a debug
API in the existing fork style (`root.memory_stats()`, `root.drawable_stats()`):

```lua
root.xwayland_unmanaged()  -- → array of { window, x, y, width, height,
                           --              mapped, layer, wants_focus, focused }
```

Read-only, coarse, test-oriented; document it as upstreamable debug tooling.

### 5.8 Removal checklist (the "rip it out" part)

Delete `client_is_unmanaged()` (`client.h:306`) and `client_wants_focus()`
(`client.h:447`) once every site below is converted:

- [ ] `xwayland.c:53` activatex11 OR guard → OR never has this listener
- [ ] `xwayland.c:106-111` configurex11 OR branch → unmanaged `request_configure`
- [ ] `xwayland.c:145` `c->bw = 0` for OR → OR has no borders at all
- [ ] `window.c:288` xdg bounds guard → unreachable for OR (XDG-only path)
- [ ] `window.c:868` `set_enabled(client_is_unmanaged(c))` → always `false` for clients
- [ ] `window.c:901` remap `bw` recompute
- [ ] `window.c:910-923` mapnotify OR branch → gone
- [ ] `window.c:1511` clip guard
- [ ] `window.c:1993-2006` unmap OR branch → gone
- [ ] `focus.c:57,73,105-114,120,204` → all OR branches gone; winecfg carve-out
      re-evaluated (it exists only because OR windows were clients)
- [ ] `somewm_api.c:455-472` mirror logic
- [ ] `input.c:407,554,2073` → unmanaged handled before the client branch
- [ ] `stack.c:253-257` inline OR skip → OR is not in `globalconf.stack` at all
- [ ] `objects/client.c` `_scene_layer` layer table + `NUM_LAYERS` consumers
- [ ] `tests/test-xwayland-override-redirect-stacking.lua` rewritten against the new API

---

## 6. Beyond OR: managed Wine windows

Not every missing Sierra Chart window is override-redirect. Phase 1 must produce a
census before Phase 2 touches the managed path:

- Which SC windows are managed vs OR, and their `_NET_WM_WINDOW_TYPE`,
  `WM_TRANSIENT_FOR`, WM_HINTS input model, `_NET_WM_STATE` (modal), requested vs
  actual geometry, assigned tags/screen/layer.
- `mapnotify()` forces `c->type = WINDOW_TYPE_DIALOG` for any client with a parent
  (`window.c:1008`) and copies the parent's tags — verify that is right for Wine's
  utility/tool windows.
- Transients get `WINDOW_LAYER_IGNORE` and follow the parent via
  `stack_transients_above()` (`stack.c:109-110`, `:201-220`) — verify with a
  three-level chain (main → dialog → sub-dialog), which SC produces.
- Modal dialogs: confirm `_NET_WM_STATE_MODAL` reaches Lua and does not end up
  behind the parent.

Fix whatever the census shows, as separate commits.

---

## 7. Phases

### Phase 0 — Setup
1. Branch `fix/xwayland-unmanaged-rewrite` from `sync/upstream-2026-07-18b`.
2. Cherry-pick `07feca2`, `c4c2d3a`, `8fcb55b` (+ vendored virtual-pointer protocol
   if `07feca2` needs it). Build, run the existing xwayland tests, confirm clean on 0.19.
3. Write `plans/scripts/wine-sandbox.sh`: starts a nested somewm, resolves the
   **nested** `DISPLAY` via `somewm-client eval 'return os.getenv("DISPLAY")'`, runs a
   Wine command inside it, and **refuses to run** if `DISPLAY`/`SOMEWM_SOCKET` would
   resolve to the live session.

### Phase 1 — Evidence
4. Reproduce with light clients first — `wine notepad` (menu bar dropdowns are OR
   windows), `winecfg` (tabs, combo boxes, modal dialogs) — then `SierraChart.exe`.
5. Window census (section 6) via `xprop`/`xwininfo` against the nested DISPLAY plus a
   temporary `[OR]` trace in `createnotifyx11`/`mapnotify`/`configurex11`/`unmapnotify`.
6. A/B control: copy the prefix, set `HKCU\Software\Wine\Drivers` `Graphics=wayland`,
   re-test. If popups behave under the Wayland driver, the bug is confined to the
   XWayland path; if not, it is generic client handling. Record the answer.
7. Answer the 5.6 open question from the wlroots 0.19.3 source.
8. Write findings into this file before writing code.

### Phase 2 — Rewrite (commit order)
- C1 `LyrUnmanaged` scene layer + `NUM_LAYERS` consumers
- C2 `UnmanagedSurface` type + create/associate/map/unmap/destroy lifecycle
- C3 `set_geometry` + `request_configure` handling
- C4 `set_override_redirect` transitions (managed ↔ unmanaged)
- C5 focus model: `unmanaged_focus`, synchronous handoff, destroy-clears-state
- C6 input: `xytonode` out-param, click routing, no Lua `mouse::enter` for OR
- C7 remove `client_is_unmanaged()` / `client_wants_focus()` + all call sites
- C8 `root.xwayland_unmanaged()` debug API
- C9 X11 stacking feedback (`wlr_xwayland_surface_restack`, configure `mask`) — if 5.6 says so
- C10+ managed-path fixes from the Phase 1 census

Each commit builds, each commit keeps the suite green.

### Phase 3 — Tests
Rewrite `tests/test-xwayland-override-redirect-stacking.lua` against
`root.xwayland_unmanaged()`, and add:
- OR surface stays above the wibar and ontop drawins across stack refreshes (H3 — the
  case the current test does not cover)
- OR surface repositioned after map via `set_geometry` (H1)
- OR flag flipped after map, both directions (H2)
- menu → submenu chain: focus goes to the parent OR surface on unmap, synchronously (H6)
- destroy-without-unmap clears focus state, no use-after-free — ASAN (H7)
- OR surfaces are absent from `client.get()` and emit no `mouse::enter` (H5)
- click on an OR surface focuses it and emits no client button signals (5.5)
- X11 stacking order matches scene order (H4, if applicable)

Reuse `tests/helpers/x11_override_redirect.py` and `tests/_x11_client.lua`; add a
submenu-chain helper mimicking Wine's map/unmap sequence.
Full `make test` + `make test-asan` on the focus paths.

### Phase 4 — Verification
- New tests green in the nested sandbox.
- `wine notepad` / `winecfg` menu + dialog matrix passes.
- Sierra Chart in the sandbox: menus, submenus, floating chart/trade/settings windows,
  correct z-order, nothing disappearing, sloppy focus does not close menus.
- `plans/scripts/somewm-memory-trend.sh --idle 60` unchanged; ASAN clean.
- Hand to the user for the live DRM/NVIDIA test (the sandbox uses the wayland backend
  and cannot prove DRM timing).

### Phase 5 — Upstream
- The rewrite is a generic X11 correctness fix and belongs upstream (relates to
  upstream #589 "Steam is a trouble maker"). Split into reviewable commits.
- Update `DEVIATIONS.md` and `plans/upstream/fork-status.md`.
- No AI co-author trailers, no tool mentions (fork policy).

---

## 8. Hard rules

1. **Never** touch the live session: no `somewm-client` without an explicit sandbox
   `SOMEWM_SOCKET`, no `exec`/`restart`/`reload`, no Wine launch without the nested
   `DISPLAY`. The running compositor is the user's working desktop.
2. Test in the nested sandbox (`plans/scripts/somewm-sandbox.sh`); state plainly what
   it cannot prove (DRM/NVIDIA timing, hardware cursor, real outputs).
3. No Wine-specific or shell-specific hacks in compositor code. Every fix is a general
   X11/XWayland correctness fix, expressed the way sway/KWin express it. Upstream code
   stays upstreamable.
4. Do not merge `sync/upstream-2026-07-18b` into `main` as part of this goal, and do
   not start the wlroots 0.20 sync here.
5. Write the failing test before the fix wherever practical; every commit ships a test.
6. Cross-review the C changes with `codex exec -m gpt-5.5 --full-auto`, and
   `gemini -m gemini-3.1-pro-preview -p` for a second opinion, before declaring done.

---

## 9. References

- **sway** (`~/git/github/sway`): `sway/desktop/xwayland.c:36-215` (full unmanaged
  lifecycle incl. `set_geometry` and `override_redirect` transitions),
  `sway/tree/root.c:43-56` (layer order), `sway/input/seatop_default.c:274,517`
  (clicks/taps on unmanaged views), `sway/input/seat.c:394-410`, `keyboard.c:637-651`
  (refocus of unmanaged surfaces).
- **KWin** — optional read-only reference for OR ("Unmanaged") semantics and X11
  stacking rules: `git clone --depth 1 https://invent.kde.org/plasma/kwin.git ~/git/github/kwin`
  (`src/x11window.cpp`, `src/workspace.cpp`, `src/xwayland/`). Read for behaviour;
  do not copy code (license).
- **Wine** `winex11.drv` `is_window_managed()` — predicts which windows take the OR
  path vs the managed path.

---

## 10. Acceptance criteria

- Sierra Chart menu dropdowns and submenus open **every time**, at the correct
  position, above the parent window, the wibar and notifications.
- Floating SC windows (chart settings, trade window, dialogs) appear on the active tag
  with correct stacking and focus.
- Sloppy focus never closes an open Wine menu.
- `grep -r client_is_unmanaged` returns nothing.
- OR surfaces absent from `client.get()`, `_NET_CLIENT_LIST`, tasklists, focus history.
- Existing suite green; new OR tests pass; ASAN clean, no dangling focus state.
- A written record in this file of which findings were real, with evidence.

## 11. Risks

- **Regressions in Steam/games**: the OR path is shared with Steam popups and game
  launchers (upstream #589, fork issues #137/#133). Keep the game-focus tests in the
  loop and re-run `tests/test-xwayland-focus-*.lua` after every commit.
- **The winecfg carve-out** (`focus.c:107-114`, `somewm_api.c:465-472`) encodes real
  behaviour discovered empirically; verify with `winecfg` in the sandbox after removal
  rather than assuming it was only a workaround for the broken model.
- **Rollback**: the work is on its own branch off an unmerged sync branch; if Phase 1
  shows the OR model is not the main cause of the Sierra Chart symptoms, stop after
  Phase 1 and re-scope — the census is valuable either way.
