# QS Memory + Storage detail panels

Feature plan for two new Quickshell overlay panels, triggered from both the
Performance tab (gear button on the Memory/Storage `GaugeCard`) and from the
Lua wibar (left-click on the `memory` / `disk` widgets).

- **Memory detail panel** — what eats how much, PSS-aware per-process
  breakdown, system "free" reality check, somewm-internal counters from
  `root.memory_stats()` + wallpaper cache.
- **Storage detail panel** — biggest directories / files, pacman cache,
  mount-by-mount pressure, "one-click" cleanups, escape hatch to `baobab` /
  `filelight`.

Both panels follow the existing `WeatherPanel.qml` overlay pattern
(`WlrLayershell` + `Core.Panels` toggle + `GlassCard`), so they inherit the
same focus / scroll-guard / multi-monitor handling with no compositor
changes.

---

## 1. Goals and non-goals

**Goals**

1. One-click access from two places per widget:
   - Cog/gear button at the top-right of the matching `GaugeCard` in the
     Performance tab of the dashboard.
   - Left-click on the Lua wibar widget (`components/memory.lua`,
     `components/disk.lua`).
2. "Graphically beautiful" — consistent with the existing glass/gauge
   language, not a raw table. Use the same `GlassCard` / `StyledText` /
   `ArcGauge` / `Anim` primitives already in use in `PerformanceTab.qml`.
3. Memory panel explains the gap between the wibar number ("9.4 GB plno")
   and the somewm process footprint (~1.3 GiB). Answers "kolik fyzicky je
   volno" honestly.
4. Storage panel gives actionable numbers for the common Arch pain points:
   pacman cache, home dir, largest files — without re-implementing what
   `baobab` / `filelight` already do well.
5. Lazy-by-default: no poll work happens unless the detail panel is open
   (same pattern as `SystemStats.perfTabActive`).
6. No new compositor-side C/Lua API. Everything reuses the `root.*` tables
   that already landed in `9052323` / `3140a4b` / `bf89f78`.

**Non-goals**

- Not replacing `baobab` / `filelight` / `btop`. The panel is a *launcher
  + summary*, not a full tree explorer.
- Not adding write/delete operations beyond the single explicitly-named
  pacman-cache action (`paccache -r` dry-run preview, then real run on
  second click).
- Not adding CLI flags or fork-only IPC. The compositor surface stays the
  same.
- Not a performance optimizer. User explicitly said: "ja nechci nic
  uvolnovat, jenom chci mit predstavu". We present numbers, the user
  decides.

---

## 2. Architecture at a glance

```
┌────────────────────────────────────────────────────────────────────┐
│  TRIGGERS                                                          │
│  ┌──────────────────────────┐    ┌───────────────────────────────┐ │
│  │ PerformanceTab.qml       │    │ fishlive/components/          │ │
│  │   Memory GaugeCard  [⚙]──┼──┐ │   memory.lua (left-click)     │ │
│  │   Storage GaugeCard [⚙]──┼─┐│ │   disk.lua   (left-click)     │ │
│  └──────────────────────────┘ ││ └───────────────────────────────┘ │
│                               ││                 │                 │
│                               ││                 │ qs ipc call     │
│                               ▼▼                 ▼                 │
│                     Core.Panels.toggle("memory-detail" / "storage-detail")
│                                              │                     │
└──────────────────────────────────────────────┼─────────────────────┘
                                               │
                     ┌─────────────────────────┴─────────────────────┐
                     │ QS overlay panels (new)                       │
                     │                                               │
                     │ modules/memory-detail/MemoryDetailPanel.qml   │
                     │ modules/storage-detail/StorageDetailPanel.qml │
                     │                                               │
                     │ Each: PanelWindow + GlassCard + sections      │
                     └────────────────┬──────────────────────────────┘
                                      │
                     ┌────────────────┴──────────────────────────┐
                     │ services/MemoryDetail.qml   (Singleton)   │
                     │ services/StorageDetail.qml  (Singleton)   │
                     │ — gated by `detailActive`, poll only when │
                     │   the owning panel is open                │
                     └───────────────────────────────────────────┘
```

No compositor changes. No new rc.lua logic except the left-click binding in
`memory.lua` / `disk.lua`.

---

## 3. Trigger wiring

### 3.1 `PerformanceTab.qml` — gear button

Current GaugeCard (lines 74–83 / 85–94 of
`plans/project/somewm-shell/modules/dashboard/PerformanceTab.qml`) has no
header actions. We add an optional trailing `Item` slot to the existing
inline `component GaugeCard: Rectangle` — specifically inside the header
`RowLayout` next to the existing icon+title — exposing:

