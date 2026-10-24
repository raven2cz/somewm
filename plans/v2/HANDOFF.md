# v2 handoff: everything a new session needs

Written 2026-10-24 at the end of the session that created the v2 line, on
`boxszn`, for the Claude session that continues on the **primary NVIDIA
workstation**. Read this file completely, then [README.md](README.md) (the
short decision record), then [nvidia-test-plan.md](nvidia-test-plan.md)
(what to do). [fork-delta-audit.md](fork-delta-audit.md) is the item-by-item
evidence behind the decisions. Speak Czech with the user; code, commits and
docs in English.

## 1. What the user decided (and did not)

| decision | source |
|---|---|
| Freeze the old fork line in all three repos as `legacy/v1` + tag `v1-legacy` | user, 2026-10-24 |
| Rebuild `main` from upstream somewm 2.1; **force-push of main approved** and done the same day | user, explicitly ("Hned dnes") |
| No `-v2` repo suffixes; branches instead | agreed (GitHub allows one fork per upstream per account) |
| SceneFX is not wanted any more | user ("sceneFx uz potrebovat nebudeme") |
| Keep the fork thin: v1 *bug fixes* mostly not ported unless they still reproduce; *features* decided one by one | user |
| **No upstream submissions for now** (no issues, no PRs, no comments upstream) | user, 2026-10-24 ("zadne opravy nebizet ted nebudeme") |
| NVIDIA validation by a Claude session on the primary workstation, from a detailed plan | user |

Open, not decided: blur (none exists on v2), Wine override-redirect port
(after test W1-W5), whether v2 becomes the daily driver (after the test plan),
the Co-Authored-By trailer inconsistency (section 9).

## 2. Why v2 exists (short)

