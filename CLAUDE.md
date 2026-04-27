# somewm - Claude Code Project Guide

## Project Overview

**somewm** is a Wayland compositor porting AwesomeWM to Wayland, built on wlroots 0.19.
It combines dwl/tinywl compositor patterns with the full AwesomeWM Lua API.

- **Language:** C (GNU11) + Lua (5.1/LuaJIT compatible)
- **Build:** Meson + Makefile wrapper
- **License:** MIT (compositor), GPL (AwesomeWM Lua code)
- **wlroots:** 0.19 (bundled in `subprojects/wlroots/`)
- **XWayland:** Optional, compile with `-Dxwayland=true`

## Hardware Context

**Primary dev/test machine:** NVIDIA RTX 5070 Ti (proprietary driver, nvidia-drm).
The upstream author does NOT use NVIDIA, so NVIDIA-specific bugs are our responsibility.
Sway officially refuses to support proprietary NVIDIA drivers but the code still works.

## User & Environment

- **User:** Antonin Fischer (raven2cz)
- **OS:** Arch Linux
- **Session:** somewm launched from TTY (NOT from display manager - DM launch is broken, separate issue)
- **Launch command:** `dbus-run-session somewm 2>&1 | tee /tmp/somewm.log`
- **Debug launch:** `dbus-run-session somewm -d 2>&1 | tee ~/.local/log/somewm-debug.log`
- **Config:** `~/.config/somewm/rc.lua`
- **Terminal:** alacritty
- **Modkey:** Mod4 (Super)

## GitHub Repository & Workflow

- **Upstream:** `trip-zip/somewm`
- **Our fork:** `raven2cz/somewm`
- **GitHub CLI:** `gh` is installed and authenticated as `raven2cz`
- **Git remotes:**
  - `origin` → `git@github.com:raven2cz/somewm.git` (our fork, push here)
  - `upstream` → `git@github.com:trip-zip/somewm.git` (upstream, read-only for us)

### Branch & Commit Workflow
```bash
# Create feature branch from main
git checkout main && git checkout -b fix/description-here

# Make changes, commit with conventional commits
git add <files> && git commit -m "fix: description"

# Push to our fork
git push -u fork fix/description-here

# View on GitHub
gh repo view raven2cz/somewm --web
```

### Commit message format
```
type: short description

Longer explanation of the change.
Fixes #NNN if applicable.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```
Types: `fix:`, `feat:`, `test:`, `refactor:`, `docs:`

### Relevant upstream issues
- **#137** - Steam games lose keyboard focus on launch (FIXED in our fork)
- **#135** - Keyboard focus desyncs from visual focus (FIXED in our fork)
- **#133** - Minecraft stuck (likely same root cause, FIXED in our fork)
- **#64** - Sloppy focus doesn't update Wayland keyboard focus (CLOSED upstream)
- **#109** - Client focus bugs (CLOSED upstream)

## Build Commands

```bash
make              # ASAN build (development, catches memory bugs)
make build-test   # Fast build without sanitizers
make install      # Install to /usr/local (needs sudo)
make clean        # Remove build artifacts
make test         # All tests (unit + integration)
make test-unit    # Lua unit tests only (busted)
make test-integration  # Visual integration tests
make test-asan    # Integration tests with ASAN
make test-fast    # Persistent compositor mode (10x faster)
make test-one TEST=tests/test_foo.sh  # Single test
make test-visual  # Watch tests in window
ninja -C build    # Direct meson build (faster iteration)
```

## Development & Testing Workflow

### Agent bootstrap

For AI-assisted sessions in this checkout, read this file first. It contains the
fork-specific workflow, deploy/reload commands, nested compositor sandbox, and
memory diagnostics.

`AGENTS.md` is the equivalent bootstrap hint for Codex-style agents; keep both
files aligned when workflow-critical commands change.

### Quick iteration cycle (no reboot)
```bash
# 1. Edit code
# 2. Build + install with SceneFX (handles ldconfig for libscenefx)
~/git/github/somewm/plans/scripts/install-scenefx.sh
# 3. Hot-swap running session via IPC
somewm-client exec somewm
```
**WARNING:** `somewm-client exec somewm` replaces the running compositor process.
If under Wayland, this may launch a nested instance instead. For DRM session
changes, a full reboot is required.

**IMPORTANT:** Always use `install-scenefx.sh` instead of `sudo make install`.
The script builds with `-Dscenefx=enabled` into `build-fx/`, runs ldconfig for
`libscenefx-0.4.so`, and installs to `/usr/local`. Plain `make install` uses the
ASAN dev build without SceneFX.

