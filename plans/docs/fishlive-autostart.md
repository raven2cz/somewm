# fishlive.autostart — Wayland-native autostart for somewm

A declarative, gated, supervised autostart system for the somewm Wayland
compositor. Replaces the broken `xdg-desktop-autostart.target` pipeline
(systemd `app-*@autostart.service`) with a Lua-native scheduler that knows
about Wayland/somewm-specific session readiness and supervises long-lived
daemons.

- **Module:** `fishlive.autostart`
- **Location:** [`plans/project/somewm-one/fishlive/autostart/`](../project/somewm-one/fishlive/autostart/)
- **Design plan:** [`plans/fishlive-autostart/plan.md`](../fishlive-autostart/plan.md)

## Why

The XDG-autostart pipeline has three concrete failures on somewm:

- **`synology-drive`** SIGABRTs because `xdg-desktop-autostart.target` fires
  before XWayland's DISPLAY socket binds (somewm starts XWayland in lazy
  mode).
- **`blueman-applet`** crashes with `AttributeError: NoneType.prepend_search_path`
  because the GTK icon theme cache is not yet initialized at autostart time.
- **`awful.spawn.once`** is naive: no retry, no logging, no status, lost on
  reload, no notion of "wait until tray is ready".

`fishlive.autostart` solves all three: gates on `ready::*` broker signals,
supervises with retry+backoff, logs per-entry, exposes runtime status via
`somewm-client` IPC, and survives `awesome.restart()` without re-spawning
oneshots.

## Quick start

```lua
local autostart = require("fishlive.autostart")

autostart.add{
    name = "nm-applet",
    cmd  = { "nm-applet" },
    mode = "respawn",
}

autostart.add{
    name = "blueman-applet",
    cmd  = { "blueman-applet" },
    when = { "ready::tray" },
    mode = "respawn",
}

autostart.add{
    name = "synology-drive",
    cmd  = { "synology-drive" },
    when = { "ready::xwayland" },
    mode = "oneshot",   -- launcher script that forks daemons and exits 0
}

autostart.start_all()
```

`add()` registers the entry and pre-warms its D-Bus watchers; `start_all()`
schedules every registered entry. Call `start_all()` exactly once at the end
of `rc.lua`.

## API

### `autostart.add{ spec }`

Register one entry. Does not start it — call `start_all()` afterwards.

| Field      | Type            | Default        | Meaning |
|------------|-----------------|----------------|---------|
| `name`     | `string`        | required       | Unique identifier; used as broker key, log filename, and status key. Must be unique. |
| `cmd`      | `string` or `table` | required   | Command line. Tables are passed argv-style; strings go through the shell. |
| `when`     | `table<string>` | `{}`           | List of broker signals (gates) that must all be `true` before spawn. Common: `"ready::somewm"`, `"ready::xwayland"`, `"ready::tray"`, `"ready::portal"`, `"ready::dbus:<name>"`. |
| `mode`     | `string`        | `"oneshot"`    | `"oneshot"` (run once; success → `done`) or `"respawn"` (keep alive forever). |
| `retries`  | `integer`       | `1` / `-1`     | Retry budget on crash. `-1` = infinite (default for respawn). Default 1 for oneshot. |
| `delay`    | `number`        | `0`            | Seconds to wait after gates pass before spawning. Useful for staggering. |
| `timeout`  | `number`        | `0` (off)      | If gates do not pass within `timeout` seconds, transition to `failed`. |
| `log`      | `string`/`false`| auto path      | Override log path, or `false` to disable file logging. |
| `env`      | `table<string,string>` | `{}`    | Extra environment variables for the child. |
| `replace`  | `boolean`       | `false`        | If a same-named entry exists, replace it (otherwise `add` errors). |
| `disabled` | `boolean`       | `false`        | Register but do not start. Useful for theming/per-host gating. |
| `backend`  | `string`        | auto           | Spawn backend: `"awful"` or `"start_process"`. Defaults to the awful path. |

### `autostart.start_all()`

Start the scheduler. Idempotent; subsequent calls are no-ops.

### `autostart.restart(name) → boolean[, err]`

Restart an entry. Only valid for entries in the `failed` state — for
everything else use `stop()` + `start_all()`.

### `autostart.stop(name) → boolean[, err]`

SIGTERM the process (if running), discard gates, transition back to
`pending`.