```qml
component GaugeCard: Rectangle {
    ...
    property string detailPanel      // "" = no gear; otherwise panel name
    signal detailClicked()

    RowLayout {  // existing header row
        ...
        Components.MaterialIcon {
            visible: gaugeCard.detailPanel !== ""
            icon: "\ue8b8"  // settings cog
            size: Math.round(16 * sp)
            color: Core.Theme.fgDim
            opacity: detailMouse.containsMouse ? 1.0 : 0.6
            Behavior on opacity { Components.CAnim {} }
            MouseArea {
                id: detailMouse
                anchors.fill: parent
                anchors.margins: -4   // easier hit target
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    gaugeCard.detailClicked()
                    Core.Panels.toggle(gaugeCard.detailPanel)
                }
            }
        }
    }
}
```

Memory card sets `detailPanel: "memory-detail"`, Storage card sets
`detailPanel: "storage-detail"`. HeroCards (GPU/CPU) do not set the
property, so they stay visually unchanged.

**Rationale:** No new QML component — we extend the inline `GaugeCard`
definition that is already local to `PerformanceTab.qml`. Keeps the diff
tight and the change invisible to other dashboards.

### 3.2 Lua wibar — left-click

`fishlive/components/memory.lua` and `disk.lua` use the canonical
`wh.create_icon_text` helper, which returns a raw `wibox.widget.textbox`.
We follow the `updates.lua` pattern (lines 32–37) to attach a single
left-click:

```lua
local awful = require("awful")
local gears = require("gears")

widget:buttons(gears.table.join(
    awful.button({}, 1, function()
        awful.spawn({"qs", "ipc", "-c", "somewm", "call",
            "somewm-shell:panels", "toggle", "memory-detail"})
    end)
))
```

Same for `disk.lua` with `"storage-detail"`. We use the spawn-table form
(not the shell-quoted form) to stay safe against future panel-name changes.

**No other rc.lua changes.** The IPC target `somewm-shell:panels` already
exists in `core/Panels.qml:95`.

### 3.3 `Core.Panels` registration

Two changes to `plans/project/somewm-shell/core/Panels.qml`:

1. Add both names to the `anyOverlayOpen` scroll-guard array
   (`Panels.qml:40`) so mouse-wheel inside the detail panel does not leak
   to tag-switching:

   ```qml
   var overlays = ["dashboard", "wallpapers", "weather", "ai-chat",
                   "sidebar-left", "memory-detail", "storage-detail"]
   ```

2. Add both names to the mutual-exclusion list in `toggle()`
   (`Panels.qml:73`) so opening one auto-closes the dashboard /
   wallpapers / weather overlay. Not strictly required — `WeatherPanel`
   currently does not auto-close dashboard either — but it keeps the UX
   predictable when the user clicks the gear from inside an open
   dashboard tab.

   **Decision:** *exclusive* with dashboard overlays, so the detail panel
   fully replaces the dashboard view. The gear click looks like "zoom
   in", and Esc returns to the dashboard if we explicitly re-open it.
   Alternative is to keep them *non-exclusive* and let the detail panel
   float over the dashboard — we lean toward exclusive for less visual
   noise, but this is worth Codex feedback.

---

## 4. Memory detail panel

### 4.1 Layout (top to bottom)

All inside a single `WeatherPanel`-style `GlassCard` at fixed
`implicitWidth: 560`, `implicitHeight: ~720` (anchored top-right with the
same 50/20 margins as the weather panel):

