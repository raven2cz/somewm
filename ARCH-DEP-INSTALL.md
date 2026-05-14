# ARCH-DEP-INSTALL — Workstation environment around somewm

This document describes the Arch Linux environment the maintainer (Antonin
Fischer / raven2cz) runs `somewm` inside. It is the supporting cast: the
notification daemon, audio stack, portals, keyring, applets, themes, fonts,
applications, and the WHY/WHERE of each setting that is not in
[INSTALL.md](INSTALL.md) and not derivable from the dotfiles repo.

Audience: future-me and AI agents asked to replicate the setup on a new
workstation, not just the compositor.

Scope boundary:
- [INSTALL.md](INSTALL.md): the three somewm repos themselves.
- This file: everything around them — system packages, user services,
  daemons, themes, app choices, integrations.
- Dotfiles repo (separate): per-app config files. This file says *which* apps
  exist and *why* they were picked, not how each one is themed.

---

## 1. Base system

| Layer | Choice | Why |
|-------|--------|-----|
| Distro | Arch Linux (rolling) | Closest match for tracking wlroots/wayland-protocols/quickshell HEAD without backporting hell. |
| Kernel | `linux` (currently 7.0.2-arch1-1) | Default, no patched kernel needed. |
| Bootloader | GRUB | Pre-existing on the box. Cmdline carries `video=DP-4:3840x2160@144` to force the 4K/144Hz primary mode at boot, before any compositor runs. |
| GPU driver | `nvidia-open` 595.x + `nvidia-utils` + `nvidia-settings` + `libva-nvidia-driver` + `nvidia-container-toolkit` | RTX 5070 Ti needs NVIDIA proprietary stack; open kernel modules + closed userspace is the supported combo for Turing+. |
| DRM modeset | `/etc/modprobe.d/nvidia.conf` → `nvidia_drm modeset=1`, `fbdev=1`, `NVreg_UsePageAttributeTable=1` | `modeset=1` is mandatory for wlroots on NVIDIA. `fbdev=1` gives a console framebuffer post-init. PAT improves write-combining performance. |
| Init | systemd | Default. somewm runs as a user-level systemd unit (`somewm.service`). |

Enabled system services (`systemctl list-unit-files --state=enabled`):

| Service | Why |
|---------|-----|
| `seatd.service` | Session/seat management for non-DM TTY launches. wlroots uses it instead of logind seat0 directly when available. |
| `NetworkManager.service` + `NetworkManager-dispatcher.service` + `NetworkManager-wait-online.service` | Network. `nm-applet` in user session talks to it. |
| `bluetooth.service` | Bluetooth audio + peripherals. `blueman-applet` is the GUI front-end. |
| `cups.service` + `cups.socket` + `avahi-daemon.service` + `avahi-daemon.socket` | Printing (Brother DCP-T525W via `brother-dcpt525w` AUR + `brscan5` for the scanner). Avahi is needed for IPP printer discovery. |
| `sshd.service` | Remote shell access. |
| `ntpd.service` + `ntpdate.service` | Clock. |
| `docker.service` | Container workloads. |
| `rpcbind.service` | NFS access (Synology NAS reachable over NFS). |

**No display manager runs as the active session-launcher.** `nody-greeter`
(LightDM-based) is installed but the working session is launched from TTY1
via `~/git/github/somewm/plans/scripts/start.sh` per [CLAUDE.md](CLAUDE.md).
The `/usr/share/wayland-sessions/somewm-nvidia.desktop` entry exists for
the day a DM launch becomes reliable, and points at `/usr/local/bin/start-somewm`,
which exports the NVIDIA env and execs `somewm`.

---

## 2. Wayland session glue

These are the user-level services that need to be alive before or alongside
`somewm` for a "feels like a desktop" experience.

### 2.1 D-Bus + session bus

- **`dbus-broker`** is the active D-Bus daemon (faster, cgroup-aware
  alternative to dbus-daemon). Comes from `dbus-broker-units` package.
  All session services and portals depend on it.

### 2.2 PipeWire audio stack

