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

## Open problems

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
