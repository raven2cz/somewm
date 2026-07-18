# Fix: Pointer focus pinned to stale surface (CurPressed stuck state)

## Problem

Two long-standing symptoms with the same root cause:

1. **On startup** — MPV / Dolphin receive focus visually but scroll and
   keyboard input silently drop until the user clicks into the window.
2. **After moving a window between screens** — hovering another window
   and scrolling does nothing until the user clicks into it.

Symptom #1 was reported by the user "weeks ago" and was never fully
resolved. Symptom #2 is the same bug, merely surfaced by a new trigger
(window moved via `c.screen = X` Lua setter, or C-level `setmon()`).

## Reproduction (both confirmed)

**Scenario A — startup:** launch Dolphin, hover titlebar / contents,
scroll wheel → nothing. Click → scroll starts working.

**Scenario B — screen migration:** move a window to another monitor with
`c:move_to_screen()` or keybinding, then hover a different window on the
original monitor → scroll silently fails until click.

## Diagnostic (with [SCROLL-FOCUS] probes)

Added probes in `motionnotify()`, `pointerfocus()`, `buttonpress()`,
`buttonrelease()`, `mapnotify()`, `arrange()`, `setmon()`,
`unmapnotify()`, `screen_client_moveto()`.

Log (`/home/box/.local/log/somewm-debug.log`) clearly shows:

```
[SCROLL-FOCUS] motionnotify enter
    cursor=(…,…) found_surface=0x…Dolphin focused_surface=0x…Ghostty
    same=0 client=org.kde.dolphin cursor_mode=Pressed button_count=0 drag=0
[SCROLL-FOCUS] motionnotify SWAP — keeping focus on stale surface
    (cursor_mode=Pressed button_count=0 drag=0 found=0x…Dolphin focused=0x…Ghostty)
[SCROLL-FOCUS] pointerfocus entry c=… surface=0x…Ghostty …
[SCROLL-FOCUS] wl_pointer.enter delivered surface=0x…Ghostty …
```

`xytonode()` correctly reports Dolphin under the cursor, but a guard in
`motionnotify()` overwrites the result with `seat->pointer_state.focused_surface`
(the stale Ghostty surface). The pointer is then delivered to the wrong
client every motion tick. Scroll events are routed to Ghostty, which is
not where the cursor is, so the user sees nothing.

## Root Cause

`input.c` around line 759 (pre-fix code):

```c
if (cursor_mode == CurPressed && !seat->drag
        && surface != seat->pointer_state.focused_surface
        && toplevel_from_wlr_surface(seat->pointer_state.focused_surface, &w, &l) >= 0) {
    c = w;
    surface = seat->pointer_state.focused_surface;
    sx = cursor->x - (l ? l->scene->node.x : w->geometry.x);
    sy = cursor->y - (l ? l->scene->node.y : w->geometry.y);
}
```

`cursor_mode` is a compositor-local enum (`CurNormal` / `CurPressed`):

- Set to `CurPressed` in `buttonpress()` at `input.c:487`.
- Set back to `CurNormal` in `buttonrelease()` at `input.c:580`.
- **ONLY those two transitions exist.**

