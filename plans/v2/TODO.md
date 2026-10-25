# v2 TODO (continue at home)

State on 2026-10-25 ~10:00, end of the r9home session (RTX 4070 SUPER + AMD
iGPU). r9home runs v2 live on the NVIDIA card. All three repos are committed
and pushed (somewm, somewm-one, somewm-shell: `main` = `origin/main` =
`origin/v2/main`). Details and evidence: [nvidia-test-results.md](nvidia-test-results.md).

## First, on the home PC

- [ ] Move it from v1 to v2 with [migrate-machine.md](migrate-machine.md)
      (repo switch, `paru -S aur/quickshell-git`, `install.sh`, GPU
      selection if there are several GPUs, environment.d, deploy, session
      launcher, switch from a TTY). CLAUDE.md's "RTX 5070 Ti" probably means
      this machine; r9home has a 4070 SUPER.
- [ ] Start a results section for that machine (copy the template at the
      end of [nvidia-test-plan.md](nvidia-test-plan.md)): D1 renderer on the
      NVIDIA device, D3 border probe, D6 Steam/games.

## Features

- [ ] Wallpaper slide on tag switch (the v1 feature: the wallpaper moves with
      the windows). The output-covering wallpaper drawin
      (`declare.c` `declare_wallpaper_drawin`) has no animation path. A
      config-only overlay attempt (Codex) clipped the outgoing image, and an
      overlay would sit above desktop-type clients (band -4 vs -6), which is
      acceptable here. Decide between redoing the overlay in somewm-one and a
      small compositor change (animation on the wallpaper path); ask before
      the compositor change.

## Phase D tests still open

- [ ] D4 idle 5 min (CPU, RSS; wallpaper cover cache = 3 surfaces per
      screen, ~33 MB each at 4K) and `somewm-memory-trend.sh --idle 60`
- [ ] D7 X11 focus by click, sloppy focus, Super+J/K
- [ ] D10 / D10b focus around OSD, keyboard panels, notifications
- [ ] D12 lock screen + PAM (wrong password once, then the right one)
- [ ] D13 `somewm-memory-trend.sh --reload 5` (reload is safe again since
      a5e4a5c; note RSS per reload; v1 leaked ~88 MB per reload)
- [ ] D14 screenshots (Print, Shift+Print, Super+Ctrl+P), gpu-screen-recorder
- [ ] D15 screen sharing via xdg-desktop-portal-wlr (portal `UseIn=somewm`,
      `XDG_CURRENT_DESKTOP=somewm` now)
- [ ] D16 mpv floating with a titlebar, resize (aspect now uses the full
      geometry like 2.1)
- [ ] D17 idle timeout / DPMS
- [ ] D2, D5, D8, D9 with the other monitors (portrait HP left of the Dell,
      Samsung TV, hotplug, drag across outputs, `screen::focus`)
- [ ] W1-W5 Sierra Chart under Wine (menus, dialogs, override-redirect
      windows; decides the OR port)
- [ ] D18 full suite again after any compositor change (13 known
      environment failures, see upstream-notes.md)

## Small fixes

- [ ] ghostty: bottom/right border pixels ~90 % of the border colour on the
      live output (top/left exact, alacritty clean)
- [ ] Try hardware cursors: drop `WLR_NO_HARDWARE_CURSORS=1` from
      `~/.config/environment.d/50-somewm.conf`, then restart the session
- [ ] `plans/scripts/somewm-memory-*.sh`: switch to the v2
      `root.memory_stats` keys
- [ ] Independent review of the C delta (HANDOFF.md suggested Fable; also the
      2026-10-25 commits a5e4a5c, d3cad6c, 5b18ed1, 63f1347)
- [ ] `somewm --version` shows the describe from configure time (cosmetic)

## User

- [ ] Rename the over-long wallpaper file in
      `~/Pictures/wallpapers/public-wallpapers/portrait/digital-landscapes/`
      (it fails to load: "Filename too long")
- [ ] Upstream submissions when wanted: material in
      [upstream-notes.md](upstream-notes.md)

## Working rules (from this session)

- Config first, compositor minimal, ask before bigger C changes.
- Codex `gpt-6.1-sol` for config cleanups and audits. It refuses crash
  investigations, so Claude debugs crashes itself. Review every Codex diff
  for edits to upstream files outside the task.
- Never `somewm-client reload` a running v1 session after installing v2.
- After a Qt upgrade: `paru -S aur/quickshell-git`.
