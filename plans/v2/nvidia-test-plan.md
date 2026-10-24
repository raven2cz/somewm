# v2 NVIDIA test plan (for Claude on the primary workstation)

Audience: a Claude Code session on the **primary workstation** (NVIDIA RTX
5070 Ti, proprietary driver, nvidia-drm, multi-monitor incl. 4K and a Samsung
TV, Sierra Chart under Wine, Steam). The v2 line was built and verified only
in a nested/headless sandbox on an AMD box (see [README.md](README.md),
section "Verified on boxszn"). This plan is what that box could not do.

Read first: `CLAUDE.md` (v2 sections), [README.md](README.md). Speak Czech
with the user; write results in English.

## Ground rules

- **Never** touch the live session casually. Phases A and B run *beside* the
  live v1 session; only phase C replaces it, and only after the user says go.
- The live session is the compositor your terminal runs in. Restarting it
  kills this Claude session. Phase C therefore ends your session on purpose:
  write state to the results file first, and the next session continues from
  it.
- Record everything in `plans/v2/nvidia-test-results.md` (create it from the
  template at the end). One row per test ID, with evidence (log excerpt,
  screenshot path, probe JSON). Commit it as you go (`docs(v2): ...`).
- A failure is data, not a reason to improvise a fix in the live session.
  Reproduce, record, then decide with the user (section "Decisions").
- Rollback is always available (section "Rollback"). Tell the user how before
  phase C.

## Phase A: get the three repos onto v2 (no install yet)

`origin/main` of all three repos was **replaced** by the v2 line on
2026-10-24; the old main is `legacy/v1` (tag `v1-legacy`). A plain `git pull`
would try to merge the two lines.

```bash
for r in somewm somewm-one somewm-shell; do
  cd ~/git/github/$r
  git status --short            # must be empty; if not, STOP and ask the user
  git fetch origin --tags
  git branch -f legacy/v1 origin/legacy/v1
  git log -1 --format='%h %s' origin/legacy/v1   # sanity: v1 tip exists
  git checkout main && git reset --hard origin/main
  git log --oneline -5
done
cd ~/git/github/somewm && git remote add upstream git@github.com:trip-zip/somewm.git 2>/dev/null; git fetch upstream
git log --oneline upstream/main..main     # expect about a dozen fork commits (README table), nothing else
```

A1. Record `somewm --version` of the *running* v1 binary and
`ls -l /usr/local/bin/somewm*`, `ls /usr/local/lib | grep -i scenefx`,
`cat ~/bin/session-launcher` (if present), `head -5 /usr/local/bin/somewm-session`.
These are the rollback reference.

A2. Build without installing:
```bash
cd ~/git/github/somewm && make        # release build/; downloads wlroots 0.20.2 on first run
./build/somewm --version              # v2.1.x-...
```
If the build fails on a missing package, list it for the user (no sudo for
Claude unless the user runs `! sudo pacman -S ...` themselves).

## Phase B: v2 nested inside the live v1 session (NVIDIA GPU, no DRM)

The nested backend renders on the NVIDIA GPU through GLES2, so corner and
animation rendering is exercised on the real driver, without DRM/KMS.

B0. Install v2 into a private prefix so the nested binary does not read the
v1 Lua tree in `/usr/local/share/somewm`:
```bash
P=$HOME/.local/somewm-v2; B=$HOME/.cache/somewm-v2-build
cd ~/git/github/somewm && meson setup $B --prefix=$P -Dsystemd=disabled -Dbuildtype=release
ninja -C $B && meson install -C $B --skip-subprojects
```
Config copy (keeps `~/.config/somewm` = live v1 untouched):
```bash
C=$HOME/.local/somewm-v2-cfg; mkdir -p $C/somewm
rsync -a --delete --exclude .git --exclude deploy.sh --exclude CLAUDE.md ~/git/github/somewm-one/ $C/somewm/
SOMEWM_NO_AUTOSTART=1 SOMEWM_NO_SHELL=1 SOMEWM_SANDBOX_CONFIG_HOME=$C \
  ~/git/github/somewm/plans/scripts/somewm-sandbox.sh --binary $P/bin/somewm --client $P/bin/somewm-client &
```
Use the printed `SOMEWM_SOCKET`/`WAYLAND_DISPLAY`, and `$P/bin/somewm-client`
for IPC. Keep the nested window **visible**: a hidden nested window gets no
frame callbacks and its animations freeze (see CLAUDE.md, nested vs headless).