Installed packages: `pipewire`, `pipewire-pulse`, `pipewire-alsa`,
`pipewire-jack`, `wireplumber`, `alsa-utils`, `pulseaudio-alsa` (compat
shim), `xfce4-pulseaudio-plugin`, `volctl` (AUR).

- `pipewire.socket` + `pipewire-pulse.socket` + `wireplumber.service` are
  enabled at the user level. Auto-start on first client.
- `volctl` is the tray volume widget consumed by somewm-shell when no
  PipeWire-native widget is available.
- `playerctl` (CLI) drives MPRIS commands from keybindings (`Super+P` etc.).
- No PulseAudio daemon — `pipewire-pulse` is the PA replacement.

### 2.3 Bluetooth

- `bluez` + `bluez-utils` + `blueman` (GTK frontend) + `obex.service` (file
  transfer). `blueman-applet` autostarts in `rc.lua` after `ready::tray`.
- `bt-headphones` script in `~/bin` toggles the daily Bluetooth audio
  device.

### 2.4 Networking

- `NetworkManager` system service + `nm-applet` GUI launched by `rc.lua`
  autostart. nm-applet provides the system tray status icon and menu;
  command-line work via `nmcli`.

### 2.5 Polkit + keyring + secrets

- **`polkit`** + **`polkit-gnome`**: GTK3 polkit agent autostarts via
  `rc.lua` (`/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1`).
  GNOME variant chosen because it has zero GNOME-session deps and works
  cleanly outside Plasma/GNOME.
- **`gnome-keyring`** + `seahorse` GUI: provides the SSH agent socket
  (`SSH_AUTH_SOCK=/run/user/1000/gcr/ssh`, served by `gcr-ssh-agent`)
  and the libsecret backend. Enabled sockets:
  `gnome-keyring-daemon.socket`, `gcr-ssh-agent.socket`, `p11-kit-server.socket`.
- The keyring is unlocked at login via PAM (`pam_gnome_keyring.so` in
  `/etc/pam.d/login`); confirm with `pam-config -a` after a fresh install.

### 2.6 XDG portals

Both portals are installed because their feature surfaces complement each
other:

- **`xdg-desktop-portal-gnome`**: file chooser, secret service, account,
  inhibit. Most GTK / Electron / Chromium apps end up using this one.
- **`xdg-desktop-portal-wlr`**: screencast and screenshot for wlroots
  compositors (used by OBS, Discord, browser screen-share). Without it,
  Chromium-based apps cannot see your screen on a wlroots compositor.
- The portal frontend (`xdg-desktop-portal.service`) auto-selects backends
  per interface based on `XDG_CURRENT_DESKTOP=wlroots` (set in
  `~/.config/environment.d/50-somewm.conf`).

### 2.7 KDE Frameworks 6 helpers (for KIO-based apps)

`kded6` and `kactivitymanagerd` autostart from `rc.lua`. Without them,
Dolphin / Kate / Okular cannot reach the activity manager or on-demand
kded plugins (solid storage, kpasswdserver, network-status). The full
`kde-applications-meta` and `plasma-meta` packages are installed as the
underlying libraries — but the Plasma shell itself never runs; somewm is
the compositor.

### 2.8 Notifications

- **`mako`** is the active notification daemon for somewm. Quickshell talks
  to it via the org.freedesktop.Notifications D-Bus interface.
- **`dunst`** is installed but unused — left in place as a fallback for
  bisecting notification rendering bugs.
- `xfce4-notifyd.desktop` exists in `/etc/xdg/autostart/` from the XFCE
  install but is not enabled in the somewm session.
- `naughty` (AwesomeWM Lua notification stack) is wired through the shell
  per the somewm-one rc.lua and renders via QML rather than its native
  popup window.

### 2.9 Clipboard

- `wl-clipboard` (`wl-copy` / `wl-paste`) — Wayland-native CLI.
- `parcellite` + `clipmenu` — long history + dmenu-style picker. Both
  start through `/etc/xdg/autostart/`.

