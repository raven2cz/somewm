# Bug 2 (Spotify mouse-swallow on HP) — log evidence + analysis

## Status update
Bug 1 (focus loss on cross-monitor drag) — **your H3 from previous audit
CONFIRMED 100%** by logs:

```
17.272  [POINTER-CROSS] cross DELL→HP, mousegrabber=1, focus=Claude Code
17.278  screen_client_moveto ENTRY (had_focus=1, isvisible=1)
17.278  c->mon CHANGE DELL→HP
17.278  banning_need_update WILL UNFOCUS focused=1
17.278  client_ban_unfocus CLEARING FOCUS  ← here, mid-drag
```

Fix planned: early-return in `client_ban_unfocus` when
`mousegrabber_isrunning() && globalconf.focus.client == c`.

## Bug 2 — observed log evidence (Spotify XWayland)

**Setup:** Spotify (X11/XWayland, client_type=2) spawned on DELL primary
(monitor `0x55e563d73b00`). User dragged Spotify to HP portrait monitor
(`0x55e563df64e0`). HP is left of DELL → cursor goes negative X.
After drag, Spotify clicks on play/pause button do nothing — Spotify
silently swallows clicks. Keyboard works.

**What compositor logs show during failed clicks:**

```
00:13:44.955 [XWL-SEAT] pointerfocus ENTER prev=(nil) new=0x55e567caadf0
              client=Spotify type=2 sx=772.1 sy=1513.3
00:13:45.554 [XWL-SEAT] button DELIVER button=272 state=1
              to pointer_focused_surface=0x55e567caadf0
              client=Spotify type=2 on selmon=0x55e563df64e0
              cursor=(-1318.1, 1994.7)
00:13:45.614 [XWL-SEAT] button DELIVER button=272 state=0   (release)
00:13:45.713 [XWL-SEAT] button DELIVER button=272 state=1   (next click)
... 18 click events delivered to Spotify, none acted on
```

Pointer focused surface is correctly Spotify. Compositor calls
`wlr_seat_pointer_notify_button(seat, time, btn, state)` after delivery.
This is the path Sway uses too.

**What the logs do NOT show (suggestive negatives):**
- No `wlr_xwayland_set_seat()` call between the drag and any of the failed
  clicks. Last seat call for Spotify was at 12:22 (initial map). After
  drag, none. (You said previously this is not per-output, so likely
  irrelevant — please confirm given current logs.)
- No `pointerfocus CLEAR` followed by `ENTER` mid-click — pointer focus
  is stable on Spotify across all 18 clicks.
- No `screen_client_moveto` for Spotify between the drag-end and the
  clicks (drag was earlier, clicks 30 s later, fully settled state).
- Spotify is NOT getting overlapped by a layer surface — distinct
  `pointerfocus ENTER` to layer surfaces appears at other times with
  `client=(nil) client_type=-1`, not during the click flow.

**Critical observation about coordinates:**
- Cursor at click: `(-1318.1, 1994.7)` — negative X (HP portrait is left
  of DELL primary in compositor coords).
- `client_set_size()` in `client.h:399-407` computes
  `int16_t cx = c->geometry.x + c->bw + tl;` and calls
  `wlr_xwayland_surface_configure(xs, cx, cy, w, h)`. If
  `c->geometry.x ≈ -2090`, cx ≈ -2089 — fits int16_t.
- BUT: Does X11 root window correctly span negative coordinates when the
  XWayland output is positioned at negative compositor coordinates?
  How does wlroots XWayland map multiple wlr_outputs (DELL at (0,0), HP
  at (-2160, 0)) into the X11 root window space?

## Quickshell (QS) ruled out
User asked if QS layer surface could be intercepting. Log evidence:
during the 18 click events, `pointer_focused_surface` is consistently
the Spotify surface, not a layer surface. QS panels appear in
pointerfocus ENTER logs at *other* times.

## Questions for Codex

1. **Verify negative inference.** Is the conclusion correct — that
   compositor properly delivers buttons to Spotify, and the failure is
   downstream in XWayland or Spotify itself? Or is there a compositor
   step we're missing (e.g. should `wlr_xwayland_set_seat()` be re-fired
   on output change, even though you said it's not per-output)?

2. **wlroots XWayland multi-output coordinate handling.** Look at
   `subprojects/wlroots/xwayland/xwm.c` and
   `subprojects/wlroots/xwayland/server.c`. How does wlroots position
   the X11 root window across multiple wlr_outputs at different positive
   AND negative compositor coordinates? Does it require the X11 root
   to start at (0,0)? Look at `xwm_output_handle_*` and
   `wlr_xwayland_output_*`.

3. **Sway reference** at `/home/box/git/github/sway`: how does Sway
   handle a window dragged to a wlr_output that is positioned at
   negative coordinates? Specifically, does Sway clamp window coordinates
   to ≥0 before configuring the X11 surface? Look at
   `sway/desktop/transaction.c`, `sway/tree/view.c`,
   `sway/desktop/xwayland.c::view_set_view_position` or equivalent.

4. **Empirical test design.** Before we add more code, we want to
   distinguish "general XWayland-on-negative-X" bug from "Spotify-
   specific". The plan is to spawn `xeyes` or `xclock` (small native
   X11), drag DELL→HP, click. If xeyes also fails to react,
   compositor/wlroots bug. If xeyes works, Spotify-specific
   (Electron/CEF). Is this the right discriminator? Any better test?

5. **If it IS a compositor bug** — what's the lightest fix? Candidates:
   (a) Clamp X11 surface position to (0,0) before configure (translate
       to "X11 root frame" that always starts at origin).
   (b) Position XWayland output rectangles in X11 root with offset so
       all positions are non-negative.
   (c) Some wlroots-level call we're missing during cross-output drag.
   Which has the smallest blast radius?

6. **Regression check** for fix to Bug 1 (early-return in
   `client_ban_unfocus` on `mousegrabber_isrunning()`): could that
   silently break:
   - `ea7e1aa` re-eval pointer focus after banning?
   - `3042fd5` motionnotify on hotplug ban?
   - Hot-unplug of source monitor while drag is in progress?

Please be terse, line-numbered, evidence-based. Repo is
`/home/box/git/github/somewm`. Sway at `/home/box/git/github/sway`.
wlroots at `/home/box/git/github/somewm/subprojects/wlroots`.