| ID | test | pass criterion |
|---|---|---|
| B1 | startup log: `grep -E ' W: \|traceback\|error' <sandbox log>` | no Lua error; warnings only the known `imagebox *_fit_policy` / `markup has more than one run` (exit screen) |
| B2 | open 3 alacritty + 1 xterm; `client.get()` shapes | all `c.shape == 14`; windows visible (not stuck transparent) |
| B3 | **corners on NVIDIA** (the v1 SceneFX defect): with the nested window focused, run `plans/scripts/border-probe.py nested-nvidia-1` for each of 3 focused windows; then drag one window around and run it again | 100% clean, flicker 0, every edge `ok`. Compare: v1 SceneFX 0.5 measured 56% with the left edge absent |
| B4 | border width 2 and radius 0 variants via IPC (`c.border_width=2`, `c.shape=nil`) + probe | 100% |
| B5 | animations: spawn/close (fade 0.5/0.4 s), maximize/unmaximize, toggle floating, swap master (Super+Ctrl+Return), focus change border ease | smooth, no flashing at 0,0, no stuck half-transparent window |
| B6 | tag switch Super+Right / Super+Left (or `awful.tag.viewnext/viewprev`) | new tag's clients and wallpaper enter from the right going up, from the left going down; no tearing; old desktop disappears at once (known 2.1 limit) |
| B7 | layout-machi: Super+/ switcher, Super+. editor | overlay grid draws (was blank before the paint.lua fix) |
| B8 | wibar | icon and number in different fonts (numbers monospace), clock date small / time larger |
| B9 | theme switch via IPC `require("fishlive.services.themes").switch("dracula")` and back | no error; `beautiful.animation_appear == "fade"` afterwards |
| B10 | lock screen `awesome.lock()` | wallpaper behind the dimmed overlay; then kill the sandbox (do not type the password into a sandbox) |
| B11 | `root.memory_stats(true)` | table with `lua_bytes`, `malloc_used_bytes` etc. |

Stop the sandbox afterwards (`kill <pid>`; `rm -f $XDG_RUNTIME_DIR/somewm-sandbox-*.sock`).

Gate B: if B3 fails (border not 100% on NVIDIA GLES2), **stop** and report to
the user before phase C; it decides whether v2 is usable as a daily driver.

## Phase C: switch the real session to v2 (user present)

Ask the user explicitly. Then:
```bash
cd ~/git/github/somewm && ./plans/scripts/install.sh   # sudo; removes v1 libscenefx leftovers
./plans/scripts/install.sh --check
cd ~/git/github/somewm-one && ./deploy.sh
cd ~/git/github/somewm-shell && ./deploy.sh
diff <(head -5 /usr/local/bin/somewm-session) <(head -5 ~/git/github/somewm/contrib/systemd/somewm-session.sh)
```
`/usr/local/bin/somewm-session` on v1 already was upstream's systemd wrapper
(both v1 and v2 install it to that path); if A1 showed a *different* script
(the v1 restart-loop launcher), tell the user: `~/bin/session-launcher` may
behave differently (no gnome-keyring start, no debug log tee). `start.sh`
does not use it.

Write "phase C done, session restart pending" into the results file, commit,
then the user logs out to a TTY and runs `~/git/github/somewm/plans/scripts/start.sh`.
The next Claude session reads the results file and continues with phase D.

## Phase D: live DRM tests on v2

Log: `~/.local/log/somewm-debug.log`. Stats watchdog:
`~/.local/log/somewm-stats.log`.

