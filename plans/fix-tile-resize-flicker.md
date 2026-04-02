# Fix: Tile Resize Flicker — Analysis & Plan v4

## Problem

mfact change (Super+H/L) causes 1-2 frame flicker on slave windows. Position
updates immediately but size is deferred through XDG configure→commit.

## Root Cause (Deep Analysis)

In `apply_geometry_to_wlroots()`:
1. Line 4551: `wlr_scene_node_set_position()` — **immediate**
2. Line 4605: `client_set_size()` → XDG configure → client must commit → **deferred**

Between these: 1-2 frames with "new position + old rendered size" = gap on edge.

### Why Previous Attempts Failed

**Attempt 1 — Deferred position (check c->resize at top of function):**
Failed because `c->resize` is 0 at entry — it's set by `client_set_size()` inside
the function. Guard `if (c->resize && ...)` never triggers for new resizes.

**Attempt 2 — Revert position after client_set_size:**
Failed because `commitnotify` calls `apply_geometry_to_wlroots` (line 1597) which
re-applies position. And borders/shadow already at new geometry = visual mismatch.

**Attempt 3 — Buffer snapshot:**
Architectural issues:
- `commitnotify` calls `apply_geometry_to_wlroots` on EVERY commit (60fps for terminals)
- `client_geometry_refresh` calls it for ALL clients each refresh cycle
- Snapshot disabled `scene_surface` but these callers kept running → stuck rendering
- Re-entrance: `client_remove_saved_buffer` → `apply_geometry_to_wlroots` → new configure loop

### How Sway Solves It (Key Difference)

Sway's commit handler **NEVER** updates scene graph position. It only:
1. Validates geometry
2. Notifies transaction system ("I'm ready")
3. ALL scene graph updates happen in `transaction_apply` → `arrange_root`

somewm doesn't have this separation. `commitnotify` directly calls
`apply_geometry_to_wlroots` which both sends configure AND updates visuals.

## Architecture: Split apply_geometry_to_wlroots

Instead of buffer snapshots (complex, fragile), split the function:

### Current (single function does everything):
```
apply_geometry_to_wlroots(c):
  1. set_position (visual)
  2. update borders/shadow/titlebar (visual)
  3. client_set_size → configure (protocol)
  4. update clip (visual)
```

### Proposed (two phases):
```
client_send_configure(c):     — PROTOCOL ONLY, no visual changes
  1. client_set_size → configure

client_apply_scene_state(c):  — VISUAL ONLY, no protocol
  1. set_position
  2. update borders/shadow/titlebar
  3. update clip
```

### New Flow

