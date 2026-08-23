# Monitor portrait profile + wallpaper support

Branch: `feat/monitor-portrait-wallpaper`
Started: 2026-04-20

## Hardware inventory (current)

Tested live via `wlr-randr` against running somewm session.

### Primary: Dell G3223Q (DP-3)
- Connector: **DP-3**
- Make/model: `Dell Inc.` / `DELL G3223Q`
- Native: **3840x2160 @ 143.963 Hz** (pick this over 60Hz preferred)
- Physical: 710x400 mm (landscape)
- Transform: **normal**
- Position: **0, 0** (origin, primary)

### Secondary A: HP U28 4K HDR (DP-2) — **portrait**
- Connector: **DP-2**
- Make/model: `HP Inc.` / `HP U28 4K HDR`
- Native: **3840x2160 @ 60 Hz**
- Physical: 620x340 mm, physically rotated so chassis top faces the Dell (→ right)
- Transform: **`"90"`** (verified live: `270` was upside-down, `90` renders correctly — wibar at the top)
- Logical size after rotation: **2160×3840**
- Position: **-2160, 0** (left of Dell so Dell stays primary at origin)

### Secondary B: Samsung TV — *optional, currently disconnected*
- Make match: `Samsung`
- Landscape, goes to the **right** of Dell: **position 3840, 0**

## Variants (auto-detected by output.name/make/model)

Both profiles live in the same `output.connect_signal("added", …)` handler — no explicit switch needed; whichever output is connected takes its branch.

| Variant | Left | Primary | Right | Notes |
|---------|------|---------|-------|-------|
| HP portrait + Dell | HP (-2160,0) portrait, transform 90 | Dell (0,0) landscape 4K@144 | — | code editing / docs |
| Samsung TV + Dell | — | Dell (0,0) landscape 4K@144 | Samsung (3840,0) landscape | media / movies |

## Scope of this branch

1. **rc.lua monitor-profile block** — extend the existing `output.connect_signal("added", …)` in `plans/project/somewm-one/rc.lua` to cover both HP (portrait) and Samsung (landscape right), while keeping the Dell Mode-144Hz block intact.
2. **Wallpaper support for portrait outputs** — verify `awful.wallpaper` / theme wallpaper assignment respects output transform & logical dimensions (2160×3840 on HP). Current wallpaper code (see feedback memory `feedback_wallpaper_apply.md`) creates a new `awful.wallpaper` each time; we need to make sure its `screen.geometry` reflects the post-transform rect and that the image is scaled/cropped correctly (portrait image or cropped landscape — to be decided per theme).
3. **Live-test both profiles** — unplug/plug HP and Samsung, verify signal fires, both monitor configs apply cleanly, no flicker / wrong resolution / wrong position.
4. **Deploy script** — `plans/project/somewm-one/deploy.sh` already handles rc.lua; should work unchanged once rc.lua is updated.

## Non-goals (deferred)

- Automatic wallpaper rotation (landscape image on portrait output via crop vs letterbox). Start with "user picks a portrait-friendly wallpaper per output."
- Dynamic profile switching via hotkey (user already gets auto-switch by virtue of which physical monitor is plugged in — good enough for v1).
- Per-output tags / layouts (current AwesomeWM default per-screen tags already works).

## Open questions

- Wallpaper pipeline: does `fishlive.config.screen` currently detect portrait and pick a different image, or stretch landscape? Need to read the code before deciding approach.
- Does `output.position` signal emit fire before or after `screen::geometry` is recomputed? Wallpaper re-apply needs correct ordering.

## Test checklist (to run after rc.lua changes)

- [ ] Restart somewm cleanly with HP + Dell plugged; verify HP at -2160,0 transform 90, Dell at 0,0.
- [ ] Wallpaper renders on HP in portrait aspect (no stretched landscape, no black bars left/right).
- [ ] Wibar sits at top of HP (portrait top, physical right edge).
- [ ] Move a client from Dell → HP via keybinding / drag; geometry adapts to portrait rect, no off-screen clipping.
- [ ] Unplug HP, plug Samsung TV; Samsung lands at 3840,0, wallpaper applies landscape.
- [ ] Replug HP while Samsung is still connected (3-monitor case): HP lands at -2160,0 without colliding with Samsung.