```
╔══ Memory — 1h "actually free": 21.3 GB ══════════════ [refresh] [✕] ══╗
║                                                                       ║
║  ┌─────────────────────────────────────────────────────────────────┐  ║
║  │ System overview (/proc/meminfo)                                 │  ║
║  │ ┌──────────┬──────────┬──────────┬──────────┐                   │  ║
║  │ │ Total    │ Used     │ Free NOW │ Cached   │                   │  ║
║  │ │ 62.5 GiB │  9.4 GiB │ 21.3 GiB │ 31.8 GiB │                   │  ║
║  │ └──────────┴──────────┴──────────┴──────────┘                   │  ║
║  │ Stacked bar: [used][buff/cache][free]   <— horizontal, animated │  ║
║  │ "Cache is reclaimable on demand — your real pressure is 15 %"   │  ║
║  └─────────────────────────────────────────────────────────────────┘  ║
║                                                                       ║
║  ┌─────────────────────────────────────────────────────────────────┐  ║
║  │ Top processes (by PSS)                                          │  ║
║  │  ● firefox           1834 MiB   ████████████████░░░░░░  35 %    │  ║
║  │  ● somewm (1.3 GiB)  1316 MiB   ██████████████░░░░░░░░  25 %    │  ║
║  │  ● qs                 512 MiB   █████░░░░░░░░░░░░░░░░░   9 %    │  ║
║  │  ● alacritty          180 MiB   █░░░░░░░░░░░░░░░░░░░░░   3 %    │  ║
║  │  … collapse/expand                                              │  ║
║  └─────────────────────────────────────────────────────────────────┘  ║
║                                                                       ║
║  ┌─────────────────────────────────────────────────────────────────┐  ║
║  │ somewm internals (root.memory_stats / wallpaper_cache_stats)    │  ║
║  │                                                                 │  ║
║  │  RSS         1316 MiB    PSS        1129 MiB                    │  ║
║  │  Lua heap       7.8 MiB  Clients            3                   │  ║
║  │  drawable SHM 348 MiB / 11 buffers (api ≡ pmap ✓)               │  ║
║  │  Wallpaper cache   569 MiB / 9 entries  (cap 32)                │  ║
║  │  Active wallpaper   32 MiB                                      │  ║
║  │  Wibox surfaces      0.5 MiB                                    │  ║
║  │                                                                 │  ║
║  │  glibc retention:  used 319  free 117  releasable 33  (MiB)     │  ║
║  │  "somewm ≈ 2× sway baseline on this hardware — see baseline.md" │  ║
║  └─────────────────────────────────────────────────────────────────┘  ║
║                                                                       ║
║  ┌─────────────────────────────────────────────────────────────────┐  ║
║  │ Trend (last 5 min, sampled every 5 s)                           │  ║
║  │                                                                 │  ║
║  │  Sparkline: RSS ── Lua ·· wallpaper ══                          │  ║
║  │  no growth detected                                             │  ║
║  └─────────────────────────────────────────────────────────────────┘  ║
║                                                                       ║
║  [ Force Lua GC ]  [ Copy snapshot to clipboard ]  [ Open baseline ]  ║
╚═══════════════════════════════════════════════════════════════════════╝
```

Key design notes:

- The **"Free NOW"** number uses `MemAvailable` from `/proc/meminfo`, not
  `MemFree` — this is the honest "how much can apps actually claim"
  number and matches the kernel's own heuristic. The existing
  SystemStats wibar value uses exactly this.
- The **stacked bar** uses the three-band layout the kernel actually
  thinks in (`MemUsed = Total - Available`, `Buffers + Cached - Shmem`,
  `MemAvailable`) — separates true pressure from reclaimable cache.
- The **top processes** list uses PSS (proportional set size, from
  `/proc/$pid/smaps_rollup`). PSS divides shared pages across owners —
  the only honest per-process memory attribution available without root.
  Without it, everything that mmaps `libc` looks fat.
- **somewm internals** come from the existing
  `root.memory_stats(true)` / `root.wallpaper_cache_stats()` /
  `root.drawable_stats()` APIs — exact same fields the snapshot script
  already consumes. The three lines "api ≡ pmap", baseline comparison,
  and "no drift" are rendered from the counters themselves.
- The **trend sparkline** is *in-memory only*, lives as long as the
  detail panel stays open. We keep a rolling ring buffer of N=60 samples
  (5 s × 60 = 5 min) per metric. No on-disk trend. For longer, the user
  already has `plans/scripts/somewm-memory-trend.sh`.
- The **footer actions** are the three things the user might want:
  - "Force Lua GC" — `somewm-client eval 'collectgarbage();
    collectgarbage(); return "ok"'` — almost never actually needed but
    useful for "did the lua heap grow?" hunting.
  - "Copy snapshot to clipboard" — runs `plans/scripts/somewm-memory-
    snapshot.sh --tsv` and pushes to clipboard via `wl-copy`.
  - "Open baseline" — launches `xdg-open
    plans/docs/memory-baseline.md` so the user can compare.

### 4.2 `services/MemoryDetail.qml` (new)

Singleton. Gated by `detailActive` the same way `SystemStats.perfTabActive`
gates GPU polling. Poll cadence 2 s while open, nothing while closed.

```qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool detailActive: false

    // ---- system ----
    property real memTotalKB: 0     // from /proc/meminfo MemTotal
    property real memAvailKB: 0     // MemAvailable
    property real memFreeKB: 0      // MemFree
    property real memBuffKB: 0      // Buffers
    property real memCachedKB: 0    // Cached
    property real memShmemKB: 0     // Shmem
    property real memSlabKB: 0      // Slab
    property real memAnonKB: 0      // AnonPages
    property real memMappedKB: 0    // Mapped
    // Derived:
    readonly property real reclaimableKB: memBuffKB + memCachedKB + memSlabKB - memShmemKB
    readonly property real usedKB: memTotalKB - memAvailKB

    // ---- top processes (PSS via /proc/*/smaps_rollup) ----
    property var topProcesses: []   // [{pid, name, pssKB, rssKB, pct}]

    // ---- somewm-internal (from somewm-client eval) ----
    property var somewm: ({})       // parsed root.memory_stats + wallpaper_cache_stats
    property bool apiPmapAgrees: true
    property string baselineNote: ""

    // ---- trend ring (N=60 samples = 5 min at 5s interval) ----
    property var trend: []          // [{t, rss, pss, lua, wp, shm}]

    // Timer: /proc/meminfo every 2s
    Timer { running: root.detailActive; interval: 2000; repeat: true
            triggeredOnStart: true; onTriggered: meminfoProc.running = true }

    // Timer: top processes PSS every 5s (expensive — globs /proc)
    Timer { running: root.detailActive; interval: 5000; repeat: true
            triggeredOnStart: true; onTriggered: psProc.running = true }

    // Timer: somewm-internal every 3s
    Timer { running: root.detailActive; interval: 3000; repeat: true
            triggeredOnStart: true; onTriggered: somewmProc.running = true }

    // Trend ring update every 5s
    Timer { running: root.detailActive; interval: 5000; repeat: true
            onTriggered: root._pushTrend() }

    Process { id: meminfoProc; command: ["cat", "/proc/meminfo"]
              stdout: StdioCollector { onStreamFinished: root._parseMeminfo(text) } }

    Process {
        id: psProc
        // Top 10 by PSS. Uses a short bash pipeline — avoids bringing in
        // `smem` as a new hard dep. Reads smaps_rollup (cheap, single
        // file per pid, no per-mapping aggregation needed).
        command: ["bash", "-c",
          "for d in /proc/[0-9]*; do " +
          "  pid=${d##*/}; " +
          "  [ -r \"$d/smaps_rollup\" ] || continue; " +
          "  pss=$(awk '/^Pss:/ {s+=$2} END{print s+0}' \"$d/smaps_rollup\"); " +
          "  rss=$(awk '/^Rss:/ {s+=$2} END{print s+0}' \"$d/smaps_rollup\"); " +
          "  name=$(tr -d '\\0' <\"$d/comm\" 2>/dev/null || echo ?); " +
          "  printf '%s\\t%s\\t%s\\t%s\\n' \"$pss\" \"$rss\" \"$pid\" \"$name\"; " +
          "done | sort -k1,1 -nr | head -15"]
        stdout: StdioCollector { onStreamFinished: root._parseProcs(text) }
    }

    Process {
        id: somewmProc
        // Single eval that returns a flat key=value stream for robust parse.
        // Uses the same format as our memory-snapshot script.
        command: ["somewm-client", "eval",
          "local m=root.memory_stats(true); " +
          "local w=root.wallpaper_cache_stats(); " +
          "local d=root.drawable_stats(); " +
          "return string.format('rss=%d pss=%d lua=%d shm_api=%d shm_buf=%d " +
          "wp_entries=%d wp_est=%d wp_cairo=%d wp_shm=%d ds=%d wb=%d " +
          "mal_used=%d mal_free=%d mal_rel=%d clients=%d', " +
          "m.rss_kb or 0, m.pss_kb or 0, m.lua_bytes, " +
          "m.drawable_shm_count_api or 0, m.drawable_shm_bytes_api or 0, " +
          "w.entries or 0, w.estimated_bytes or 0, w.cairo_bytes or 0, w.shm_bytes or 0, " +
          "d.surface_bytes or 0, m.wibox_surface_bytes or 0, " +
          "m.malloc_used_bytes or 0, m.malloc_free_bytes or 0, m.malloc_releasable_bytes or 0, " +
          "m.clients or 0)"]
        stdout: StdioCollector { onStreamFinished: root._parseSomewm(text) }
    }

    // actions
    function forceGc() { /* spawn somewm-client eval collectgarbage twice */ }
    function copySnapshot() { /* spawn snapshot script --tsv | wl-copy */ }
    function openBaseline() { /* xdg-open plans/docs/memory-baseline.md */ }
}
```

