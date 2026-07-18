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
    libinput libdrm libgbm mesa vulkan-icd-loader \
    pixman cairo pango \
    lua51 luajit lua51-lgi \
    xorg-xwayland \
    libliftoff libdisplay-info \
    seatd

# Quickshell (somewm-shell runtime)
sudo pacman -S --needed quickshell qt6-base qt6-declarative qt6-svg

# Optional but recommended for sessions / D-Bus integration
sudo pacman -S --needed dbus-broker xdg-desktop-portal-wlr polkit gnome-keyring

# IPC client (somewm-client)
sudo pacman -S --needed somewm   # if available, otherwise built from source below
```

If `somewm` is not in pacman/AUR, the `somewm-client` binary is built and
installed by `install-scenefx.sh` together with the compositor.

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

## 3. Build & install somewm (with SceneFX)

```bash
cd ~/git/github/somewm
./plans/scripts/install-scenefx.sh
```

What this does:
1. Configures meson into `build-fx/` with `-Dscenefx=enabled`.
2. Builds with ninja.
3. Installs to `/usr/local` (sudo).
4. Adds `/usr/local/lib` to `/etc/ld.so.conf.d/local.conf` if missing.
5. Runs `ldconfig` so the linker finds `libscenefx-0.4.so`.
6. Verifies `/usr/local/bin/somewm` resolves all libraries.

Verify after install:
```bash
./plans/scripts/install-scenefx.sh --check
which somewm                # /usr/local/bin/somewm
which somewm-client         # /usr/local/bin/somewm-client
ldconfig -p | grep scenefx  # libscenefx-0.4.so registered
```

**Never** use plain `sudo make install` here — that uses the ASAN dev build
without SceneFX and skips the ldconfig step.

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
# 1. Pull all three
cd ~/git/github/somewm        && git pull origin main
cd ~/git/github/somewm-one    && git pull origin main
cd ~/git/github/somewm-shell  && git pull origin main

# 2. Rebuild + reinstall the compositor
cd ~/git/github/somewm
./plans/scripts/install-scenefx.sh

# 3. Deploy the configs
cd ~/git/github/somewm-one    && ./deploy.sh
cd ~/git/github/somewm-shell  && ./deploy.sh

# 4. Reload the live session (if somewm is running)
somewm-client reload          # picks up rc.lua changes
pkill -u "$(id -un)" -f 'qs -c somewm'
qs -c somewm &                # restart the shell to pick up QML changes
disown
```

If only `somewm-one` changed: `./deploy.sh && somewm-client reload`.
If only `somewm-shell` changed: `./deploy.sh && pkill -f 'qs -c somewm' && qs -c somewm &`.

For C-side compositor changes: `install-scenefx.sh` then either
`somewm-client exec somewm` to hot-swap the binary in place (Wayland-only,
careful — replaces the running process) or full reboot for DRM-backend changes.

---

## 8. Update workflow without a live session (cold update)

If the box is not currently running somewm (e.g. fresh login from another DE):

```bash
cd ~/git/github/somewm        && git pull && ./plans/scripts/install-scenefx.sh
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
kill <pid_from_sandbox_output>
rm -f /run/user/$(id -u)/somewm-sandbox-*.sock
```

---

## 10. Troubleshooting

**`somewm` won't start, libscenefx not found**
```bash
~/git/github/somewm/plans/scripts/install-scenefx.sh --check
sudo ldconfig
```

**Reload of `rc.lua` does nothing after editing the somewm-one repo**
You forgot `./deploy.sh`. The repo is the source, `~/.config/somewm/` is the
deployed copy. `somewm-client reload` reads from the deployed copy.

**Quickshell shows old QML after editing somewm-shell repo**
`./deploy.sh` deploys the QML, but `qs -c somewm` keeps the old QML cached.
Restart it: `pkill -f 'qs -c somewm' && qs -c somewm &`.

**Nested sandbox returns "WAYLAND_DISPLAY not set"**
The script prints two sockets: `SOMEWM_SOCKET` (IPC for `somewm-client`) and
`WAYLAND_DISPLAY` (Wayland display for client apps). They are different.

**`build-fx/` permissions broken after a manual `sudo ninja install`**
`install-scenefx.sh` self-heals this on the next run by reclaiming ownership.
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
| `/usr/local/bin/somewm` | system (sudo) | `install-scenefx.sh` |
| `/usr/local/bin/somewm-client` | system (sudo) | `install-scenefx.sh` |
| `/usr/local/lib/libscenefx-0.4.so` | system (sudo) | `install-scenefx.sh` |
| `/etc/ld.so.conf.d/local.conf` | system (sudo) | `install-scenefx.sh` |
| `~/.config/somewm/` | user | `somewm-one/deploy.sh` |
| `~/.config/quickshell/somewm/` | user | `somewm-shell/deploy.sh` |
| `~/.local/log/somewm-debug.log` | user | `start.sh` |
| `~/.local/log/somewm-stats.log` | user | `start.sh` watchdog |
| `~/.cache/quickshell/qmlcache/` | user | cleared by `start.sh` |

Backups created automatically:
- `~/.config/somewm/rc.lua.bak` — every `somewm-one/deploy.sh` run.
