# somewm - Claude Code Project Guide

## Project Overview

**somewm** is a Wayland compositor porting AwesomeWM to Wayland. Since 2.1 every
bar, popup, client and widget is declared in one Clay layout tree per output,
which somewm solves and reconciles into the wlroots scene graph.

- **Language:** C (GNU11) + Lua (5.1/LuaJIT compatible)
- **Build:** Meson + Makefile wrapper
- **License:** MIT (compositor), GPL (AwesomeWM Lua code)
- **wlroots:** 0.20.2, always built from `subprojects/wlroots.wrap` with
  `subprojects/packagefiles/wlroots-corners.diff` (rounded corners, GLES2 and
  pixman renderers only; no Vulkan renderer is built) and linked in
- **XWayland:** always on (the `-Dxwayland` option is gone)
- **No SceneFX.** Upstream refuses it as a dependency (#387, closed
  2026-10-13). Corners come from `client.shape`, shadows are upstream's
  nine-patch; there is no backdrop blur.

## Fork lines (read this first)

| line | branch / tag | base | status |
|---|---|---|---|
| **v2** (current) | `main` | upstream 2.1 + a thin fork delta | active |
| v1 (legacy) | `legacy/v1`, tag `v1-legacy` | upstream Aug 2026 + 230 fork commits, wlroots 0.19 + SceneFX | frozen 2026-10-24, kept buildable |

The v2 line was started on 2026-10-24 because upstream 2.0/2.1 rewrote ~720
files; the fat v1 fork could no longer be synced. Rule for v2: **keep the
fork thin.** Prefer upstream features; port a v1 fix only after it reproduces
on 2.1; every fork commit should be upstreamable on its own. The decision
record, fork-delta table and the NVIDIA test plan live in `plans/v2/`;
**start with `plans/v2/HANDOFF.md`** (complete state of the v2 work).

## Hardware Context

**Primary dev/test machine:** NVIDIA RTX 5070 Ti (proprietary driver, nvidia-drm).
The upstream author does NOT use NVIDIA, so NVIDIA-specific bugs are our responsibility.
Sway officially refuses to support proprietary NVIDIA drivers but the code still works.

**Secondary machine `boxszn`:** AMD Phoenix iGPU, KDE Plasma Wayland session, no
NVIDIA, no passwordless sudo. Only the nested/headless sandbox is possible there;
DRM and NVIDIA validation happens on the primary machine
(`plans/v2/nvidia-test-plan.md`).

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
```
Types: `fix:`, `feat:`, `test:`, `refactor:`, `docs:`

**No `Co-Authored-By: Claude` trailer.** Commits in this fork (and especially
those destined for upstream PRs to `trip-zip/somewm`) are authored by the human
maintainer. Do not add Claude as co-author. Same applies to PR/issue bodies:
no "Generated with Claude Code" footer, no AI tool mentions.

### Upstream contribution policy

Upstream (`AGENTS.md`, `AI_POLICY.md`, `CONTRIBUTING.md`) accepts issues only
written by a person, and PRs only for issues the maintainer already agreed to;
AI use must be disclosed. Agents must **never** open issues/PRs or comment
upstream. Prepare a fix on a branch and a short note for the maintainer
(human) to submit. Upstream-candidate fork commits are listed in
`plans/v2/README.md`.

## Build Commands

```bash
make              # Optimized release build into build/ (no sanitizers, default)
make asan         # ASAN+UBSan build into build-asan/ (development, catches memory bugs)
make build-test   # Fast build without sanitizers into build-test/
make install      # Install build/ to /usr/local (needs sudo)
make clean        # Remove build, build-asan, build-test
make test         # All tests (unit + integration)
make test-unit    # Lua unit tests only (busted)
make test-integration  # Visual integration tests
make test-asan    # Integration tests with ASAN (uses build-asan/)
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

For full workstation setup or "update all three projects" requests, see
[INSTALL.md](INSTALL.md). It documents prerequisites, clone order, build +
deploy commands, and the update workflow across `somewm` + `somewm-one` +
`somewm-shell` together — i.e. the recipe to follow when moving to a fresh
workstation or doing a clean reinstall.

### Quick iteration cycle
```bash
# 1. Edit code
# 2. Build + install (release build/, wipes the installed Lua tree first,
#    removes v1 SceneFX leftovers from /usr/local)
~/git/github/somewm/plans/scripts/install.sh
# 3. Lua-only change: hot reload in place
somewm-client reload
# 4. C change: restart the session from the TTY (see below)
```
`plans/scripts/install.sh --check` verifies the install (links, no libscenefx).
`plans/scripts/v2-stack-sandbox.sh [--headless] [--shell]` runs this checkout
+ somewm-one (+ somewm-shell) isolated from the live session and /usr/local.
`somewm-client exec <cmd>` **spawns a shell command** (awful.spawn.with_shell);
it does not replace the compositor.