**Gate lifecycle:** `MemoryDetailPanel.qml` sets `detailActive = Core.Panels.isOpen("memory-detail")` in a `Connections` block against `Core.Panels`, mirroring the pattern in `PerformanceTab.qml:23`. When the panel closes, timers stop immediately.

### 4.3 `modules/memory-detail/MemoryDetailPanel.qml` (new)

Structure mirrors `WeatherPanel.qml`:

```qml
Variants {
    model: Quickshell.screens
    PanelWindow {
        id: panel
        required property var modelData
        screen: modelData
        property bool shouldShow: Core.Panels.isOpen("memory-detail") &&
                                  Services.Compositor.isActiveScreen(modelData)
        visible: shouldShow || fadeAnim.running
        color: "transparent"
        focusable: shouldShow
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "somewm-shell:memory-detail"
        WlrLayershell.keyboardFocus: shouldShow ? WlrKeyboardFocus.Exclusive
                                                : WlrKeyboardFocus.None
        anchors { top: true; right: true }
        margins.top: 50; margins.right: 20
        implicitWidth: 560
        implicitHeight: 720
        mask: Region { item: card }

        Components.GlassCard {
            id: card
            anchors.fill: parent
            focus: panel.shouldShow
            Keys.onEscapePressed: Core.Panels.close("memory-detail")
            opacity: panel.shouldShow ? 1.0 : 0.0
            scale:   panel.shouldShow ? 1.0 : 0.95
            Behavior on opacity { NumberAnimation {
                id: fadeAnim; duration: Core.Anims.duration.normal
                easing.type: Core.Anims.ease.decel } }
            Behavior on scale { Components.Anim {} }

            // Sub-components live next to this file so they stay private:
            //   SystemOverviewSection.qml
            //   TopProcessesSection.qml
            //   SomewmInternalsSection.qml
            //   TrendSection.qml
            //   FooterActions.qml
            // (Plain Column layout — no TabBar; everything vertical scroll.)
        }
    }
}
```

Wire `detailActive`:

```qml
Connections {
    target: Core.Panels
    function onOpenPanelsChanged() {
        Services.MemoryDetail.detailActive = Core.Panels.isOpen("memory-detail")
    }
}
Component.onCompleted: Services.MemoryDetail.detailActive = Core.Panels.isOpen("memory-detail")
Component.onDestruction: Services.MemoryDetail.detailActive = false
```

### 4.4 Data source honesty matrix

| Field                          | Source                                               | Trust |
|--------------------------------|------------------------------------------------------|-------|
| Total / Used / Free / Cached   | `/proc/meminfo` MemTotal / MemAvailable / MemFree / Cached | kernel, ground truth |
| Top processes PSS              | `/proc/$pid/smaps_rollup`                            | kernel, ground truth |
| somewm RSS/PSS                 | `root.memory_stats(true)` which reads `/proc/self/smaps_rollup` | kernel, ground truth |
| Lua heap                       | `collectgarbage("count") × 1024`                     | exact after double GC |
| Wallpaper cache                | `root.wallpaper_cache_stats()` C counter             | exact (tracked at set/free) |
| drawable SHM                   | `root.memory_stats().drawable_shm_bytes_api`         | exact; pmap cross-check  |
| glibc retention                | `mallinfo2()` inside `root.memory_stats`             | allocator-internal view  |
| Baseline "~2× sway"            | Static string pulled from `plans/docs/memory-baseline.md` | human-authored |

No estimation or guessing anywhere. If a value is unavailable (e.g. old
kernel without `smaps_rollup`) we show `—`, not a fake number.

---

## 5. Storage detail panel

### 5.1 Layout

