# fishlive.autostart — Wayland-native autostart for somewm

**Status:** plan, not implemented (revised after Sonnet review)
**Author:** Antonin Fischer (raven2cz) + Claude Opus 4.7
**Date:** 2026-04-26
**Related:** `codex-design.md` (Codex gpt-5.4 first draft, 297 lines)

## 1. Goal

Replace the broken XDG-autostart pipeline (systemd `app-*@autostart.service`)
with a Lua-native autostart system that:

- Knows about Wayland/somewm-specific session readiness (XWayland, tray,
  portal, screen decoration)
- Supervises long-lived daemons with retry+backoff
- Logs per-entry to a dedicated file
- Exposes runtime status via `somewm-client` IPC
- Keeps the user's preferred declarative model — no `awful.spawn.once` from rc.lua

**Concrete failures we're fixing:**

- `synology-drive` (Qt5) SIGABRT — `xdg-desktop-autostart.target` fires before
  XWayland's DISPLAY socket binds
- `blueman-applet` (GTK Python) `AttributeError: NoneType.prepend_search_path`
  — fires before icon theme cache initializes
- `awful.spawn.once` is naive: no retry, no logging, no status, lost on reload

**Upstream vs fork split (read this before everything else):** somewm is a
generic compositor framework that we contribute back to `trip-zip/somewm`.
Anything we touch in upstream files (C source, `lua/awful/`, `lua/gears/`,
upstream `tests/`) must be **generic, reusable, and PR-able**. Personal
config, our `fishlive.*` modules, and project-specific automation live
strictly under `plans/project/somewm-one/` and `plans/`. This plan is
explicitly designed in two layers (§4.1 upstream-ready, §4.2 fork-local) so
the upstream-suitable changes can ship as a focused PR independently of our
private autostart system.

## 2. Synthesis vs Codex design

Codex proposed 14 source files + 8 test files. **I'm cutting that to 5+4**
because this is personal config, not a generic library. Concrete deviations:

| Codex proposed | This plan | Why |
| --- | --- | --- |
| 14 separate files (init, scheduler, supervisor, log, status, providers/{init,compositor,xwayland,tray,portal,dbus,custom}, spawn, spawn_backends/{awful,start_process}) | 5 files (init, entry, providers, spawn, log) | Avoid scaffolding before lines exist. Split when files exceed ~300 lines. |
| New `autostart.on_ready()` API | Reuse `fishlive.broker.connect_signal()` directly + provider emits via `broker.emit_signal()` (NOT `register_producer()`) | Broker already does sticky values + late-join replay. Bypass producer-lifecycle so D-Bus watchers never get torn down by consumer-disconnect. |
| `mode = "dbus_activated"` | Dropped from v1 | "Don't register it" is simpler than a no-op mode. blueman dbus-activates naturally if not autostarted |
| `pre_check`, `post_check` callbacks | Dropped from v1 | Codex itself flagged "can become ad hoc". Add later if real cases demand |
| `pidfile` field | Dropped from v1 | Internal PID tracking + native exit callbacks cover the cases we care about |
| Backoff reset after 30 s healthy | Reset after 60 s | 30 s is too short for slow-loading apps that crash 25 s after start |
| Separate `providers/custom.lua` | Drop — just emit on `fishlive.broker` from outside | Custom signals don't need a provider module |
| `ready::dbus(<name>)` notation | `ready::dbus:<name>` (colon, not parens) | Cleaner string, no shell-escape pitfalls in IPC eval; aliases `ready::tray`/`ready::portal` are emitted simultaneously by `providers.lua` |

**Kept verbatim from Codex (good calls):**
- File location: `plans/project/somewm-one/fishlive/autostart/` (user config, not framework)
- C-side hooks exactly as specced (with hot-reload mirror)
- State machine names and transitions
- Backoff formula `min(base * 2^(n-1), 60)` seconds
- Test strategy 3-layer (unit / integration / smoke)
- Migration plan: incremental, never disable XDG before native works
- Log rotation by size (1 MiB), keep `.log`, `.log.1`, `.log.2`

## 3. Architecture

### 3.1 Components

