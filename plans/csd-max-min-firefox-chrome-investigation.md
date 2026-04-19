# CSD max/min buttons — Firefox + Chrome min→restore→max bug investigation

**Status**: open, work paused — bug not fixed, needs fresh investigation on return

**Branch**: `feat/csd-max-min-buttons` (pushed to origin/raven2cz)

**Last commits**:
- `748070e` — happy-path wiring (works for simple max/restore cycles)
- `8a42b35` — attempted fix from Codex+Sonnet review (did NOT fix Firefox,
  Chrome broken after this commit — but Chrome was not tested on 748070e,
  so Chrome regression may predate the attempted fix)

## Problem summary

Firefox, Chrome, Nautilus (and other Gtk/Chromium CSD apps) now send
`xdg_toplevel.set_maximized` / `set_minimized` when the user clicks
their client-side decoration buttons. 748070e wired those requests to
the existing AwesomeWM `client_set_maximized` / `client_set_minimized`
Lua API.

**Happy path works**: open Firefox, click max → maximizes. Click restore
→ restores. Repeat. All fine.

**Broken sequence** (Firefox, confirmed; Chrome, unknown baseline):

1. Firefox windowed, floating layout
2. Click CSD minimize button → window hides (OK)
3. Click wibar tasklist entry to restore → window reappears (OK)
4. Click CSD maximize button → **window jumps to a screen corner, stays
   at roughly its pre-minimize floating size**, not fullscreen. Feels
   like a resize-drag started instead of a maximize.

Log evidence during reproduction:

```
00:09:56.907  [FOCUS-ACTIVATE] Firefox deactivated
00:09:56.908  [FOCUS-ACTIVATE] terminal activated
00:09:57.894  FBO 3836x2123  (full output damage; Firefox briefly looks max-sized)
00:09:58.867  mousegrabber_run called   ← awful.mouse.client.resize started
00:09:58.867  XCursor 'top_left_corner' missing, falling back   ← NW resize cursor
00:09:58.885…00:10:00.126  ~80 FBOs, monotonically shrinking 3824x2113 → 1896x1364
```

The `mousegrabber_run + top_left_corner` pair is the smoking gun. In
somewm/AwesomeWM code, that pair is only reached via
`awful.mouse.client.resize`, typically bound to `Mod4+R-click`.

**Key observation**: somewm does NOT register
`wlr_xdg_toplevel.events.request_resize`, so Firefox sending
`xdg_toplevel.resize` would be silently dropped at the wlroots level.
Therefore `mousegrabber_run` must originate from Lua, not from an
unlistened wlroots signal — yet the user did not press Mod4+R-click.
Something is routing the CSD click through a Lua path that terminates
in `mouse.client.resize`.

## What we tried (748070e → 8a42b35)

### Round 1 reviews
Parallel Codex (gpt-5.4) + Sonnet agent review of 748070e code.

Both converged on two hypotheses:

**H1 — Handler ordering**: `maximizenotify` called
`wlr_xdg_toplevel_set_maximized(wants)` BEFORE running Lua. The next
configure therefore carried `maximized=true` at the OLD floating size;
Firefox/GTK recomputed CSD hit regions for that stale size. Claimed
this, combined with set_suspended(false) on unminimize, put Firefox in
a confused state that treats the next click as a resize.

**H2 — Unminimize stale state**: `client_set_minimized(false)` only
calls `wlr_xdg_toplevel_set_suspended(false)`. It does not re-send a
fresh configure with the current maximized/geometry state. Firefox
CSD resumes with stale hit regions.

### Attempted fix 8a42b35

- `window.c maximizenotify`: reorder — Lua first, only ack-configure
  as a trailing fallback when Lua short-circuited (already in the
  requested state).
- `objects/client.c client_set_minimized`: on `s==false` with mapped
  surface, call `wlr_xdg_toplevel_set_maximized(c->maximized)` +
  `apply_geometry_to_wlroots(c)` to force a fresh configure.

### Live test result

- **Firefox**: same bug, min→restore→max still jumps to edge.
- **Chrome**: "client area completely outside, buttons unclickable"
  after min→restore. User DID NOT test Chrome on 748070e — the Chrome
  regression may be pre-existing, not introduced by 8a42b35.

Both hypotheses (H1, H2) were thus unverified speculation; the actual
bug is something else we haven't identified.

## Uncertainties to resolve

