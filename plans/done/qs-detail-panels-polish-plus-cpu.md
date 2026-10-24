# QS detail-panels polish + new CPU/GPU detail panel

**Status:** PLAN rev 2 — incorporates review findings from gemini
(gemini-3.1-pro-preview) + sonnet (claude-sonnet-4-6). codex gpt-5.5
got stuck in exploration / code generation, killed. Two structured
reviews is sufficient triangulation.
**Branch:** extend `feat/qs-memory-storage-detail-panels`.
**Why a second round:** user live-tested round-1 panels on 4K, reported
polish issues (readability, animation jank, wasted vertical space, bar
chart legend confusion) and requested a third detail panel for CPU/GPU.

## Review deltas applied (rev 2)

Incorporated from external review:

- **§7 force-stop (CRITICAL — both reviewers):** `proc.running = false`
  does NOT reliably send SIGTERM in Quickshell. However, processes
  already wrapped in `timeout N` (all existing Process blocks do this
  already) propagate SIGTERM to children when the timeout wrapper is
  killed, so `running = false` IS safe for those. Plan updated to
  (a) verify every Process is wrapped in `timeout`, (b) add a lifecycle
  sandbox test that greps for orphan children after close, (c) use
  `exec cmd` in any bash wrapper that cannot be replaced by direct
  binary invocation. gemini alternative "drop bash, invoke binary
  directly" noted as future refactor.
- **§8.2 per-core sampling (CRITICAL — gemini + sonnet):** 1.5 s Timer
  + 1 s sleep + teardown margin too thin. **New approach:** self-
  throttling — start next sample from previous `onExited` handler
  instead of a fixed Timer. Alternative fallback: read `/proc/stat`
  directly from QML via `FileView` (Quickshell idiom) and diff in JS,
  eliminating the bash `sleep` entirely. Chosen default: `FileView`
  approach (cleaner, no subprocess churn). Bash fallback only if
  FileView proves awkward for multi-line reads.