### 2.10 Caffeine / idle inhibit

- `caffeine-ng` (AUR) — tray-driven idle inhibitor. Honored by the somewm
  idle/lock pipeline (`swayidle` + `swaylock` are installed as fallbacks
  even though somewm-shell ships its own lock).

---

## 3. Display manager / session entry

Currently TTY-only:

```bash
~/git/github/somewm/plans/scripts/start.sh
```

What the maintainer actually does:

1. Boot lands on TTY1.
2. Login as `box`.
3. `start.sh` runs the wrapper described in [INSTALL.md §6](INSTALL.md#6-first-launch).

For the day DM launch is wanted again:

- `nody-greeter` (AUR) is the LightDM theme that has been stable on this
  hardware historically. Switch with `sudo systemctl enable lightdm.service`
  (after installing `lightdm` + `nody-greeter`).
- `/usr/share/wayland-sessions/somewm-nvidia.desktop` already lists the
  session.
- `/usr/local/bin/start-somewm` exports the NVIDIA env (LIBVA, GLX,
  GBM_BACKEND, WLR_NO_HARDWARE_CURSORS) and execs `somewm`. Logs to
  `~/.local/log/somewm-session.log`.

---

## 4. Environment variables

`~/.config/environment.d/50-somewm.conf` — read by systemd at user-session
start. Anything that needs to be present before `somewm.service` starts goes
here, not in `~/.bashrc`.

```ini
XDG_SESSION_TYPE=wayland
XDG_CURRENT_DESKTOP=wlroots
DESKTOP_SESSION=somewm

XDG_CONFIG_HOME=${HOME}/.config
XDG_CACHE_HOME=${HOME}/.cache

# NVIDIA on wlroots
LIBVA_DRIVER_NAME=nvidia
__GLX_VENDOR_LIBRARY_NAME=nvidia
GBM_BACKEND=nvidia-drm
WLR_NO_HARDWARE_CURSORS=1

# Qt — render with kvantum/qt6ct, no client-side decoration on Wayland
QT_QPA_PLATFORMTHEME=qt6ct
QT_WAYLAND_DISABLE_WINDOWDECORATION=1

EDITOR=lvim
JAVA_HOME=/usr/lib/jvm/default
```

`~/.config/environment.d/10-user-path.conf` prepends `~/bin` and
`~/.local/bin` to `PATH`.

Why `XDG_CURRENT_DESKTOP=wlroots` (not `somewm`):
- Portals and a few apps key off this string. `wlroots` is the recognized
  identifier that selects `xdg-desktop-portal-wlr` for screencast.
  Setting it to `somewm` would skip wlr backend selection.

---

## 5. Themes and fonts

### 5.1 GTK 3/4

`~/.config/gtk-3.0/settings.ini` and `gtk-4.0/settings.ini`:

| Key | Value | Why |
|-----|-------|-----|
| `gtk-application-prefer-dark-theme` | `true` | Dark by default everywhere. |
| `gtk-theme-name` | `Pop-dark` | From `pop-theme` AUR. Plays well with Papirus icons and Oxygen_White cursor on hi-DPI. |
| `gtk-icon-theme-name` | `Papirus-Dark` | `papirus-icon-theme` package. |
| `gtk-cursor-theme-name` | `Oxygen_White` | `oxygen-icons` package. White cursor is more visible on dark themes than the default Adwaita arrow. |
| `gtk-cursor-theme-size` | `24` | Tuned for 4K / 144 DPI displays. |
| `gtk-font-name` | `Noto Sans, 10` | Default. |
| `gtk-xft-dpi` | `142540` | High-DPI (the 1024×DPI integer encoding; 142540/1024 ≈ 139 DPI for the 4K primary). Keep in sync with monitor swaps. |

`~/.icons/default/index.theme` → inherits `Oxygen_White` (cursor only).

### 5.2 Qt 5/6

`~/.config/qt6ct/qt6ct.conf`:

- `style=kvantum` — global Kvantum style engine (`kvantum-qt5` +
  `kvantum-qt6` packages).
- `icon_theme=Papirus-Dark`, `color_scheme_path=.../darker.conf`,
  `standard_dialogs=kde`.
- Fixed font: Hack 12. General: Noto Sans 12.

`QT_QPA_PLATFORMTHEME=qt6ct` is the env var that makes Qt6 actually pick
this up; without it, Qt apps render Adwaita.

### 5.3 Fonts

Heavy Nerd Fonts coverage from AUR (`ttf-*-nerd`, `otf-*-nerd`) — used by
the terminals (Hack, Iosevka, JetBrains Mono, Cascadia) and by the
Quickshell shell (icon glyphs in panels and dashboard).

Notable extras:
- `ttf-google-fonts-git` — full Google Fonts catalog for design work.
- `ttf-ms-fonts` — Microsoft fonts for cross-platform document fidelity.
- `ttf-merriweather`, `ttf-merriweather-sans`, `ttf-oswald`, `ttf-roboto-slab`,
  `ttf-rubik-vf`, `ttf-signika`, `ttf-quintessential` — picked manually
  for specific design tasks; safe to install when missing.

---

## 6. Applications inventory

The maintainer uses a deliberately broad app set across several stacks
(GTK, Qt, Electron, JetBrains, KDE PIM). Replicating means installing the
list below; configuration lives in the dotfiles repo, not here.

### 6.1 Browsers

| Package | Source | Why |
|---------|--------|-----|
| `firefox-developer-edition` | repo | Default browser (set in `~/.config/mimeapps.list` for `text/html`, `http`, `https`). |
| `brave-bin` | AUR | Privacy-focused secondary, ad-block by default. |
| `google-chrome` | AUR | DRM-licensed media (Netflix, Disney+) and Google-stack site testing. |
| `firefox` (vanilla) | repo | Optional — keep Developer Edition only if disk space tight. |

### 6.2 Editors / IDEs

| Package | Source | Why |
|---------|--------|-----|
| `lvim` (LunarVim, on top of `neovim`) | AUR-style install | Default `EDITOR`. |
| `sublime-text-4` | AUR | Quick file/diff opens (`subl <path>`). |
| `visual-studio-code-bin` | AUR | Long-form coding, extensions ecosystem. |
| `webstorm` | AUR | JS/TS work. |
| `jetbrains-toolbox` | AUR | Manages WebStorm / IntelliJ / DataGrip / Rider updates. Autostarts via `/etc/xdg/autostart/jetbrains-toolbox.desktop`. |
| `kate` (from `kde-applications-meta`) | repo | Quick-edit GUI. |
| `gnome-text-editor` | repo | Lightweight fallback. |

### 6.3 Terminals

| Package | Why |
|---------|-----|
| `alacritty` | Default per [CLAUDE.md](CLAUDE.md). GPU-accelerated, minimal. |
| `ghostty` | Newer, used for shader/animation experiments. **Beware:** `custom-shader-animation = true` causes 120 FPS GPU burn — see memory `project_ghostty_shader_gpu`. |
| `gnome-terminal` | Fallback. |
| `xfce4-terminal` | Fallback. |

### 6.4 Media / image / video

| Package | Source | Why |
|---------|--------|-----|
| `mpv` | repo | Default for `video/mp4`, `video/x-matroska`. |
| `vlc` | repo | Fallback for codecs mpv won't touch. |
| `qimgv-git` | AUR | Default for `image/png`. Fast, swipeable. |
| `feh` | repo | CLI/scripted image viewing. |
| `gimp` | repo | Raster editing. |
| `inkscape` | repo | Vector. |
| `simplescreenrecorder` | AUR | Screen recording (X11; for Wayland-native use OBS). |
| `flameshot` | repo | Screenshot annotation (X11/XWayland mode). |
| `ksnip` | repo | Wayland-native screenshot via portal. |

### 6.5 Audio / music

| Package | Source | Why |
|---------|--------|-----|
| `spotify` + `spotify-launcher` | AUR | Music. |
| `foobar2000` | AUR (Wine wrapper) | Local music library. |
| `playerctl` | repo | MPRIS CLI for keybindings. |
| `cava` | repo | Audio visualizer for the shell. |

### 6.6 Productivity / cloud / mail

| Package | Source | Why |
|---------|--------|-----|
| `obsidian` | AUR | Notes (default for `obsidian://`). |
| `marktext-bin` | AUR | Markdown editor. |
| `synology-drive` | AUR | Sync to home NAS. Autostarts via `rc.lua` (`when = ready::xwayland`, `mode = oneshot` because the launcher forks daemons and exits). MIME defaults for `application/x-synology-drive-{doc,sheet,slides}` route to `synology-drive-open-file.desktop`. |
| `libreoffice-fresh` | repo | Documents. |
| `geary` | repo | Lightweight mail client. |
| `kde-applications-meta` | repo | Pulls in Akonadi/Kontact PIM stack — used selectively. |
| `dolphin` (via `kde-applications-meta`) | repo | File manager. KIO requires `kded6` + `kactivitymanagerd` (autostarted). |

### 6.7 Download / sharing

| Package | Source | Why |
|---------|--------|-----|
| `jdownloader2` | AUR | Bulk file downloads, captcha/relink handling. |
| `kdeconnect` (via KDE meta) | repo | Phone integration. |
| `remmina` | repo | RDP/VNC client. `remmina-applet.desktop` in autostart. |

### 6.8 Containers / virtualization

| Package | Why |
|---------|-----|
| `docker` + `docker-buildx` + `docker-compose` | Default container stack. |
| `nvidia-container-toolkit` | Pass NVIDIA GPU into containers (CUDA workloads). |

### 6.9 AI tooling

| Package | Source | Why |
|---------|--------|-----|
| `claude-code` | AUR | Claude CLI (this assistant). MIME handler for `claude-cli://` URLs. |
| `codex` | external (Node) | OpenAI Codex CLI — used for cross-model code review per [CLAUDE.md](CLAUDE.md). |
| `gemini` | external (Node) | Google Gemini CLI — used for cross-model code review per [CLAUDE.md](CLAUDE.md). |
| `ccusage` | AUR | Claude usage / billing tracker. |

### 6.10 AUR helpers

| Package | Why |
|---------|-----|
| `paru-git` | Primary AUR helper. |
| `aurutils` | Local repo / batch builds. |
| `downgrade` | Roll back broken updates. |
| `checkupdates-with-aur` | Update notifier (drives `aurupdates-notify.sh` in `~/bin`). |
| `aur-malware-check.sh` (`~/bin`) | Scans staged AUR PKGBUILDs for known malware patterns before build. |

### 6.11 Other utilities

- `caffeine-ng` — idle inhibit applet.
- `parcellite` + `clipmenu` — clipboard.
- `nm-applet` (`network-manager-applet`) — tray network.
- `blueman-applet` — tray Bluetooth.
- `volctl` — tray volume.
- `conky-lua-nv` — desktop info widget (NVIDIA GPU sensor support).
- `picom-git` — only for occasional X11 sessions; never used inside somewm.
- `grub-customizer` — boot menu tweaks.
- `dconf-editor` — GSettings GUI.

---

## 7. `~/bin` and `~/.local/bin` scripts

Custom maintainer scripts that the somewm session expects. These are
maintained in the **dotfiles repo** (separate from this somewm checkout)
and symlinked into `~/bin` / `~/.local/bin` by the dotfiles `init-env-dotfiles.sh`.

Highlights worth knowing about when bringing a new box up:

| Script | Path | Purpose |
|--------|------|---------|
| `init-env-dotfiles.sh` | `~/bin` | Bootstraps the dotfiles checkout into `$HOME` (run once on a fresh user). |
| `init-git-subtrees-dotfiles.sh` | `~/bin` | Adds the dotfiles git subtrees. |
| `pull-all-repos-update.sh` | `~/bin` | Pulls every tracked git repo under `~/git`. |
| `pull-git-subtrees-dotfiles.sh` | `~/bin` | Refresh all dotfile subtrees. |
| `aurupdates.sh` + `aurupdates-notify.sh` | `~/bin` | Periodic AUR update check + libnotify popup. |
| `aur-malware-check.sh` | `~/bin` | Pre-build PKGBUILD safety scan. |
| `bt-headphones` | `~/bin` | Toggle the Bluetooth headphones device. |
| `lock.sh` | `~/bin` | Calls into the somewm-shell lock (or swaylock as fallback). |
| `ghostty-setup.sh` | `~/bin` | Ghostty config bootstrap. |
| `wdisplay-switcher` / `display-switch` / `xrandr-auto.sh` | `~/bin` | Multi-monitor presets. |
| `JDownloader` | `~/bin` | Launcher wrapper. |
| `notify-trans` | `~/.local/bin` | `argos-translate` wrapper that pipes selection → translation → notification popup. Bound to a keybinding in `rc.lua`. |
| `claude` / `codex` / `gemini` | `~/.local/bin` | Symlinks/wrappers to the AI CLIs. |
| `volume` | `~/.local/bin` | PipeWire volume helper for keybindings. |
| `kernel` | `~/.local/bin` | `uname` / kernel info popup. |
| `clock` | `~/.local/bin` | Date/time popup. |
| `dwm_time` | `~/.local/bin` | Status string generator (legacy from dwm days, still consumed). |
| `memory` | `~/.local/bin` | Memory popup using `/proc/meminfo`. |
| `wall_animated_bg.sh` | `~/.local/bin` | Animated wallpaper helper (predates somewm wallpaper engine; kept for one-off uses). |

---

## 8. Multi-monitor

Per [CLAUDE.md memory](CLAUDE.md): three outputs.

| Output | Role | Notes |
|--------|------|-------|
| Primary 4K @ 144 Hz | Main work surface | Pinned with `video=DP-4:3840x2160@144` on the kernel cmdline. |
| Samsung TV | Secondary | Hot-pluggable; surfaces multi-screen bugs (see memory `project_multimonitor_samsung`). |
| HP portrait | Rotated 90° left | First-class portrait support is a somewm feature (memory `project_monitor_hp_portrait`). |

Per-monitor wallpaper, tag layout, and panel placement live in the
`somewm-one` rc.lua, not here.

---

## 9. Reinstall checklist (TL;DR)

For a fresh Arch box where you want this exact environment:

1. Pacstrap a base Arch with `linux`, `base`, `base-devel`, `nvidia-open`,
   `grub`, `networkmanager`, `pipewire`, `pipewire-pulse`, `wireplumber`,
   `bluez`, `cups`, `seatd`, `dbus-broker-units`.
2. Add `/etc/modprobe.d/nvidia.conf` (modeset/fbdev/PAT) and rebuild initramfs.
3. Install `paru-git` from AUR.
4. Install all explicit packages from this file's tables (group install
   via `paru -S --needed <list>`).
5. Enable system services: `seatd`, `NetworkManager`, `bluetooth`, `cups`,
   `avahi-daemon`, `sshd`, `ntpd`, `docker` if needed.
6. Enable user sockets: `pipewire.socket`, `pipewire-pulse.socket`,
   `wireplumber.service`, `gnome-keyring-daemon.socket`,
   `gcr-ssh-agent.socket`, `p11-kit-server.socket`,
   `xdg-user-dirs.service`.
7. Run the dotfiles bootstrap (`~/bin/init-env-dotfiles.sh` from the
   dotfiles repo) to populate `~/.config/{gtk-3.0,gtk-4.0,qt6ct,...}`,
   `~/bin`, `~/.local/bin`, `~/.config/environment.d/`, `~/.ssh/config`,
   `~/.gnupg/`.
8. Follow [INSTALL.md](INSTALL.md) for the somewm + somewm-one + somewm-shell
   stack itself.
9. Reboot, log in on TTY1, run `start.sh`.

If anything in this document drifts from reality on the live box, **the
live box wins** — update this file, do not pretend it is current.
