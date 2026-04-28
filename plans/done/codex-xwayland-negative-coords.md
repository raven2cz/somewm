# Bug: XWayland clients fail to receive mouse input on outputs at negative compositor coords

## Setup
- Compositor: somewm (wlroots 0.19, AwesomeWM-on-Wayland), branch `stabilize/2026-04-28`.
- Hardware: NVIDIA RTX 5070 Ti.
- Outputs:
  - DELL G3223Q (DP-3): `position = { x = 0, y = 0 }`, mode 3840x2160.
  - HP U28 (DP-2): `position = { x = -2160, y = 0 }`, transform 90 (portrait), effective box 2160x3840.
- HP is intentionally left of DELL in the user's rc.lua (matches physical layout).

## Empirical findings
1. With HP at compositor `(-2160, 0)`:
   - **Wayland-native** clients on HP work fine (mouse + keyboard).
   - **XWayland** clients (xterm, Spotify, Steam) on HP: keyboard works, mouse clicks/scroll **do not** reach the X11 client.
   - `[XWL-SEAT] button DELIVER` logs confirm `wlr_seat_pointer_notify_button` IS called, with cursor lx around `-1193`.
   - `xrandr` reports `Screen 0: current 3840 x 3840`, with `DP-2 connected 2160x3840+-2160+0 left` (RandR sees the negative-x output but the X11 screen extent only spans 0..3840).
2. After running `wlr-randr --output DP-2 --pos 3840,0` (HP shifted to positive coords beside DELL):
   - **Both keyboard AND mouse** start working for xterm/Spotify on HP.
3. After restoring HP to `-2160,0`: mouse fails again.

## What I already verified in wlroots/sway
- `wlr_xdg_output_v1.c:29-30` — wlroots' xdg-output advertises positions directly from `wlr_output_layout`. There's no way to tell xdg-output a different layout than the real one. XWayland reads xdg-output to build its X11 RandR output set.
- `wlr_xwayland_surface_configure` (xwayland/xwm.c:2112) is a thin wrapper around `xcb_configure_window` — passes coords straight through. wlroots does not translate coords.
- Commit `6114dd6a` ("xwayland: stop translating _NET_WM_STRUT_PARTIAL coordinates") explicitly notes "the X11 screen size should generally match the overall wlr_output_layout bounding box" and removed wlroots-side translation, leaving it to compositors.
- `sway/config/output.c:672` — sway also passes user's `oc->x, oc->y` straight to `wlr_output_layout_add`. No normalization. Sway does NOT solve this case (most sway users don't set negative output positions).

## somewm call sites that touch XWayland coords
- `xwayland.c:101` — `wlr_xwayland_surface_configure(s, event->x, event->y, ...)` (pre-mapped echo).
- `xwayland.c:107` — `wlr_xwayland_surface_configure(s, event->x, event->y, ...)` for unmanaged. Also `wlr_scene_node_set_position(scene, event->x, event->y)`.
- `objects/client.c:2702` — `wlr_xwayland_surface_configure(s, geometry.x+bw+tl, geometry.y+bw+tt, w, h)` on geometry change.
- `client.h:406` — `wlr_xwayland_surface_configure(s, cx, cy, w, h)` from `client_set_size`.
- `client.h:208-209` — `client_get_geometry` reads `xsurface->x/y`.
- `client.h:403-404` — `client_set_size` compares against `xsurface->x/y`.
- `monitor.c:316,318,432,649` — `wlr_output_layout_add[_auto]` uses logical coords incl. negatives.

## Hypotheses I'm choosing between

**A) Normalize the entire `wlr_output_layout` to all-positive coords inside `updatemons()`.**
   - In `monitor.c::updatemons()` after layout assembly, compute bbox; if `bbox.x < 0` or `bbox.y < 0`, re-add every monitor via `wlr_output_layout_add(..., x-bbox.x, y-bbox.y)`.
   - Pros: single fix point; xdg-output advertises positive coords; XWayland's X11 root extent then covers all outputs; everything downstream sees consistent positive coords.
   - Cons: changes user-facing semantics. `outputs[N].position` returns the normalized value (HP becomes (0,0), DELL becomes (2160,0)). The user explicitly wrote `x = -2160` in rc.lua because of physical placement; they would now query and see `0`. Visually identical (HP still left of DELL).

**B) Dual coordinate space: keep `output_layout` with negative coords, but apply offset only at XWayland boundaries.**
   - Add a helper `xwayland_layout_offset(int16_t *dx, int16_t *dy)` that returns `(-min_x, -min_y)` over enabled monitors.
   - At each `wlr_xwayland_surface_configure(s, x, y, ...)` call site, use `(x+dx, y+dy)`.
   - At each read of `xsurface->x/y` in compositor code, subtract `(dx, dy)` to convert back.
   - Pros: zero user-facing API change. Logical positions preserved.
   - Cons: doesn't fix the underlying xdg-output advertisement. Per my reading of `wlr_xdg_output_v1.c`, xdg-output still advertises negative coords to XWayland, so XWayland's X11 root extent still doesn't cover the HP, so X11 pointer events at negative root coords still get filtered. **My current best guess: option B alone is insufficient.**

**C) Hybrid: normalize layout but keep logical coords in `m->logical_x/logical_y`; expose logical via Lua `:get_position()`.**
   - User-facing API preserved.
   - Compositor-internal layout normalized.
   - Code change: add 2 fields to Monitor, set them in `set_position` paths, return them from `luaA_output_get_position`, optionally translate other Lua-visible coords (mouse position?).

## Questions for you (Codex)

1. **Verify the root cause.** Is my hypothesis correct that XWayland (xorg-xserver) filters X11 pointer events that fall outside the X11 root extent (0,0)..(screen_width, screen_height), even when a RandR output is configured at a negative position? Search XWayland source if accessible. If wrong, what's the actual mechanism that breaks pointer routing on negative-x outputs?
2. **Is option B truly insufficient?** Could there be a way to advertise different output positions to XWayland specifically (without affecting other Wayland clients)? Look in wlroots for any per-client xdg-output filtering or for an alternative mechanism (e.g., `wlr_xwayland_set_workareas`, force-xrandr-emulation).
3. **Recommend between A vs C.** If we must shift the layout, is the API breakage in option A acceptable, or does option C (with `m->logical_x/y`) pay enough for its complexity? Look at how sway/cosmic/Hyprland surface logical vs physical positions.
4. **Additional concerns.** Cursor position invariants when shifting layout mid-session, Lua signal ordering during `updatemons` re-entrancy, anything else I might be missing.

Please reply with: (a) verified root cause, (b) recommended option (A/B/C/other), (c) concrete implementation sketch including which somewm files to touch and which lines, (d) gotchas.

Reference paths on disk:
- somewm: `/home/box/git/github/somewm/`
- sway: `/home/box/git/github/sway/` (just updated to HEAD)
- wlroots: `/home/box/git/github/wlroots/` (just updated to HEAD)
- bundled wlroots in somewm: `/home/box/git/github/somewm/subprojects/wlroots/`
