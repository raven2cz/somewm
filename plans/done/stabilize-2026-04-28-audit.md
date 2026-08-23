# Audit: cross-monitor drag focus loss + Spotify mouse-swallow

## User-reported symptoms (verbatim CZ + EN summary)

> Když posunuji ve floating layout clienta z DELL doleva na portrait obrazovku
> HP, tak z toho aktivního clienta po přesunu na ten druhý screen najednou se
> zruší focus a jeho border, i když aktivně pořád s ním manipuluji s myší.
> Musíš do něj kliknout, aby se focus aktivoval a mohu jej znovu ovládat.

EN: User drags a floating client from DELL (4K landscape, primary) to HP
(4K rotated portrait) using the mouse (mousegrabber-driven move). After the
client crosses the screen boundary onto HP, **focus is cleared and the border
disappears, even while the user is still holding/manipulating with the mouse**.
Must click to refocus.

> Když toto udělám se Spotify oknem, tak sice focus získat, ovládat klávesnicí
> lze, ale Spotify na HP displeji VŮBEC nereaguje na mysi kliky! Takže nelze
> zastavit písničku, dát další skladbu, protože eventy myši se nějak blokují!

EN: With Spotify (XWayland) the symptom is different: keyboard focus works on
HP, BUT **Spotify silently swallows all mouse clicks on HP** — pause/skip
buttons don't react. Mouse events are not delivered.

## Hardware

3 monitors: DELL primary 4K landscape, Samsung TV (landscape), HP 4K rotated
portrait (90° left). User's session-launched somewm under DRM (TTY login).

## Recent fixes in this area (last ~30 days)