```
┌─────────────────────────────────────────────────────────────────┐
│ rc.lua                                                          │
│   require("fishlive.autostart").add{...}; ....start_all()       │
└──────────┬──────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────┐    reads     ┌───────────────────────┐
│ fishlive.autostart      │◄─────────────┤ fishlive.broker       │
│   init.lua (public API) │              │ (existing pub/sub     │
│   entry.lua (state mach)│              │  with sticky cache)   │
│   spawn.lua (backends)  │              └───────▲───────────────┘
│   log.lua (rotation)    │                      │ emit
└─────┬───────────────────┘              ┌───────┴───────────────┐
      │ spawns                           │ providers.lua         │
      ▼                                  │   xwayland watcher    │
   awful.spawn.with_line_callback        │   tray DBus watcher   │
                                         │   portal DBus watcher │
                                         │   compositor signal   │
                                         │   bridge (somewm::*)  │
                                         └───────▲───────────────┘
                                                 │
                                                 │ awesome.connect_signal
                                                 │
                              ┌──────────────────┴──────────────┐
                              │ C: somewm.c, xwayland.c          │
                              │   luaA_emit_signal_global(...)   │
                              │     "somewm::ready"              │
                              │     "xwayland::ready"            │
                              └──────────────────────────────────┘
```

### 3.2 Why broker, not a new bus

