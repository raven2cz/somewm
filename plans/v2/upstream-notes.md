# Notes for upstream (trip-zip/somewm)

Material for issues or PRs to upstream, collected while moving to v2
(upstream 2.1 + thin fork). Upstream accepts issues only when a person
writes them, and PRs only for issues the maintainer has agreed to
(`AGENTS.md`, `AI_POLICY.md`, `CONTRIBUTING.md`). So this is raw material
for the maintainer (raven2cz) to write up; AI use must be disclosed. Nothing
here has been sent. User decision 2026-10-24: no submissions for now.

Base: upstream/main `6eaa61e` (2.1.0 + 5). Commits refer to raven2cz/somewm
main.

## Bugs (crash or wrong behaviour), with fix and test

### 1. Crash after a hot reload while a configure retry is pending

- **Where:** `window.c` `configure_retry()` / `configure_retry_arm()`
  (upstream 42806d3, "A client is drawn at the size it committed …").
  `luaa.c` `clients_detach()`.
- **What:** `configure_retry_arm()` registers a timer whose data is the
  `client_t`. A hot reload copies each client into a snapshot (`memcpy`) and
  `lua_close()` frees the old userdata, but the timer stays registered with
  the old pointer. About a second later `configure_retry()` reads freed memory
  and the compositor crashes (SIGSEGV on the first load from `c`).
- **Trigger:** a terminal that commits whole cells (ghostty, kitty,
  alacritty), sized to a box that is not a multiple of the cell. Then
  `somewm-client reload`.
- **Fix:** a5e4a5c. Remove the timer in `clients_detach()` before the snapshot
  (the rebuilt client arms it again on its next commit), and in
  `client_wipe()` as a guard. 12 lines.
- **Test:** `tests/restart/configure-retry-after-restart.sh`. It crashes
  without the fix; the restart suite passes 40/40 with it.

### 2. A shadow shows through a translucent client

- **Where:** `render.c` `reconcile_shadow()`.
- **What:** the nine-patch paints its solid interior, and part of its fade,
  under the owner and relies on the owner's content to hide them. A
  translucent client (terminal background opacity) shows them through
  itself. With an offset shadow this is a light band along the top and left
  edges inside the window. The docs say "Content hides the portions behind
  it", which is only true for opaque content.
- **Fix:** d3cad6c. Client frames and floating wiboxes cut each piece by the
  owner's box (`RENDER_SHADOW_CLIP_OWNER`, up to 4 scene parts per piece
  sharing the raster), so nothing is painted under the owner. Opaque owners
  look the same.
- **Test:** `tests/test-client-shadow-translucent.lua` (pixels inside a
  half-transparent client are even, the shadow is still visible outside).
  Unit coverage is in `tests/test-render.c` (`test_shadow_owner_cut`).

### 3. Hot reload drops unmapped X11 clients (found by review, not fixed)

`luaa.c` snapshots `globalconf.clients` only. An X11 client that is unmapped
at reload time is not in the snapshot, and a later remap can use freed
state. Recorded in HANDOFF.md section 9. No reproduction yet.

### 4. Mousegrabber auto-stop can stop a new grab (found by review, not fixed)

`event.c`: when a grab callback returns false, the auto-stop runs after the
callback. If the callback started a replacement grab, that grab is stopped.
Recorded in HANDOFF.md section 9.

## Docs and code disagree

### 5. A docked wibar never gets a shadow

