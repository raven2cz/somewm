# INSTALL — somewm + somewm-one + somewm-shell

Reference for setting up or updating the full SomeWM stack on a fresh workstation
or after a clean reinstall. Audience: maintainer (Antonin Fischer / raven2cz) and
AI agents driving the install.

The stack is three repos that work together:

| Repo | Role | Local path | GitHub |
|------|------|------------|--------|
| `somewm` | compositor + Lua framework (this repo) | `~/git/github/somewm` | `raven2cz/somewm` (fork), `trip-zip/somewm` (upstream) |
| `somewm-one` | personal `rc.lua` + themes + plugins | `~/git/github/somewm-one` | `raven2cz/somewm-one` |
| `somewm-shell` | Quickshell desktop shell (panels, dashboard, launcher) | `~/git/github/somewm-shell` | `raven2cz/somewm-shell` |

Environment overrides (only set if the local paths differ from defaults above):

```bash
export SOMEWM_FORK_PATH="$HOME/git/github/somewm"
export SOMEWM_ONE_PATH="$HOME/git/github/somewm-one"
export SOMEWM_SHELL_PATH="$HOME/git/github/somewm-shell"
```

For the surrounding Arch environment — notification daemon, audio stack,
portals, keyring, applets, themes, fonts, applications, and the WHY/WHERE of
each setting around `somewm` — see [ARCH-DEP-INSTALL.md](ARCH-DEP-INSTALL.md).
This file covers only the three somewm repos themselves.

---

## 1. System prerequisites (Arch Linux)

```bash
# Build deps for somewm + wlroots subproject
sudo pacman -S --needed \
    base-devel git meson ninja pkgconf cmake \
    wayland wayland-protocols libxkbcommon \
    libinput libdrm mesa vulkan-icd-loader \
    pixman cairo pango \
    lua51 luajit lua51-lgi \
    xorg-xwayland xcb-util-wm xcb-util-errors \
    libliftoff libdisplay-info librsvg \
    seatd

# Tests and screenshots (busted lives at
# /usr/lib/luarocks/rocks-5.1/busted/2.3.0-1/bin/busted; run it with lua5.1)
sudo pacman -S --needed lua51-busted grim wl-clipboard github-cli

# Quickshell (somewm-shell runtime)
sudo pacman -S --needed quickshell qt6-base qt6-declarative qt6-svg

# Optional but recommended for sessions / D-Bus integration
sudo pacman -S --needed dbus-broker xdg-desktop-portal-wlr polkit gnome-keyring

```
(`somewm-client` is built and installed with the compositor; GBM comes with
`mesa`.)

If `somewm` is not in pacman/AUR, the `somewm-client` binary is built and
installed by `plans/scripts/install.sh` together with the compositor.