### Full test cycle (reboot required for DRM changes)
```bash
# Build + install with SceneFX + reboot
~/git/github/somewm/plans/scripts/install-scenefx.sh && sudo reboot

# After reboot, launch from TTY (script at plans/scripts/start.sh)
~/git/github/somewm/plans/scripts/start.sh
```

### Nested compositor sandbox (no reboot, limited fidelity)

Use this when you need to run `somewm` inside the current Wayland session. It is
the right workflow for quick MPV/client geometry checks, Lua IPC checks, and
memory diagnostics without replacing the real session.

```bash
~/git/github/somewm/plans/scripts/somewm-sandbox.sh
```

The script prints the two values needed for follow-up commands:
- `SOMEWM_SOCKET` - IPC socket for `somewm-client`
- `WAYLAND_DISPLAY` - Wayland display for client apps inside the nested session

Launch a client directly inside the nested compositor:
```bash
~/git/github/somewm/plans/scripts/somewm-sandbox.sh -- mpv --no-terminal /path/to/video.mp4
```

Or launch manually after the script prints the environment:
```bash
SOMEWM_SOCKET=/run/user/1000/somewm-sandbox-12345.sock somewm-client eval 'return #client.get()'
WAYLAND_DISPLAY=wayland-1 mpv --no-terminal /path/to/video.mp4 &
```

For isolated upstream-style config instead of the live user config:
```bash
~/git/github/somewm/plans/scripts/somewm-sandbox.sh --test-config
```

**CRITICAL: Two different sockets exist — do NOT confuse them:**
1. **IPC socket** (`SOMEWM_SOCKET=...somewm-sandbox-*.sock`) — for `somewm-client` commands
2. **Wayland display socket** (`WAYLAND_DISPLAY=wayland-N`) — for client apps, auto-created by wlroots

Manual equivalent, if the helper script is not available:
```bash
SOCKET="$XDG_RUNTIME_DIR/somewm-sandbox-$$.sock"
WLR_BACKENDS=wayland \
SOMEWM_SOCKET="$SOCKET" \
~/git/github/somewm/build-fx/somewm -d 2>/tmp/somewm-nested-debug.log &
sleep 3
DISPLAY_NAME=$(SOMEWM_SOCKET="$SOCKET" somewm-client eval 'return os.getenv("WAYLAND_DISPLAY")')
WAYLAND_DISPLAY="$DISPLAY_NAME" mpv --no-terminal /path/to/video.mp4 &
SOMEWM_SOCKET="$SOCKET" somewm-client eval 'return #client.get()'
```

- XWayland display: `somewm-client eval 'return os.getenv("DISPLAY")'` (will be different from parent, e.g. `:4`)
- **Limitation:** Uses wayland backend, not DRM - won't reproduce NVIDIA timing/DRM bugs

### IPC debugging (from another terminal while somewm runs)
```bash
somewm-client ping                                    # test connection
somewm-client eval 'return awesome.version'           # eval Lua, return result
somewm-client eval 'return client.focus and client.focus.name or "none"'
somewm-client eval 'for _,c in ipairs(client.get()) do print(c.name, c.class) end'
somewm-client eval 'return os.getenv("DISPLAY")'      # XWayland display number
somewm-client exec somewm                              # hot-swap binary (CAREFUL!)
somewm-client restart                                  # restart with same binary
```
**IPC syntax:** Single-line Lua only. Multi-line fails. Use `;` to chain statements.

### Memory diagnostics

somewm has explicit memory diagnostics for early leak tracking. Use these before
assuming RSS growth is a compositor leak: wallpaper/tag-slide cache, NVIDIA,
SceneFX, Cairo/Pango/font caches, and allocator high-water retention are all
expected to keep memory resident.

**Live one-shot snapshot:**
```bash
~/git/github/somewm/plans/scripts/somewm-memory-snapshot.sh
~/git/github/somewm/plans/scripts/somewm-memory-snapshot.sh --tsv
```

The snapshot combines `/proc`, `smaps_rollup`, `pmap`, and `somewm.memory.stats(true)`.
Key fields:
- `rss_kb`, `pss_kb`, `private_dirty_kb`, `anonymous_kb` — host process memory
- `drawable_shm_kb` / `drawable_shm_count` — live `memfd:drawable-shm` maps
- `lua_bytes` — Lua heap after forced double GC
- `wallpaper_estimated_bytes` — C-side wallpaper cache estimate
- `drawable_surface_bytes`, `wibox_surface_bytes` — somewm-owned Cairo surfaces
- `malloc_used_bytes`, `malloc_free_bytes`, `malloc_releasable_bytes` — glibc allocator view