| Commit | Date | Touch | Fix summary |
|---|---|---|---|
| `4be9f21` | 2026-04-25 | input.c | Deliver pointer enter to newly mapped layer surfaces (deferred enter idle) |
| `240ffa0` | 2026-04-22 | input.c | Gate motionnotify pin on `seat->pointer_state.button_count`, not `cursor_mode` (CurPressed could wedge) |
| `edc5605` | 2026-04-21 | input.c | Emit `screen::focus` when cursor crosses monitor boundary so QS/Lua's `awful.screen.focused()` follows |
| `2b6413c` | 2026-04-21 | window.c | Render clients across monitors outside carousel layout (don't clip to `c->mon->m`) |
| `b20caf7` | 2026-04-20 | rc.lua  | Add monitor profiles for HP portrait + Samsung |
| `75aa450` | 2026-04-17 | window.c | Keep borders visible on windows dragged past monitor edge |
| `3042fd5` | 2026-04-17 | monitor.c | Fire `motionnotify` on monitor-hotplug banning (Chromium freeze) |
| `ea7e1aa` | 2026-04-15 | somewm.c | Re-evaluate pointer focus after banning refresh |
| `a064e8e` | 2026-04-13 | focus.c | Activate XDG toplevels before keyboard enter (Lua focus path) |

## Code I verified

**input.c motionnotify, lines 798–814** — selmon update + screen::focus:

```c
{
    Monitor *mon = xytomon(cursor->x, cursor->y);
    if (mon && mon != selmon) {
        selmon = mon;
        luaA_emit_signal_global("screen::focus");
    }
}
```

No guard on `seat->pointer_state.button_count` and no guard on `seat->drag`.
Fires every time cursor crosses a monitor boundary, including mid-drag.

**input.c motionnotify pin block, lines 759–766**:

```c
if (seat->pointer_state.button_count > 0 && !seat->drag
        && surface != seat->pointer_state.focused_surface
        && toplevel_from_wlr_surface(seat->pointer_state.focused_surface, &w, &l) >= 0) {
    c = w;
    surface = seat->pointer_state.focused_surface;
    sx = cursor->x - (l ? l->scene->node.x : w->geometry.x);
    sy = cursor->y - (l ? l->scene->node.y : w->geometry.y);
}
```

This pins the *pointer* surface to the focused surface during a button-press
drag. NOTE: `seat->drag` here is the **Wayland data-device drag** (DnD
protocol), NOT a window-move via mousegrabber. During a window-move,
`seat->drag == NULL` and `button_count > 0`, so this block fires.

**focus.c focusclient, lines 89–93**:

```c
/* Don't change border color if there is an exclusive focus or we are
 * handling a drag operation */
if (!exclusive_focus && !seat->drag)
    client_set_border_color(c, get_focuscolor());
```

Same caveat: `seat->drag` only covers Wayland DnD. Mousegrabber drags pass
through this and DO change border color.

**focus.c focusclient, lines 175–197** — XWayland seat binding lives ONLY
inside `focusclient()`. Not duplicated in `pointerfocus()`:

```c
if (surface_ready) {
#ifdef XWAYLAND
    if (c->client_type == X11)
        wlr_xwayland_set_seat(xwayland, seat);
#endif
    kb = wlr_seat_get_keyboard(seat);
    if (kb)
        wlr_seat_keyboard_notify_enter(seat, surface, kb->keycodes, ...);
    ...
}
```

**input.c pointerfocus, lines 1026–1085** — handles pointer enter but never
calls `focusclient()` and never calls `wlr_xwayland_set_seat()`.

**Lua handler for `screen::focus`** — only one in user's rc.lua/fishlive:

`plans/project/somewm-one/fishlive/config/shell_ipc.lua:52`:
```lua
awesome.connect_signal("screen::focus", function()
    local s = awful.screen.focused()
    if s then
        awful.spawn.easy_async(
            "qs ipc -c somewm call somewm-shell:compositor setScreen " .. ...,
            function() end)
    end
end)
```

Pure outbound IPC — does NOT touch focus, tags, or clients. So screen::focus
emission alone cannot directly clear focus on the dragged client via this
handler. (Other handlers may exist; I found no others matching `screen::focus`
in lua/, plans/project/somewm-one/, ~/.config/somewm/.)

**rc.lua focus-follows-mouse**, line 204:
```lua
client.connect_signal("mouse::enter", function(c)
    c:activate { context = "mouse_enter", raise = false }
end)
```

This fires when cursor enters a different client's surface. During a window
drag, the client moves WITH the cursor, so the cursor never enters a different
client — *unless* the dragged client is partially off-screen and the cursor
exits the client surface into empty space, then re-enters.

## Hypotheses

### Bug 1: focus loss on cross-screen drag

I do **not** have a fully verified root cause. Plausible candidates, ordered
by likelihood:

**H1 (most likely)**: During the drag, when the client is partially off the
source monitor, the cursor briefly exits the client's surface into empty space
(the gap between monitors in compositor coords, or a region the dragged client
hasn't reached yet on the destination monitor). `pointerfocus(NULL)` clears
pointer focus. On next motion tick, cursor re-enters the dragged client's
surface on HP, but **`mouse::enter` does NOT fire because Wayland deduplicates
re-enter to the same client** — and somewhere the client got marked as
unfocused. Then the user stops moving the mouse for a moment, focus stays
cleared. (Needs verification: does `mouse::enter` actually deduplicate? The
`ignore_next_enter_leave` guard at input.c:997 hints at it.)

**H2**: `selmon` change at input.c:811 → `screen::focus` emit → some Lua code
I haven't found yet calls `awful.client.focus.history.get(s)` or similar,
selecting an existing client on HP and stealing focus.

**H3**: Cross-monitor drag triggers `client_set_border_color(get_bordercolor())`
somewhere on the source client because some path treats "cursor not on my
monitor" as "I'm no longer focused" and resets border. (Have not found such
code yet; speculative.)

### Bug 2: Spotify mouse-swallow on HP

**H4**: `wlr_xwayland_set_seat()` is called only inside `focusclient()`
(focus.c:180). When user drags Spotify across screens, the XWayland surface
keeps pointer focus (via `pointerfocus()`), but if `focusclient()` is not
invoked during the cross, **XWayland was never told the seat is bound on the
HP output**. Without this, the X server may route input correctly for keyboard
(because keyboard enter was sent earlier on initial focus) but click events
get lost in routing.

**H5 (alternative)**: Stale pointer-constraint from DELL output. If Spotify
had an active constraint (rare for media apps but possible), the constraint
region is in source-monitor coords and the cursor is now on HP — the constraint
silently drops clicks. `active_constraint` is checked at input.c:778.

**H6 (alternative)**: XWayland surface coordinate translation is wrong because
`c->mon` is stale (still DELL) but cursor is on HP. `cursor_to_client_coordinates`
uses `c->geometry.x` which IS updated by Lua mousegrabber, so this should be
fine — but worth ruling out.

## Risk of regression for any fix

- Adding a `seat->pointer_state.button_count == 0` guard around the
  `screen::focus` emit at input.c:811 would prevent the QS panel from following
  the cursor mid-drag. **Probably OK** — once the user releases the mouse, the
  next motion tick will fire the signal.
- Calling `wlr_xwayland_set_seat()` from `pointerfocus()` when surface changes
  to an XWayland client could fire too often (every cursor sweep across an
  XWayland window). Need to gate on "actually changed XWayland client" or
  "monitor crossed during drag".
- Any change to motionnotify is high-blast-radius — recent fixes (240ffa0,
  edc5605, ea7e1aa, 3042fd5) all touch this function; the test surface is
  large.

## What I want from Codex

1. **Verify the code claims** at the cited file:line locations against the
   actual current somewm tree. Flag anything I misread.
2. **Cross-check H1–H6** against the actual code paths. Which is most
   plausible? Are there alternatives I missed (e.g., a `mouse::leave` handler,
   a `focus::lost` path, banning_refresh interaction during drag, scene-graph
   ban triggered when client crosses tag visibility on the dest monitor)?
3. **Static reasoning for Bug 2** — does pointer-focus alone suffice for
   XWayland click delivery, or is `wlr_xwayland_set_seat()` actually required
   per output change? Look at how Sway handles this (subprojects/wlroots,
   /home/box/git/github/sway).
4. **Recommend instrumentation logs** to add (specific WLR_LOG calls with
   markers) so the user can capture two log files (working vs broken case)
   and we can confirm which hypothesis matches before writing a fix.
5. **Regression risk** — for each plausible fix, name which prior commit's
   guarantees it could break.

Be terse, line-numbered, evidence-based. Skip generalities.