### Full test cycle (reboot required for DRM changes)
```bash
~/git/github/somewm/plans/scripts/install.sh && sudo reboot
# After reboot, launch from TTY
~/git/github/somewm/plans/scripts/start.sh
```

### Going back to v1
```bash
git checkout legacy/v1   # in all three repos (somewm, somewm-one, somewm-shell)
# v1 used the SceneFX installer of that line:
plans/scripts/install-scenefx.sh   # exists on legacy/v1 only
```

### Wine / X11 debugging

Wine talks X11, so it needs the DISPLAY of the *nested* Xwayland. `wine-sandbox.sh`
resolves it and refuses to run against the live session:

```bash
plans/scripts/wine-sandbox.sh start          # nested compositor, backgrounded
plans/scripts/wine-sandbox.sh wine -- notepad
plans/scripts/wine-sandbox.sh census --probe # X11 tree vs somewm's client list
plans/scripts/wine-sandbox.sh click 83 44    # real click through zwlr_virtual_pointer
plans/scripts/wine-sandbox.sh stop
```

Use `click`/`move` rather than xdotool: xdotool goes through XTEST inside Xwayland
and bypasses the compositor's input path entirely, which proves nothing about
compositor bugs.

X11 override-redirect surfaces (Wine menus, tooltips) are not clients and never
appear in `client.get()`; inspect them with `root.xwayland_unmanaged()`.

### Nested compositor sandbox (no reboot, limited fidelity)

Use this when you need to run `somewm` inside the current Wayland session. It is
the right workflow for quick MPV/client geometry checks, Lua IPC checks, and
memory diagnostics without replacing the real session.

**Nested vs headless.** With `WLR_BACKENDS=wayland` the nested output only
renders when the parent compositor sends frame callbacks. Under KDE a hidden or
occluded nested window gets none, so QML/Clay animations freeze half-way and
`grim` hangs. For anything time-based (animations, Quickshell panels) use
`--headless` (own frame timer, pixman renderer); `somewm-client screenshot save
<path>` works with either backend.

**Isolating somewm-one/somewm-shell.** `SOMEWM_SANDBOX_CONFIG_HOME=<dir>` points
the sandbox at a config copy (`<dir>/somewm/rc.lua`). In that config,
`SOMEWM_NO_AUTOSTART=1` skips the session daemons (kded6, nm-applet, polkit) and
`SOMEWM_NO_SHELL=1` keeps rc.lua from (re)launching Quickshell. somewm-shell
hardcodes `$HOME/.config/...`, so a shell test needs a throwaway `HOME` whose
`.config` is that directory.

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
~/git/github/somewm/build/somewm -d 2>/tmp/somewm-nested-debug.log &
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
**IPC globals:** `eval` runs with the C globals only (`client`, `screen`, `tag`,
`root`, `awesome`, `mouse`). `awful`, `gears`, `beautiful`, `naughty` are *not*
globals (rc.lua makes them locals): write `require("awful").spawn(...)`.

### Memory diagnostics

> **v2 note:** `root.memory_stats()`, `root.wallpaper_cache_stats()` and
> `root.drawable_stats()` were v1 fork APIs and do not exist on v2 (under Clay
> drawables hold no cairo/shm surface and the wallpaper cache is gone). The
> snapshot script falls back to Lua heap + client count; a v2 rewrite is a
> follow-up in `plans/v2/README.md`. The text below describes v1.

somewm has explicit memory diagnostics for early leak tracking. Use these before
assuming RSS growth is a compositor leak: wallpaper/tag-slide cache, NVIDIA,
SceneFX, Cairo/Pango/font caches, and allocator high-water retention are all
expected to keep memory resident.

**Live one-shot snapshot:**
```bash
~/git/github/somewm/plans/scripts/somewm-memory-snapshot.sh
~/git/github/somewm/plans/scripts/somewm-memory-snapshot.sh --tsv
```

The snapshot combines `/proc`, `smaps_rollup`, `pmap`, and `root.memory_stats(true)`.
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
it remains after `root.memory_stats(true)` GC and is not explained by
`wallpaper_estimated_bytes` or `drawable_shm_kb`.

**Lua-side stats API:**
```bash
somewm-client eval 'local s=root.memory_stats(true); return s.lua_bytes'
somewm-client eval 'local s=root.wallpaper_cache_stats(); return s.entries.." entries "..s.estimated_bytes.." bytes"'
somewm-client eval 'local s=root.drawable_stats(); return s.surface_bytes'
```

`root.memory_stats(true)` forces two Lua GC passes before reporting. The API is
read-only and intentionally coarse; it tracks somewm-owned buffers, not all
driver or wlroots internals.

