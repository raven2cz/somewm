# v2 NVIDIA test plan (for Claude on the primary workstation)

Audience: a Claude Code session on the **primary workstation** (NVIDIA RTX
5070 Ti, proprietary driver, nvidia-drm, multi-monitor incl. 4K and a Samsung
TV, Sierra Chart under Wine, Steam). The v2 line was built and verified only
in a nested/headless sandbox on an AMD box (see [README.md](README.md),
section "Verified on boxszn"). This plan is what that box could not do.

> **Bootstrap.** On the NVIDIA workstation the local checkout is still the v1
> line, where `plans/v2/` does not exist yet. Read these files straight from
> origin before switching anything:
> `git -C ~/git/github/somewm fetch origin && git -C ~/git/github/somewm show origin/main:plans/v2/HANDOFF.md`
> (same for `README.md`, `nvidia-test-plan.md`), then run phase A of the test
> plan, which moves all three checkouts onto v2.

Read first: [HANDOFF.md](HANDOFF.md) (complete state: what was done, why,
what is and is not fixed, how to run things), `CLAUDE.md` (v2 sections),
[README.md](README.md). Speak Czech
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

Run this as a script (it stops at the first problem). Pass 1 checks all
three repos before anything changes; pass 2 switches them. It keeps the old
local main as a uniquely named backup branch and refuses to reset over
local commits that are on neither origin line. It is safe to re-run after a
partial run (a repo already on origin/main is left alone):
```bash
set -euo pipefail
REPOS="somewm somewm-one somewm-shell"
STAMP=$(date +%Y%m%d-%H%M%S)
for r in $REPOS; do                       # pass 1: preflight, no changes
  R=~/git/github/$r
  test -z "$(git -C $R status --porcelain)" || { echo "$r: uncommitted changes: STOP, ask the user"; exit 1; }
  git -C $R fetch origin --tags
  git -C $R rev-parse --verify -q origin/legacy/v1 >/dev/null || { echo "$r: no origin/legacy/v1"; exit 1; }
  extra=$(git -C $R log --oneline main --not origin/legacy/v1 origin/main)
  [ -z "$extra" ] || { echo "$r: local commits on main that origin has on neither line:"; echo "$extra"; echo "STOP, ask the user"; exit 1; }
done
for r in $REPOS; do                       # pass 2: switch
  R=~/git/github/$r
  echo "== $r"
  if [ "$(git -C $R rev-parse main)" != "$(git -C $R rev-parse origin/main)" ]; then
    git -C $R branch "backup/pre-v2-main-$STAMP" main
    git -C $R checkout -q main
    git -C $R reset --hard origin/main
  fi
  git -C $R checkout -q main
  git -C $R branch -f legacy/v1 origin/legacy/v1
  git -C $R log --oneline -3
done
git -C ~/git/github/somewm remote get-url upstream >/dev/null 2>&1 || git -C ~/git/github/somewm remote add upstream git@github.com:trip-zip/somewm.git
git -C ~/git/github/somewm fetch upstream
git -C ~/git/github/somewm log --oneline upstream/main..main   # the fork commits listed in HANDOFF.md section 3, nothing else
```
Expected tips: the newest commit of each repo is the one HANDOFF.md
section 3 lists last for that repo. If the upstream list contains commits
not in HANDOFF.md, read them before going on. Remote `v2/main` mirrors
`origin/main` (main is authoritative).

A1. Record `somewm --version` of the *running* v1 binary and
`ls -l /usr/local/bin/somewm*`, `ls /usr/local/lib | grep -i scenefx`,
`cat ~/bin/session-launcher` (if present), `head -5 /usr/local/bin/somewm-session`.
These are the rollback reference.

