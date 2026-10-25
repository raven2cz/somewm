# v2 NVIDIA test results

Machine: r9home ("Strakonice"), NVIDIA GeForce RTX 4070 SUPER (AD104) +
AMD Raphael iGPU (Radeon 610M), nvidia-open kernel module
Driver at start: kernel module 615.71.09 on linux-cachyos 7.2.7; a full
system upgrade (`paru -Syu`, 2026-10-25 07:00) moved userspace to 615.78.08
and the kernel to 7.3.0 -> reboot required before any GPU test
Outputs: DP-1 LG ULTRAGEAR+ 3840x2160@144, scale 1, at 0,0 (single output at test time)
Driver after reboot: 615.78.08 everywhere (kernel 7.3.0-5-cachyos)
v2 commit: somewm 100c356, somewm-one c8db93e, somewm-shell d8987bd
Running v1 before the switch: `/usr/local/bin/somewm` from 2026-08-23
(kolo10 code on wlroots 0.19 + SceneFX 0.4; `--version` prints no
version line)

| ID | result (pass/fail/skip) | evidence | notes |
|---|---|---|---|
| A | pass | all three repos: local `main` == `origin/main`, `legacy/v1` present on origin; `git log main..upstream/main` empty, merge base `6eaa61e`, 27 fork commits | the user had already switched the checkouts on this box |
| A1 | pass | `/usr/local/bin/somewm` 2412784 B (2026-08-23 19:00), `somewm-client` 100536 B, `somewm-session` = upstream systemd wrapper (2026-04-18); `/usr/local/lib`: `libscenefx-0.4.so`, `libscenefx-0.5.so`; `~/bin/session-launcher` = TUI session menu | rollback reference |
| A2 | pass | `v2.1.0-32-g100c356`, wlroots 0.20.2 | ignored v1 trees `subprojects/{wlroots-0.20,scenefx*}` broke meson ("Multiple wrap files provide wlroots-0.20"); moved to `~/.cache/somewm-v1-subprojects/`; install.sh and plan A2 now do this |
| B0 | pass | sandbox log: `EGL vendor: NVIDIA`, `Creating GLES2 renderer`, `OpenGL ES 3.2 NVIDIA 615.78.08` | |
| B1 | pass | only known warnings (imagebox fit policy, multi-run markup); the markup one is gone after the somewm-one cleanup | |
| B2 | pass | 3 Alacritty + XTerm, all `shape 14`, visible | |
| B3 | pass | border-probe nested-nvidia-1..3: 100.0 %, flicker 0, all edges ok; with rounded border (fork change) nested-nvidia-rounded-1..3: 100.0 %, flicker 0 | stock 2.1 draws a SQUARE border around a rounded client (docs: use border_width 0) |
| B3b | pass | corner crops /tmp/v2b/corners-rb.png: rounded 1px ring, anti-aliased, inner radius 13 matches the surface | after the fork change |
| D18 (prelim, headless) | pass | fork branch: 321 pass / 13 fail / 25 skip; the same 13 fail with the identical assertion on a pristine `upstream/main` worktree on this box (text/font metrics, systray separator, bundled bar groups, drag-border-refocus) | 0 new failures from the fork delta |
| C | done | user ran `install.sh` (sudo) + `--check`: All good, no libscenefx in /usr/local/lib; build objects rebuilt after the fork commits (the `--version` string still says g100c356: it is computed when the meson tree is configured, cosmetic); `deploy.sh` for somewm-one and somewm-shell; `somewm -k ~/.config/somewm/rc.lua`: no issues; `/usr/local/bin/somewm-session` = upstream wrapper | next: log out to a TTY, start via `~/bin/session-launcher` (entry `somewm` -> `somewm-session` -> systemd `somewm.service` -> `/usr/local/bin/somewm`; wrapper and unit identical to the v2 build, `daemon-reload` done; logs in `journalctl --user -u somewm`, no `-d`) or `plans/scripts/start.sh` (debug log `~/.local/log/somewm-debug.log`); the next session continues with phase D |
| D1 | pass (after fix) | first v2 start composited on the AMD iGPU (`EGL driver name: radeonsi`, multi-GPU copy to the NVIDIA card that drives DP-1; v1 logs show the same); fixed with udev symlink `/dev/dri/nvidia-card` (`/etc/udev/rules.d/61-somewm-nvidia-card.rules`, KERNELS 0000:01:00.0) + `WLR_DRM_DEVICES=/dev/dri/nvidia-card` in `~/.config/environment.d/50-somewm.conf`; start.sh now sources environment.d (e20152b). After restart: `Opening fixed list of KMS devices from WLR_DRM_DEVICES`, `GL renderer: NVIDIA GeForce RTX 4070 SUPER`. Software cursor forced by `WLR_NO_HARDWARE_CURSORS=1` (v1-era env) | `XDG_CURRENT_DESKTOP` in environment.d changed `wlroots` -> `somewm` (somewm.portal `UseIn=somewm`). Log: only `mouse::leave on unregistered drawin` warnings |
| D3 | pass with notes | border-probe drm-alacritty: bottom ok, sides ok except the top 15 px, top edge tinted 50 %: the wibar shadow falls over a client directly below the bar (by design); drm-1 on ghostty: top/left 100 %, bottom/right tinted ~90 % (e2b55a -> cca3 54), also with `shape = nil` (worse): ghostty-specific, its surface appears to cover the border's far edges | open: ghostty bottom/right border tint |
| D4 | pending | first 2 min: RSS 537 MB, CPU 5-10 % while the terminal scrolls; GPU 9 %, 304 MiB | needs a real 5 min idle sample |
| D6 | pass (user) | user: Steam and Dispatch (Proton, X11) work, clicks and keyboard; live client list with Steam running: Steam main window mapped and managed, 0 unmapped/no-screen clients (v1 showed ~110 Steam ghost clients) | the v1 issue "clicks do not work in games/Steam" does not reproduce on v2 |
| D11 | pass (user) | Quickshell did not start: AUR `quickshell-git` 0.3.0 was built against the old Qt (`symbol lookup error ... Qt_6_PRIVATE_API`, Qt now 6.12.0; same error already in September logs). `paru -S quickshell-git` silently installed cachyos `noctalia-qs` (repo package with `Provides: quickshell-git`, built for Qt 6.11.2); `paru -S aur/quickshell-git` built 0.3.2 against Qt 6.12, log clean, user: panels work. rc.lua starts it automatically (theme-export.sh + relaunch, no SOMEWM_NO_SHELL). somewm-one deploy.sh deleted the shell's themes/*/theme.json (rsync --delete): fixed (e9ba2bd) | after every Qt upgrade rebuild with `paru -S aur/quickshell-git` (not the bare name) |