| Question | How to resolve |
|---|---|
| Was Chrome already broken on 748070e, or did 8a42b35 break it? | Deploy 748070e, test Chrome min→restore explicitly |
| Which half of 8a42b35 (if any) helps Firefox at all? | Split 8a42b35 into two commits, bisect |
| What Lua path triggers `mousegrabber_run`? | Add a printf/backtrace at mousegrabber_run entry |
| Is Firefox actually getting a fresh configure after unminimize? | Instrument wlr_xdg_toplevel_set_maximized and configure send |
| Does another compositor (sway/kwin) exhibit the same behavior with same Firefox version? | Live comparison |
| Is Firefox in CSD or SSD mode in our compositor? | Check xdg-decoration protocol state at mapnotify |

## Next-step plan (when resuming)

### Phase 1 — isolation (must do first)

Deploy `748070e` (revert point), test carefully:

1. Chrome: min → wibar restore → observe. Is the client area misaligned?
   → If YES: Chrome regression is pre-existing, NOT caused by 8a42b35.
   → If NO: 8a42b35 broke Chrome. Keep that fact noted; revert
     `client_set_minimized` change but possibly keep `maximizenotify`
     reorder as it may still help.
2. Firefox: min → wibar restore → max. Confirm same bug on 748070e
   (should be identical to the report).

### Phase 2 — diagnostics

Add instrumentation commits (diagnostic-only, revert before merge):

1. `window.c maximizenotify`: log entry with
   `c->minimized, c->maximized, c->fullscreen, toplevel->requested.*,
   c->geometry` — before and after each `wlr_xdg_toplevel_set_maximized`
   call.
2. `objects/client.c client_set_minimized`: log on both transitions
   with full client state.
3. `lua/awful/mouse/init.lua` (or wherever `client.resize` is defined):
   log the entry with a Lua stack trace (`debug.traceback()`) so we
   see who called it.
4. `somewm.c` pointer button handling: log surface + coords + modifier
   mask on every button press while Firefox is focused.

See Codex round-2 review saved at `plans/csd-max-min-codex-round2.md`
(exists after `8a42b35`) for a more detailed diagnostic patch.

### Phase 3 — reference check

Install sway (keep somewm config) or run kwin nested. Reproduce the
exact sequence with the same Firefox build. Record:

- Does the bug reproduce elsewhere? (If yes → Firefox-side issue)
- What configure sequence does sway/kwin send? (Compare with our log)
- Where do they register `request_resize`? (May answer why it matters)

### Phase 4 — targeted fix

Only after Phase 1-3 produce ground-truth evidence about what is
actually happening. Candidate fixes (priority order once evidence
points somewhere):

- Register `request_resize` + route to a controlled handler that
  either rejects or routes explicitly via Lua with protocol edges.
- Defer the unminimize reconfigure to the next arrange cycle instead
  of calling `apply_geometry_to_wlroots` synchronously.
- Suppress client pointer input for N ms after a
  `set_suspended(false)` to let Gtk/Chromium re-settle its CSD.
- Something else entirely, surfaced by the instrumentation.

## Files to touch (pointers for next session)

- `window.c`
  - `maximizenotify` ~line 1266 (current reordered version on 8a42b35)
  - `minimizenotify` ~line 1319
  - `initialcommitnotify` ~line 290 (wm_capabilities advertise)
  - `apply_geometry_to_wlroots` ~line 1366
- `objects/client.c`
  - `client_set_minimized` ~line 2822 (current 8a42b35 version adds
    unminimize reconfigure)
  - `client_set_maximized_common` ~line 2969 (current adds
    `wlr_xdg_toplevel_set_maximized` on state change)
- `objects/client.h` ~line 177 — minimize wl_listener field added
- `plans/project/somewm-one/fishlive/config/keybindings.lua` ~line 408 —
  default mousebindings (Mod4+R-click → mouse_resize)
- `plans/project/somewm-one/fishlive/config/screen.lua` ~line 105 —
  tasklist button 1 → `c:activate { action = "toggle_minimization" }`

## Reference: external reviews

- Codex round 1 (gpt-5.4): proposed the H1+H2 fix implemented in 8a42b35
  — proposed but not verified. Saved session artifact: /tmp/codex-review.md
- Sonnet round 1: converged on same H1 fix with slightly different
  redundant-ack fallback.
- Codex round 2 (gpt-5.4): ran with new failure evidence, focused on
  diagnostic instrumentation rather than fixes. Saved at
  `plans/csd-max-min-codex-round2.md` (once committed).

## Scope boundary

This bug is about **xdg-shell CSD Gtk/Chromium apps** only. XWayland
(X11) clients have their own `_NET_WM_STATE_MAXIMIZED_*` /
`_NET_WM_STATE_HIDDEN` path via `ewmh.c`, confirmed working and
untouched by this branch.

Server-side-decorated apps (alacritty, foot) are also untouched — they
have no CSD buttons to click.