Upstream `trip-zip/somewm` released 2.0.0 (2026-08-28), 2.0.1 (10-10),
2.1.0 (10-18): 115 commits, ~720 files after the v1 fork's last sync base
`c7b3208`. 2.1 renders through **Clay** (a C layout library: one layout tree
per output, solved in `declare.c`, reconciled into wlr_scene in `render.c`;
rects/borders are GPU scene rects rounded by somewm's own
`subprojects/packagefiles/wlroots-corners.diff`, text/images rasterised with
cairo into buffers, client windows are GPU textures as before). It builds
wlroots 0.20.2 from the wrap every time, GLES2 + pixman renderers only (no
Vulkan), XWayland always on, no SceneFX, no wlroots 0.19. The maintainer
closed the fork's SceneFX/animation/tag-slide issues (#387, #381, #393) on
2026-10-13 in favour of his own animation API (#840) and said he will never
take SceneFX as a dependency. Blur exists nowhere upstream.

## 3. Repository state at handoff

Remotes: somewm `origin` = `git@github.com:raven2cz/somewm.git`, `upstream`
= `git@github.com:trip-zip/somewm.git` (added in this session; on the NVIDIA
box add it if missing).

| repo | `legacy/v1` (= tag `v1-legacy`) | `main` = `v2/main` | base of v2 |
|---|---|---|---|
| somewm | `678640f` | `a13f3ae` + this handoff commit | `upstream/main` `6eaa61e` (2.1.0 + 5) |
| somewm-one | `89702b1` | `c3d88c6` | `legacy/v1` |
| somewm-shell | `671e597` | `106e04e` | `legacy/v1` |

On the NVIDIA box the local `main` still points at v1: switch as in
nvidia-test-plan.md phase A (`git branch -f legacy/v1 origin/legacy/v1;
git checkout main; git reset --hard origin/main`), never `git pull`.

### somewm commits on top of upstream/main

| commit | content | status |
|---|---|---|
| `93b1726` chore(fork) | `plans/` carried from v1 (minus SceneFX diagnostics/patches, v1 sync records moved to `plans/done/legacy-v1/`), `install.sh` replaces `install-scenefx.sh`, sandbox/test scripts look in `build/`, AGENTS.md pointer to CLAUDE.md | fork-only |
| `a01a16f` fix(xwayland) | `associatex11()` maps a surface whose buffer was committed before associate (Sierra Chart dialogs that never appeared: in `client.get()`, 0x0, no scene). Skips a *stale* buffer kept from before an X11 unmap (commit seq recorded at dissociate, `c->x11_dissociated_surface/seq`) | sandbox tests pass; **real Wine untested** |
| `f715bff` fix: exit code | `main()` returns `globalconf.exit_code` set by `awesome.quit(code)` (upstream always returned 0) | tested by build only |
| `7d080ee` fix(input) | `screen::focus` queued when the pointer crosses outputs (was only on empty-space clicks) | needs multi-monitor (D9) |
| `77c40de` fix(focus) | no ban-unfocus while a mousegrabber runs (client dragged across outputs kept focus); pointer focus rebased (`motionnotify(0)`) when the grab callback ends it | needs multi-monitor (D8) |
| `19bd7f9` fix(layer-shell) | `focus_restore()` on layer unmap only if that surface held `exclusive_focus` (notifications/QS popups no longer steal focus) | layer-shell tests pass; live D10 |
| `36f88b1` fix(sandbox) | `somewm-sandbox.sh` deleted any caller-provided config home under /tmp on exit; now only its own `--test-config` dir | verified |
| `5cfbb15` docs | CLAUDE.md and INSTALL.md rewritten for v2 | - |
| `e095d6e` feat(root) | `root.memory_stats([gc])`: `lua_bytes`, `clients`, `screens`, `tags`, `drawins`, `wallpaper_bytes`, and on glibc >= 2.33 `malloc_{arena,used,free,releasable}_bytes`; test `tests/test-memory-stats.lua` | test passes |
| `0be4c0b` fix(focus) | when a grab stops: unfocus a focused client that is still banned; run a `focus_restore()` deferred by the layer-shell fix (`globalconf.focus_restore_after_grab`) | tests pass |
| `bf62bd8` docs | plans/v2/README.md; `plans/scripts/border-probe.py` back from v1, radius from `c.shape` | probe 100% on pixman sandbox |
| `a13f3ae` docs | nvidia-test-plan.md | - |
| (this commit) | HANDOFF.md, fork-delta-audit.md, `plans/scripts/v2-stack-sandbox.sh` | - |

### somewm-one commits on top of legacy/v1

| commit | content |
|---|---|
| `ea09ed1` | `anim_client.lua` deleted. New `fishlive/config/animations.lua`: theme keys (appear fade 0.5 s, disappear fade 0.4 s, maximize 0.25, floating 0.3, layout 0.15, focus border ease 0.15, tag 0.25) filled only where the theme has none, re-applied after every theme switch (`fishlive/services/themes.lua`); corners `c.shape = 14` via a rule callback, square for class `^steam_app_`, `^Wine$`, `^Xwayland$`, `%.exe$` and while fullscreen; notification popup `animation = {visible = {0.5 s fade}}`. `rules.lua` drops `corner_radius`/`backdrop_blur`; Super+N is plain minimize; `client_fixes.lua` drops the anim_client check. `layout-machi/paint.lua` paints the switcher/editor draw functions into a surface (2.1 ignores a function `bgimage`). `rc.lua`: `SOMEWM_NO_AUTOSTART=1` skips `autostart.start_all()`, `SOMEWM_NO_SHELL=1` skips the Quickshell (re)launch. spec stub updated |
| `608822d` | menu "Rebuild & Restart" -> "Restart" via `awesome.restart()` when `awesome.rebuild_restart` is missing |
| `50977b9` | `widget_helper.create_runs(n)` (row of single-font textboxes); `create_icon_text`, network, keyboard (margin instead of the leading span) and clock (icon + two textclocks) use it, because 2.1 draws a multi-font markup in its first run's font; themes: `lockscreen_bg_image` -> `lockscreen_wallpaper` |
| `a8abf49` | KDE-like tag slide: in `property::selected`, higher index -> `beautiful.animation_tag = "slide_right"`, lower -> `"slide_left"`; `M.tag_slide = false` disables |
| `a8f4a7f` | emits `tag_slide::start (s, name)` / `tag_slide::end (s)` around the slide (shell collage listens) |
| `c3d88c6` | CLAUDE.md v2 notes |

### somewm-shell commits on top of legacy/v1

| commit | content |
|---|---|
| `bb80b0f` | MemoryDetail falls back to Lua heap + client count (the `somewm.memory.stats` it called exists nowhere); CpuDetail footer buttons pass a shell command to `somewm-client exec` (it is `with_shell`, not Lua) |
| `e0e4008` | MemoryDetail prefers `root.memory_stats`, maps `wallpaper_bytes` |
| `106e04e` | CLAUDE.md v2 notes |

## 4. Fixed / not fixed / dropped (v1 items)

Status per v1 item; numbers are rows in fork-delta-audit.md.

**Ported (in v2):** #2 associate-before-commit, #21 exit code (only the
`main()` part), #28 screen::focus on crossing, #29+#31 drag focus and
post-grab rebase, #32 layer unmap focus, #18 memory stats (rewritten), #41
lock screen image (config key rename; no blur), #12 animations (mapped to
upstream API), #14 tag slide (rebuilt on upstream API, see limits).

**Covered by upstream, nothing to do:** #6 corners, #8 shadows, #10 opacity,
#23 numlock, #24 keyboard settings / ready signals, #25 `_notif_history` /
`_shell_overlay` (plain Lua fields), #33 hotplug pointer, #36 NVIDIA XDG
initialized guard, #38 NVIDIA XWayland focus guards, fullscreen stacking.