No system wlroots package is needed: since 2.1 somewm always builds wlroots
0.20.2 from its wrap (with somewm's corner diff) and links it in.

NVIDIA-specific (only on the dev box):
```bash
sudo pacman -S nvidia nvidia-utils nvidia-settings
# Kernel boots with nvidia-drm.modeset=1 already (per fork CLAUDE.md).
```

---

## 2. Clone the three repos

```bash
mkdir -p ~/git/github
cd ~/git/github

# somewm — fork-as-origin, upstream as read-only
git clone git@github.com:raven2cz/somewm.git
cd somewm
git remote add upstream git@github.com:trip-zip/somewm.git
git fetch upstream
cd ..

# somewm-one — personal rc.lua + themes
git clone git@github.com:raven2cz/somewm-one.git

# somewm-shell — Quickshell desktop shell
git clone git@github.com:raven2cz/somewm-shell.git
```

If SSH keys are not yet provisioned on the new box, swap `git@github.com:` for
`https://github.com/` and re-add SSH remotes once keys are in place.

---

## 3. Build & install somewm

```bash
cd ~/git/github/somewm
./plans/scripts/install.sh
```

What this does:
1. `make` -- release build in `build/` (a `build/` configured by the v1 line,
   which still has the `scenefx` option, is removed first).
2. Removes v1 SceneFX leftovers from `/usr/local` (`libscenefx-*`, its
   pkg-config file and headers), if any.
3. `sudo make install` -- installs to `/usr/local`, wiping the installed Lua
   tree first so no stale v1 module (`anim_client`, `tag_slide`,
   `gears.wallpaper`) can be picked up.
4. `ldconfig`, then verifies the v2 binary links and checks for v1 leftovers.

Verify after install:
```bash
./plans/scripts/install.sh --check
somewm --version            # v2.1.x-... on the v2 line
```

The v1 line (`legacy/v1`) has its own `install-scenefx.sh`; use that only after
checking out `legacy/v1`.

---

## 4. Deploy somewm-one (rc.lua + themes)

```bash
cd ~/git/github/somewm-one
./deploy.sh
```

What this does:
1. Backs up current `~/.config/somewm/rc.lua` to `rc.lua.bak`.
2. `rsync --delete` the repo into `~/.config/somewm/`, excluding repo-management
   files (`deploy.sh`, `.git`, `LICENSE`, `CLAUDE.md`, `themes/*/user-wallpapers/`,
   `screen_scopes.json`, `.active_theme`, `.default_portrait`, `rc.lua.bak`).
3. Runs the pre-deploy snapshot from `~/git/github/somewm/plans/scripts/somewm-snapshot.sh`
   if available (silently skipped otherwise).

Dry run before applying:
```bash
./deploy.sh --dry-run
```

---

## 5. Deploy somewm-shell (Quickshell)

```bash
cd ~/git/github/somewm-shell
./deploy.sh
```

What this does:
1. Creates `~/.config/quickshell/somewm/`.
2. `rsync` the repo there, excluding `deploy.sh`, `.git`, `LICENSE`, `CLAUDE.md`,
   and `*.default.json`.
3. Seeds `*.default.json → *.json` only if the target does not exist (preserves
   in-app user edits).
4. Seeds `~/.config/somewm/themes/default/theme.json` from `theme.default.json`
   if missing, so the QS Theme singleton has real colors on first run.

Dry run:
```bash
./deploy.sh --dry-run
```

---

## 6. First launch

From a TTY (Ctrl+Alt+F2 if currently in a graphical session):

```bash
~/git/github/somewm/plans/scripts/start.sh
```

What `start.sh` does:
1. Rotates `~/.local/log/somewm-debug.log` (keeps last 5).
2. Kills orphaned `qs -c somewm` processes and clears stale Quickshell runtime
   dirs from a previous crash.
3. Clears `~/.cache/quickshell/qmlcache`.
4. Exports `LD_LIBRARY_PATH=/usr/local/lib` if not already there.
5. Imports session env (DISPLAY, WAYLAND_DISPLAY, XDG_*, SSH_AUTH_SOCK) into
   the systemd user bus.
6. Spawns a 5s-interval RSS/CPU/GPU/FD watchdog into `~/.local/log/somewm-stats.log`.
7. `exec somewm -d 2>&1 | tee ~/.local/log/somewm-debug.log`.

The `-d` flag enables debug-level logging (overrides `WLR_LOG`).

---

## 7. Update workflow (existing install)

When called with "please update all three projects":

```bash
# 0. One-time, on a checkout that still has the v1 main: on 2026-10-24
#    origin/main was replaced by the v2 line (v1 lives on as legacy/v1), so
#    a plain `git pull` would try to merge the two lines. Switch with the
#    checked script in plans/v2/nvidia-test-plan.md, phase A (backup branch,
#    refuses to drop local commits). Only after that does `git pull` work.

# 1. Pull all three
cd ~/git/github/somewm        && git pull origin main
cd ~/git/github/somewm-one    && git pull origin main
cd ~/git/github/somewm-shell  && git pull origin main

# 2. Rebuild + reinstall the compositor
cd ~/git/github/somewm
./plans/scripts/install.sh

# 3. Deploy the configs
cd ~/git/github/somewm-one    && ./deploy.sh
cd ~/git/github/somewm-shell  && ./deploy.sh

# 4a. If step 2 installed a new compositor: log out to the TTY and run
#     plans/scripts/start.sh. Do NOT just reload: the running binary stays
#     the old one, and on a v1 -> v2 switch a reload would load v2 Lua into
#     the v1 binary.
# 4b. Lua/QML-only changes: reload in place
somewm-client reload          # picks up rc.lua changes
pkill -u "$(id -un)" -f 'qs -c somewm' || true
qs -c somewm -n -d >/dev/null 2>&1 &   # restart the shell for QML changes
disown
```

If only `somewm-one` changed: `./deploy.sh && somewm-client reload`.
If only `somewm-shell` changed: `./deploy.sh; pkill -f 'qs -c somewm' || true; qs -c somewm -n -d &`.

For C-side compositor changes: `install.sh`, then restart the session from the
TTY (`start.sh`). Note that `somewm-client exec` spawns a shell command, it
does not replace the running compositor.

---

## 8. Update workflow without a live session (cold update)

If the box is not currently running somewm (e.g. fresh login from another DE):

On a checkout still on the v1 main, do phase A of
`plans/v2/nvidia-test-plan.md` first (see step 0 above).

```bash
cd ~/git/github/somewm        && git pull && ./plans/scripts/install.sh
cd ~/git/github/somewm-one    && git pull && ./deploy.sh
cd ~/git/github/somewm-shell  && git pull && ./deploy.sh
# Then log out, switch to TTY, and run start.sh.
```

---

## 9. Sandbox / nested test (no reboot)

For C/Lua changes that need real compositor verification but should not touch
the live session:

```bash
~/git/github/somewm/plans/scripts/somewm-sandbox.sh
# Prints SOMEWM_SOCKET and WAYLAND_DISPLAY for follow-up commands.
```

Or with isolated upstream-style config:
```bash
~/git/github/somewm/plans/scripts/somewm-sandbox.sh --test-config
```

Limitations: uses wayland backend, not DRM — does not reproduce NVIDIA timing
or DRM-format bugs. Per-sandbox cleanup is mandatory:

```bash
kill <pid_from_sandbox_output>     # its exit trap removes that sandbox's own socket
# (v2-stack-sandbox.sh: use --stop; never rm a somewm-sandbox-*.sock wildcard,
#  it would hit other running sandboxes)
```

---

## 10. Troubleshooting

**`somewm` won't start after switching lines**
```bash
~/git/github/somewm/plans/scripts/install.sh --check   # v2
# a v1 binary needs libscenefx: check out legacy/v1 and run its installer
```

**Reload of `rc.lua` does nothing after editing the somewm-one repo**
You forgot `./deploy.sh`. The repo is the source, `~/.config/somewm/` is the
deployed copy. `somewm-client reload` reads from the deployed copy.

**Quickshell shows old QML after editing somewm-shell repo**
`./deploy.sh` deploys the QML, but `qs -c somewm` keeps the old QML cached.
Restart it: `pkill -f 'qs -c somewm' || true; qs -c somewm -n -d &`.

**Nested sandbox returns "WAYLAND_DISPLAY not set"**
The script prints two sockets: `SOMEWM_SOCKET` (IPC for `somewm-client`) and
`WAYLAND_DISPLAY` (Wayland display for client apps). They are different.

**`build/` permissions broken after a manual `sudo ninja install`**
`install.sh` self-heals this on the next run by reclaiming ownership.
No manual `chown` needed.

**Memory / leak diagnostics**
```bash
~/git/github/somewm/plans/scripts/somewm-memory-snapshot.sh
~/git/github/somewm/plans/scripts/somewm-memory-trend.sh --idle 60
```

---

## 11. Files this install touches

| Path | Owner | Source |
|------|-------|--------|
| `/usr/local/bin/somewm` | system (sudo) | `install.sh` |
| `/usr/local/bin/somewm-client` | system (sudo) | `install.sh` |
| `/usr/local/share/somewm/` | system (sudo) | `install.sh` (Lua tree wiped on each install) |
| `~/.config/somewm/` | user | `somewm-one/deploy.sh` |
| `~/.config/quickshell/somewm/` | user | `somewm-shell/deploy.sh` |
| `~/.local/log/somewm-debug.log` | user | `start.sh` |
| `~/.local/log/somewm-stats.log` | user | `start.sh` watchdog |
| `~/.cache/quickshell/qmlcache/` | user | cleared by `start.sh` |

Backups created automatically:
- `~/.config/somewm/rc.lua.bak` — every `somewm-one/deploy.sh` run.