**Normal tiled arrange (Lua mfact change):**
1. `client_resize_do()` → `c->geometry` updated
2. `client_geometry_refresh()` → for each tiled client:
   - `client_send_configure(c)` → sends configure, `c->resize = serial`
   - If `c->resize` was set (size actually changing): **DON'T call client_apply_scene_state**
   - If `c->resize` is 0 (size didn't change, only position): call `client_apply_scene_state(c)`
3. Client commits at new size
4. `commitnotify()`:
   - Check resize serial → `c->resize = 0`
   - **NOW call `client_apply_scene_state(c)`** — position + borders + clip atomically
   - Re-apply opacity/effects

**Floating/fullscreen:**
Always call both immediately (no deferred phase). Position and size applied together.

**Key insight:** Position update is deferred only when size is ALSO changing.
If only position changes (no resize), position applies immediately. This handles
floating move, fullscreen toggle, screen move, etc.

### Call Sites Update

| Caller | Current | New |
|--------|---------|-----|
| `client_geometry_refresh` (line 2192) | `apply_geometry_to_wlroots(c)` | Split: configure first, then scene state if no pending resize |
| `commitnotify` tiled (line 1597) | `apply_geometry_to_wlroots(c)` | Just `client_send_configure(c)` (visuals deferred until resize completes) |
| `commitnotify` resize complete (line 1603) | — | **NEW:** `client_apply_scene_state(c)` |
| `resize()` (line 4723) | `apply_geometry_to_wlroots(c)` | Both: `client_send_configure(c)` + `client_apply_scene_state(c)` (floating/interactive) |
| `mapnotify` (lines 3664, 3793) | `apply_geometry_to_wlroots(c)` | Both (client not yet visible, no flicker risk) |
| `screen_client_moveto` (line 2285) | `apply_geometry_to_wlroots(c)` | Both (immediate update needed) |

### Deferred Scene State Tracking

Add to `client_t`:
```c
bool scene_state_pending;  /* true when visual update deferred (tiled resize) */
```

This flag is set when `client_send_configure` issues a resize for a tiled client,
and cleared when `client_apply_scene_state` is called (after resize completes or
on timeout).

### Safety: Floating/Fullscreen/Animation

- **Floating**: `resize()` always calls both phases immediately → no change
- **Fullscreen**: Both phases called immediately → no change  
- **Animations**: `animation_tick_all()` in refresh cycle runs before
  `client_geometry_refresh()` → animation positions applied by Lua before
  geometry refresh → if animation changes geometry, both phases called
- **Carousel layout**: Offscreen clients get both phases (position is intentionally
  offscreen, clip handles visibility)

### Timeout

If client doesn't commit within 200ms after configure:
- Timer fires → `c->resize = 0` → `client_apply_scene_state(c)`
- Shows whatever the client has at new position

### Files Changed

| File | Change | ~Lines |
|------|--------|--------|
| `somewm.c` | Split `apply_geometry_to_wlroots` → `client_send_configure` + `client_apply_scene_state` | ~30 (restructure, not new code) |
| `somewm.c` | `commitnotify`: apply scene state on resize complete | +8 |
| `somewm.c` | `client_geometry_refresh_tiled`: new wrapper | +15 |
| `somewm.c` | Timeout handler | +10 |
| `objects/client.h` | `scene_state_pending` flag, `resize_timeout` | +2 |
| `objects/client.c` | `client_geometry_refresh` update | +5 |
| **Total** | | **~70 lines (net)** |

### Why This Is Better Than Buffer Snapshots

1. **No new scene nodes** — no snapshot tree, no buffer copying, no wlr_buffer_lock
2. **No interaction with commitnotify re-entrance** — commitnotify only calls
   `client_send_configure` (protocol), visuals are a separate explicit call
3. **No disabled scene_surface** — surface always enabled, just at old position
4. **No interference with SceneFX** — no missing corner_radius/blur on snapshots
5. **Simpler cleanup** — just a bool flag, no tree destruction in unmapnotify
6. **Compatible with animations** — animation system doesn't touch scene state directly

### Trade-off

During the 1-2 frame wait, borders/shadow/titlebar stay at OLD geometry too
(because `client_apply_scene_state` is deferred). This means the entire client
appears frozen at old position+size, then jumps to new position+size atomically.

This is acceptable — it's the same behavior as Sway's saved buffer approach,
just without the explicit buffer freeze. The key is that position and size
change TOGETHER, not separately.

### Potential Issue: Borders at Old Size

If borders are at old size while the client's surface is rendering at new size
(client committed new buffer before our deferred apply), the surface content may
briefly extend past the border. This is at most 1 frame and is far less visible
than the current gap.

## References

- Sway: commit handler NEVER updates scene graph — `xdg_shell.c:291-349`
- Sway: transaction_apply → arrange_root applies positions — `transaction.c:755-756`  
- somewm: 6 call sites for `apply_geometry_to_wlroots` identified
- somewm: `client_geometry_refresh` runs every refresh cycle for ALL clients

## Review Results (v3 reviewed by Sonnet + GPT-5.4)

### Critical Issues Found

**1. Stale geometry race (GPT-5.4, HIGH)**
`client_geometry_refresh()` mutates `c->geometry` every refresh cycle. If geometry
changes again before commit, the commit for serial A clears `c->resize` but we'd
apply scene state for geometry B (never configured). Need geometry generation
tracking, not just pending flag.

**2. Corner radius is not visual-only (GPT-5.4, HIGH)**
`client_apply_corner_radius()` calls `client_update_border_for_corners()` which
updates border geometry. Can't be in the "safe" opacity/blur group.

**3. Terminal commit frequency (Sonnet, HIGH)**
Terminals call `client_set_size` on EVERY commit (text scrolling) → returns
non-zero serial because of cell-size rounding → `scene_state_pending` set
permanently → visual updates never applied → client freezes.

**4. Clip deferral leaks content (GPT-5.4, MEDIUM)**
Without clip update, content can render onto wrong monitor or stay visible
when carousel layout expects it hidden.

### Conclusion

**Simple approaches don't work.** Every shortcut creates new edge cases:
- Deferred position: `c->resize` is 0 at entry, set inside function
- Buffer snapshots: re-entrance, commitnotify calls apply_geometry on every frame
- Split function: stale geometry race, terminal commit frequency, corner_radius

**Proper fix requires** a lightweight transaction system with geometry generation
tracking (similar to Sway's `pending`/`current` dual state). This is a 2.x
architectural change (~200-300 lines).

### Recommended for 2.x

Implement a per-client `pending_geometry` / `current_geometry` dual state:
1. Lua sets `pending_geometry` via `client_resize_do`
2. `client_send_configure` sends configure for pending_geometry
3. Scene graph always uses `current_geometry` (visual state)
4. When client commits matching size: `current_geometry = pending_geometry`
5. Scene graph updated atomically with new current_geometry

This matches Sway's architecture but without the global transaction system.
Each client manages its own pending/current independently.