### `autostart.status() → table`

Snapshot of all entries plus `ready::*` cache. See [Status snapshot](#status-snapshot).

### `autostart.list() → table<string>`

Registration order list, useful for IPC pretty-printers.

## State machine

```
                    autostart.add{ spec }
                            │
                            ▼
                      ┌──────────┐
                      │ pending  │  ← initial state after registration
                      └────┬─────┘
                           │ start_all() / e:start()
                           ▼
              gates_satisfied(self)?
                  ╱           ╲
                 │ no           │ yes
                 ▼              ▼
           ┌──────────┐    ┌──────────┐
           │  gated   │    │ starting │ ← spawn.spawn(cmd)
           └────┬─────┘    └────┬─────┘
                │                │ ok
                │ broker signal  ▼
                │ → fire_gate_check
                │           ┌──────────┐
                │ delay > 0 │ running  │
                │ schedule  └────┬─────┘
                │                │ child exit
                │                ▼
                │           died (mode == respawn?)
                │             ╱        ╲
                │            │ yes       │ no / oneshot retries exhausted
                │            ▼           ▼
                │     ┌─────────────┐  ┌────────┐  ┌──────┐
                │     │restart_pend.│  │ failed │  │ done │
                │     └──────┬──────┘  └────────┘  └──────┘
                │            │ backoff schedule       (terminal)
                │            │ + RE-CHECK gates
                │            ▼
                └─────── (back to gated or starting)
```

**Terminal states:** `failed` (oneshot crash with retries exhausted, or
gate timeout) and `done` (oneshot exit 0).

**Backoff formula:** `min(base * 2^(attempt - 1), 60)` seconds. Reset to
base after 60 s of healthy runtime.

## Gate evaluation

```
   broker.connect_signal("ready::tray", cb)
   │
   ├─ if cache already has a value (sticky cache):
   │      → SYNCHRONOUS replay during connect_signal
   │      → fire_gate_check() runs INSIDE the subscribe loop
   │      → timeout is scheduled BEFORE the loop, so cached
   │        replay bumps the generation and cancels it cleanly
   │
   └─ otherwise: wait for emit_value / emit_signal

   fire_gate_check(self):
   ┌─────────────────────────────────────────┐
   │ evaluates all-of self.spec.when         │
   │ if satisfied:                           │
   │   delay > 0 ? schedule(delay,           │
   │     ╭─ re-check on fire ─╮              │
   │     gates_satisfied?                    │
   │      yes → start_starting               │
   │      no  → start_gated   ◄─ flap during │
   │                            delay window │
   │   delay == 0 → start_starting           │
   └─────────────────────────────────────────┘
```

Two non-obvious invariants:

1. **Cached gates replay synchronously inside `connect_signal`.** The
   timeout has to be armed before the loop subscribes, otherwise a sticky
   cache hit would fire the gate before the timeout exists, and the
   timeout would still be live after the entry is already running.
2. **Delay window can flap.** A gate may go `true → false` while the
   delay timer is pending (e.g. tray icon vanishes). The fired callback
   re-evaluates the gates and either advances to `starting` or returns
   to `gated`.

## Hot reload (`awesome.restart()`)

The compositor process keeps running across `awesome.restart()`; only the
Lua VM is rebuilt. Two consequences:

- C-side ready flags (`globalconf.somewm_ready_seen`, `xwayland_ready_seen`)
  persist, and the new VM re-emits `awesome::somewm_ready` / `xwayland::ready`
  during `start_all()` so the broker cache is restored.
- Detached children spawned by oneshots are still alive in the OS. Without
  carryover, `start_all()` would happily re-spawn the launcher and end up
  with two daemons.

The carryover protocol:

```
   OLD Lua VM                              NEW Lua VM
   ───────────                             ───────────
   awesome.restart()
        │
        ├─ autostart._on_exit()
        │   │ for each oneshot in `done`:
        │   │   done_names[name] = true
        │   │ save_done_set() →
        │   │   $XDG_RUNTIME_DIR/
        │   │   somewm-autostart-done.list ───┐
        │   │                                 │
        │   └─ batched TERM/grace/KILL        │
        │      for respawn entries            │
        ▼                                     │
   Lua VM destroyed                           │
   C process keeps running ───────────────────┤
                                              │
   rc.lua re-execute                          │
   awesome._restart = true (set by C)         │
        │                                     │
        ▼                                     │
   autostart.start_all()                      │
        │                                     │
        ├─ C re-emits somewm::ready ──→       │
        │  + xwayland::ready    broker cache  │
        │                                     │
        ├─ if awesome._restart:               │
        │     load_done_set() ◄───────────────┘
        │     done_set = { "synology-drive"=true, ... }
        │
        └─ for each entry:
             if done_set[name] and oneshot:
                 _state = "done"          ← skip; do not respawn
                 log: hot_reload_carryover
             else:
                 e:start()
```

A cold boot has `awesome._restart == nil`, so the file is ignored and
oneshots run normally. A stale file from a crashed compositor is harmless:
cold boot ignores it, and the next exit overwrites it.

## Shutdown — three phases

On `awesome::exit`, `_on_exit` runs:

```
   awesome::exit signal
        │
        ▼
   autostart._on_exit()
        │
        ├─ [persist phase]
        │   save_done_set(done_names)
        │
        ├─ [phase 1: TERM]
        │   for each respawn entry:
        │       shutdown_term(e) → kill(pid, SIGTERM)
        │       pending[] += { entry, pid }
        │
        ├─ [phase 2: shared grace, max 2s]
        │   while now < deadline:
        │       any spawn_mod.is_alive(pid)?
        │           no → break early
        │       sleep 0.1
        │   ── one shared poll, not N × 2s ──
        │
        └─ [phase 3: SIGKILL stragglers]
            for each pending p:
                shutdown_kill(p.entry, p.pid)
                ── ownership check: entry still owns same pid ──
```

The shared grace loop matters: with N respawn entries, a per-entry serial
grace would multiply compositor exit latency by N. The shared poll is
bounded at `SHUTDOWN_GRACE_SECONDS = 2` regardless of fleet size.

## Providers — broker bridge

```
   ┌──────────────────────────────────────────────────────┐
   │  C-side somewm                                       │
   │  ──────────────                                      │
   │  somewm_ready_seen, xwayland_ready_seen              │
   │  awesome::somewm_ready, awesome::xwayland_ready      │
   └────────┬─────────────────────────────────────────────┘
            │
            ▼
   ┌──────────────────────┐         ┌──────────────────────┐
   │ providers.lua        │         │  D-Bus watchers      │
   │ - somewm::ready hook │         │  - org.kde.Status... │
   │ - xwayland::ready    │         │    Notifier          │
   │   hook               │         │  - org.freedesktop.  │
   │                      │         │    portal.Desktop    │
   └──────┬───────────────┘         └──────────┬───────────┘
          │                                    │
          ├─ broker.emit_value("ready::somewm",   true)
          ├─ broker.emit_value("ready::xwayland", true)
          ├─ broker.emit_value("ready::tray",     true)
          └─ broker.emit_value("ready::portal",   true)
                       │
                       ▼
              ┌─────────────────┐
              │ fishlive.broker │
              │  - sticky cache │
              │  - subscribers  │
              │  - late-join    │
              │    sync replay  │
              └────────┬────────┘
                       │
                       ▼
              autostart entries waiting on ready::*
```

D-Bus name watchers are pre-warmed at `add()` time, not at `start_all()`,
so they come up at registration. This matches the broker sticky-cache
promise: a late subscriber gets the cached value synchronously.

## Generation counter

Every entry has a monotonic `_generation`. `bump_generation(self)` is
called on every state transition (`gated → starting`, `died → …`,
`stop()`, `disconnect_gates()`). Scheduled callbacks (timeout, delay,
backoff) capture `gen_at_schedule` and check it on fire:

```lua
schedule(self, delay, function()
    if self._generation ~= gen_at_schedule then return end
    -- ... do work
end)
```

This guarantees stale callbacks from a previous generation cannot
interfere with a new one — the classic race after hot reload, restart,
or stop.

## Defaults by mode

| Mode        | `retries` default | On `exit(0)`        | On crash              | Backoff |
|-------------|-------------------|---------------------|-----------------------|---------|
| `oneshot`   | `1`               | `done` (terminal)   | `restart_pending` until retries exhausted → `failed` | exp 1s, 2s, 4s … cap 60s |
| `respawn`   | `-1` (infinite)   | `restart_pending`   | `restart_pending`     | exp 1s, 2s, 4s … cap 60s |

Before each respawn, gates are re-checked. If a dependency vanished
(e.g. tray died), the entry returns to `gated` instead of crash-looping
the launcher at the backoff cap.

## Status snapshot

```lua
local status = require("fishlive.autostart").status()
```

Shape:

```lua
{
  generation = <int>,                         -- module-level generation
  ready = {                                   -- broker cache for ready::*
    ["ready::somewm"]   = true | false,
    ["ready::xwayland"] = true | false,
    ["ready::tray"]     = true | false,
    ["ready::portal"]   = true | false,
  },
  entries = {
    ["nm-applet"] = {
      state    = "running" | "gated" | "starting" | "died"
                | "restart_pending" | "failed" | "done" | "pending",
      pid      = <int> | nil,
      attempts = <int>,
      waiting_for = { "ready::tray" },         -- gated state only
      started_at  = <unix_ts> | nil,
      log_path    = "/.../nm-applet.log",
    },
    -- ... one entry per registered name
  },
}
```

## IPC inspection

From any terminal while somewm runs:

```bash
# Whole-fleet status
somewm-client eval '
  local s = require("fishlive.autostart").status()
  for n, e in pairs(s.entries) do
      print(n, e.state, e.pid or "-", "attempts=" .. e.attempts)
  end
'

# Just the ready bus
somewm-client eval '
  local s = require("fishlive.autostart").status()
  for k, v in pairs(s.ready) do print(k, tostring(v)) end
'

# Restart a failed entry
somewm-client eval 'return require("fishlive.autostart").restart("synology-drive")'

# Stop an entry
somewm-client eval 'return require("fishlive.autostart").stop("blueman-applet")'
```

## Logs

Each entry writes to `$XDG_STATE_HOME/somewm/autostart/<name>.log` (or
the value of `spec.log`). Logs rotate by size: 1 MiB cap, keeping `.log`,
`.log.1`, `.log.2`. Override path via `spec.log = "/tmp/foo.log"`, disable
via `spec.log = false`.

Log lines are JSON-shaped events with at minimum `state`, `attempt`,
`reason` (when applicable), and `waiting_for` (when in `gated`).

## File layout

```
fishlive/autostart/
├── init.lua        — public API + module state + hot-reload + shutdown
├── entry.lua       — per-entry state machine (start, gate, schedule, exit)
├── providers.lua   — C-signal hooks + D-Bus name watchers → broker
├── spawn.lua       — backend bridge (awful.spawn / start_process)
└── log.lua         — per-entry log file with rotation
```

## Testing

Unit specs under `plans/project/somewm-one/spec/autostart_spec.lua`. Run:

```bash
LUA_PATH='/usr/share/lua/5.5/?.lua;/usr/share/lua/5.5/?/init.lua;;' \
    busted plans/project/somewm-one/spec/autostart_spec.lua
```

Coverage includes: state machine transitions, gate timeout, cached-gate
replay race, hot-reload carryover (warm + cold boot), delay-window flap,
respawn-after-death gate re-check, shutdown ordering.

## Migration notes

Migrating an entry from `awful.spawn.once` or XDG `.desktop`:

1. Decide `mode`. If the program supervises itself (forks daemons, exits
   immediately) → `oneshot`. If it must stay alive → `respawn`.
2. Decide gates. Tray icons → `ready::tray`. X11/XWayland clients →
   `ready::xwayland`. Portal-dependent → `ready::portal`. Always include
   `ready::somewm` if the program touches the compositor protocol.
3. For lazy-XWayland kicks, use `awful.spawn.easy_async({ "xprop", "-root",
   "_NET_SUPPORTED" }, function() end)` once before `start_all()` — the
   first X11 connect spins up XWayland and emits `ready::xwayland`.
4. Remove the corresponding XDG `.desktop` file or `awful.spawn.once` line.
5. Verify with `somewm-client eval 'return require("fishlive.autostart").status()'`.

## See also

- [`plans/fishlive-autostart/plan.md`](../fishlive-autostart/plan.md) — full
  design plan, deviations from initial Codex draft, decision rationale
- [`plans/project/somewm-one/GUIDE.md`](../project/somewm-one/GUIDE.md) —
  somewm-one developer guide (covers fishlive framework, broker, services,
  components)
- [`plans/project/somewm-one/fishlive/autostart/`](../project/somewm-one/fishlive/autostart/) —
  source