**Dropped as obsolete under Clay:** #5 SceneFX build, #9 border plumbing,
#13 animation.c, #15 wallpaper cache (somewm-one calls are guarded no-ops),
#16 gears.wallpaper, #17 awful.wallpaper negative-origin fix (still verify
D2), #19 scene dumps (use `somewm-client clay tree`, `screen.inspector`),
#26/#27 dead v1 code, #39, #40.

**Not ported, needs a decision or a reproduction first:**
- #1 XWayland override-redirect rewrite (Wine menus/submenus, role flips,
  focus hold under sloppy focus). Test W1-W5; minimal port ~150 lines.
- #34 floating transient of a tiled parent below an unrelated floating window
  (Sierra Chart dialogs), test W4.
- #30 deferred pointer-enter retry; #35 mpv aspect excluding titlebar (D16);
  #37 unmap without Lua state; #11 layer-surface opacity (rofi fade);
  #20 bench stamping; #3/#4 X11 debug traces and `root.xwayland_unmanaged`.
- #7 backdrop blur (clients, lock screen): none on v2.
- #22 v1 `somewm-session` restart/rebuild loop: not carried. `main()` now
  returns the quit code, so a loop on `awesome.quit(2)` could be rebuilt
  later. `/usr/local/bin/somewm-session` is upstream's systemd wrapper in
  both lines (v1 meson installed both scripts to that path; the systemd one
  wins); `start.sh` does not use it.

**Known v2 limits found in this session (upstream behaviour, not bugs we
can fix in config):**
- A leaving client only animates its frame; its content snaps away. So the
  tag slide brings the new desktop in but the old one vanishes at once.
- A tag word is one word for arriving and leaving clients; it names the
  *edge arriving clients come from* (measured: `slide_right` enters from the
  right edge, from x=674 to x=18 on a 1280 output).
- A markup with several fonts is drawn in the first run's font; colours of
  the runs survive (measured with a test wibox). Remaining warning source:
  the exit screen's bold/underlined hotkey letter (loses bold, keeps colour).