**Live trend/stress runner:**
```bash
# Idle stability sample
~/git/github/somewm/plans/scripts/somewm-memory-trend.sh --idle 60

# Tag-switch workload against the current session
~/git/github/somewm/plans/scripts/somewm-memory-trend.sh --tag-switch 500

# Reload leak check
~/git/github/somewm/plans/scripts/somewm-memory-trend.sh --reload 5

# Combined smoke test
~/git/github/somewm/plans/scripts/somewm-memory-trend.sh --all
```

Results are written under `tests/bench/results/memory/YYYYMMDD-HHMMSS/` with
`samples.tsv` and `summary.txt`. Treat monotonic growth as suspicious only when
it remains after `somewm.memory.stats(true)` GC and is not explained by
`wallpaper_estimated_bytes` or `drawable_shm_kb`.

**Lua-side stats API:**
```bash
somewm-client eval 'local s=somewm.memory.stats(true); return s.lua_bytes'
somewm-client eval 'local s=somewm.memory.wallpaper_cache(); return s.entries.." entries "..s.estimated_bytes.." bytes"'
somewm-client eval 'local s=somewm.memory.drawables(); return s.surface_bytes'
```

`somewm.memory.stats(true)` forces two Lua GC passes before reporting. The API
is read-only and intentionally coarse; it tracks somewm-owned buffers, not all
driver or wlroots internals. The same surface is reachable via
`require("somewm").memory.stats(true)` for callers using Lua module imports.

**Tests:**
```bash
# Upstream-friendly compositor API coverage
make test-one TEST=tests/test-memory-stats.lua

# Fork-local CLI/script smoke test, no live compositor required
~/git/github/somewm/plans/tests/test-memory-diagnostics.sh
```

**Upstream note:** The `somewm.memory.*` introspection is potentially
upstreamable as debug tooling. Per issue #508 review (JimmyCozza), the API
lives under `somewm.*` rather than `root.*` — `root.*` mirrors AwesomeWM's
compatible surface, while observation helpers belong with the somewm-specific
extensions that 2.x cleanup is consolidating. The live scripts in
`plans/scripts/` are fork workflow tooling and may need to stay fork-only
unless upstream asks for them.

### Log analysis
```bash
# Live tail of debug log
tail -f ~/.local/log/somewm-debug.log

# Filter focus events
grep -E '\[FOCUS|MAPNOTIFY' ~/.local/log/somewm-debug.log | tail -50

# Filter by client name
grep 'Dispatch\|mpv\|steam' ~/.local/log/somewm-debug.log | tail -50
```

### Debug logging markers (currently in code)
- `[SOMEWM-DEBUG]` - startup marker (WLR_ERROR level, always visible)
- `[FOCUS]` - focusclient() in somewm.c
- `[FOCUS-API]` - some_set_seat_keyboard_focus() in somewm_api.c
- `[FOCUS-ACTIVATE]` - client_activate_surface() in client.h
- `[FOCUS-ENTER]` - client_notify_enter() in client.h
- `[MAPNOTIFY-FOCUS]` - mapnotify() re-delivery in somewm.c

### Important: `-d` flag for debug logging
`globalconf.log_level` overrides `WLR_LOG` env var. Default is 1 (ERROR).
The `-d` flag sets it to 3 (DEBUG). Without `-d`, debug logs don't appear
even with `WLR_LOG=debug`.

## Debugging & Diagnostics

### Environment Variables
```bash
WLR_DEBUG=1 somewm                    # (less useful, -d flag is better)
WAYLAND_DEBUG=1 somewm                # Protocol-level traces (very verbose)
WLR_RENDERER=vulkan somewm            # Force Vulkan renderer (NVIDIA)
WLR_RENDERER=gles2 somewm             # Force GLES2 renderer
WLR_NO_HARDWARE_CURSORS=1 somewm      # Software cursor (NVIDIA fix)
WLR_DRM_NO_ATOMIC=1 somewm            # Force legacy DRM (NVIDIA fix)
XCURSOR_THEME=Adwaita XCURSOR_SIZE=24 # Cursor theme
```

### ASAN (Address Sanitizer)
Default `make` build includes ASAN. Crashes produce stack traces.
`ASAN_OPTIONS=detect_leaks=0` suppresses leak reports during development.

## Key Architecture