```
╔══ Storage ═══════════════════════════════════════════════ [refresh] [✕] ══╗
║                                                                           ║
║  ┌─────────────────────────────────────────────────────────────────────┐  ║
║  │ Mounts                                                              │  ║
║  │  /                btrfs    182 / 476 GiB  ███████████░░░░░░  38 %   │  ║
║  │  /home            btrfs    412 / 931 GiB  ████████░░░░░░░░░  44 %   │  ║
║  │  /boot            ext4     0.3 /   1 GiB  ███░░░░░░░░░░░░░░  30 %   │  ║
║  │  /mnt/samsung-tv  ext4    ...                                       │  ║
║  └─────────────────────────────────────────────────────────────────────┘  ║
║                                                                           ║
║  ┌─────────────────────────────────────────────────────────────────────┐  ║
║  │ Arch system hotspots                                                │  ║
║  │  Pacman cache         /var/cache/pacman/pkg      11.2 GiB           │  ║
║  │    [ Clean (keep 2) ]   [ Clean (keep 0) ]   [ Dry-run first ]      │  ║
║  │  Pacman logs          /var/log/pacman.log          21 MiB           │  ║
║  │  journald             /var/log/journal            842 MiB  (cap 1G) │  ║
║  │  systemd coredumps    /var/lib/systemd/coredump   315 MiB           │  ║
║  │  AUR build cache      ~/.cache/paru,yay            3.1 GiB          │  ║
║  │  Flatpak unused       (if flatpak installed)        —               │  ║
║  └─────────────────────────────────────────────────────────────────────┘  ║
║                                                                           ║
║  ┌─────────────────────────────────────────────────────────────────────┐  ║
║  │ Biggest top-level directories under $HOME                           │  ║
║  │  1.  ~/.mozilla                                      8.7 GiB        │  ║
║  │  2.  ~/Downloads                                     5.4 GiB        │  ║
║  │  3.  ~/git                                           4.9 GiB        │  ║
║  │  4.  ~/.cache                                        3.8 GiB        │  ║
║  │  5.  ~/.local/share                                  2.6 GiB        │  ║
║  │  (top 10; updates lazily, one `du -sh -- *` per panel open)         │  ║
║  └─────────────────────────────────────────────────────────────────────┘  ║
║                                                                           ║
║  ┌─────────────────────────────────────────────────────────────────────┐  ║
║  │ Biggest files (under $HOME, > 256 MiB)                              │  ║
║  │  ~/Downloads/arch-2026.iso                       3.8 GiB            │  ║
║  │  ~/.var/app/.../steam.img                        1.2 GiB            │  ║
║  │  …                                                                  │  ║
║  └─────────────────────────────────────────────────────────────────────┘  ║
║                                                                           ║
║  [ Open baobab ]  [ Open filelight ]   [ Copy report ]                    ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

Design notes:

- **Mounts**: `df -B1 --output=source,fstype,used,size,target -x tmpfs -x devtmpfs -x squashfs`, one row per mount. Primary mount first. Btrfs subvolumes that share a pool are grouped (they all show the same raw numbers; we deduplicate visually with a small "btrfs pool" badge).
- **Arch hotspots**: a fixed, known list — no user-selectable paths. Each row runs `du -sb <path>` only when the panel opens (one shot, not periodic).
  - Pacman cache: surfaced via `paccache -dk2 -v` (dry-run preview) and `paccache -rk2`/`paccache -rk0` (real). The button flow is strict: first click = dry run, shows preview; second click = real run with confirmation toast.
  - `journalctl --disk-usage` for journald.
  - Flatpak row only visible if `flatpak` is on `$PATH`.
- **Biggest dirs**: `du -sh -- ~/* ~/.*` top-10, sorted. Runs in background; spinner while pending. We deliberately stick to depth-1 for speed — users who want deeper tree analysis open `baobab`.
- **Biggest files**: `find ~ -xdev -type f -size +256M -printf '%s\t%p\n' | sort -nr | head -20`. Again on panel open only. Respects `-xdev` to avoid walking bind mounts.
- **Escape hatches**: explicit buttons for `baobab /` and `filelight ~/`. Both are installed on the user's system (verified).

### 5.2 `services/StorageDetail.qml` (new)

Same singleton pattern, `detailActive` gate, but the cadence is
panel-open-one-shot for most work (du / find are too expensive to poll):

```qml
Singleton {
    id: root
    property bool detailActive: false

    property var mounts: []            // [{src, fstype, used, size, target, pct}]
    property var hotspots: ({})        // name -> bytes
    property var topDirs: []           // [{path, bytes}]
    property var topFiles: []          // [{path, bytes}]
    property bool pacmanCacheBusy: false
    property string pacmanCachePreview: ""

    // Mounts poll every 30 s while open (cheap)
    Timer { running: detailActive; interval: 30000; repeat: true
            triggeredOnStart: true; onTriggered: dfProc.running = true }

    // Hotspots + top dirs + top files: one-shot on panel open.
    onDetailActiveChanged: if (detailActive) { hotspotsProc.running = true;
                                               topDirsProc.running = true;
                                               topFilesProc.running = true }

    function refresh() { /* re-run all */ }
    function pacmanCacheDryRun(keep) { /* paccache -dk<keep> -v */ }
    function pacmanCacheRun(keep)    { /* paccache -rk<keep> + toast */ }
    function openBaobab()             { Quickshell.execDetached(["baobab", "/"]) }
    function openFilelight()          { Quickshell.execDetached(["filelight", Qt.resolvedUrl("~")]) }
}
```

### 5.3 Safety for the paccache button

**Hard rule:** every destructive action goes through a two-click flow —
dry-run preview first, explicit confirm second. The preview renders the
full list of packages that would be removed (paccache `-v` output).

Nothing else in the panel is destructive. `baobab` and `filelight` are
read-only viewers.

No `rm -rf` primitive anywhere in the QML. No user-specified path input.
No shell interpolation of paths (all exec uses list form).

### 5.4 Optional external tools

- `baobab` — installed, used as escape hatch.
- `filelight` — installed, used as escape hatch.
- `duf` / `ncdu` — **not installed**. We don't add them as hard deps. If
  the user wants them later, the mounts row has a natural "open duf"
  button we can wire conditionally (`if (command -v duf)`).

---

## 6. Theming / visual language

Use existing tokens exclusively:

- Surfaces: `Core.Theme.surfaceContainer` / `surfaceContainerHigh`,
  `GlassCard`.
- Text: `Core.Theme.fgMain` / `fgDim` / `fgMuted`, `StyledText`.
- Widget accents: `Core.Theme.widgetMemory` (memory panel hero),
  `Core.Theme.widgetDisk` (storage panel hero), `Core.Theme.accent` for
  action buttons.
- Animations: `Core.Anims.duration.*` and easing curves from `Anim.qml` /
  `CAnim.qml`. No bespoke easing.
- Radii: `Core.Theme.radius.md` for cards, `1000` for capsules (matches
  Performance `HeroCard` temp bar).
- Font sizes: `Core.Theme.fontSize.sm` / `md` / `lg`; monospace is
  `Core.Theme.fontMono` for all numeric values.

Entrance: `opacity 0→1 + scale 0.95→1`, same curve as `WeatherPanel`.

---

## 7. File-level change list

New files (all under `plans/project/somewm-shell/`):

```
modules/memory-detail/
  qmldir
  MemoryDetailPanel.qml
  SystemOverviewSection.qml
  TopProcessesSection.qml
  SomewmInternalsSection.qml
  TrendSection.qml
  FooterActions.qml
