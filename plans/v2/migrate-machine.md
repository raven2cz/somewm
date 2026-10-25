# Moving another machine from v1 to v2

Checked on r9home (RTX 4070 SUPER + AMD iGPU, CachyOS) on 2026-10-25. Run the
steps in order from a terminal in the running v1 session. Steps 1-7 change
nothing in the running session. Step 8 switches it. Commands that need sudo
are marked; run those yourself.

## 0. Before you start

- Update the system and reboot if the kernel or the NVIDIA driver changed.
  A half-finished upgrade leaves the kernel module and `nvidia-utils` on
  different versions, and new GL processes then fail.
  ```bash
  sudo pacman -Syu        # or paru -Syu
  cat /proc/driver/nvidia/version; pacman -Q nvidia-utils   # same version
  ```
- Write down the rollback reference:
  `ls -l /usr/local/bin/somewm*; ls /usr/local/lib | grep -i scenefx`.

## 1. Switch the three checkouts to v2

`origin/main` is the v2 line; v1 lives on `legacy/v1`. A plain `git pull`
would merge the two lines. Use this script instead. It refuses to drop
local commits, keeps the old main as a backup branch, and is safe to re-run:
```bash
set -euo pipefail
REPOS="somewm somewm-one somewm-shell"
STAMP=$(date +%Y%m%d-%H%M%S)
for r in $REPOS; do
  R=~/git/github/$r
  test -z "$(git -C $R status --porcelain)" || { echo "$r: uncommitted changes: STOP"; exit 1; }
  git -C $R fetch origin --tags
  extra=$(git -C $R log --oneline main --not origin/legacy/v1 origin/main)
  [ -z "$extra" ] || { echo "$r: local commits on neither line:"; echo "$extra"; exit 1; }
done
for r in $REPOS; do
  R=~/git/github/$r
  if [ "$(git -C $R rev-parse main)" != "$(git -C $R rev-parse origin/main)" ]; then
    git -C $R branch "backup/pre-v2-main-$STAMP" main
    git -C $R checkout -q main
    git -C $R reset --hard origin/main
  fi
  git -C $R branch -f legacy/v1 origin/legacy/v1
  git -C $R log --oneline -1
done
```

## 2. Quickshell from the AUR (sudo)

```bash
paru -S aur/quickshell-git
qs --version        # must say "distributed by AUR (package: quickshell-git)"
```
Keep the `aur/` prefix. Without it, `paru -S quickshell-git` let pacman
install the cachyos repo package `noctalia-qs`, which declares
`Provides: quickshell-git` and was built for an older Qt.
`quickshell-git` uses Qt's private API, so after every Qt upgrade it
fails to start (`symbol lookup error ... Qt_6_PRIVATE_API`). Rebuild it
with the same command after each Qt upgrade.

## 3. Build and install the compositor (sudo inside the script)

```bash
~/git/github/somewm/plans/scripts/install.sh
~/git/github/somewm/plans/scripts/install.sh --check     # "All good", no libscenefx
```
The script moves v1 leftovers aside. It moves the ignored
`subprojects/wlroots-0.20` and `scenefx*` trees to
`~/.cache/somewm-v1-subprojects/`; they break meson with "Multiple wrap
files provide wlroots-0.20". It also deletes the v1 `build/` tree and
removes `libscenefx` from `/usr/local`.

## 4. GPU selection (only on machines with more than one GPU)

wlroots composites on the first DRM device. If that is an iGPU and the
monitors hang on the NVIDIA card, every frame is copied across GPUs. GL
clients may also render on the iGPU. Find the card that drives the
monitors:
```bash
for c in /sys/class/drm/card*-*; do [ "$(cat $c/status)" = connected ] && echo "$c -> $(basename $(readlink -f $c/device/device))"; done
```
`WLR_DRM_DEVICES` is ':'-separated, so `/dev/dri/by-path/pci-…` cannot be
used. Create a stable symlink instead. Use the PCI address printed above
(here `0000:01:00.0`). sudo:
```bash
echo 'SUBSYSTEM=="drm", KERNEL=="card[0-9]*", KERNELS=="0000:01:00.0", SYMLINK+="dri/nvidia-card"' \
  | sudo tee /etc/udev/rules.d/61-somewm-nvidia-card.rules
sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=drm
sleep 1; ls -l /dev/dri/nvidia-card
```

## 5. Session environment

`~/.config/environment.d/50-somewm.conf` is read by `somewm-session`
(the session-launcher path) and, since e20152b, by `plans/scripts/start.sh`.
Check these lines:
```
XDG_CURRENT_DESKTOP=somewm            # not "wlroots": somewm.portal has UseIn=somewm (screen sharing)
WLR_DRM_DEVICES=/dev/dri/nvidia-card  # only with step 4
# NVIDIA
LIBVA_DRIVER_NAME=nvidia
__GLX_VENDOR_LIBRARY_NAME=nvidia
GBM_BACKEND=nvidia-drm
WLR_NO_HARDWARE_CURSORS=1             # v1 workaround, still set on r9home
```
If the symlink is missing, start.sh drops `WLR_DRM_DEVICES` with a warning
and starts anyway. The systemd path does not have that fallback. If the
session then fails to start, remove the line from a TTY.

## 6. Configs

```bash
(cd ~/git/github/somewm-one && ./deploy.sh)
(cd ~/git/github/somewm-shell && ./deploy.sh)
somewm -k ~/.config/somewm/rc.lua     # "No compatibility issues found"
```

## 7. Session launcher

```bash
diff /usr/local/bin/somewm-session ~/git/github/somewm/contrib/systemd/somewm-session.sh && echo wrapper ok
systemctl --user daemon-reload
systemctl --user show somewm.service -p ExecStart | grep -o '/usr/local/bin/somewm'
```
`~/bin/session-launcher` → `somewm-session` → `somewm.service` →
`/usr/local/bin/somewm`. Logs: `journalctl --user -u somewm` (no `-d`).
`plans/scripts/start.sh` runs `somewm -d` and logs to
`~/.local/log/somewm-debug.log`.

## 8. Switch

Do **not** run `somewm-client reload` in the old session; it would load the
v2 Lua into the v1 binary. Log out to a TTY and start with `start.sh` or
the session launcher. Then check:
```bash
grep -E 'KMS devices|GL renderer' ~/.local/log/somewm-debug.log | head -3   # NVIDIA
pgrep -a qs                      # Quickshell started by rc.lua
somewm-client eval 'return awesome.version'
```

## Rollback

See [nvidia-test-plan.md](nvidia-test-plan.md), "Rollback to v1". Put the
moved trees back from `~/.cache/somewm-v1-subprojects/` into
`subprojects/` if `install-scenefx.sh` needs them, and remove the
`WLR_DRM_DEVICES` line if v1 should keep its old GPU choice.