`fishlive.broker` already provides exactly what we need:
- `emit_signal(name, value)` caches last value
- `connect_signal(name, fn)` immediately invokes fn with cached value if any
- pcall wrapping per consumer (one bad subscriber doesn't break others)

Readiness signals are values too (`true` once ready). Using broker means:
- Late-loaded autostart entries see ready signals that fired earlier
- No new pub/sub mechanism to maintain
- `providers/` just calls `broker.emit_signal("ready::xwayland", true)`

We use `ready::*` namespace on the broker to keep semantics clear:
- `ready::somewm` — main loop ready
- `ready::xwayland` — DISPLAY usable
- `ready::screen` — all initial screens decorated (deferred to v1.1)
- `ready::tray` — `org.kde.StatusNotifierWatcher` owned
- `ready::portal` — `org.freedesktop.portal.Desktop` owned
- `ready::dbus:<name>` — generic D-Bus name appeared (e.g. `ready::dbus:org.kde.StatusNotifierWatcher`)

**Canonical naming rule:** `ready::tray` and `ready::portal` are *aliases* for
specific generic D-Bus gates. Both names are emitted simultaneously by
`providers.lua` so users can write `when = { "ready::tray" }` (preferred,
short) or `when = { "ready::dbus:org.kde.StatusNotifierWatcher" }` (verbose,
explicit). Documentation examples always use the short alias. The `:`
separator (not parentheses) keeps the name a valid Lua identifier-friendly
string and avoids the `()` ambiguity Sonnet flagged.

## 4. File layout

This work splits cleanly into TWO independent layers — an **upstream-ready
generic layer** (C signals + their tests) and a **fork-local user-config
layer** (`fishlive.autostart`). The fork-local layer depends on the upstream
layer's signals, but the upstream layer has zero knowledge of `fishlive.*`.

### 4.1 Upstream-ready layer (must be PR-able to `trip-zip/somewm`)

```
somewm.c             emit "somewm::ready" after first some_refresh()
xwayland.c           emit "xwayland::ready" after EWMH init
luaa.c               re-emit cached ready signals on hot reload
globalconf.h         add bool somewm_ready_seen, xwayland_ready_seen

tests/
├── test-signal-somewm-ready.lua    Compositor emits "somewm::ready" exactly once per cold boot
├── test-signal-xwayland-ready.lua  Compositor emits "xwayland::ready" after XWayland init
└── test-signal-hot-reload.lua      After awesome.restart(), both signals re-emit
```

These tests connect via `awesome.connect_signal` from a test rc.lua and
assert via `somewm-client eval`. They make NO reference to `fishlive.*` and
are valid regardless of whether anyone uses the signals. They are the
upstream contract.

### 4.2 Fork-local layer (lives only in our user config)

```
plans/project/somewm-one/fishlive/autostart/
├── init.lua          Public API: add, start_all, status, restart, stop
├── entry.lua         Per-entry state machine, gate resolution, backoff
├── providers.lua     Compositor + DBus watcher providers, single bus connection
├── spawn.lua         Spawn backends: awful (default), start_process (legacy)
└── log.lua           Per-entry file logger with size rotation

plans/project/somewm-one/spec/
└── autostart_spec.lua             Unit: state machine + scheduler + log + backoff

plans/tests/
├── test-autostart-lifecycle.sh    Integration: signal order + status IPC
├── test-autostart-xwayland.sh     Integration: X11 entry waits for ready::xwayland
└── test-autostart-tray.sh         Integration: tray entry waits for ready::tray
```

Fork-local tests live under `plans/tests/` (not upstream `tests/`) because
they `require("fishlive.autostart")` which doesn't exist upstream.

## 5. Public API

```lua
local autostart = require("fishlive.autostart")

-- Register an entry (does NOT start it)
autostart.add {
    name    = "blueman",                       -- mandatory, unique
    cmd     = { "blueman-applet" },            -- mandatory; table preferred over string
    when    = { "ready::tray", "ready::portal" }, -- gates; default {"ready::somewm"}
    mode    = "respawn",                       -- "oneshot" (default) | "respawn"
    retries = -1,                              -- TOTAL attempts; -1 = unlimited; 1 = try once (oneshot default), 2 = try twice, ...
    delay   = 0,                               -- extra wait after gates (s)
    timeout = 30,                              -- max wait for gates (s)
    log     = true,                            -- true | false | "/custom/path.log"
    env     = { GTK_THEME = "Adwaita" },       -- merged into compositor env
    replace = true,                            -- if managed instance exists, kill + restart
    disabled = false,                          -- registered but not scheduled
}

-- Start scheduler (call once at end of rc.lua)
autostart.start_all()

-- Runtime control (also exposed via IPC)
autostart.status()         -- → { entries = { [name] = {...state...} } }
autostart.restart("name")  -- → bool, err?
autostart.stop("name")     -- → bool, err?
```

### 5.1 `status()` return shape

```lua
{
    generation = 7,                   -- compositor restart counter
    ready = {
        ["ready::somewm"]   = true,
        ["ready::xwayland"] = true,
        ["ready::tray"]     = false,
        ["ready::portal"]   = true,
    },
    entries = {
        ["blueman"] = {
            state       = "gated",          -- pending|gated|starting|running|died|restart_pending|failed
            mode        = "respawn",
            attempts    = 0,
            pid         = nil,
            started_at  = nil,
            died_at     = nil,
            exit_code   = nil,
            log_path    = "/home/box/.local/log/somewm-autostart/blueman.log",
            waiting_for = { "ready::tray" },
        },
        ["synology-drive"] = {
            state       = "running",
            mode        = "oneshot",
            attempts    = 1,
            pid         = 12345,
            started_at  = 1714142103,
        },
    },
}
```

### 5.2 IPC

```bash
somewm-client eval 'local s = require("fishlive.autostart").status(); for n,e in pairs(s.entries) do print(n, e.state, e.pid or "-") end'
```

## 6. State machine

```
       add()             start_all()           gates met + delay
pending ─────► (in registry) ──────► gated ────────────────────► starting
                                       │ timeout                     │ spawn ok
                                       ▼                             ▼
                                    failed ◄─── manual restart ─── running
                                       ▲                             │ exit
                                       │ retries=0                   ▼
                                       └──────────────────────────  died
                                                                     │ retries left
                                                                     ▼
                                                              restart_pending
                                                                     │ backoff timer
                                                                     ▼
                                                                 starting
```

State transition rules implemented in `entry.lua`. Each state has explicit
enter/exit hooks for timer cleanup. Generation counter prevents stale-callback
bugs (same pattern as `fishlive.service`).

**Manual-stop transitions (not shown in diagram):**
- `gated → pending` on `autostart.stop(name)` — entry returns to registry, gates discarded
- `running → pending` on `autostart.stop(name)` — SIGTERM the PID, then transition
- `restart_pending → pending` on `autostart.stop(name)` — cancel backoff timer
- `failed → gated` on `autostart.restart(name)` — reset attempts to 0

**Hot-reload semantics:** On `awesome::restart`, all entries get `exit`
treatment (§7.1). The new Lua VM re-runs rc.lua, which re-registers entries
via `add()`. Broker state is wiped (new VM = new module load) but providers
re-populate it on init (§8.4). Critically, `xwayland::ready` will not
naturally re-fire because `xwaylandready()` does not re-run; the C-side
hot-reload mirror in `luaa.c` re-emits cached signals (§10).

## 7. Spawn + supervision

- **Default backend** (`spawn.lua` `awful_backend`): `awful.spawn.with_line_callback`
  - Returns PID + exit callback in one call
  - Stdout/stderr lines appended to log file
- **Legacy backend** (`spawn.lua` `start_process_backend`): wraps `~/bin/start_process`
  - Used only for entries with `backend = "start_process"` in spec
  - Internal PID tracking still tracks the wrapper, not the child
- **Backoff**: `min(base * 2^(attempt-1), 60)` seconds, base = `max(spec.delay, 1)`
- **Reset attempts**: if process stayed alive ≥ 60 s, reset attempt counter
- **Already running**: only check our own managed PID table. Don't `pgrep -f`
  by default (it's the fuzziness that broke `start_process` historically).
  If user really wants pgrep behavior, use `backend = "start_process"`.

### 7.1 Shutdown semantics

`awesome.connect_signal("exit", ...)` → walk managed-PID table:
- `respawn` mode: `SIGTERM` → wait 2 s via `gears.timer.start_new` → `SIGKILL` if still alive
- `oneshot` mode: leave alone (caller decided lifecycle)

Before sending `SIGKILL`, verify PID is still ours (`kill -0 pid` and check
exit-callback hasn't fired) — Linux PID recycling could otherwise hit an
unrelated process.

This is the Lua equivalent of systemd's `PartOf=somewm.service`.

### 7.2 Spawn failure handling

`awful.spawn.with_line_callback` returns `(pid, snid)` on success and a
`string` (error message) on failure (e.g. binary not found, fork failed).
`spawn.lua` must check the return type:
- Number PID → `entry → running`, register exit callback
- String error → log the error, transition `entry → died` immediately,
  count as one attempt, apply backoff per `mode`/`retries` rules

This makes "binary moved/uninstalled" behave like a normal crash, so the
backoff and `failed` paths cover it without special-casing.

## 8. Readiness providers

### 8.1 Compositor signal bridge

```lua
-- providers.lua
awesome.connect_signal("somewm::ready", function()
    broker.emit_signal("ready::somewm", true)
end)
awesome.connect_signal("xwayland::ready", function()
    broker.emit_signal("ready::xwayland", true)
end)
```

### 8.2 D-Bus name watchers

Single shared `Gio.bus_get(SESSION)` connection, **opened at module load
time** in `providers.lua` (not lazily on first `add()`). This guarantees
the watcher infrastructure exists before any `start_all()` call, so the
broker's sticky cache always has a real producer behind it. `bus_get` is
async; the providers module finishes loading regardless, and watchers
register inside the bus-acquired callback.

For each requested `org.foo` name, register `Gio.bus_watch_name_on_connection`
with both `name_appeared_callback` and `name_vanished_callback`. On appear,
emit BOTH the alias (if any) and the generic form:
```
broker.emit_signal("ready::dbus:org.kde.StatusNotifierWatcher", true)
broker.emit_signal("ready::tray", true)  -- alias
```
On vanish, emit `false` to both. Re-emit on appear → vanish → appear cycles.

**Critical: providers MUST emit via `broker.emit_signal()` directly, never
via `broker.register_producer()`.** The broker tears down a registered
producer when the last consumer disconnects, which would kill our D-Bus
watchers as soon as all entries finished gating. Direct emission bypasses
the producer-lifecycle machinery; the watchers live for the lifetime of
the providers module.

`ready::tray` and `ready::portal` are aliases hard-coded into `providers.lua`
for convenience. New aliases can be added by appending to a small alias map
without API change.

### 8.3 Re-emission on D-Bus name flap

`oneshot` entries that already transitioned to `running` ignore subsequent
re-emissions of their gates (the broker fires `connect_signal` on every
update, but `entry.lua` only acts on signal in `gated`/`pending` state).
`respawn` entries similarly ignore gate re-emissions while alive — they
only react to the next gate cycle if the process itself died first.

### 8.5 `screen::ready` (deferred to v1.1)

Codex proposed this; I'm deferring to v1.1 because:
- Requires touching `fishlive.config.screen` to emit a signal
- Most apps that need it can wait on `ready::tray` instead (tray host
  comes up after wibar)
- Adding it later is non-breaking

If a real case appears (multi-monitor app needing all screens decorated),
add it then.

## 9. Logging

Per-entry log: `~/.local/log/somewm-autostart/<name>.log`

Format:
```
2026-04-26T21:25:19.418+0200 [autostart entry=blueman state=starting attempt=1 pid=12345 gates=ready::tray,ready::portal]
2026-04-26T21:25:19.450+0200 [stdout] blueman-applet: starting plugin manager
...
2026-04-26T21:25:42.103+0200 [autostart entry=blueman state=running pid=12345 runtime=22.7s]
2026-04-26T21:31:01.220+0200 [autostart entry=blueman state=died pid=12345 exit=1 reason=exit runtime=341.8s]
```

Rotation: when file size > 1 MiB, rotate `.log` → `.log.1`, `.log.1` → `.log.2`,
delete `.log.2`. Check at each new log write (cheap stat).

Aggregate summary log: `~/.local/log/somewm-autostart.log` — one line per
state transition, no stdout/stderr. Useful for "what happened in last session".

## 10. C-side hooks (UPSTREAM contribution)

Three changes, all generic somewm framework. **This entire section is
designed for an upstream PR to `trip-zip/somewm`.** The signals are useful
for any user, regardless of whether they use `fishlive.autostart`:
- A user could `awesome.connect_signal("xwayland::ready", function() awful.spawn("xclock") end)` directly in rc.lua with no fork-local code.
- Other compositors with AwesomeWM-style Lua bridges can adopt the same
  signal contract.

Naming convention follows existing somewm/AwesomeWM signals
(`request::manage`, `mouse::enter`, `awesome::startup`). The `ready`
suffix matches dwl/sway terminology for "compositor reached steady state".

To support hot reload correctly, two C-side `bool` flags cache whether each
readiness milestone has fired:

```c
// globalconf.h (added to globalconf_t)
bool somewm_ready_seen;
bool xwayland_ready_seen;
```

| File | Location | Change |
| --- | --- | --- |
| `somewm.c` | `run()` after first `some_refresh()` (~line 752 area) | `globalconf.somewm_ready_seen = true; luaA_emit_signal_global("somewm::ready");` |
| `xwayland.c` | end of `xwaylandready()` after EWMH init succeeds (~line 245) | `globalconf.xwayland_ready_seen = true; luaA_emit_signal_global("xwayland::ready");` |
| `luaa.c` | hot-reload completion path after second `some_refresh()` | for each `*_ready_seen` flag set, re-emit the corresponding signal — parity with cold boot |

The two flags persist across hot reload because `globalconf` is C-side state
(not the Lua VM). Without the `xwayland_ready_seen` re-emission, post-reload
Lua subscribers gated on `xwayland::ready` would stall permanently because
`xwaylandready()` only runs once per XWayland process lifetime — this is a
generic correctness issue, not specific to autostart.

Function-name verification before coding: use `luaA_emit_signal_global`
exactly as defined in `somewm_api.c` (do not invent `luaA_signal_emit` or
similar; check actual source before each emission site).

### 10.1 Upstream PR scope

The PR includes:
- `globalconf.h` flag additions
- C emission sites in `somewm.c` and `xwayland.c`
- Hot-reload re-emission in `luaa.c`
- Three integration tests in `tests/` (signal-somewm-ready, signal-xwayland-ready, signal-hot-reload)
- Doc note in upstream README/AwesomeWM lib about the new signals

The PR does NOT include anything from `plans/`, `fishlive.*`, or our
themes — those stay fork-local.

Optional v1.1 (also potentially upstream): `awesome.compositor_ready()` Lua
getter returning cached bool. Defer until something actually needs it.

## 11. Library choices

| Need | Library | Why |
| --- | --- | --- |
| D-Bus name watching | `lgi.Gio.bus_watch_name_on_connection` | Already used by `awful.statusnotifierwatcher`, `awful.systray` |
| Timers | `gears.timer` | Standard somewm primitive, GLib main loop integration |
| Spawn + exit callback | `awful.spawn.with_line_callback` | Already used by `fishlive.service` for event watchers |
| Pub/sub with sticky cache | `fishlive.broker` | Existing in tree, exact semantics needed |
| Error isolation | `gears.protected_call` | Already used by `awful.spawn`, systray |
| Log timestamps | `os.date("!%Y-%m-%dT%H:%M:%S")` + `lgi.GLib.get_real_time()` for ms | Same pattern as `fishlive.startup_timer` |

No new dependencies. Everything is already in the somewm tree.

## 12. Test strategy

Three layers, mirroring the upstream/fork split from §4:

### 12.0 Upstream signal tests (`tests/test-signal-*.lua`, contributed to `trip-zip/somewm`)

| Test | Setup | Assertion |
| --- | --- | --- |
| `signal-somewm-ready` | rc.lua connects counter to `somewm::ready` | Cold boot: counter == 1 after first refresh; signal fires no more than once unless reload triggers it |
| `signal-xwayland-ready` | rc.lua connects flag to `xwayland::ready`; XWayland enabled in build | Flag transitions to true after `xwaylandready()` runs; never fires if XWayland disabled |
| `signal-hot-reload` | rc.lua counts each signal; trigger `awesome.restart()` mid-test | After reload, both `somewm::ready` and `xwayland::ready` re-fire (counter +1 each) — verifies `globalconf.*_ready_seen` mirror in `luaa.c` |

These tests do NOT use `fishlive.*`. They are the upstream contract for the
new signals and form the body of the upstream PR.

### 12.1 Fork-local unit (`plans/project/somewm-one/spec/autostart_spec.lua`, busted)

| Case | Asserts |
| --- | --- |
| Single-gate entry | `gated` → `running` after `broker.emit_signal("ready::x", true)` |
| Multi-gate entry | Stays `gated` until ALL gates fire |
| Late-join | Entry registered AFTER signal already emitted starts immediately |
| Gate timeout | Stays in gated for `timeout` s, transitions to `failed` |
| Backoff progression | After N deaths, delay matches `min(base * 2^(n-1), 60)` |
| Backoff reset | Death after 60s healthy → next backoff = base, not 2*base |
| `respawn` retries=-1 | Restarts indefinitely |
| `oneshot` retries=0 | Dies once, transitions to `failed` |
| `replace=true` | Kills existing PID before spawn |
| `disabled=true` | Stays in `pending`, never scheduled |
| Manual `restart()` from `failed` | Resets attempts, transitions to `gated` |
| Manual `stop()` from `gated` | Returns to `pending`, gates discarded |
| Manual `stop()` from `running` | SIGTERM sent, transitions to `pending` |
| D-Bus name flap on `oneshot` running entry | Re-emission of gate ignored, no relaunch |
| Spawn returns nil/string error | Counts as one attempt, transitions to `died` |
| Log format | Each transition writes correctly-formatted line |
| Log rotation | At 1 MiB, .log → .log.1, .log.1 → .log.2, .log.2 deleted |

Mock `awful.spawn`, `gears.timer`, `lgi.Gio` via dependency injection
(same pattern as `fishlive.service`).

### 12.2 Fork-local integration (`plans/tests/test-autostart-*.sh`)

| Test | Setup | Assertion |
| --- | --- | --- |
| `lifecycle` | Register fake entry on `ready::somewm`; cover `status()` IPC serialization | Status reflects each transition; PID is real; IPC returns full table |
| `xwayland` | Register entry on `ready::xwayland` before XWayland init; trigger `awesome::restart` after entry runs | Stays gated until `xwaylandready()` fires; survives hot reload (re-emit from `luaa.c`) |
| `tray` | Register entry on `ready::tray`, manually own `org.kde.StatusNotifierWatcher`, then drop name + re-own | Entry transitions only after first name acquisition; flap does not re-launch oneshot |

Use `~/git/github/somewm/plans/scripts/somewm-sandbox.sh` to run nested
compositor with these tests.

### 12.3 Smoke (manual)

In real TTY session after install:
1. Register blueman + synology + nm-applet via rc.lua
2. Boot, check `somewm-client eval 'return require("fishlive.autostart").status()'`
3. All three should be `running` within 10 s
4. Inspect logs in `~/.local/log/somewm-autostart/` for warnings
5. Kill blueman manually → verify it respawns
6. Kill synology manually → verify it does NOT respawn (oneshot)

## 13. Migration plan

Phased — never break existing autostart before native is proven.

Scope is intentionally narrow: only the three apps that today either race
the compositor or sit on `awful.spawn.once`. Everything else (conky,
volctl, polkit, kdeconnect, parcellite, …) is deliberately out of scope.
Polkit specifically has its own solution outside of autostart and is not
to be re-added here. Other XDG entries either work fine through their
existing path or are dormant under wlroots — no need to touch them
preemptively. Add later only if a concrete failure shows up.

| Phase | Action | Verify before next |
| --- | --- | --- |
| 1 | Land `fishlive.autostart` module + tests + C signals (no rc.lua change) | Unit + integration tests pass |
| 2 | Add `nm-applet` to autostart in rc.lua, remove `awful.spawn.once` line | Cold boot: nm-applet appears in tray |
| 3 | Add `blueman-applet` to autostart with `ready::tray` gate, delete `~/.config/autostart/blueman.desktop` | Cold boot: blueman tray icon appears, no GTK NoneType error |
| 4 | Add `synology-drive` to autostart with `ready::xwayland` gate, delete `~/.config/autostart/synology-drive.desktop` | Cold boot: synology starts after XWayland, no Qt5 SIGABRT |
| 5 | Cleanup: remove `Wants=xdg-desktop-autostart.target` from `contrib/systemd/somewm.service.in` if no remaining XDG entry needs it | Reboot — no orphan systemd autostart units, all three apps still up |

Rollback strategy at each phase: revert just that commit. Phases are
single-commit, single-purpose so rollback is trivial. Phases 3 and 4
also re-add the `.desktop` file on revert so the XDG fallback comes back
automatically.

**Diagnosing wedged session (no GUI feedback):** if a phase stalls and the
session has no tray icons / no blueman, drop to TTY (Ctrl+Alt+F2) and run:
```bash
somewm-client eval 'local s = require("fishlive.autostart").status(); for n,e in pairs(s.entries) do print(n, e.state, e.waiting_for and table.concat(e.waiting_for, ",") or "") end'
tail -50 ~/.local/log/somewm-autostart.log
ls ~/.local/log/somewm-autostart/
```
Entries stuck in `gated` for >30 s with `waiting_for = {"ready::tray"}`
indicate a D-Bus watcher misconfiguration; entries in `failed` with
non-zero `attempts` indicate a real spawn problem (check per-entry log).

## 14. Risks & mitigations

| Risk | Mitigation |
| --- | --- |
| `lgi` closures survive hot reload, leak memory | Generation-tag providers; on reload, disconnect all watchers + flush broker entries with `ready::*` prefix |
| D-Bus name flaps during portal restart | Edge-triggered: `oneshot` entries that already ran ignore re-emission. `respawn` entries respawn only if their PID died, not on signal |
| Race between `awesome::startup` and module load | Broker sticky cache replays past signals to late subscribers — already handled |
| User adds same entry twice via `add(spec)` with same name | `init.lua` errors loudly with "duplicate entry name" |
| Compositor crash leaves orphan PIDs | Same as today (XDG autostart has same issue). Optional v1.1: write a tracker file `~/.local/state/somewm-autostart.pids` for next-session cleanup |
| `oneshot` entry that legitimately needs to be re-runnable (e.g. wallpaper script) | User uses `mode = "oneshot"` + `autostart.restart(name)` IPC manually |
| NVIDIA/DRM timing differs nested vs real | Smoke test (§12.3) is mandatory in real TTY before declaring phase done |

## 15. Open questions for user

1. **`conky` and `volctl`** — these have `OnlyShowIn=Awesome;` in current
   .desktop files (so they're skipped under wlroots). Migrate to autostart
   in phase 5, OR leave them out of XDG and not autostart? (My recommendation:
   migrate to autostart so they have proper supervision)

2. **`start_process` retention** — keep `~/bin/start_process` as fallback
   backend (`backend = "start_process"`) for legacy entries, or fully retire
   it once natively-supervised? (My recommendation: keep for ~3 months,
   then audit and remove)

3. **C-side signal upstreaming timing** — `somewm::ready`, `xwayland::ready`,
   and the hot-reload mirror are designed as generic upstreamable changes
   (§4.1, §10.1). Two reasonable orderings:
   - **(a) PR first, fork-local autostart later** — submit `tests/test-signal-*.lua`
     + C changes upstream as a small, focused PR with no `fishlive.*`
     dependency. Build `fishlive.autostart` on top after upstream merges (or
     after our fork picks up the PR via merge commit).
   - **(b) Land in fork first, submit PR after autostart proves the value** —
     riskier for upstream review (they see a "why do we need this signal?"
     question), but lets us iterate faster if signal semantics need tweaking.
   - **Recommendation: (a)** — the signal contract is independently useful
     (any rc.lua user benefits) and the upstream tests stand on their own.
     Upstream PR review may take weeks; our fork merges the PR branch
     immediately so fork-local autostart work isn't blocked.

4. **Default for `mode`** — currently `oneshot`. Most desktop daemons (blueman,
   synology, nm-applet, parcellite) want `respawn`. Should default flip to
   `respawn`? (Recommendation: keep `oneshot` default — explicit `respawn` is
   safer than accidental respawn loops)

## 16. Implementation order (tasks)

**Phase A — Upstream PR branch (`upstream-pr/compositor-ready-signals`,
branched from `upstream/main`, NOT our divergent fork main):**

1. C-side: add `globalconf.somewm_ready_seen` + `globalconf.xwayland_ready_seen` flags
2. C-side: emit `xwayland::ready` in `xwayland.c` (smallest change first)
3. C-side: emit `somewm::ready` in `somewm.c`
4. C-side: hot-reload mirror in `luaa.c` (re-emit cached signals)
5. Tests: `tests/test-signal-somewm-ready.lua`
6. Tests: `tests/test-signal-xwayland-ready.lua`
7. Tests: `tests/test-signal-hot-reload.lua`
8. Open upstream PR; meanwhile cherry-pick the branch into our fork main so phase B can proceed

**Phase B — Fork-local autostart (`feat/fishlive-autostart`, branched from
our fork main with PR branch already merged in):**

9. Lua: `fishlive/autostart/log.lua` (no deps, easy to test)
10. Lua: `fishlive/autostart/spawn.lua` (mockable backends)
11. Lua: `fishlive/autostart/entry.lua` (state machine, takes log+spawn as deps)
12. Lua: `fishlive/autostart/providers.lua` (broker integration + DBus watchers)
13. Lua: `fishlive/autostart/init.lua` (public API + scheduler glue)
14. Tests: `plans/project/somewm-one/spec/autostart_spec.lua` (unit, all cases from §12.1)
15. Tests: `plans/tests/test-autostart-*.sh` (integration, 3 tests)
16. rc.lua: phase 2 (nm-applet migration)
17. Smoke test in nested + real session
18. Phases 3-5 from §13 (blueman, synology-drive, XDG-target cleanup) —
    nothing else; conky / volctl / polkit are explicitly out of scope

Each step is one commit with conventional commit message. Phase A commits
must be reviewable in isolation — no `fishlive.*` references, no `plans/`
files, no fork-specific paths.