modules/storage-detail/
  qmldir
  StorageDetailPanel.qml
  MountsSection.qml
  HotspotsSection.qml
  TopDirsSection.qml
  TopFilesSection.qml
  FooterActions.qml
services/MemoryDetail.qml
services/StorageDetail.qml
```

Edited files:

```
plans/project/somewm-shell/core/Panels.qml
    + "memory-detail", "storage-detail" to anyOverlayOpen array
    + same to exclusive[] in toggle()

plans/project/somewm-shell/modules/dashboard/PerformanceTab.qml
    + detailPanel / detailClicked on the inline GaugeCard
    + detailPanel: "memory-detail"  on Memory card
    + detailPanel: "storage-detail" on Storage card

plans/project/somewm-shell/shell.qml
    + load new panel modules (mirroring how WeatherPanel is loaded)

plans/project/somewm-shell/services/qmldir
    + singleton registrations for MemoryDetail + StorageDetail

plans/project/somewm-one/fishlive/components/memory.lua
    + widget:buttons() with awful.button({}, 1, ...) -> qs ipc toggle
plans/project/somewm-one/fishlive/components/disk.lua
    + same
```

---

## 8. Testing plan

1. **Smoke**: launch sandbox via `plans/scripts/somewm-sandbox.sh`, open
   Performance tab, click gear on Memory — panel opens and shows numbers
   that match `root.memory_stats()`. Click gear on Storage — panel opens
   and shows `df` that matches `df -h`.
2. **Wibar left-click**: inside the same sandbox, run
   `qs ipc -c somewm call somewm-shell:panels toggle memory-detail`
   directly; confirm open/close. Then deploy `memory.lua` / `disk.lua`
   change and verify the left-click does the same.
3. **Lazy-by-default**: leave the dashboard and detail panels closed for
   60 s, check `ps -o pcpu --ppid $QS_PID` — should be ~0.
4. **Scroll guard**: open Memory detail panel over the dashboard,
   mouse-wheel inside the panel; verify `awesome._shell_overlay` goes
   `true`, no tag switch on the compositor.
5. **paccache safety**: dry run first click, confirm preview matches
   `paccache -dk2 -v` in a terminal; only real run on second click;
   refresh updates the Pacman cache row size.
6. **Compositor-side regression**: run `make test` — no compositor files
   changed, this must stay green.
7. **Multi-monitor**: Samsung TV attached, panel shows only on the
   focused screen (same `Services.Compositor.isActiveScreen` guard as
   the weather panel).

---

## 9. Out-of-scope / explicit deferrals

- **Per-process trend**: we snapshot PSS top-N every 5 s while panel is
  open, but we don't track per-process *growth*. If a user wants that,
  the memory-trend script already exists on the CLI.
- **Network / socket mounts**: `df` will include NFS/SSHFS automatically
  if mounted; we don't filter by mount type beyond excluding tmpfs.
- **Configurable hotspots list**: hard-coded for Arch in this pass. A
  future `~/.config/somewm-shell/storage-hotspots.json` is plausible
  but not needed now.
- **Notifications on thresholds**: e.g. "pacman cache > 5 GiB" toast.
  Explicitly not part of this work — the user asked for "mental model",
  not alerting.

---

## 10. Risks / open questions (for Codex review)

1. **PSS scan cost**: scanning every `/proc/*/smaps_rollup` every 5 s is
   cheap on modern systems but not free (~5–20 ms). Is the cadence right,
   or should we do it once per panel open and refresh manually? The user
   already sees the wibar number every 2 s, so the panel can afford to
   be slower.
2. **Mutual exclusion with dashboard**: should opening Memory detail
   close the dashboard (current plan) or overlay it? Both are defensible
   — Codex, pick one.
3. **`somewm-client eval` string format**: we currently do flat
   `k=v k=v` stream parsing. It's simple and robust. Alternative: return
   JSON from Lua. Pro JSON: no parser in QS. Con: Lua's `cjson` isn't
   guaranteed available in somewm — the existing snapshot scripts use the
   flat format exactly because it avoids that. Probably keep flat.
4. **Trend ring**: 5 min × 5 s = 60 samples per metric, stored as plain
   QML arrays. Memory budget is tiny (<10 kB). But the sparkline
   rendering — should it use `Components.Graph` (existing) or a new
   inline `Canvas` draw? Existing `Graph.qml` should suffice.
5. **Storage refresh UX**: the header `[refresh]` button re-runs the
   expensive `du` / `find`. Should it show a loading overlay on the
   affected sections, or just spin the button icon? Loading overlay per
   section is more honest but adds work.
6. **Btrfs subvolume dedup**: multiple subvolumes from the same pool
   show the same underlying free/used. Our current plan tags them
   visually ("btrfs pool"). Alternative: collapse into one row with
   expandable sublist. Codex: what's the cleanest UI?
7. **Paccache permissions**: `paccache -r` needs root. We must `pkexec
   paccache` — which pops the polkit prompt. That's fine for a shell
   tool but needs to be explicit in the button label: "Clean (keep 2)
   — polkit prompt".
8. **Is `Quickshell.execDetached` the right API for launching baobab?**
   Need to check the QS docs / quickshell source — alternative is a
   `Process { running: true; detached: true }` or just `Process` with
   `command: ["setsid", "baobab", "/"]`.

---

## 11. Rough implementation order

1. `Core.Panels.qml` — register the two new panel names (trivial, blocks
   everything else).
2. `services/MemoryDetail.qml` with just the `/proc/meminfo` section;
   verify values update while `detailActive` is true and stop when it's
   false. This is the "lazy gate" contract test.
3. `modules/memory-detail/MemoryDetailPanel.qml` shell + first section
   (SystemOverview). Click the gear, see real numbers. At this point the
   feature is already useful.
4. Extend `MemoryDetail` with `somewm-client eval` block and
   `SomewmInternalsSection`. Cross-check against snapshot script.
5. Top-processes PSS scanner + `TopProcessesSection`. Highest perf risk
   section — measure before shipping.
6. Trend ring + `TrendSection` + sparkline.
7. FooterActions (GC, copy, open baseline).
8. Repeat 2–4 for Storage.
9. Biggest dirs/files + paccache two-click flow (highest UX risk).
10. Lua wibar left-click bindings.
11. Testing matrix (section 8), deploy via `somewm-shell/deploy.sh` +
    `somewm-one/deploy.sh`, reload.

Each step is independently shippable — they all live behind the same
`Core.Panels` toggle, so half-finished sections just don't render.

---

## 12. Deliverables

- 2 new panels, 2 new services, 2 edited trigger sites, 1 Panels.qml
  registration.
- Compositor unchanged.
- Existing memory diagnostics scripts unchanged; we *consume* them, we
  don't fork them.
- `plans/docs/memory-baseline.md` remains the written reference the
  panel points the user at.