- **§2 clip bar (sonnet):** the left-cap rounded seam is NOT handled by
  `clip: true`. Fix: keep `radius: height/2` on the USED bar (it forms
  the pill's left cap), set `radius: 0` on the reclaimable bar, track
  uses `clip: true` to mask the right side. Verified conceptually
  correct.
- **§3 Option C (sonnet):** the `_ready` gate works; plan's reasoning
  was slightly off but the conclusion holds. Keep Option C, add a
  one-line comment explaining binding evaluation order.
- **§5 homeTotal (both reviewers):** "% of top-10 sum" is misleading
  without an explicit label. Run one additional `du -xb --max-depth=0
  $HOME` at the same 30 s interval as the other storage probes to get
  the TRUE $HOME total. Percent column then shows "% of $HOME" and is
  honest.
- **§8.1 nvidia-smi cold-start (sonnet):** 150-300 ms per invocation.
  Fix: probe GPU model once at panel first-open via `/sys/class/drm/
  card*/device/{vendor,device}` sysfs reads (instant). Keep
  `nvidia-smi --query-gpu=...` for live utilisation — NVML stays warm
  after first call.
- **§8 registry refactor (both reviewers):** split into own commit
  BEFORE the CPU panel is added. Must preserve the asymmetry where
  `sidebar-left` is in `overlayPanels` but NOT in `exclusivePanels`
  (scroll-guard vs mutual exclusion are two different concepts).
- **§6 button labels (sonnet):** use "Baobab" / "Filelight" (capital,
  proper name, implies launch) rather than lowercased tool names.
  Accessibility friendlier.
- **§4 "since open" (sonnet):** trend ring resets on every open, so
  min/max are per-session-open not per-session. Label as "since panel
  open".
- **§9 grep guards (sonnet):** use `grep -A N "<anchor>"` to scope the
  assertion, not bare grep.

---

## 1. 4K height: let panels grow

**Problem:** Both panels cap at ~760/820 px. On a 4K screen with 2160 px
vertical (primary) or 3840 px vertical (portrait HP), this forces the
Flickable to scroll even though the screen has ~1400 px of vacant area.

**Fix:** Remove the hard cap. Keep the screen-edge safety margin (`-120`
from `modelData.height` for top padding + bottom chrome) but let the
panel take whatever it needs up to that bound, without the 760/820
ceiling.

```qml
// MemoryDetailPanel.qml:41 — was
implicitHeight: Math.min(Math.round(760 * Core.Theme.dpiScale),
                         modelData && modelData.height ? modelData.height - 120 : 760)
// becomes
implicitHeight: modelData && modelData.height ? modelData.height - 120
                                              : Math.round(760 * Core.Theme.dpiScale)
```

**Cap for safety:** 1400 px absolute max on very tall screens (portrait
HP monitor is 3840 px vertical — full-length detail panel is a usability
bug, not a feature). So:

```qml
implicitHeight: Math.min(
    Math.round(1400 * Core.Theme.dpiScale),
    modelData && modelData.height ? modelData.height - 120
                                  : Math.round(760 * Core.Theme.dpiScale))
```

**Contract:** the inner `Flickable` keeps its `contentHeight` binding so
it still scrolls if actual content exceeds the grown panel. No layout
regression on 1080p/1440p displays (the `modelData.height - 120` term
rules).

---

## 2. Memory "System Overview" bar chart

Current behaviour (SystemOverviewSection.qml:101-146):
- Track (background): full-width Rectangle, `radius: height/2` → fully
  rounded pill, 4 % white.
- **Used** bar: `width = parent.width * usedFrac`, solid
  `Core.Theme.widgetMemory` (pink), `radius: height/2`.
- **Reclaimable** bar: starts at `x = parent.width * usedFrac`, width
  proportional to reclaimable fraction, 30 % alpha of same pink,
  `radius: height/2`.

User-visible problems:
- a. Legend missing: user doesn't know tmavě růžová = used,
     světle růžová = reclaimable (page cache + buffers that can be
     evicted under memory pressure).
- b. Percentage not shown inside the bar — user has to read the "Real
     pressure: NN%" text below, far from the visual cue.
- c. Both bars are individually pill-shaped (`radius: height/2`). Where
     "used" ends and "reclaimable" begins, the used bar's rounded RIGHT
     edge overlaps the reclaimable bar's rounded LEFT edge → two
     curved shapes crashing into each other. Looks broken.

**Fix:**

**(a) Legend row above the bar:**

```qml
RowLayout {
    spacing: Core.Theme.spacing.md
    Layout.fillWidth: true

    Repeater {
        model: [
            { label: "used",         color: Core.Theme.widgetMemory, alpha: 1.0 },
            { label: "reclaimable",  color: Core.Theme.widgetMemory, alpha: 0.3 },
            { label: "free",         color: Qt.rgba(1,1,1,0.12),     alpha: 1.0 },
        ]
        delegate: RowLayout {
            spacing: Core.Theme.spacing.xs
            Rectangle {
                width: Math.round(10 * Core.Theme.dpiScale)
                height: Math.round(10 * Core.Theme.dpiScale)
                radius: 2
                color: Qt.rgba(modelData.color.r, modelData.color.g,
                               modelData.color.b, modelData.alpha)
            }
            Components.StyledText {
                text: modelData.label
                font.pixelSize: Core.Theme.fontSize.xs
                color: Core.Theme.fgMuted
            }
        }
    }
}
```

**(b) Percent inside the bar:**

Add a centered, anchored Text on top of the bar stack showing the USED
percent (not reclaimable — that's a secondary concept; surfacing it here
would be noisy). Render with contrasting color + subtle shadow for
readability:

```qml
Components.StyledText {
    anchors.centerIn: parent
    text: Math.round(100 * usedFrac) + "%"
    font.family: Core.Theme.fontMono
    font.pixelSize: Core.Theme.fontSize.sm
    font.bold: true
    color: "#ffffff"
    layer.enabled: true
    // subtle dark drop for contrast on the pink fill
    style: Text.Outline
    styleColor: Qt.rgba(0, 0, 0, 0.45)
}
```

**(c) Consistent corner treatment** — only round the OUTSIDE corners
of the stacked used+reclaimable block, not the seam between them.
**Per sonnet review:** `clip: true` handles the RIGHT cap. The LEFT cap
is NOT clipped (both usedBar and track start at x=0) — so usedBar MUST
keep its own `radius: height/2` to form the left pill. reclaimBar has
`radius: 0` (flat seam). All coordinates go through `Math.round()` to
avoid fractional-DPI hairline bleed (gemini):

```qml
Rectangle {
    id: barTrack
    Layout.fillWidth: true
    Layout.preferredHeight: Math.round(16 * Core.Theme.dpiScale)
    radius: height / 2
    color: Qt.rgba(1, 1, 1, 0.08)
    clip: true       // masks reclaimBar's right edge that would
                     // otherwise overflow past the track's rounded cap

    Rectangle {
        id: usedBar
        anchors.left: parent.left
        anchors.top: parent.top; anchors.bottom: parent.bottom
        // Rounded: usedBar forms the pill's LEFT cap (clip doesn't
        // mask it — both start at x=0). Review: sonnet round-2 plan.
        width: Math.round(parent.width * usedFrac)
        radius: height / 2
        color: Core.Theme.widgetMemory
        Behavior on width { NumberAnimation { duration: Core.Anims.duration.smooth } }
    }
    Rectangle {
        id: reclaimBar
        anchors.top: parent.top; anchors.bottom: parent.bottom
        x: Math.round(parent.width * usedFrac)
        width: Math.round(parent.width * reclaimFrac)
        radius: 0                                    // flat seam
        color: Qt.rgba(Core.Theme.widgetMemory.r, Core.Theme.widgetMemory.g,
                       Core.Theme.widgetMemory.b, 0.30)
        Behavior on x { NumberAnimation { duration: Core.Anims.duration.smooth } }
        Behavior on width { NumberAnimation { duration: Core.Anims.duration.smooth } }
    }
    // Percent label layered above both bars (see (b))
    Components.StyledText { … }
}
```

The `clip: true` on the track masks reclaimBar's right edge; usedBar's
own `radius: height/2` forms the left pill cap; the middle seam is
flat. One continuous pill.

**Accessibility:** Tooltip on hover (HoverHandler) showing e.g.
`13 GiB used · 8 GiB reclaimable · 11 GiB free`.

---

## 3. Top-processes animation jumping from zero

**Problem:** TopProcessesSection uses `Repeater { model: procs }` where
`procs = Services.MemoryDetail.topProcesses` is replaced as a whole new
array every 5 s. Each model swap destroys all delegates and creates new
ones. Each new delegate's inner fill Rectangle has `Behavior on width`
→ width starts at 0 → animates to target → user sees 10 bars sweep from
0 every 5 s, misread as "all processes just freed memory".

**Root cause:** array-identity swap. Stable delegates require a model
that QML recognises as identity-stable (ListModel with in-place update,
or object-array with a row key that Repeater honours).

**Fix options (plan chooses B):**

**Option A (dumb):** remove `Behavior on width` entirely. Delegates
still recreated but appear at their final width immediately. No jank,
but also no smooth transition when ordering shuffles.

**Option B (proper):** convert `Services.MemoryDetail.topProcesses`
into a `ListModel`. On each refresh, diff new rows against existing by
`pid`: update matching rows' fields in place, append new pids, remove
departed pids. Repeater keeps delegates, `Behavior on width` only fires
on real value changes. Ordering change triggers move, animates cleanly.

**Option C (same effect, simpler code):** keep the array property but
add a `Component.onCompleted: _ready = true` gate on each delegate;
`Behavior.enabled: _ready`. Means delegates draw at final width with no
animation; subsequent width changes (none, because delegate dies next
refresh) would animate. Result: no from-zero sweep, no smooth transition
either. Cheap win if B proves too invasive.

**Decision:** start with **C** (minimal change, removes the visual bug
immediately). Revisit **B** only if user asks for bar reshuffling
animation during ordering changes. Document the trade-off inline.

**Sonnet review correction on Option C:** the `_ready` bool defaults
to `false`; `Behavior.enabled: _ready` evaluates to `false` during the
delegate's initial layout pass. The width binding resolves to its
final value (delegate never has a "pending" width change at creation).
`Component.onCompleted` then sets `_ready = true`, which wakes the
`Behavior` — but there is no queued width change to animate, so
nothing animates. Subsequent width changes (e.g., layout reflow) DO
animate, which is desirable. Gemini's "slightly unpredictable"
warning is valid for custom bindings that re-fire unexpectedly; in
our case the binding inputs (`modelData.pssKB`, `maxPss`) don't
mutate after delegate construction, so there is no re-fire risk. Add
a one-line inline comment documenting this so a future refactor
doesn't "fix" the flag and re-introduce the sweep.

Same fix applies to TopDirsSection (Storage) — same pattern, same
problem (every 30 s refresh instead of 5 s, but equally wrong).

---

## 4. Memory Trend graphs have no Y scale

**Problem:** TrendSection.qml uses `Components.Graph` (custom thin-line
chart). Three side-by-side (RSS, Lua, Wallpaper). Each normalises
`dataPoints` to 0..1 relative to max. User complaints:

- No Y-axis labels → cannot tell what the peak represents (20 MiB?
  2 GiB?). Visual is a squiggle without scale.
- First ~1 minute of panel open shows a mostly-empty graph (ring buffer
  fills one point every 5 s up to 60 points; 5 minutes to fill). User
  sees near-empty graphs and assumes broken.

**Fix A — peak/current labels:** each MiniGraph already has a
`maxPoints` (60). Wrap it in a RowLayout with:
- above the line, the current value (large, right-aligned)
- on the right edge, the running peak (small, muted)
- on the bottom, elapsed time range ("last 5 min" or "last N s")

```
RSS          [====== line ======]  cur 480 MiB
                                   peak 512 MiB (last 5 min)
```

**Fix B — pre-warm the ring buffer:** when `detailActive` flips true,
ask MemoryDetail to immediately push 3 samples spaced 500 ms apart so
the user sees a non-empty line right away. Honest about lack of prior
history (grey tint for prewarm points), full color after live samples
arrive.

**Fix C — consider dropping the chart entirely:** a static sparkline
for a metric that only changes slowly (RSS of somewm, Lua heap) is low
information density. Replace with:
- current number (large)
- delta since open ("+12 MiB")
- ±min/max since open

This is more useful and doesn't waste vertical space on a near-flat
line. Decision: **do Fix C for Lua heap and Wallpaper (they change
little)**, keep the chart for RSS (it trends up slowly and operators
care about growth shape), add Fix A labels.

---

## 5. Storage "Biggest top-level dirs" bars + percent + title

**User reports:** "all bars are fully filled, should be proportional to
the biggest". Current code **does** scale `width = parent.width *
(bytes / maxBytes)` and `maxBytes = dirs[0].bytes` (biggest). So the
first bar is always full-width by construction — that's correct. The
polish gap is elsewhere:

a. The user is right that **"fully filled first bar" is confusing**
   because it implies 100 % usage in absolute terms, not "100 % of the
   largest dir". We should express both:
   - fill width = proportional to largest (relative view — already OK)
   - a **small percent label = share of $HOME total** (absolute view)

b. **Readability:** current row shows absolute MiB/GiB in mono text to
   the right of the bar. The user wants a percent label with good
   contrast — NOT white-on-yellow. Keep text in `Core.Theme.fgMain`
   (off-white) on the glass background (dark), which is high contrast.
   If we overlay percent ON the bar, use the same layered-label trick
   as §2: white text + `Text.Outline` dark style color for contrast on
   yellow.

c. **Short title:** `"Biggest top-level directories under $HOME"` →
   `"Top $HOME dirs"` (11 chars). Aligns with user request "mozna
   zkratit to directories na dirs".

**Implementation (revised per review):** both reviewers flagged that
"% of top-10 sum" is misleading without an explicit label, and sonnet
argued for running an extra `du -xb --max-depth=0 $HOME` (one more
Process at the 30 s interval, cheap on SSD) to get the true $HOME
total. Adopted.

```qml
// StorageDetail.qml — new Process, runs at the same 30 s interval as
// topDirsProc. `--max-depth=0` emits ONE row: $HOME rollup.
Process {
    id: homeTotalProc
    command: ["timeout", "15", "bash", "-c",
        "du -xb --max-depth=0 \"$HOME\" 2>/dev/null | awk '{print $1}'"]
    stdout: StdioCollector {
        onStreamFinished: root._parseHomeTotal(text)
    }
}

property double homeTotalBytes: 0
function _parseHomeTotal(text) {
    var n = parseInt((text || "").trim())
    if (n > 0) root.homeTotalBytes = n
}
```

```qml
// TopDirsSection.qml — percent column against TRUE home total
Components.StyledText {
    Layout.preferredWidth: Math.round(48 * Core.Theme.dpiScale)
    text: Services.StorageDetail.homeTotalBytes > 0
        ? Math.round(100 * modelData.bytes / Services.StorageDetail.homeTotalBytes) + "%"
        : "—"
    horizontalAlignment: Text.AlignRight
    color: Core.Theme.fgMuted
}
```

Percent label header (column title row above the Repeater) says
"% of $HOME" explicitly. No ambiguity about which denominator.

Until the second `du` call completes (0.5–5 s depending on SSD
saturation), render `—` placeholder — better than a wrong number.

---

## 6. Long button / section labels

**Current** (`modules/storage-detail/FooterActions.qml`):
- "Open baobab"
- "Open filelight"
- "Open $HOME"

**User sentiment:** "hrozne dlouhe popisky, trapne". These aren't
actually that long, but the row feels heavy. Proposal (revised per
sonnet accessibility note — capitalize = proper name, implies launch):

- Drop the verb. Each button already has an icon → "Baobab",
  "Filelight", "$HOME". Capitalised noun = proper name, visually
  reads as "launch X", screen-reader friendly.
- For "Clean pkg cache": keep as "Clean cache" (2 words, explicit).

Apply same to:
- MountsSection title "Mounts" (fine, keep).
- HotspotsSection title "Disk hotspots (journald + pkg cache)" →
  "Hotspots".
- TopDirsSection title (see §5): "Top $HOME dirs".
- TrendSection (Memory): keep section titles but ensure we don't run
  over. Trim "Real memory pressure (used / total)" to "Pressure".

All label shortenings will go through a single constants block at the
top of each panel so translations/rewording stay in one place.

---

## 7. Lifecycle audit — verify procs/timers stop on close

**Claim to verify:** services already gate their `running` property on
`detailActive` (MemoryDetail:99-134, StorageDetail:59-65). When the
panel closes, all Timer `running` bindings re-evaluate to false and
Timer stops firing; in-flight `Process` instances run to completion on
the next tick but no new ones are spawned.

**What's NOT in place:**
- Explicit verification that no Process is *still running* when panel
  closes (e.g., a slow `du -xb $HOME` that takes 20 s will keep running
  for another 20 s after close).
- Documentation of the expected resource profile when closed.

**Fix (revised per review):**

(a) Add explicit `destroy-on-close`. **Critical contract** from
sonnet review: in Quickshell, `proc.running = false` does NOT
reliably SIGTERM the child. It DOES terminate the immediate child
(the bash/shell process). If that child is `timeout N <cmd>`, the
POSIX `timeout` utility DOES forward SIGTERM to its child. All our
existing Process blocks already wrap in `timeout` → safe. This MUST
be enforced as an invariant.

```qml
// MemoryDetail:
onDetailActiveChanged: {
    if (!detailActive) {
        // Each of these is wrapped in `timeout N bash -c …` at the
        // command-array level — stopping the Process kills timeout,
        // which propagates SIGTERM to gawk/du/etc. If a new Process
        // is added WITHOUT timeout wrapper, it will leak orphans.
        // See test-detail-panels-lifecycle.sh which enforces this.
        if (procsProc.running)      procsProc.running = false
        if (memInfoProc.running)    memInfoProc.running = false
        if (somewmProc.running)     somewmProc.running = false
        if (somewmRssProc.running)  somewmRssProc.running = false
        // Reset so next open starts clean (otherwise user sees stale
        // "45 % pressure" flash from 3 minutes ago before first probe
        // lands).
        procsLoaded = false
        somewmLoaded = false
    } else {
        // Kick off immediate fetch — don't wait for Timer.
        refresh()
    }
}
```

StorageDetail: same pattern on `mountsProc`, `hotspotsProc`,
`topDirsProc`, `paccacheDryProc`, plus the new `homeTotalProc`
introduced in §5.

(b) **Invariant test (new test file):** every Process in the detail
services must have `"timeout "` as the first arg in its `command`
list. Add this to test-detail-panels.sh:

```bash
for svc in services/MemoryDetail.qml services/StorageDetail.qml \
           services/CpuDetail.qml; do
    awk '/Process \{/,/^    \}/' "$SHELL_DIR/$svc" \
      | grep -E 'command:\s*\[' \
      | grep -v '"timeout "' \
      && fail "$svc: Process without timeout wrapper (orphan risk)"
done
```

(c) Write `plans/tests/test-detail-panels-lifecycle.sh` (NEW FILE):
spawn nested somewm + QS, open each detail panel, kick off a slow
operation (e.g., open storage panel to start `du -xb $HOME`), close
panel immediately, sleep 5 s, then grep `/proc/<qs_pid>/task/*/comm`
for `du|gawk|nvidia-smi|sleep|bash` survivors. Any survivors = FAIL.

(d) Instrument `detailActive` changes with console.debug in the
services so the QS log shows open/close transitions explicitly.
Helps when triaging future lifecycle bugs.

(e) **Future refactor (flagged not blocking):** gemini is correct
that pure-QML `/proc` reading via `FileView` would eliminate the
subprocess class of lifecycle bugs entirely. Out of scope for this
PR — document as TODO in CpuDetail.qml.

---

## 8. New CPU/GPU detail panel

Same architecture as MemoryDetail/StorageDetail, new name
`"cpu-detail"`.

**Sections** (top → bottom):

### 8.1 System Overview
- Kernel string (from `/proc/sys/kernel/osrelease` via FileView —
  instant read, no uname subprocess needed)
- Uptime (from `/proc/uptime` via FileView, humanised: "4 h 12 m")
- Load avg: 1/5/15 min from `/proc/loadavg` via FileView, colored red
  if `load1 > cpuCount`
- CPU model + core count (from `/proc/cpuinfo` FileView — parse
  "model name" once; `nproc` equivalent via counting processor lines)
- **GPU model (revised per sonnet review):** first-open, synchronous:
  `/sys/class/drm/card*/device/vendor` + `device` files (instant, no
  subprocess). Map PCI IDs to names via a small embedded lookup table
  for common NVIDIA/AMD IDs, fall back to the raw hex if unknown.
  Spawn `nvidia-smi` ONLY for live utilisation (section 8.4), not for
  model detection — saves 150-300 ms cold start on every panel open.

Rendered like a compact 2-column grid (label: value) with monospace
values, similar to SomewmInternalsSection in MemoryDetail.

### 8.2 Per-core utilisation (LIVE)

**Revised per gemini + sonnet review:** the original plan used a bash
script with `cat /proc/stat; sleep 1; cat /proc/stat` in one
subprocess, triggered by a 1.5 s Timer. Problems:
- 1 s sleep + process teardown can exceed 1.5 s Timer interval → ticks
  overlap or drop silently.
- Bash subprocess churn = CPU overhead measuring itself.

**New approach:** pure QML delta sampling via `FileView`
(Quickshell.Io). Read `/proc/stat` every 2 s into a JS string, parse
cpu0..cpuN lines in JS, keep last snapshot in a property, compute
delta in JS. Zero subprocess churn, zero overlap risk.

```qml
FileView {
    id: procStatView
    path: "/proc/stat"
    blockLoading: false
    watchChanges: false  // we poll manually; /proc inotify is unreliable
    onLoaded: root._onStatLoaded(text())
}

Timer {
    id: statTimer
    interval: 2000
    repeat: true
    running: root.detailActive
    onTriggered: procStatView.reload()
}

property var _prevStat: null  // { cpuN: { total, idle } }
property var perCoreUsage: []  // [ { core: "C0", pct: 42 }, ... ]

function _onStatLoaded(text) {
    var now = _parseStat(text)  // parse into per-cpu totals
    if (_prevStat) {
        var out = []
        for (var k in now) {
            if (!_prevStat[k]) continue
            var dTot = now[k].total - _prevStat[k].total
            var dIdle = now[k].idle - _prevStat[k].idle
            if (dTot <= 0) continue
            out.push({ core: k.toUpperCase(),
                       pct: Math.max(0, Math.min(100, 100 * (1 - dIdle/dTot))) })
        }
        perCoreUsage = out
    }
    _prevStat = now
}
```

- 1 bar per core, labelled `C0` … `CN`.
- Color: green → orange → red gradient by pct.
- Update every 2 s (was 1.5 s; bumped for margin).
- Fallback if `FileView` doesn't suit: Process with `timeout 2 bash
  -c "cat /proc/stat"` (single snapshot, no sleep, self-throttling via
  `onExited: statTimer.restart()`).

### 8.3 Top processes (BY CPU)
- Same row-with-bar layout as Memory's top-processes.
- Sampled from `/proc/[0-9]*/stat` using `utime + stime` delta. Same
  subprocess-free approach as §8.2 is harder here (need per-pid reads
  — QML `FileView` loops over hundreds of files would be slow). Stay
  with a bash Process for this section but:
  - Use `timeout 4 bash -c …` wrapper (SIGTERM-safe, per §7).
  - Use gawk single-pass over `/proc/[0-9]*/stat` — same idiom as
    MemoryDetail's procsProc (§MemoryDetail round-3 fix).
  - Self-throttle: kick next sample from `onExited`, not fixed Timer.
  - Two snapshots: read all stats, sleep 1 s INSIDE the same gawk
    program, read again, emit deltas. Single subprocess per refresh.
- **Reuse the §3 animation fix** (Option C delegate gate) so this
  panel doesn't have the same jump-from-zero regression.

### 8.4 GPU utilisation (NVIDIA-only, gated)
- If `nvidia-smi` exists: single `nvidia-smi --query-gpu=utilization.gpu,
  utilization.memory,memory.used,memory.total,temperature.gpu
  --format=csv,noheader,nounits` call every 2 s.
- Show as 4 mini stat cards (GPU %, VRAM, VRAM used/total, °C).
- If no nvidia-smi: section hidden, not an error.

### 8.5 Top GPU processes (NVIDIA-only, gated)
- `nvidia-smi --query-compute-apps=pid,process_name,used_memory
  --format=csv,noheader,nounits`
- Simple list (PID, name, VRAM). No bars needed — usually 0–3 rows on
  desktop.

### 8.6 Fastfetch-style footer (static, load once)
- `uname -m`, `lsb_release -d` / `/etc/os-release`, desktop
  environment ("somewm"), shell ($SHELL), total RAM, resolution.
- Loaded once on first `detailActive`, cached for session.

### 8.7 Footer actions
- "htop" → `awful.spawn({"alacritty", "-e", "htop"})`
- "btop" (if installed)
- "nvidia-smi dmon" (if NVIDIA)

**Files to add:**

- `services/CpuDetail.qml` (new singleton — timers, Processes, parsers)
- `modules/cpu-detail/CpuDetailPanel.qml` — PanelWindow shell
- `modules/cpu-detail/SystemSection.qml`
- `modules/cpu-detail/CoresSection.qml`
- `modules/cpu-detail/TopCpuProcessesSection.qml`
- `modules/cpu-detail/GpuSection.qml`
- `modules/cpu-detail/TopGpuProcessesSection.qml`
- `modules/cpu-detail/FastfetchFooter.qml`
- `modules/cpu-detail/FooterActions.qml`
- `modules/cpu-detail/qmldir`
- `plans/project/somewm-one/fishlive/components/cpu.lua` — wibar widget

**Files to edit:**
- `core/Panels.qml` — add `"cpu-detail"` to `overlays` (anyOverlayOpen)
  and `exclusive` lists. **Ideally** convert to a constant declared
  once and reused to avoid future triple-edit bugs.
- `services/qmldir` — `singleton CpuDetail CpuDetail.qml`
- `core/DetailController.qml` — add `Services.CpuDetail.detailActive`
  refresh hook.
- `shell.qml` — import cpu-detail module, instantiate `CpuDetailPanel`.
- `modules/dashboard/PerformanceTab.qml` — the CPU HeroCard (lines
  38-52) currently has no gear. Add `detailPanel: "cpu-detail"` to the
  card's signal handler; the existing `GaugeCard.detailPanel` pattern
  auto-renders the gear when set. If HeroCard doesn't support
  `detailPanel`, add the gear row manually using the same pattern.
- `plans/project/somewm-one/rc.lua` — autostart already covers
  `fishlive.components.cpu` via the wibar aggregator if we add it to
  the widgets list; confirm and wire.

**Central panel registry** (separate commit BEFORE CPU panel work,
per both reviewers — must be bisect-friendly):

Rather than keep editing two arrays in Panels.qml every time a new
detail panel is added, declare once at the top of the file:

```qml
// overlayPanels: all panels that count as "open overlay" for the
// compositor scroll-guard IPC push (includes sidebar-left).
readonly property var overlayPanels: [
    "dashboard", "wallpapers", "weather", "ai-chat",
    "sidebar-left",
    "memory-detail", "storage-detail",
]
// exclusivePanels: panels that mutually close each other when one
// opens. DELIBERATELY excludes sidebar-left — sidebar is a
// non-mutually-exclusive overlay (e.g. the quick-settings sidebar
// can be open WHILE the dashboard is open).
// Do not merge the two lists. The asymmetry is correct.
readonly property var exclusivePanels: [
    "dashboard", "wallpapers", "weather", "ai-chat",
    "memory-detail", "storage-detail",
]
```

**Commit 1** (this refactor, no new panels): convert inline literals
to these two properties, verify sandbox behaviour unchanged (memory
+ storage panels still mutually exclusive, sidebar-left still allowed
alongside). Test-detail-panels.sh gets a new guard asserting
`sidebar-left` is in overlayPanels but NOT in exclusivePanels — this
asymmetry MUST persist.

**Commit 2** (this CPU panel feature): adds `"cpu-detail"` to both
arrays (it IS mutually exclusive with dashboard/memory/storage).

---

## 9. Tests

**Extend `plans/tests/test-detail-panels.sh`:**

- **qmllint** list grows by ~10 new QML files.
- **registration**: verify new qmldir entries, new ModuleLoader block
  in shell.qml, new `cpu-detail` pin in `Panels.overlayPanels`.
- **CpuDetail parser contract:**
  - `/proc/stat` delta sampler: feed a fixture with two snapshots,
    expect computed per-core % ± tolerance.
  - `/proc/loadavg`: trivial float extract.
  - `nvidia-smi` CSV: feed fixture, assert the 5 fields get extracted.
  - Fastfetch OS release: feed `/etc/os-release` fixture, expect the
    `PRETTY_NAME` extraction.
- **Round-4 fix guards** (added to test-detail-panels.sh):
  - System overview bar has a percent label (grep for
    `anchors.centerIn: parent` under a Components.StyledText within
    the barTrack block).
  - System overview bar's inner Rectangles have `radius: 0` (flat
    seam enforced).
  - System overview bar has legend Row (grep for the legend strings).
  - Top-processes delegate gates Behavior on `_ready` flag.
  - Top-dirs renders a percent column.
  - Footer button labels are shortened (grep for the new strings, NOT
    the old "Open baobab" etc).
  - Each service has a `onDetailActiveChanged` block that cancels
    in-flight Process instances when panel closes.
- **Lifecycle regression test (new file, separate):**
  `plans/tests/test-detail-panels-lifecycle.sh` — spawns nested
  somewm + QS, opens each detail panel, closes it, greps for stale
  `du` / `gawk` / `nvidia-smi` children 3 s after close. FAIL if any.

---

## 10. Review strategy

Previous rounds established:
- codex gpt-5.5 exploration-heavy, poor at large-diff summary
- gemini-3.1-pro-preview decent but rate-limited
- sonnet in Agent tool — fastest turnaround, good signal

For this plan:

**Before implementation:**
- codex gpt-5.5 on the plan doc itself (not diff) — review the
  architectural decisions (§2 clip trick, §3 stable-model trade-off,
  §8 registry refactor). Plan doc is ~500 lines, well under codex's
  bite-size.

**After implementation:**
- sonnet (Agent tool) on implementation diff.
- codex gpt-5.5 only if diff fits (< 2000 lines).
- gemini-3.1-pro-preview skip unless first two are clean (no need to
  burn quota on a third opinion when we already have two).

Iterate until no HIGH or MEDIUM findings.

---

## 11. Open questions for user

- §1: hard cap at 1400 px acceptable? (portrait-HP edge case)
- §3: Option C chosen. If user wants smooth reshuffle later, promote to
  Option B (ListModel diff). Flagging now; not blocking.
- §4 Fix C: replace Trend sparklines for Lua/Wallpaper with textual
  delta? (saves vertical space, more informative)
- §5: percent column = "% of $HOME shown" (top 10 sum). Surface "real"
  $HOME total via an extra `du -xb $HOME` (no depth) call? Cheap on
  modern SSD, but one extra process per refresh.
- §8.2: 1.5 s refresh for per-core bars — too aggressive? Fine for
  modern CPU but generates /proc/stat reads.
- §8.4 GPU: NVIDIA-only OK for this user (RTX 5070 Ti), but should we
  sniff AMD (`amdgpu_top` / `radeontop`) as a TODO? Flag in code as
  `// TODO: AMD via radeontop when someone asks for it`.

---

## 12. Implementation order (revised)

Each numbered step = one atomic commit. Rebase-friendly. Runs
`test-detail-panels.sh` after every step — fail fast.

1. **§7 lifecycle** — add `onDetailActiveChanged` force-stop + timeout
   invariant test. Apply to both existing services. ~80 LOC total.
2. **§1 height + §6 labels** — pure polish. ~30 LOC total.
3. **§3 animation** — delegate `_ready` gate in TopProcessesSection +
   TopDirsSection. ~10 LOC per file.
4. **§2 bar chart** — clip + legend + percent label, per sonnet's
   left-cap correction. ~60 LOC.
5. **§4 Trend rework** — drop Lua/Wallpaper sparks for text deltas,
   add Y-axis labels to RSS. ~80 LOC.
6. **§5 top dirs percent** — new `homeTotalProc` in StorageDetail +
   percent column + header label. ~40 LOC.
7. **Panel registry refactor** — §8 "Central panel registry" as
   STANDALONE commit (no new panel yet). Verify asymmetry. ~30 LOC.
8. **§8 new CPU/GPU panel** — ~8 new QML files, 1 service, lua wibar
   widget, dashboard gear wire-up. ~1500 LOC total.
9. **§9 tests** — extend test-detail-panels.sh and add
   test-detail-panels-lifecycle.sh (new file). ~100 LOC.
10. Final review pass (§10) on the complete diff.
11. Deploy, user live tests.

If any step fails review, drop that step and the ones depending on
it; re-plan rather than force through.
