# CSD max/min buttons — Firefox + Chrome min→restore→max bug

**Status**: 2026-04-19 — root cause identified via KWin reference, fix plan drafted

**Branch**: `feat/csd-max-min-buttons` (pushed to origin/raven2cz)

**Commits**:
- `748070e` — happy-path wiring (max/restore works; min→restore broken)
- `8a42b35` — failed speculative fix (Codex+Sonnet H1+H2 hypotheses — did NOT fix)
- `2ea6c61` — investigation notes (this file, now being rewritten)

## Problem summary (confirmed by user live test)

Happy-path maximize/restore works in all CSD apps (Firefox, Chrome, Nautilus).

**Broken path: minimize → restore from minimize.**

After CSD minimize click → wibar tasklist restore:
- **Chrome**: client area misaligned with window frame, buttons unclickable
- **Firefox**: window appears restored, but the next CSD maximize click triggers
  `mousegrabber_run + top_left_corner` (log evidence), i.e. a resize-drag
  interaction instead of maximize

User's diagnosis: "za vsechno muze spatny restore z minimalizace" — the
unminimize path leaves the xdg client in an inconsistent state (geometry,
state bits, activated, suspended) and everything downstream is corrupted.

## Root cause (per KWin reference)

Studied `~/git/github/kwin` xdg-shell handling:

**KWin `XdgToplevelWindow::doMinimize()`** (xdgshellwindow.cpp:863):
```cpp
void XdgToplevelWindow::doMinimize() {
    if (m_isInitialized) {
        if (isMinimized()) {
            workspace()->activateNextWindow(this);
        }
    }
    workspace()->updateMinimizedOfTransients(this);
}
```
**No** `set_suspended`, **no** configure. Just moves focus away.

**KWin `setSuspended`** (windowitem.cpp:189):
```cpp
m_window->setSuspended(!visible && !m_window->isOffscreenRendering());
```
Driven by **scene visibility / occlusion** — a rendering hint, not a
minimize signal. xdg-shell spec agrees: `suspended` is "indicates that
the content of the toplevel is not visible" (rendering optimization).

**KWin unminimize path**: tasklist click → `setMinimized(false)` →
natural `setActive(true)` flow → `doSetActive()` adds `Activated` to
`m_nextStates` → `scheduleConfigure()` sends **one coherent configure**
bundling Activated + existing Maximized + existing size.

**somewm violation** (`objects/client.c:2822-2854`):
```c
if(c->client_type == XDGShell) {
    wlr_xdg_toplevel_set_suspended(c->surface.xdg->toplevel, s);   // A
    if(!s && ...initialized && mapped) {
        wlr_xdg_toplevel_set_maximized(c->surface.xdg->toplevel,   // B
                                       c->maximized);
        apply_geometry_to_wlroots(c);                               // C
    }
}
```
On minimize we send `set_suspended(true)` — Gtk/Chromium treat suspended
as a hint to collapse CSD rendering state. On unminimize we fire three
separate protocol/scene events (A+B+C) in quick succession, each
scheduling its own configure or mutating scene independently. The
client's CSD hit-region recomputation lands on a transient inconsistent
(state, size, suspended, activated) tuple. KWin does **one** configure.

## Fix plan

### Core principle
Mirror KWin's pattern: **don't drive xdg state from `client_set_minimized`**.
Minimize/unminimize is a compositor-internal concept (hide/show scene
node, tasklist signal). Let the natural focus/activate machinery generate
the coherent configure on restore.

### Changes

#### `objects/client.c` `client_set_minimized` (~2822)
**Remove the entire `if(c->client_type == XDGShell)` block** (lines
2839-2855). Keep only:
- `c->minimized = s`
- `banning_need_update()`
- `wlr_scene_node_set_enabled(&c->scene->node, !s)`
- foreign-toplevel handle update
- workarea update
- `property::minimized` signal

No manual `set_suspended`, no `set_maximized`, no
`apply_geometry_to_wlroots`. All xdg state driving is delegated
downstream.

#### Why this works for all three unminimize paths

The signal `property::minimized` is wired at
`lua/awful/layout/init.lua:343` to `arrange_prop_nf` → triggers
`arrange(screen)` → runs `window.c:209-218` foreach-clients loop →
calls `client_set_suspended(c, !visible)` where `visible =
client_isvisible(c)` excludes minimized (objects/client.h:497).