A2. Build without installing. An old `build/` from the v1 line carries
options v2 no longer has (`scenefx`, `wlroots_version`, `xwayland`) and
breaks meson; remove it first if so (install.sh does the same):
```bash
cd ~/git/github/somewm
for d in build build-test build-asan; do   # v1-configured trees break meson on v2
  grep -q '"name": "scenefx"' $d/meson-info/intro-buildoptions.json 2>/dev/null && rm -rf $d
done
# ignored v1 subproject trees: wlroots-0.20/ also provides wlroots-0.20 and
# meson stops with "Multiple wrap files provide" (install.sh does the same)
for sp in wlroots-0.20 scenefx scenefx-0.4 scenefx-0.5; do
  [ -d subprojects/$sp ] && mkdir -p ~/.cache/somewm-v1-subprojects && mv subprojects/$sp ~/.cache/somewm-v1-subprojects/
done
make                                  # release build/; downloads wlroots 0.20.2 on first run
./build/somewm --version              # v2.1.x-...
```
If the build fails on a missing package, list it for the user (no sudo for
Claude unless the user runs `! sudo pacman -S ...` themselves).

## Phase B: v2 nested inside the live v1 session (NVIDIA GPU, no DRM)

The nested backend renders through the NVIDIA GPU with GLES2 (the stack
script sets `WLR_RENDERER=gles2` for nested runs), so corners and animation
rendering run on the real driver, without DRM/KMS.

B0. One command builds v2 into a private prefix (`~/.local/somewm-v2`, never
`/usr/local`), copies somewm-one into a private config home and starts the
nested compositor with `SOMEWM_NO_AUTOSTART=1 SOMEWM_NO_SHELL=1`. The sandbox
**keeps running** until `--stop`. Run every B test from a shell that has
sourced its env file; without it, `somewm-client` and X11 clients would talk
to the live v1 session:
```bash
~/git/github/somewm/plans/scripts/v2-stack-sandbox.sh      # nested; add --shell for somewm-shell (own qs instance)
bash                                                        # dedicated shell for phase B
source ~/.local/somewm-v2-sbx/env      # SOMEWM_SOCKET, WAYLAND_DISPLAY, DISPLAY (nested Xwayland), PATH, V2_SBX_LOG; with --shell also HOME
somewm-client eval 'return awesome.version'                 # must print v2.1...
grep -E 'WLR_RENDERER|Creating GLES2|Using OpenGL' "$V2_SBX_LOG"   # record: GLES2 on the NVIDIA device
# ... B1-B11 ...
exit
~/git/github/somewm/plans/scripts/v2-stack-sandbox.sh --stop
```
Keep the nested window **visible**: a hidden nested window gets no frame
callbacks and its animations freeze (CLAUDE.md, nested vs headless).

**Keybindings do not reach the sandbox.** The live v1 compositor grabs Super
combos itself (it does not offer the shortcut-inhibit protocol), so drive
B5-B7 through IPC instead:
```bash
somewm-client eval 'require("awful").spawn("alacritty"); return 1'                 # spawn
somewm-client eval 'client.focus:kill(); return 1'                                 # close focused
somewm-client eval 'client.focus.maximized = not client.focus.maximized; return 1'
somewm-client eval 'client.focus.floating = not client.focus.floating; return 1'
somewm-client eval 'local a=require("awful"); client.focus:swap(a.client.visible(client.focus.screen)[1]); return 1'
somewm-client eval 'require("awful").client.focus.byidx(1); return 1'               # focus change
somewm-client eval 'require("awful").tag.viewnext(); return 1'                     # Super+Right
somewm-client eval 'require("awful").tag.viewprev(); return 1'                     # Super+Left
somewm-client eval 'local a=require("awful"); a.layout.set(require("layout-machi").default_layout); return 1'
somewm-client eval 'require("layout-machi").switcher.start(client.focus); return 1' # Super+/
somewm-client eval 'require("layout-machi").default_editor.start_interactive(); return 1' # Super+.
```
(Leave the machi overlays with Escape typed into the nested window.)

