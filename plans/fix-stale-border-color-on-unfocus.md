# Fix: Stale yellow border on unfocused clients

## Problem

When focus is switched via Wayland foreign-toplevel-management protocol
(e.g. dock panel's `toplevel.activate()`), the previously focused client
keeps its accent border color (`#e2b55a`) despite `active:false`.

## Reproduction

1. Open 2+ windows of same app (e.g. ghostty)
2. Super+X → dock panel
3. Click multi-window icon → preview opens
4. Click a preview card to activate a specific window
5. Previous window still has yellow border, new window also has yellow border
6. Verify: `somewm-client eval` shows `active:false` but `border:#e2b55a`

## Root Cause

`foreign_toplevel_request_activate()` (somewm.c:3009-3026) does NOT call
`focusclient()`. Instead it only emits `request::activate` to Lua and relies
on Lua's `awful.permissions.activate()` to handle focus.

### Normal focus path (Super+K, mouse click):
1. C `focusclient()` called directly
2. Line 2858: old client border → `get_bordercolor()` (unfocused)
3. Line 2830: new client border → `get_focuscolor()` (focused)
4. Lines 2864/2948: emit `client::unfocus` / `client::focus` signals
5. Lua receives signals, updates `c.active`, emits `request::border`

### Foreign-toplevel path (dock activate):
1. C emits `request::activate` signal to Lua (line 3024)
2. **C does NOT call `focusclient()` — no border update in C**
3. Lua `awful.permissions.activate()` sets `c.active = true`
4. Lua emits `request::border` for new client
5. **Old client's `c.active` never becomes false → no `request::border` → border stays focused color**

## Key code locations

| Function | File | Lines | Role |
|----------|------|-------|------|
| `focusclient()` | somewm.c | 2780-2952 | Main focus path, updates borders |
| `client_set_border_color()` | client.h | 363-373 | Sets 4 border rects + scenefx frame |
| `foreign_toplevel_request_activate()` | somewm.c | 3009-3026 | Foreign-toplevel handler, emits Lua signal only |
| `some_set_seat_keyboard_focus()` | somewm_api.c | 437-527 | Keyboard focus, does NOT update borders |
| `get_focuscolor()` | somewm.c | 3205 | `globalconf.appearance.focuscolor` |
| `get_bordercolor()` | somewm.c | 3214 | `globalconf.appearance.bordercolor` |

## Fix direction

The foreign-toplevel handler should go through `focusclient()` so the full
focus chain runs (old border reset, new border set, Lua signals).

Simple approach — replace signal-only with `focusclient()`:
```c
void
foreign_toplevel_request_activate(struct wl_listener *listener, void *data)
{
    Client *c = wl_container_of(listener, c, foreign_request_activate);
    focusclient(c, 1);
}
```

**Caution:** Need to verify that `focusclient()` handles tag switching
correctly. The current Lua path passes `switch_to_tag=true` hint. If we
call `focusclient()` directly, we may need to ensure the client's tag is
visible first (or call `c:activate{raise=true}` equivalent from C).

Alternative: keep Lua path but ensure `focusclient()` is called at the end
(e.g. from Lua's activate handler via `client.focus = c`).

Cross-reference with sway: check how sway handles foreign-toplevel activate
in `sway/desktop/xdg_shell.c` or `sway/input/seat.c`.

## Status

Analysis complete — ready for implementation in next session.