**Tests:**
```bash
# Upstream-friendly compositor API coverage
make test-one TEST=tests/test-memory-stats.lua

# Fork-local CLI/script smoke test, no live compositor required
~/git/github/somewm/plans/tests/test-memory-diagnostics.sh
```

**Upstream note:** The `root.memory_stats()`/`root.wallpaper_cache_stats()`
introspection is potentially upstreamable as debug tooling. The live scripts in
`plans/scripts/` are fork workflow tooling and may need to stay fork-only unless
upstream asks for them.

### Log analysis
```bash
# Live tail of debug log
tail -f ~/.local/log/somewm-debug.log

# Filter focus events
grep -E '\[FOCUS|MAPNOTIFY' ~/.local/log/somewm-debug.log | tail -50

# Filter by client name
grep 'Dispatch\|mpv\|steam' ~/.local/log/somewm-debug.log | tail -50
```

### Debug logging markers
The v1 `[FOCUS*]`/`[SOMEWM-DEBUG]` markers are gone on v2. `[HOTPLUG]` remains
(monitor.c, window.c). For the render side use `somewm-client clay tree
[screen]` (what the last frame solved) and `screen.inspector`
(`somewm.inspector.toggle(s)`).

### Important: `-d` flag for debug logging
`globalconf.log_level` overrides `WLR_LOG` env var. Default is 1 (ERROR).
The `-d` flag sets it to 3 (DEBUG). Without `-d`, debug logs don't appear
even with `WLR_LOG=debug`.

## Debugging & Diagnostics

### Environment Variables
```bash
WLR_DEBUG=1 somewm                    # (less useful, -d flag is better)
WAYLAND_DEBUG=1 somewm                # Protocol-level traces (very verbose)
WLR_RENDERER=gles2 somewm             # GLES2 (the only GPU renderer built on v2)
WLR_RENDERER=pixman somewm            # software renderer
WLR_NO_HARDWARE_CURSORS=1 somewm      # Software cursor (NVIDIA fix)
WLR_DRM_NO_ATOMIC=1 somewm            # Force legacy DRM (NVIDIA fix)
XCURSOR_THEME=Adwaita XCURSOR_SIZE=24 # Cursor theme
```

### ASAN (Address Sanitizer)
`make asan` builds with ASAN+UBSan into `build-asan/` (default `make` is now
release, no sanitizers). Crashes produce stack traces.
`ASAN_OPTIONS=detect_leaks=0` suppresses leak reports during development.

## Key Architecture

### Rendering (v2)
Lua declares every bar, popup, client and widget into one Clay tree per output
(`lua/wibox/clay.lua`, `lua/awful/client/clay.lua`); `declare.c` solves it and
`render.c` reconciles Clay's render commands into wlr_scene (rects and borders
as scene rects rounded by the wlroots diff; text, images and paths rasterised
with cairo into buffers). Scene layers are only `LyrDesktop` and `LyrBlock`;
draw order is the Clay zIndex band (`declare.c` `Z_*`: background layer,
desktop clients, bottom, below/normal clients, drawins, above, fullscreen,
ontop, top layer, popups, notifications, overlay layer, unmanaged X11, lock).
Widgets no longer implement `fit`/`draw`; a function `bgimage` is not drawn;
a markup with several fonts is drawn in its first run's font (colours do
survive).

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
PATH 1 - C direct (focusclient in focus.c:41):
  Used by: keybindings (Super+K), pointer clicks, mapnotify
  Does: stack update, border color, activate surface, keyboard enter,
        pointer constraint, Lua signals, foreign toplevel handle

PATH 2 - Lua API (some_set_seat_keyboard_focus in somewm_api.c:166):
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
- Upstream 2.1 builds wlroots with the GLES2 renderer only; corners are drawn
  by its own diff, not SceneFX. The v1 one-pixel rounded border defect was a
  SceneFX 0.5 problem; whether 2.1's corners are clean on NVIDIA is item #1 of
  the NVIDIA test plan.
- Surface may not be `mapped` when focus is set (race with NVIDIA DRM)
- XWayland surfaces need `wlr_xwayland_set_seat()` on EVERY focus change
- Keyboard enter must be sent even when `wlr_seat_get_keyboard()` returns NULL
- Games need keyboard re-delivery after initialization (timer workaround)
- Software cursor fallback is common (`Falling back to software cursor`)
- DRM format issues (ARGB8888 vs XRGB8888)

## Directory Structure