| ID | test | pass criterion |
|---|---|---|
| B1 | startup log: command B1 below | no Lua error; warnings only the known `imagebox *_fit_policy` / `markup has more than one run` (exit screen) |
| B2 | spawn 3 alacritty via IPC and 1 `xterm &` from the sandbox shell; list with the B2 command below | 4 clients (XTerm among them, i.e. DISPLAY pointed at the sandbox), all shape 14, windows visible (not stuck transparent) |
| B3 | **borders on NVIDIA** (the v1 SceneFX defect): for each of 3 windows, focus it, wait 1 s, run `~/git/github/somewm/plans/scripts/border-probe.py nested-nvidia-<n>` | 100% clean, flicker 0, every edge `ok`. Compare: v1 SceneFX 0.5 measured 56% with the left edge absent. See "probe limits" below |
| B3b | corners and dragging, by eye: `grim` crops of each window's 4 corners; then move a window in steps (`client.focus:relative_move(40,0,0,0)` x10 via IPC) taking a `grim` after each step | corners round and complete; no edge missing or doubled in any step |
| B4 | border width 2 and radius 0 variants via IPC (`client.focus.border_width=2`, `client.focus.shape=nil`) + probe | 100% |
| B5 | animations via the IPC lines above: spawn/close (fade 0.5/0.4 s), maximize, floating, swap, focus border ease | smooth, no flashing at 0,0, no stuck half-transparent window |
| B6 | tag switch via IPC viewnext/viewprev | new tag's clients enter from the right going up, from the left going down; no tearing; wallpaper switches at once and the old desktop disappears at once (known 2.x limits) |
| B7 | layout-machi switcher and editor via IPC | overlay grid draws (was blank before the paint.lua fix) |
| B8 | wibar | icon and number in different fonts (numbers monospace), clock date small / time larger |
| B9 | theme switch: command B9 below, then switch back to the previous theme | prints `fade`; no error in the log |
| B10 | memory stats: command B10 below | two numbers |
| B11 | **last:** `somewm-client eval 'awesome.lock(); return 1'` | wallpaper behind the dimmed overlay; then `exit` the sandbox shell and `--stop` (do not type the password into a sandbox) |

Commands too long for the table:
```bash
# B1 (in the sandbox shell)
grep -Ei ' W: |traceback|error' "$V2_SBX_LOG" | grep -v EGL
# B2
somewm-client eval 'local t={} for _,c in ipairs(client.get()) do t[#t+1]=tostring(c.class)..":"..tostring(c.shape) end return table.concat(t," ")'
# B9
somewm-client eval 'require("fishlive.services.themes").switch("dracula"); return require("beautiful").animation_appear'
# B10
somewm-client eval 'local m=root.memory_stats(true); return m.lua_bytes.." "..tostring(m.malloc_used_bytes)'
# D1 (live session)
grep -E 'renderer|GLES|EGL' ~/.local/log/somewm-debug.log | head
```

**Probe limits.** `border-probe.py` walks the straight edges of the focused
client at the geometry it reads once, skips the rounded corners, assumes
output scale 1, and its "flicker" compares two captures 0.4 s apart. Run it
only on settled, stationary windows on a scale-1 output; corners and
dragging are checked by eye (B3b, D3b), not by the probe.

Gate B: if B3/B3b fail on NVIDIA GLES2, **stop** and report to the user before
phase C; it decides whether v2 is usable as a daily driver.

## Phase C: switch the real session to v2 (user present)