So arrange ALWAYS fires on min/unmin and ALWAYS calls `set_suspended`
with the right value — regardless of whether the unminimize originated
from:
- `c:activate` (tasklist / keybind): arrange fires; also activate
  later adds `set_activated(true)` — both batched if still pending
- `awful.client.restore()`: arrange fires; that's all
- foreign-toplevel unminimize (protocols.c:625): arrange fires; that's all

wlroots' `wlr_xdg_surface_schedule_configure` coalesces onto an idle
configure if one is pending (wlr_xdg_surface.c:170). The single
configure that gets sent batches ALL currently-pending toplevel state:
size, maximized, fullscreen, activated, suspended. Identical to KWin's
"one coherent configure" pattern.

#### `window.c` `maximizenotify` (~1267)
**No change.** 748070e + 8a42b35 reorder is correct — bug was never in
max path.

#### `window.c` `minimizenotify` (~1330)
**No change.** Already minimal (routes to Lua).

#### `window.c` arrange loop (~209-218) — suspended policy
**No change.** Keeping `client_set_suspended(c, !client_isvisible(c))`
as the single source of truth for suspended state. Semantically correct
per xdg-shell.xml — minimized windows ARE "not visible", so
`suspended=true` is legitimate. The bug was never that suspended was
set on minimize; it was that on unminimize we fired 3 events (suspended,
maximized, geometry) at different code paths and layers. Removing the
manual driving from `client_set_minimized` consolidates to a single
scheduled configure.

### Verification plan (after implementation)

1. **Build + deploy + restart**:
   ```bash
   plans/scripts/install-scenefx.sh
   somewm-client exec somewm   # or reboot for DRM fidelity
   ```

2. **Happy-path regression check** (must still work):
   - Firefox: open → max → restore → max → restore ✓
   - Chrome: same
   - Nautilus: same

3. **Bug-fix check** (previously broken):
   - Firefox: open → CSD min → wibar restore → CSD max
     → expect: cleanly maximizes, no resize-drag, no corner-jump
   - Chrome: open → CSD min → wibar restore
     → expect: client area aligned with frame, buttons clickable
   - Chrome: open → CSD min → wibar restore → CSD max ✓

4. **Keybind fallback check**:
   - Super+Ctrl+n minimize, Super+Ctrl+n unminimize → same result as
     CSD click → should also work

### Non-goals (scope boundary)

- XWayland minimize path (`ewmh.c`) — untouched, works.
- SSD apps (alacritty, foot) — no CSD, N/A.
- Fullscreen interaction with minimize — out of scope (separate code path).
- Driving `suspended` from scene occlusion — deferred. Can be added
  later as an optimization; current fix works without it.

## Rejected alternatives

- **Send one merged configure manually on unminimize** (pack `set_maximized`
  + `set_size` into a single schedule_configure): viable but fragile;
  duplicates wlroots' batching logic. KWin doesn't do this — it relies
  on the natural Activated configure carrying everything.
- **Register `request_resize` to catch the spurious resize-drag**: treats
  symptom not cause. The resize-drag is Firefox reacting to inconsistent
  CSD state; fix the state, the drag won't happen.
- **Suppress pointer input for N ms after unminimize**: hack, makes the
  UI feel laggy, only masks timing-dependent variants of the same bug.

## Files touched (in implementation)

- `objects/client.c` — simplify `client_set_minimized` (~2822-2864)
- `plans/csd-max-min-firefox-chrome-investigation.md` — this file

No changes to `window.c` (minimizenotify/maximizenotify already OK as-is
from 748070e + 8a42b35 reorder).

## References

- KWin `src/xdgshellwindow.cpp:863` — doMinimize pattern
- KWin `src/xdgshellwindow.cpp:873` — doSetActive → scheduleConfigure
- KWin `src/scene/windowitem.cpp:189` — suspended = scene visibility
- Sway `sway/desktop/xdg_shell.c:385` — request_maximize = schedule_configure only
- Sway does NOT register xdg request_minimize
- wlroots `types/xdg_shell/wlr_xdg_toplevel.c` — set_activated etc. call schedule_configure

## Context that must survive

Previous 8a42b35 fix was based on two **unverified** hypotheses
(H1 ordering, H2 fresh-configure). User memory rule: "U složitých
render/timing bugů přidat logování PŘED hypotézami". This plan is based
on the KWin reference (ground truth from a working implementation), not
further speculation. If live test fails, go back to adding
instrumentation before the next hypothesis.