```
somewm.c              # main(), setup/run/cleanup
declare.c, render.c   # Clay declare/solve per output, scene reconcile
clay_impl.c           # the one TU compiling third_party clay.h
focus.c, input.c, window.c, monitor.c, protocols.c, xwayland.c  # split-out compositor core
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

## Sibling repos (split out of this fork on 2026-04-29)

User config and the Quickshell desktop shell live in standalone public repos:

- **somewm-one** — rc.lua + themes + fishlive modules
  - GitHub: <https://github.com/raven2cz/somewm-one>
  - Local checkout: `~/git/github/somewm-one` (override with `SOMEWM_ONE_PATH`)
  - Workflow: edit there → `./deploy.sh` → `somewm-client reload`
- **somewm-shell** — Quickshell/QML desktop shell
  - GitHub: <https://github.com/raven2cz/somewm-shell>
  - Local checkout: `~/git/github/somewm-shell` (override with `SOMEWM_SHELL_PATH`)
  - Workflow: edit there → `./deploy.sh` → kill+restart `qs -c somewm`

This fork goes back to being a working tree for upstream PRs to
`trip-zip/somewm` and a home for fork-only ops scripts under `plans/scripts/`.

History was preserved via `git subtree split`. Files that lived under
`plans/project/somewm-{one,shell}/` were extracted with their commits;
commit IDs were rewritten so cross-references break (acceptable trade-off).

## Plans Directory

`plans/` contains development plans, issue tracking, and fix documentation.
- `plans/upstream/` - Upstream sync records and fork status
- `plans/done/repo-split/` - 2026-04-29 split-out playbook + paper trail
- `plans/done/` - Archived completed plans and investigations
- `plans/v2/` - v2 decision record, fork-delta table, NVIDIA test plan
- `plans/done/legacy-v1/` - v1-era sync records (kolo9/kolo10, Wine OR rewrite)
- `plans/scripts/install.sh` - Build + install the v2 release tree (USE THIS)
- `plans/scripts/start.sh` - Launch somewm with debug logging from TTY
- `plans/scripts/somewm-sandbox.sh` - Launch nested/headless somewm sandbox for client and IPC debugging
- `plans/scripts/wine-sandbox.sh` - Run Wine apps in a nested sandbox; refuses any subcommand that would resolve to the live session's DISPLAY/socket
- `plans/scripts/x11-census.py` - Compare the X11 window tree with somewm's client list (`--probe`, `--json`)
- `plans/scripts/x11-monitor.py` - Live log of X11 create/map/unmap/configure events
- `plans/scripts/somewm-memory-snapshot.sh` - One-shot live memory snapshot
- `plans/scripts/somewm-memory-trend.sh` - Live memory trend/stress runner
- `plans/scripts/somewm-debug-wrapper.sh` - Debug session wrapper with timestamped logs

## Reference Projects

- **Sway:** `/home/box/git/github/sway` - production Wayland compositor, wlroots reference
  - Focus: `sway/input/seat.c` (seat_keyboard_notify_enter, seat_send_focus)
  - Output: `sway/desktop/output.c` (begin_destroy)
  - XWayland: `sway/desktop/xwayland.c`
  - NVIDIA: `sway/server.c:164` (nvidia-drm detection)
- **wlroots:** `subprojects/wlroots-0.20.2/` (unpacked from the wrap) - compositor library, bundled
  - Seat/keyboard: `types/seat/wlr_seat_keyboard.c` (the same-surface skip at line 237!)
  - Output: `types/output/output.c` (wlr_output_finish assertions)
  - Scene: `types/scene/` (scene graph rendering)

## NVIDIA-Specific Workarounds Checklist

When debugging NVIDIA issues, check:
1. Renderer: v2 has GLES2 (and pixman) only; Vulkan is not built
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
# OpenAI Codex CLI - default model is gpt-5.6-sol (set in ~/.codex/config.toml)
cat diff.patch | codex exec --sandbox workspace-write "Review prompt here"
# Cheaper model for small reviews:
cat diff.patch | codex exec -m gpt-5.5 --sandbox workspace-write "Review prompt here"

# Google Gemini CLI (gemini-3.1-pro-preview model)
cat diff.patch | gemini -m gemini-3.1-pro-preview -p "Review prompt here"

# Claude Sonnet (via Agent tool with model=sonnet)
# No CLI needed — use Agent tool directly
```

**IMPORTANT:** Do NOT guess CLI flags — these are the correct invocations:
- `codex exec` (not `codex --quiet`); omit `-m` to get the default `gpt-5.6-sol`.
  `-m sol` is rejected ("model is not supported"); the full name is required.
  `--full-auto` is deprecated, use `--sandbox workspace-write`
- `gemini -m model -p "prompt"` (not `gemini-cli`, binary is `gemini`)
- Pipe diff to stdin, review prompt as the command argument

## Fork delta on v2

See `plans/v2/README.md` for the full table. In short (all upstream
candidates): XWayland map-before-associate (Sierra Chart dialogs), main()
returns awesome.quit's code, screen::focus on pointer crossing outputs,
focus kept on a client dragged across outputs (+ post-grab pointer rebase),
layer-surface unmap restores focus only for the focus holder.
