# Fix: Maximize/Fullscreen restore-to-original geometry

**Branch:** `fix/maximize-fullscreen-restore-original`
**Status:** landed (2026-04-18), commits `5ecfc34`, `25a1708`, `c613444`
**Related:** supersedes reverted commit `8eef823` on main
**Upstream scope:** mostly project-specific; see "Upstream scope" at bottom.

## The two bugs

### Bug 1 — Super+M auto-raises maximized client
User report: *"rozhodne ne pro maximize! To je porad client jako kazdy jiny!"*

Before the fix, pressing Super+M raised the maximized client to the top of the
stack. Maximized ≠ focus-stealing: a maximized window should behave like any
other tiled client and stay at its current stack position.

### Bug 2 — `Max → FS → Unfull` loses original geometry
Given a client sized e.g. `1200x800+500+300`:

1. Super+M → maximizes to monitor rect (e.g. `1920x1080+0+0`)
2. Super+F → fullscreen
3. Super+F again → unfullscreen

Expected: client restores to `1200x800+500+300` (original pre-max size).
Actual: client restored to the maximized rect `1920x1080+0+0`.

Same corruption for `Max → FS → Max` (fs toggles off into maximized, next
unmaximize should still land on original).

## Why the original C fix (`8eef823`) failed

The first attempt added a Lua-side un-maximize dispatch inside
`client_set_fullscreen` (objects/client.c) and a Lua dispatch block inside the
C protocol `setfullscreen` (window.c). The idea: when entering fullscreen from
maximized, emit `client_set_maximized(false)` first so `aplace.restore` ran the
maximize memento and wrote pre-max geometry into `c->geometry`, then capture
`c->prev = c->geometry` for the fullscreen restore.

**What actually happened (race with `anim_client.lua`):**

`anim_client` connects to `property::maximized` and calls
`animate_geo(c, from, to, "maximize")`. `animate_geo` synchronously calls
`set_geo(from)` at the *start* of the tween to rewind the client back to its
"from" geometry before the animation plays. So the sequence was:

```
fullscreen toggle
 └─ client_set_maximized(c, false)
     └─ aplace.restore("maximize")   → c.geometry = pre-max (1200x800+500+300)
     └─ signal property::maximized fires
         └─ anim_client animate_geo(c, from=maximized, to=pre-max, "maximize")
             └─ set_geo(from)        → c.geometry = MAXIMIZED again (1920x1080+0+0)
 └─ c->prev = c->geometry             → captures WRONG (maximized) geometry
 └─ aplace.maximize(context="fullscreen")
     └─ stores maximized rect under data[c]["maximize"] (context_mapper collision)
```

The `context_mapper` in awful.placement maps both `"fullscreen"` and
`"maximized"` contexts onto the single `data[c]["maximize"]` memento key, so
the fullscreen-entry snapshot **overwrote** the real pre-max memento with the
corrupted maximized rect. Every subsequent restore pulled the wrong value.

Root cause in one sentence: *anim_client synchronously reverts `c.geometry`
during its signal handler, so any C code that captures `c->geometry` right
after toggling the Lua maximize state reads the animation "from" frame, not
the un-maximize result.*

## The fix (landed)

### 1. Revert the C-side un-maximize dispatch (`25a1708`)
- `objects/client.c` `client_set_fullscreen`: removed the
  `client_set_maximized(L, abs_cidx, false)` + `set_below/above/ontop` block.
- `window.c` `setfullscreen`: removed the Lua dispatch block and the
  reentrance guard that depended on it. Restored the bare
  `c->maximized = 0; c->maximized_horizontal = 0; c->maximized_vertical = 0;`
  + `wlr_xdg_toplevel_set_maximized(..., false)`.
- **Kept** from `e7eb6c5`: the `was_fullscreen` local + no-op transition guard
  (`if (!was_fullscreen) c->prev = c->geometry;`). That part is independent
  hardening and not tied to the broken maximize coupling.

### 2. Move the memento logic into user-space keybindings (`c613444`)
File: `plans/project/somewm-one/fishlive/config/keybindings.lua`.

Uses **per-client ad-hoc fields** that never collide with AwesomeWM's shared
`data[c]["maximize"]` memento:

- `c._pre_max_geom`   — geometry before Super+M
- `c._pre_max_v_geom` — geometry before Super+Ctrl+M (vertical maximize)
- `c._pre_fs_geom`    — geometry before Super+F