If a release event is lost (grab consumption, mousegrabber early-return,
compositor grab teardown, Lua path that doesn't emit release, etc.),
`cursor_mode` stays `CurPressed` **forever**. Every subsequent `motionnotify()`
hits the guard, swaps the found surface for the stale focused_surface,
and pins the pointer there. Scroll wheel events go to the stale surface.

Logs confirm this: `cursor_mode=Pressed button_count=0` — no buttons
physically down, but the compositor thinks one is. The guard keeps
firing, the user has to click (which re-enters the real
`buttonpress → release` cycle and resets `cursor_mode` to `CurNormal`).

## Why screen migration triggers it

`screen_client_moveto()` (Lua `c.screen = X`) and `setmon()` both end up
re-arranging geometry via `arrange()`, which calls `motionnotify(0, …)`
to rebase pointer focus. If at that moment `cursor_mode` is already
stuck, the swap block pins the rebase to the stale surface on the
old screen even though the cursor is now over a different window.

## Immediate Fix (this commit)

Replace `cursor_mode == CurPressed` with
`seat->pointer_state.button_count > 0` at `input.c:759`.

`button_count` is wlroots-maintained and reflects the actual held-button
state at the seat level. It's decremented by
`wlr_seat_pointer_notify_button()` on release, so it cannot desync the
way a compositor-local enum can.

This is the consensus minimal fix from three independent reviews
(Sonnet, Codex, Gemini).

### Rationale — what Hyprland / Sway / Smithay do

- **Sway**: uses a `seatop` state machine. On press, enters a `down`
  seatop that explicitly pins the surface; on release (when its own
  `pressed_button_count == 0`) it exits. No ad-hoc sticky enum.
  See: <https://github.com/swaywm/sway/blob/master/sway/input/seatop_default.c>
- **Hyprland**: motion resolver gates the "keep pinned" behavior on a
  held-buttons container, not a compositor enum — very close to our
  proposed `button_count > 0`.
- **Smithay / Niri**: uses the upstream grab framework; grab teardown
  naturally restores focus behavior when the press/grab ends.

All three reviewers converged on: *compositor-local enum is the wrong
state to gate implicit-grab semantics on; seat button state is the
right one*.

## Known caveats of the minimal fix (Codex)

`button_count` is only decremented on paths that call
`wlr_seat_pointer_notify_button()`. In somewm, at `input.c:647`, a
button event can return early if `mousegrabber_isrunning()`. Those paths
never bump `button_count` at all, so the new guard is only as trustworthy
as the button delivery path. This fixes the concrete stuck-state class
we can reproduce; it does not fix a hypothetical desync if a compositor
grab intentionally swallows a release before reaching wlroots.

For now this is acceptable — the reported scenarios (MPV/Dolphin startup
scroll, post-screen-migration scroll) all go through the normal
press/release path.

### Intentional behavioral side-effect: Lua mousegrabber

During a Lua-driven mousegrabber session (e.g. `awful.mouse.client.move`),
`mousegrabber_isrunning()` short-circuits the button handler before it
can update `cursor_mode` or call `wlr_seat_pointer_notify_button()`.
Consequently:

- **Old behavior** (`cursor_mode == CurPressed`): if the grabber was
  initiated by a held mouse button, `cursor_mode` kept whatever value
  it had, and the pin block could fire unpredictably.
- **New behavior** (`button_count > 0`): `button_count` stays at 0
  throughout the grabber, so the pin block is bypassed for the whole
  session. The cursor freely re-targets surfaces as it moves.

This is the **correct** semantics: during a compositor-level grab the
underlying Wayland pointer focus should follow the cursor, not be
latched to a surface. Lua move/resize rely on cursor motion deltas,
not on `wl_pointer.enter` delivery. No regressions expected.

## Generic follow-up (future commit, TBD)

Three independent reviewers recommended different long-term directions:

### Option A — Remove the swap block entirely (Sonnet)

`&& !seat->drag` already guards DnD. In Wayland, implicit grabs are a
client-side concept: a client that received `wl_pointer.button` press
tracks the press itself and interprets subsequent motion events as a
drag. The compositor doesn't need to prevent `wl_pointer.enter` from
switching surfaces — clients that care simply ignore motion/enter on
other surfaces while they think they're dragging. wlroots' own grab
machinery handles actual grabs (DnD, popups, move/resize).

Risk: text selection across windows may rely on compositor-side pinning
(unclear — needs testing).

### Option B — Explicit compositor-grab state (Codex / Gemini)

Introduce dedicated compositor-grab tracking:
- For client implicit grabs: rely on `seat->pointer_state.button_count`.
- For compositor grabs (Lua move/resize, mousegrabber): use wlroots'
  grab machinery (`wlr_seat_pointer_start_grab()`) or explicit
  refcount/state with a clear teardown.
- Explicit refocus/rebase hook when a compositor grab ends.

This is the most robust long-term architecture but the most invasive.

### Option C — Audit all `cursor_mode` checks

`cursor_mode == CurPressed` appears elsewhere (historically around
input.c:1981 and 1997 — to be re-verified). Any of them can wedge the
same way. Audit:
- Surface `destroy` / `unmap` mid-drag — does `cursor_mode` reset?
- Popup grab steals the seat — does `cursor_mode` reset?
- Mousegrabber Lua cancellation mid-drag — does `cursor_mode` reset?

Each place where the answer is "no" is a potential stuck-state repro.

## Diagnostic removal

All probes are tagged `[SCROLL-FOCUS]`. Remove with a single grep-driven
pass across `input.c`, `window.c`, `objects/screen.c` before the fix
commit lands. Tracked by task #39.

## Status

- **2026-04-22**: Root cause identified, three-model review complete,
  minimal fix + probe removal prepared.
- **Next**: user live test. If regressions: revert. If clean: pick one of
  Options A / B / C as follow-up commit.
