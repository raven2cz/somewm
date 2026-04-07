# Fix: Pointer enter not delivered to newly visible layer surfaces

## Problem

When a layer-shell surface (e.g. QS dock panel) appears under the cursor,
hover/focus doesn't work until the user physically moves the mouse.

## Root Cause

`commitlayersurfacenotify()` in somewm.c detects layer surface map transitions
(`was_mapped=0 → l->mapped=1`) but does not re-evaluate pointer focus afterward.
The cursor remains focused on whatever was under it before the surface appeared.

Sway handles this via `cursor_rebase_all()` in `handle_map()`
(sway/desktop/layer_shell.c:301). somewm's own `unmaplayersurfacenotify()`
already calls `motionnotify(0, NULL, 0, 0, 0, 0)` for the reverse case.

## Why regular clients don't need the same fix

`mapnotify()` at lines 3862-3873 already has a cursor-in-geometry check that
calls `pointerfocus()` directly. It deliberately avoids `motionnotify()` because
`xytonode()` may not find the surface yet (buffer not committed). Layer surfaces
don't have this problem — `commitlayersurfacenotify()` runs after buffer commit.

## Fix Applied

In `commitlayersurfacenotify()` (somewm.c:~1507-1514), after `arrangelayers()`:
```c
/* Re-evaluate pointer focus when layer surface maps */
if (!was_mapped && l->mapped && !exclusive_focus)
    motionnotify(0, NULL, 0, 0, 0, 0);
```

Key design decisions:
- **After `arrangelayers()`**: scene node geometry must be updated before
  `xytonode()` hit-test runs, otherwise stale 0x0 geometry causes misses
- **`!exclusive_focus` guard**: prevents disrupting keyboard grabs (e.g. session
  lock). The unmap path clears `exclusive_focus` before rebasing, but map doesn't
- **`time=0`**: skips Lua mouse signals (`mouse::enter/leave/move` are gated on
  `time != 0`), only runs `xytonode()` + `pointerfocus()` for wl_pointer delivery
- **`CurPressed` safe**: if user holds a button, `motionnotify()` keeps focus on
  the drag target — new surface won't steal focus mid-drag

## Cross-model review

Reviewed by Codex (gpt-5.4), Gemini (3.1-pro-preview), and Sonnet.
All three approved. Incorporated suggestions:
- exclusive_focus guard (Sonnet)
- Precise comment about motionnotify vs cursor_rebase_all scope (Codex)

## Status

Fix implemented, reviewed, ready for commit + upstream PR.