Super+F (fullscreen toggle):
- On enter: if client is maximized, save `c._pre_fs_geom = c._pre_max_geom`
  (the *original* pre-max size, not the maximized rect). Otherwise save
  current geometry.
- On exit: restore saved geometry + clear all max flags.

Super+M (maximize toggle):
- If fullscreen → exit FS, clear max, restore `_pre_fs_geom` (which holds
  pre-max).
- Elif maximized → restore `_pre_max_geom`, clear max.
- Else → save `_pre_max_geom = c:geometry()` then maximize.
- **Removed `c:raise()`** — fixes Bug 1.

Super+Ctrl+M (vertical maximize toggle): same pattern with `_pre_max_v_geom`.
Also no `c:raise()`.

### 3. Stack-order companion fix (`5ecfc34`, landed earlier on branch)
In `objects/stack.c`, maximized clients now stay in `LyrTile` regardless of
their `floating` flag. AwesomeWM's X11 convention auto-floats maximized
windows; in the Wayland scene graph that pushed them into `LyrFloat` and made
them render above genuinely floating siblings, which confused the visual
stack. Keeping them in `LyrTile` matches how tiled-but-maximized clients look
under X11.

## Verification

All four scenarios verified in nested sandbox
(`WLR_BACKENDS=wayland SOMEWM_SOCKET=...`):

| Case | Sequence | Expected | Got |
|---|---|---|---|
| 2a | Max → FS → Unfull | 1200x800+500+300 m=false fs=false | ✓ |
| 2b | Max → FS → Max (toggle off) | 1200x800+500+300 m=false fs=false | ✓ |
| 2c | FS → Max → Unfull | original pre-fs geometry | ✓ |
| 2d | FS → Max → Unmax | original pre-fs geometry | ✓ |
| 1  | Super+M on c1, then focus c2 | c2 above c1 (no auto-raise) | ✓ |

## If this bug resurfaces — checklist

1. **First suspect: did something re-introduce a C-side un-maximize during
   fullscreen entry?** Check `objects/client.c` `client_set_fullscreen` and
   `window.c` `setfullscreen`. If so, the anim_client race is back.
2. **Check `anim_client.lua`** — if it ever stops calling `set_geo(from)`
   synchronously (e.g. switches to an async tween start), the C-side coupling
   *could* be re-introduced safely. Until then, keep the memento logic in
   user-space.
3. **Check `awful.placement`'s `context_mapper`** — if `"fullscreen"` and
   `"maximized"` ever get separate memento keys, AwesomeWM's own
   `aplace.restore` would stop clobbering across contexts and some of the
   manual memento fields could be retired.
4. **Check Super+M binding** — any reintroduction of `c:raise()` for maximize
   revives Bug 1.
5. **Check `objects/stack.c`** — if maximized-floating handling regresses,
   maximized windows render above floating siblings again.

## Upstream scope

- **`25a1708` (revert)** — not upstream material. Undoes `8eef823` which was
  never pushed upstream.
- **`c613444` (keybindings.lua)** — user-space config in
  `plans/project/somewm-one/`. Strictly our fork.
- **`5ecfc34` (stack.c)** — candidate for upstream. Real Wayland semantic
  issue. Uncertain whether trip-zip accepts AwesomeWM-semantic changes.
- **`e7eb6c5` (was_fullscreen + no-op guard)** — candidate for upstream.
  Generic hardening, independent of the rest.

Both upstream candidates are C-level and independent of our config, so they
can be cherry-picked onto a branch off `upstream/main` if/when we want to
open a PR.

## Key files touched

- `objects/client.c` — `client_set_fullscreen` (Lua path for Super+F)
- `window.c` — `setfullscreen` (C protocol path, e.g. xdg-shell fullscreen
  request from the client)
- `objects/stack.c` — stack layer assignment for maximized clients
- `plans/project/somewm-one/fishlive/config/keybindings.lua` — Super+F,
  Super+M, Super+Ctrl+M bindings

## Commits (in landing order on branch)

1. `e7eb6c5` fix(fullscreen): add reentrance + no-op transition guards in setfullscreen
2. `5ecfc34` fix(stack): keep maximized clients in LyrTile regardless of floating
3. `25a1708` revert(fullscreen): remove 8eef823 un-maximize side-effect
4. `c613444` fix(keybindings): preserve pre-max/pre-fs geometry across max/fs toggles