| ID | area | test | pass criterion |
|---|---|---|---|
| D1 | startup | session comes up; `somewm --version`; `grep -E 'renderer\|GLES\|EGL' ~/.local/log/somewm-debug.log \| head` | GLES2 renderer on the NVIDIA device; no `Falling back`-type renderer errors (software cursor fallback is acceptable, note it) |
| D2 | outputs | every monitor lit at its mode/scale; portrait and the Samsung TV; wallpaper per screen correct, including a monitor left of / above the primary (negative layout origin, audit #17) | correct placement, no offset wallpaper |
| D3 | corners | `border-probe.py drm-1..3` on 3 windows, then while dragging, then on the 4K output and the TV | 100% / flicker 0 |
| D4 | performance | idle 5 min: `somewm-stats.log` CPU% and RSS; drag a window for 10 s; tag switch 20x quickly | idle CPU ~0-2%; no stutter; RSS stable (`plans/scripts/somewm-memory-trend.sh --idle 60`) |
| D5 | hotplug | unplug/replug a monitor (or power-cycle the TV) | no crash; clients return to their screens; wibar re-created |
| D6 | Steam games | launch a `steam_app_*` game (issue #137 history) | keyboard focus on launch, square corners (rule), no focus theft by Steam |
| D7 | XWayland focus | X11 app focus by click and sloppy focus; Super+K cycling | keyboard follows visual focus |
| D8 | drag across outputs (fork fix) | drag a floating window from monitor A to B with the mouse, release, click into it immediately without moving | stays focused during the drag; first click lands |
| D9 | screen::focus (fork fix) | move the pointer to another monitor and open a shell panel by keybinding | panel opens on the monitor under the pointer |
| D10 | notification focus (fork fix) | type in a terminal, `notify-send test`, let it time out | the terminal keeps keyboard focus throughout |
| D11 | Quickshell shell | dashboard, dock (running apps), control panel (volume, brightness), OSD, hot edges, wallpaper picker + theme switch, collage, memory/cpu/storage panels | all open and render; memory panel shows malloc rows |
| D12 | lock screen + PAM | lock (keybinding), unlock with the real password; also wrong password once | wallpaper shown; error shown; unlock works; focus returns to the previous client |
| D13 | hot reload | `somewm-client reload` 5x (`plans/scripts/somewm-memory-trend.sh --reload 5`) | no crash; note RSS growth per reload (v1 leaked ~88 MB/reload) |
| D14 | screenshots / recording | Print, Shift+Print region, Super+Ctrl+P snipping, gpu-screen-recorder (NVENC) | files produced, correct output |
| D15 | screen sharing | browser or OBS screen share through xdg-desktop-portal-wlr (new upstream support) | stream is live, not frozen on the first frame |
| D16 | mpv | play a video floating with a titlebar; resize | aspect kept on the *content* (audit #35: upstream applies the ratio incl. titlebar; record what happens) |
| D17 | idle/DPMS | wait for the idle timeout; move the mouse | outputs blank and come back |
| D18 | integration suite | `make test-integration` (no live session needed; takes minutes) | compare with README's 342/7/7; the same 7 environment failures are acceptable |

### D-Wine: Sierra Chart and Wine (decides the override-redirect port)

v2 did **not** port v1's override-redirect rewrite. Upstream keeps OR windows
as Lua clients and stacks them in a Clay band. Test in the sandbox first, then
live:
```bash
plans/scripts/wine-sandbox.sh start
plans/scripts/wine-sandbox.sh census --probe     # X11 tree vs client.get()
~/git/fishlive/scripts/sierrachart/run-sierrachart.sh   # live
```

| ID | test | pass criterion |
|---|---|---|
| W1 | open main menu, submenus, context menu (right click in a chart) | menus appear above the window, at the right position, and stay open while the pointer moves over them |
| W2 | sloppy focus: open a menu, move the pointer across *another* window | menu does not close / lose keyboard (audit #1: upstream's guard is narrow) |
| W3 | open dialogs repeatedly (Chart Settings, Find Symbol) 20x | every dialog appears (the associate fix; v1 symptom: dialog in `client.get()` with 0x0 geometry, no scene) |
| W4 | floating dialog of a tiled parent vs an unrelated floating window | dialog above the unrelated window (audit #34) |
| W5 | windows that flip override_redirect (Wine tooltips that become windows) | no ghost client, no stuck invisible window (`census --probe`) |

If W1/W2/W5 fail, the minimal port is: role-flip handlers
(`set_override_redirect`) + the unmanaged focus-hold guard (~150 lines, see
`plans/done/legacy-v1/goal-xwayland-wine-popups.md`). Record exact repro
steps; that is also what upstream needs for an issue.

## Decisions to bring back to the user

1. Is v2 good enough as the daily driver (gates: B3/D3 corners, D6 games,
   W1-W3 Sierra Chart)?
2. Which fork commits to offer upstream (the human maintainer submits; follow
   `CONTRIBUTING.md`/`AI_POLICY.md`, disclose AI use).
3. Wine OR port: none / minimal / full.
4. Blur: live without it, or invest in a blur pass on the wlroots diff.

## Rollback to v1

```bash
for r in somewm somewm-one somewm-shell; do git -C ~/git/github/$r checkout legacy/v1; done
cd ~/git/github/somewm && ./plans/scripts/install-scenefx.sh    # exists on legacy/v1; needs wlroots0.19 + SceneFX 0.4 deps
cd ~/git/github/somewm-one && ./deploy.sh
cd ~/git/github/somewm-shell && ./deploy.sh
# restart the session from the TTY (start.sh)
```
`install.sh` (v2) removed `libscenefx-*` from `/usr/local/lib`;
`install-scenefx.sh` rebuilds and reinstalls it.

## Results template (`plans/v2/nvidia-test-results.md`)

```markdown
# v2 NVIDIA test results

Machine: <hostname>, driver <nvidia-smi version>, outputs <list>
v2 commit: somewm <hash>, somewm-one <hash>, somewm-shell <hash>
Running v1 before the switch: <somewm --version>

| ID | result (pass/fail/skip) | evidence | notes |
|---|---|---|---|
| A1 | | | |
...

## Open problems
## Decisions taken with the user
```