- The Shadows guide says: "For an existing wibar, assign the same table to
  `s.mywibox.shadow`". A wibar in flow (`declare_bar`) declares no shadow,
  and `tests/test-clay-bar-contracts.lua` asserts that ("flow wibar
  unexpectedly declares a shadow"). `shadow_drawin_*` has no effect on a
  wibar either.
- **Our change:** 5b18ed1. A bar that fills its slot (or has a shaped frame)
  declares its shadow in band `Z_DRAWIN - 1`, so it falls on the clients
  below the bar. The renderer cuts every piece at the bar's inner edge, so
  nothing lands on the bar. About 90 lines.
  Limitation: with two bars on the same edge, the outer bar's shadow can
  paint over the inner one. Either the docs should say a docked bar has no
  shadow, or something like this should go upstream.

### 6. A rounded client keeps a square border

- The Rounded Corners guide documents it: set `border_width = 0`, otherwise
  the border stays square and its width comes off the radius. That leaves
  rounded clients with no visible focus colour (2.1 marks focus only
  through the border).
- **Our change:** 63f1347. The CLIENT frame carries `radius = shape radius`,
  so Clay's border is rounded, with its inner edge at radius minus width,
  matching the content. 6 lines of Lua. Test:
  `tests/test-client-rounded-border.lua` (fails on stock 2.1).

### 7. The `shadow_clip` / `clip_directional` docs

Both are accepted and ignored since 2.0.1 (documented). A one-sided shadow
can be approximated with a negative spread and an offset; that recipe would
help in the guide:
`radius 50, offset 10/10, spread -35` gives a soft shadow on the right and
bottom only. It needs a window at least ~100 px wide; smaller windows get
no shadow.

### 8. The nine-patch draws nothing when the box is too small, silently

`reconcile_shadow()` disables every piece when `!fits` (for example a 33 px
bar with spread -30). With no warning, the shadow just disappears. It would
help to clamp spread or radius instead, or to log it once.

## Fork fixes already listed as upstream candidates

From plans/v2/README.md. Each is upstreamable on its own:
- XWayland: map a surface whose buffer was committed before `associate`
  (Wine/Sierra Chart dialogs never appeared). The gap is also in wlroots'
  `xwayland_surface_associate`.
- `main()` returns the code passed to `awesome.quit(code)` (2 lines).
- `screen::focus` when the pointer crosses outputs (not only on
  empty-space clicks).
- Focus is kept on a client dragged across outputs, and pointer focus is
  rebased when a grab ends (the first click after a drop landed nowhere).
- A layer surface unmap restores focus only if that surface held it
  (notifications and Quickshell popups stole focus).
- `root.memory_stats([gc])` (proposal #508).

## Environment and test-suite observations

- **Test suite and font stack:** 13 integration tests fail identically on a
  pristine upstream/main on Arch/CachyOS (pango 1.58.2, harfbuzz 14.6,
  freetype 2.15, hinting-slight). They compare exact text metrics: line
  height 25 vs 24, text width ≠ 326, golden dumps. These are
  `test-bundled-bar-groups`, `test-clay-calendar-presentation`,
  `test-clay-empty-contributions`, `test-clay-hotkeys-sizing`,
  `test-clay-image-in-column`, `test-clay-image-sizing`,
  `test-clay-notification`, `test-clay-textbox`, `test-clay-textbox-markup`,
  `test-clay-text-scale-change`, `test-clay-tidy-bundled`,
  `test-systray-menu-separator`, plus `test-drag-border-refocus` (kitty test
  client in the isolated bus). Tolerances or a pinned font build would make
  them portable. `test-clay-cursor` was flaky under full parallel load once
  (passes alone).
- **Multi-GPU:** wlroots takes the first DRM device. On a box with an AMD
  iGPU listed first, it composites on the iGPU and copies every frame to the
  NVIDIA card that drives the monitors. `WLR_DRM_DEVICES` is ':'-separated,
  so the stable `/dev/dri/by-path/pci-…` names cannot be used; a udev symlink
  works (plans/v2/migrate-machine.md step 4). A note in the install docs
  would help NVIDIA hybrid desktops.
- **Version string:** `somewm --version` keeps the git describe from when the
  meson tree was configured (`g100c356` after later commits were built in).
  Cosmetic.
- **Log noise:** `mouse_emit_leave: mouse::leave on unregistered drawin` and
  `Trying to emit signal 'mouse::leave' on non-object` appear at session
  start.