### Scene Graph Layers (bottom to top)
```
LyrBg       - Wallpaper
LyrBottom   - Below-normal surfaces
LyrTile     - Tiled windows
LyrFloat    - Floating windows
LyrWibox    - Panels/wibox (Lua widgets)
LyrTop      - Above-normal surfaces
LyrFS       - Fullscreen windows
LyrOverlay  - Overlays
LyrBlock    - Session lock
```

### Client Types
```c
enum { XDGShell, LayerShell, X11 };  // client_type field
```

### Client Lifecycle
1. `createnotify()` / `xwaylandready()` - surface created, listeners attached
2. `mapnotify()` - surface mapped, `request::manage` Lua signal, focus delivery
3. `focusclient()` - keyboard/pointer focus + Lua signals
4. `unmapnotify()` - surface unmapped, `request::unmanage`
5. `destroynotify()` - surface destroyed, cleanup

### Focus Flow (two paths - CRITICAL)
```
PATH 1 - C direct (focusclient in somewm.c:~2302):
  Used by: keybindings (Super+K), pointer clicks, mapnotify
  Does: stack update, border color, activate surface, keyboard enter,
        pointer constraint, Lua signals, foreign toplevel handle

PATH 2 - Lua API (some_set_seat_keyboard_focus in somewm_api.c:~421):
  Used by: client.focus = c (Lua setter), awful.client.focus.*
  Does: activate surface, keyboard enter, pointer constraint
  NOTE: ALL game focus goes through this path, NEVER through focusclient()
```

**wlroots same-surface skip (types/seat/wlr_seat_keyboard.c:237):**
```c
if (seat->keyboard_state.focused_surface == surface) {
    return;  // silently drops re-delivery!
}
```
Workaround: clear focus first, then re-enter (KWin MR !60 pattern).

### Known NVIDIA issues
- Surface may not be `mapped` when focus is set (race with NVIDIA DRM)
- XWayland surfaces need `wlr_xwayland_set_seat()` on EVERY focus change
- Keyboard enter must be sent even when `wlr_seat_get_keyboard()` returns NULL
- Games need keyboard re-delivery after initialization (timer workaround)
- Software cursor fallback is common (`Falling back to software cursor`)
- DRM format issues (ARGB8888 vs XRGB8888)

## Directory Structure

```
somewm.c              # Main compositor (5800+ lines) - event loop, focus, input, output
somewm_api.c          # Lua API bridge (C->Lua, Lua->C)
somewm_api.h          # API declarations
somewm_types.h        # Core types: Monitor, LayerSurface, scene layers
client.h              # XWayland/XDG client abstraction (inline helpers)
globalconf.h          # Global config struct (awesome_t)
objects/
  client.c/.h         # Client Lua object (client_t struct, ~5000 lines)
  tag.c/.h            # Tag/workspace management
  screen.c/.h         # Screen/monitor Lua object
  drawin.c/.h         # Drawable window (panels, popups)
  drawable.c/.h       # Cairo surface management
  wibox.c/.h          # Widget box (Lua wibox)
  key.c/.h            # Key binding objects
  button.c/.h         # Mouse button objects
  layer_surface.c/.h  # Layer shell (panels, lock screens)
  signal.c/.h         # Signal system
lua/
  awful/              # AwesomeWM API (client, tag, layout, screen, mouse, spawn)
  beautiful/          # Theme system
  gears/             # Utility library (object, color, geometry, shape, timer)
  wibox/             # Widget system
  naughty/           # Notification system
  ruled/             # Rules engine
common/              # C utilities (luaclass, luaobject, array, buffer)
tests/               # Integration tests (shell scripts)
spec/                # Unit tests (Lua busted)
plans/               # Development plans and issue tracking
```

## User Configuration

Config at `~/.config/somewm/rc.lua` - standard AwesomeWM rc.lua format.
Themes at `~/.config/somewm/themes/`.

Current rc.lua includes:
- Focus follows mouse (`mouse::enter` signal)
- Anti-focus-stealing for games (blocks Steam from stealing focus from `steam_app_*`)
- Timer-based focus re-delivery for game windows (60s, 2s interval)
- `steam_app_*` client rule (no titlebar, focusable)

## somewm-one (User Config Project)

Our rc.lua + themes + plugins are versioned in `plans/project/somewm-one/`.
This is the "release" copy — edit here, deploy to `~/.config/somewm`.