Ask the user explicitly. Then run as a script (it stops on the first error
and checks that all three repos are on v2 before installing):
```bash
set -euo pipefail
for r in somewm somewm-one somewm-shell; do
  test "$(git -C ~/git/github/$r rev-parse HEAD)" = "$(git -C ~/git/github/$r rev-parse origin/main)" \
    || { echo "$r is not at origin/main: STOP"; exit 1; }
done
~/git/github/somewm/plans/scripts/install.sh        # sudo; removes v1 libscenefx leftovers, wipes the installed Lua tree
~/git/github/somewm/plans/scripts/install.sh --check
(cd ~/git/github/somewm-one && ./deploy.sh)
(cd ~/git/github/somewm-shell && ./deploy.sh)
diff <(head -5 /usr/local/bin/somewm-session) <(head -5 ~/git/github/somewm/contrib/systemd/somewm-session.sh) || true
```
After `install.sh`, **do not** `somewm-client reload` the running v1
session (it would load v2 Lua into the v1 binary); only a session restart
switches the binary.

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
| D1 | startup | session comes up; `somewm --version`; command D1 under the B table | GLES2 renderer on the NVIDIA device; no `Falling back`-type renderer errors (software cursor fallback is acceptable, note it) |
| D2 | outputs | every monitor lit at its mode/scale; portrait and the Samsung TV; wallpaper per screen correct, including a monitor left of / above the primary (negative layout origin, audit #17) | correct placement, no offset wallpaper |
| D3 | borders | `border-probe.py drm-1..3` on 3 settled windows on a scale-1 output | 100% / flicker 0 |
| D3b | corners, dragging, scaled outputs | by eye: corner crops on every output (4K, TV, scaled ones), and a slow mouse drag of a window captured as a burst of `grim` shots | corners complete, no edge dropping out while dragging |
| D4 | performance | idle 5 min: `somewm-stats.log` CPU% and RSS; drag a window for 10 s; tag switch 20x quickly | idle CPU ~0-2%; no stutter; RSS stable (`plans/scripts/somewm-memory-trend.sh --idle 60`) |
| D5 | hotplug | unplug/replug a monitor (or power-cycle the TV) | no crash; clients return to their screens; wibar re-created |
| D6 | Steam games | launch a `steam_app_*` game (issue #137 history) | keyboard focus on launch, square corners (rule), no focus theft by Steam |
| D7 | XWayland focus | X11 app focus by click and sloppy focus; Super+K cycling | keyboard follows visual focus |
| D8 | drag across outputs (fork fix) | drag a floating window from monitor A to B with the mouse, release, click into it immediately without moving | stays focused during the drag; first click lands |
| D9 | screen::focus (fork fix) | move the pointer to another monitor and open a shell panel by keybinding | panel opens on the monitor under the pointer |
| D10 | layer-surface unmap focus (fork fix) | type in a terminal while a layer-shell surface without keyboard opens and closes: `qs ipc -c somewm call somewm-shell:panels showOsd volume 50`; repeat with a panel that takes keyboard (`qs ipc -c somewm call somewm-shell:panels toggle dashboard`, close with Escape) | the terminal keeps keyboard focus after the OSD; after the keyboard panel closes, focus returns to the terminal |
| D10b | notification | `notify-send test` while typing in a terminal | terminal keeps focus (notifications are wiboxes, not layer surfaces) |
| D11 | Quickshell shell | dashboard, dock (running apps), control panel (volume, brightness), OSD, hot edges, wallpaper picker + theme switch, collage, memory/cpu/storage panels | all open and render; memory panel shows malloc rows |
| D12 | lock screen + PAM | lock (keybinding), unlock with the real password; also wrong password once | wallpaper shown; error shown; unlock works; focus returns to the previous client |
| D13 | hot reload | `somewm-client reload` 5x (`plans/scripts/somewm-memory-trend.sh --reload 5`) | no crash; note RSS growth per reload (v1 leaked ~88 MB/reload) |
| D14 | screenshots / recording | Print, Shift+Print region, Super+Ctrl+P snipping, gpu-screen-recorder (NVENC) | files produced, correct output |
| D15 | screen sharing | browser or OBS screen share through xdg-desktop-portal-wlr (new upstream support) | stream is live, not frozen on the first frame |
| D16 | mpv | play a video floating with a titlebar; resize | aspect kept on the *content* (audit #35: upstream applies the ratio incl. titlebar; record what happens) |
| D17 | idle/DPMS | wait for the idle timeout; move the mouse | outputs blank and come back |
| D18 | integration suite | D18 commands below | failures equal to pristine upstream's on this machine (AMD box for reference: 342 pass, 7 environment failures, 7 skips; `test-carousel-peek` flaky under load) |

D18 commands (headless; v1-configured test trees were removed in A2):
```bash
cd ~/git/github/somewm && make build-test
HEADLESS=1 JOBS=6 SOMEWM=./build-test/somewm SOMEWM_CLIENT=./build-test/somewm-client ./tests/run-integration.sh > /tmp/v2-suite.txt 2>&1; tail -3 /tmp/v2-suite.txt
# compare the failures with pristine upstream on the same machine:
git worktree add /tmp/up-wt upstream/main
(cd /tmp/up-wt && make build-test >/dev/null && HEADLESS=1 SOMEWM=./build-test/somewm SOMEWM_CLIENT=./build-test/somewm-client ./tests/run-integration.sh tests/<each failed test>.lua)
git worktree remove --force /tmp/up-wt
```

### D-Wine: Sierra Chart and Wine (decides the override-redirect port)

v2 did **not** port v1's override-redirect rewrite. Upstream keeps OR windows
as Lua clients and stacks them in a Clay band. Test in the sandbox first
(v2 binary from the private prefix and the isolated config that
v2-stack-sandbox.sh made in phase B; stop the stack sandbox first), then live:
```bash
cd ~/git/github/somewm
plans/scripts/wine-sandbox.sh start --binary ~/.local/somewm-v2/bin/somewm \
    --client ~/.local/somewm-v2/bin/somewm-client --config-home ~/.local/somewm-v2-sbx/config
WINEPREFIX=~/.wine-sierra plans/scripts/wine-sandbox.sh wine -- ~/.wine-sierra/drive_c/SierraChart/SierraChart.exe &
# W1-W5 inside the nested window; between steps:
plans/scripts/wine-sandbox.sh census --probe     # X11 tree vs client.get()
plans/scripts/wine-sandbox.sh stop
# live (phase D): the user's launcher; the path comes from the v1 notes, check it exists
ls ~/git/fishlive/scripts/sierrachart/run-sierrachart.sh && ~/git/fishlive/scripts/sierrachart/run-sierrachart.sh
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
2. Upstream submissions: **not now** (user, 2026-10-24). Do not open
   issues/PRs or comment upstream; only keep the candidate list current.
3. Wine OR port: none / minimal / full.
4. Blur: live without it, or invest in a blur pass on the wlroots diff.

## Rollback to v1

Run as a script; it stops before deleting anything unless all three repos
are on `legacy/v1`:
```bash
set -euo pipefail
for r in somewm somewm-one somewm-shell; do
  git -C ~/git/github/$r checkout -q legacy/v1
  test "$(git -C ~/git/github/$r rev-parse HEAD)" = "$(git -C ~/git/github/$r rev-parse origin/legacy/v1)" \
    || { echo "$r is not at origin/legacy/v1: STOP"; exit 1; }
done
test -x ~/git/github/somewm/plans/scripts/install-scenefx.sh || { echo "no v1 installer: STOP"; exit 1; }
sudo rm -rf /usr/local/share/somewm/lua        # the v1 installer does not wipe the installed Lua tree
cd ~/git/github/somewm && ./plans/scripts/install-scenefx.sh    # needs the v1 deps (wlroots 0.19 + SceneFX 0.4 build)
./plans/scripts/install-scenefx.sh --check     # NB: v1's --check prints problems but exits 0: read its output
(cd ~/git/github/somewm-one && ./deploy.sh)
(cd ~/git/github/somewm-shell && ./deploy.sh)
```
Then restart the session from the TTY (`start.sh`). To return to v2 later:
`git checkout main` in all three repos, then phase C again.
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