## Open problems

- Compositor crash (SIGSEGV, use-after-free) in upstream window.c configure_retry
  seen in a headless sandbox with hot reloads (core: coredumpctl 275046);
  being investigated by Codex. Until fixed: no hot reload in the live session.
- Wallpaper slide on tag switch (v1 feature) not done: the output-covering
  wallpaper drawin has no animation path; overlay approach clipped the
  outgoing image.

- ghostty: bottom/right border pixels tinted (~90 % border colour) on the live
  output, top/left exact; alacritty is clean. Suspect the client surface
  overlapping the border's far edges. Not yet investigated.
- `WLR_NO_HARDWARE_CURSORS=1` is still set (v1 workaround); try hardware
  cursors on nvidia-open 615.

- The CLAUDE.md hardware line says RTX 5070 Ti; this box has an RTX 4070
  SUPER.

## Decisions taken with the user

- 2026-10-25: rounded clients keep a coloured focus border that follows the
  corners (fork change in lua/awful/client/clay.lua, `box.radius`), instead of
  the docs' `border_width = 0`.
- 2026-10-25: docked wibar gets a shadow (fork change, minimal: declare.c
  declare_bar + render.c half-plane cut, band Z_DRAWIN-1 over normal clients;
  limitation: a second bar on the same edge can get the outer bar's shadow).
  Codex's first, larger version (raised every bar's paint) was rejected.
- 2026-10-25: implementation by Codex gpt-6.1-sol, Claude reviews and tests;
  compositor changes minimal, config first (somewm-one cleanup against 2.1
  and somewm.org docs); SceneFX removed from all current docs/scripts.
- 2026-10-25: shadows tuned live to the v1 look (soft, right/bottom; SceneFX
  in v1 ignored clip_directional and blurred a window-sized box, ~50 % at the
  edge). 2.1 nine-patch equivalent, all six themes (somewm-one eea2e0a):
  windows radius 50, offset 10/10, spread -35; bars/popups radius 40,
  spread -16 (a 33 px bar cannot take more: the nine-patch needs
  height + 2*spread >= 0, otherwise no shadow is drawn).