```bash
# Edit config
vim plans/project/somewm-one/rc.lua

# Deploy to active config (backs up rc.lua.bak first)
plans/project/somewm-one/deploy.sh

# Dry run (show what would be synced)
plans/project/somewm-one/deploy.sh --dry-run

# Reload after deploy (from running somewm session)
somewm-client reload
```

Contents:
- `rc.lua` — main config (837 lines, AwesomeWM format)
- `themes/default/` — theme with icons, backgrounds, layout PNGs
- `layout-machi/` — layout-machi plugin (tiling layout engine)
- `deploy.sh` — rsync to `~/.config/somewm` (excludes itself)

**Rule:** Always edit `plans/project/somewm-one/rc.lua`, never `~/.config/somewm/rc.lua` directly.
After editing, run `deploy.sh` to sync.

## Plans Directory

`plans/` contains development plans, issue tracking, and fix documentation.
- `plans/upstream/` - Upstream sync records and fork status
- `plans/project/somewm-one/` - User config project (rc.lua, themes, deploy script)
- `plans/project/somewm-shell/` - Quickshell desktop shell (QML/Qt6)
- `plans/project/somewm-shell-ai/` - AI-assisted shell modules
- `plans/done/` - Archived completed plans and investigations
- `plans/scripts/install-scenefx.sh` - Build + install with SceneFX + ldconfig (USE THIS, not `make install`)
- `plans/scripts/start.sh` - Launch somewm with debug logging from TTY
- `plans/scripts/somewm-sandbox.sh` - Launch nested/headless somewm sandbox for client and IPC debugging
- `plans/scripts/somewm-memory-snapshot.sh` - One-shot live memory snapshot
- `plans/scripts/somewm-memory-trend.sh` - Live memory trend/stress runner
- `plans/scripts/somewm-debug-wrapper.sh` - Debug session wrapper with timestamped logs

## Reference Projects

- **Sway:** `/home/box/git/github/sway` - production Wayland compositor, wlroots reference
  - Focus: `sway/input/seat.c` (seat_keyboard_notify_enter, seat_send_focus)
  - Output: `sway/desktop/output.c` (begin_destroy)
  - XWayland: `sway/desktop/xwayland.c`
  - NVIDIA: `sway/server.c:164` (nvidia-drm detection)
- **wlroots:** `subprojects/wlroots/` - compositor library, bundled
  - Seat/keyboard: `types/seat/wlr_seat_keyboard.c` (the same-surface skip at line 237!)
  - Output: `types/output/output.c` (wlr_output_finish assertions)
  - Scene: `types/scene/` (scene graph rendering)

## NVIDIA-Specific Workarounds Checklist

When debugging NVIDIA issues, check:
1. `WLR_RENDERER=vulkan` vs `gles2` vs auto
2. `WLR_NO_HARDWARE_CURSORS=1`
3. `WLR_DRM_NO_ATOMIC=1`
4. `__NV_PRIME_RENDER_OFFLOAD=1` for hybrid GPU
5. DRM format negotiation (ARGB8888 vs XRGB8888)
6. Timeline semaphore support (`drw->features.timeline`)
7. GPU reset handling (`gpureset` listener in somewm.c)
8. Buffer allocation (GBM vs Vulkan allocator)

## Code Style

- C: GNU11, tabs for indentation, 80-col soft limit
- Lua: tabs, stylua configured in `.stylua.toml`
- Commit messages: `type: description` (fix:, feat:, test:, refactor:)
- AwesomeWM patterns preserved where possible (signal system, object model)

## External AI Code Review Tools

For cross-model code review, these CLI tools are available:

```bash
# OpenAI Codex CLI (gpt-5.4 model)
cat diff.patch | codex exec -m gpt-5.4 --full-auto "Review prompt here"

# Google Gemini CLI (gemini-3.1-pro-preview model)
cat diff.patch | gemini -m gemini-3.1-pro-preview -p "Review prompt here"

# Claude Sonnet (via Agent tool with model=sonnet)
# No CLI needed — use Agent tool directly
```

**IMPORTANT:** Do NOT guess CLI flags — these are the correct invocations:
- `codex exec` (not `codex --quiet`), with `-m model --full-auto`
- `gemini -m model -p "prompt"` (not `gemini-cli`, binary is `gemini`)
- Pipe diff to stdin, review prompt as the command argument

## Completed Fixes (in our fork raven2cz/somewm)

### Branch: fix/xwayland-keyboard-focus
1. `fd6ec3d` - XWayland keyboard focus delivery in Lua focus path
2. `d203de4` - XWayland focusable detection via ICCCM input model
3. `aea9cc4` - awesome.exec() Lua state use-after-free