- A function `bgimage` is not drawn (warns once).
- No minimize fade, no layer-surface fade.
- IPC `eval` sees only C globals (`client`, `screen`, `tag`, `root`,
  `awesome`, `mouse`); `awful`, `gears`, `beautiful` need `require`. This was
  equally true on v1 (somewm-shell's CPU buttons were broken there too).
- `somewm-client exec <cmd>` = `awful.spawn.with_shell(cmd)`. It never
  replaced the compositor on v2 (older docs said so).

## 5. Verified on boxszn (and how)

Box: AMD Phoenix iGPU, KDE Wayland, no NVIDIA, no passwordless sudo, no Wine.

- Build: `make` release and `make build-test` clean (`-Werror`).
- Upstream integration suite on the fork (JOBS=8): **342 pass / 7 fail /
  7 skip**. The 7 (`test-clay-calendar-presentation`,
  `test-clay-hotkeys-sizing`, `test-clay-notification`,
  `test-clay-text-scale-change`, `test-clay-wallpaper-source`,
  `test-client-subsurface-opacity`, `test-font-resolution`) also fail on a
  pristine `upstream/main` worktree on this machine: environment (fonts),
  not the fork.
- After all fixes: the 40 XWayland/layer-shell/focus/grab tests +
  `test-memory-stats` pass.
- `somewm -k rc.lua` on somewm-one: only the `somewm.tag_slide` require
  (removed since).
- somewm-one in the sandbox: no Lua errors; windows map visible with
  `c.shape == 14`; layout-machi switcher overlay draws; theme switch keeps
  animation keys; lock screen shows the wallpaper; tag slide direction
  measured with a red xterm (`fin-*`: next enters from the right, prev from
  the left); `tag_slide::start/end` fire; fade interpolates on tag switch.
- somewm-shell in a headless sandbox: dashboard, memory/cpu/storage panels,
  wallpaper picker, control panel render; memory panel shows malloc rows.
- busted (somewm-one): 225 pass / 7 fail / 1 error, identical before and
  after the port (pre-existing `wallpaper_spec` failures).
- `border-probe.py` on the pixman sandbox: 100% clean, flicker 0.
- Cross-model review (gpt-5.6-sol) of the C delta: 4 findings, all fixed;
  further review rounds are recorded in section 10.

**Not verified anywhere yet:** DRM/KMS, NVIDIA, real multi-monitor and
hotplug, Steam games, Wine/Sierra Chart, PAM unlock with a real password,
screen sharing, gpu-screen-recorder, idle/DPMS, performance on 4K.

## 6. How to run things on v2

| task | command |
|---|---|
| build | `make` (release `build/`), `make build-test`, `make asan` |
| install | `plans/scripts/install.sh` (sudo; check: `--check`) |
| unit tests (compositor) | `make test-unit` |
| one integration test | `make test-one TEST=tests/test-foo.lua` |
| a set | `JOBS=6 SOMEWM=./build-test/somewm SOMEWM_CLIENT=./build-test/somewm-client ./tests/run-integration.sh tests/a.lua tests/b.lua` |
| whole v2 stack, isolated | `plans/scripts/v2-stack-sandbox.sh [--headless] [--shell] [--no-build]`, then `source ~/.local/somewm-v2-sbx/env` in a subshell; `--stop` |
| plain nested compositor | `plans/scripts/somewm-sandbox.sh [--headless] [--test-config]` |
| screenshot | `grim <file>` (with the sandbox env) or `somewm-client screenshot save <file>` |
| shell panel | `qs ipc -c somewm call somewm-shell:panels toggle <dashboard\|memory-detail\|cpu-detail\|storage-detail\|wallpapers\|sidebar-left\|controlpanel>` |
| border check | `plans/scripts/border-probe.py <label>` (focused client; results in `tests/bench/results/border/<label>/`) |
| render tree | `somewm-client clay tree [screen]`; `somewm.inspector.toggle(s)` |
| memory | `somewm-client eval 'local m=root.memory_stats(true); return m.lua_bytes'`; `plans/scripts/somewm-memory-snapshot.sh` (falls back for missing v1 fields) |
| somewm-one busted | `lua5.1 /usr/lib/luarocks/rocks-5.1/busted/2.3.0-1/bin/busted --helper=spec/preload.lua --lpath='?.lua;?/init.lua' spec/` |
| config check | `somewm -k ~/.config/somewm/rc.lua` |

Sandbox gotchas learned the hard way:
- Under KDE a hidden nested window gets no frame callbacks: animations
  freeze half-way, `grim` hangs. Use `--headless` for time-based checks.
- `--headless` runs in its own `XDG_RUNTIME_DIR` (a `/tmp/tmp.*` dir); `qs
  ipc` and `grim` need it (the env file exports it).
- somewm-shell hardcodes `$HOME/.config/...`; the stack script gives it a
  throwaway HOME. `qs ipc` must see the same `XDG_CONFIG_HOME` path the
  instance was started with (a symlinked path does not match).
- rc.lua's Quickshell relaunch runs `pkill -f 'qs -c somewm'`: without
  `SOMEWM_NO_SHELL=1` a sandbox kills the host's Quickshell.
- Start long-lived sandboxes with `setsid` (the stack script does); a
  compositor in the caller's process group took the calling shell down
  (exit 144) in this session.

Tooling notes: on boxszn `codex exec` defaults to an unsupported model; pass
`-m gpt-5.6-sol`. `gh` is installed but was not authenticated; GitHub over
SSH works.

## 7. What to do next

Follow nvidia-test-plan.md phases A -> B -> (user go) C -> D, recording every
test ID in `plans/v2/nvidia-test-results.md`. Phase B now has a one-liner:
`plans/scripts/v2-stack-sandbox.sh` (nested, visible window) for the corner
test on the real GPU. Gates: B3/D3 corners, D6 Steam, W1-W3 Sierra Chart.

## 8. Rollback

`git checkout legacy/v1` in all three repos, `plans/scripts/install-scenefx.sh`
(exists on that branch; needs the v1 deps: wlroots 0.19 + SceneFX 0.4 build),
both `deploy.sh`, restart from the TTY. Details in the test plan.

## 9. Loose ends

- Co-Authored-By trailer: somewm's CLAUDE.md forbids it (upstream-bound
  commits are the maintainer's); somewm-one's and somewm-shell's CLAUDE.md
  ask for it. This session followed each repo's own rule (none in somewm,
  `Co-Authored-By: Claude Opus 5.5` in the siblings). Ask the user before
  changing either rule.
- `plans/scripts/somewm-memory-*.sh` still list v1 field names; switch to
  the v2 keys.
- busted `wallpaper_spec` failures in somewm-one (pre-existing).
- somewm-one `fishlive/services/wallpaper.lua` / `themes.lua` still call the
  v1 wallpaper-cache API behind guards; dead on v2, harmless; could be
  removed.

## 10. Review log

| round | reviewer | scope | findings | outcome |
|---|---|---|---|---|
| 1 | gpt-5.6-sol (codex) | somewm C delta | stale re-associate buffer; grab-deferred unfocus; grab-deferred focus_restore; mallinfo2 needs glibc 2.33 | all fixed (`a01a16f`, `0be4c0b`, `e095d6e`) |
