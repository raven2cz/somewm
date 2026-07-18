# Detailed design for `fishlive.autostart` — somewm Wayland-native autostart

## 1. Module file layout

The module should live beside the existing `fishlive` code in `plans/project/somewm-one/fishlive/`, because this is a personal config feature first, not a generic somewm core library.

| File | Purpose |
| --- | --- |
| `plans/project/somewm-one/fishlive/autostart/init.lua` | Public module API: `add`, `start_all`, `status`, `restart`, `stop`, `on_ready`. |
| `plans/project/somewm-one/fishlive/autostart/scheduler.lua` | Gate resolution, dependency tracking, entry queueing, timeout timers. |
| `plans/project/somewm-one/fishlive/autostart/supervisor.lua` | Per-entry runtime state, PID ownership, exit handling, restart/backoff logic. |
| `plans/project/somewm-one/fishlive/autostart/log.lua` | Structured logging to `~/.local/log/somewm-autostart.log`. |
| `plans/project/somewm-one/fishlive/autostart/status.lua` | Read-only runtime snapshot builder used by `autostart.status()`. |
| `plans/project/somewm-one/fishlive/autostart/providers/init.lua` | Provider registry and sticky ready-state cache. |
| `plans/project/somewm-one/fishlive/autostart/providers/compositor.lua` | Watches `somewm::ready` and `screen::ready`; exposes compositor readiness. |
| `plans/project/somewm-one/fishlive/autostart/providers/xwayland.lua` | Watches `xwayland::ready`; tracks whether XWayland is enabled and seen. |
| `plans/project/somewm-one/fishlive/autostart/providers/tray.lua` | Watches `org.kde.StatusNotifierWatcher` ownership and emits `tray::ready`. |
| `plans/project/somewm-one/fishlive/autostart/providers/portal.lua` | Watches `org.freedesktop.portal.Desktop` ownership and emits `portal::ready`. |
| `plans/project/somewm-one/fishlive/autostart/providers/dbus.lua` | Generic `dbus::name(org.foo)` watcher with shared GIO bus connection. |
| `plans/project/somewm-one/fishlive/autostart/providers/custom.lua` | User-defined/manual readiness gates backed by `autostart.emit_ready()`. |
| `plans/project/somewm-one/fishlive/autostart/spawn.lua` | Backend selector and common spawn contract. |
| `plans/project/somewm-one/fishlive/autostart/spawn_backends/awful.lua` | Native backend using `awful.spawn` / `awesome.spawn` for PID + exit callback. |
| `plans/project/somewm-one/fishlive/autostart/spawn_backends/start_process.lua` | Compatibility wrapper for existing `~/bin/start_process` semantics when explicitly requested. |
| `plans/project/somewm-one/spec/autostart_spec.lua` | Unit tests for public API and state transitions. |
| `plans/project/somewm-one/spec/autostart_scheduler_spec.lua` | Unit tests for gate resolution and timer behavior. |
| `plans/project/somewm-one/spec/autostart_supervisor_spec.lua` | Unit tests for restart policy, PID tracking, exit handling. |
| `plans/project/somewm-one/spec/autostart_dbus_spec.lua` | Unit tests with mocked GIO bus name watchers. |
| `tests/test-autostart-lifecycle.lua` | Integration test inside somewm runtime for signal order and state exposure. |
| `tests/test-autostart-xwayland-gate.lua` | Integration test that an X11-gated entry waits for `xwayland::ready`. |
| `tests/test-autostart-tray-gate.lua` | Integration test that a tray-gated entry waits for watcher ownership. |
| `tests/test-autostart-status-ipc.lua` | Integration test for `somewm-client eval "return autostart.status()"`. |

C-side hooks:

| File | Change |
| --- | --- |
| `somewm.c` | Emit `somewm::ready` after initial `some_refresh()` in `run()`. |
| `xwayland.c` | Emit `xwayland::ready` from `xwaylandready()` after XCB/EWMH init succeeds. |
| `luaa.c` | Mirror `somewm::ready` during hot reload after `some_refresh()` so reload keeps parity. |
| `luaa.c` or `somewm_api.c` | Add `awesome.compositor_ready()` bool getter for late-loaded modules. |

## 2. Public API spec

### API signatures

```lua
local autostart = require("fishlive.autostart")

autostart.add(spec) -> entry
autostart.start_all() -> nil
autostart.status() -> table
autostart.restart(name) -> boolean, err?
autostart.stop(name) -> boolean, err?
autostart.on_ready(signal_name, callback) -> disconnect_fn
```

### Example

```lua
local autostart = require("fishlive.autostart")

autostart.add({
    name = "nm-applet",
    cmd = { "nm-applet", "--indicator" },
    when = { "tray::ready", "portal::ready" },
    mode = "respawn",
    retries = -1,
    delay = 0.5,
    timeout = 20,
    replace = true,
    log = true,
})

autostart.add({
    name = "synology-drive",
    cmd = { "synology-drive", "start" },
    when = { "xwayland::ready", "tray::ready" },
    mode = "oneshot",
    retries = 3,
    delay = 1.0,
    timeout = 30,
    pre_check = function(ctx)
        return not ctx.is_running("cloud-drive-ui")
    end,
})

autostart.start_all()
```

### Spec fields

| Field | Type | Required | Default | Notes |
| --- | --- | --- | --- | --- |
| `name` | `string` | yes | none | Unique key; used by status, logs, IPC control. |
| `cmd` | `string` or `table` | yes | none | `table` form is preferred; string form uses shell. |
| `when` | `string` or `table<string>` | no | `{ "somewm::ready" }` | All listed gates must be satisfied. |
| `mode` | `string` | no | `"oneshot"` | One of `oneshot`, `respawn`, `dbus_activated`. |
| `retries` | `number` | no | `0` for `oneshot`, `-1` for `respawn` | `-1` means unlimited. |
| `delay` | `number` | no | `0` | Extra delay after gates become ready. |
| `timeout` | `number` | no | `15` | Max seconds allowed to wait for gates or post-check success. |
| `log` | `boolean` or `string` | no | `true` | `true` uses per-entry default file name; string overrides path. |
| `env` | `table<string,string>` | no | `{}` | Extra environment merged over compositor env. |
| `pre_check` | `function(ctx)` | no | `nil` | Runs before spawn; return `false, reason` to skip or defer. |
| `post_check` | `function(ctx)` | no | `nil` | Runs after spawn; return `true` when healthy. |
| `replace` | `boolean` | no | `false` | If true, stop existing managed instance before restart. |
| `pidfile` | `string` | no | `nil` | Optional external PID hint for legacy daemons. |
| `disabled` | `boolean` | no | `false` | Registered but never scheduled. |

Decisions:

- Mandatory only: `name`, `cmd`.
- `when` defaults to `somewm::ready` because most entries should not fire before compositor bootstrap completes.
- `mode="dbus_activated"` means do not spawn a process directly; instead wait for its bus name gate and mark the entry satisfied.

## 3. Readiness signal catalog

| Signal | Trigger condition | Emission location | Fallback if missing | Idempotency |
| --- | --- | --- | --- | --- |
| `somewm::ready` | Initial startup path has loaded `rc.lua`, scanned screens, emitted `startup`, and finished first `some_refresh()` | `somewm.c:run()` after `some_refresh()`; mirrored in hot reload path in `luaa.c` | No synthetic fallback; entries fail on their own `timeout` | Sticky; emit on false→true only per compositor generation |
| `xwayland::ready` | `xwaylandready()` completed and XWayland accepts X11 connections; `DISPLAY` is already exported | `xwayland.c:xwaylandready()` after XCB connect and EWMH init | No fake timeout; entry waits until timeout if XWayland disabled or broken | Sticky; emit on false→true only |
| `screen::ready` | All screens present during initial scan have completed `request::desktop_decoration` and created their wibar objects; emit on next GLib idle tick | Lua provider, fed from `fishlive.config.screen` after `s.mywibox` creation | If a screen decoration handler never finishes, dependent entries time out | One-shot for startup generation; never re-emitted on tag switch |
| `tray::ready` | Session bus name `org.kde.StatusNotifierWatcher` is owned | `providers/tray.lua` via generic D-Bus watcher | No provider timeout; dependent entry timeout handles absence | Re-emitted on owner loss/reacquire, but scheduler dedupes completed one-shot entries |
| `portal::ready` | Session bus name `org.freedesktop.portal.Desktop` is owned | `providers/portal.lua` via generic D-Bus watcher | No provider timeout | Re-emitted on owner reacquire |
| `dbus::name(org.foo)` | Requested well-known bus name has an owner | `providers/dbus.lua` | No provider timeout | Re-emitted on owner reacquire |
| `custom::<name>` | User or module explicitly marks a custom gate ready | `providers/custom.lua` | Controlled entirely by caller | Sticky until compositor restart |

Opinionated choices:

- `xwayland::ready` should mean “DISPLAY is usable”, not “some X11 client mapped”. That is the actual failure point for Synology/Qt5 startup.
- `screen::ready` should mean “all initial screens decorated”, not “first wibar exists”. This avoids racey tray consumers on multi-monitor startup.
- Providers keep sticky readiness state. `autostart.on_ready()` must immediately invoke the callback if the signal is already ready.

## 4. State machine for an entry

```text
pending
  -> gated
  -> ready_to_start
  -> starting
  -> running
  -> died
  -> restart_pending
  -> starting
  -> ...
  -> failed
```

State definitions:

| State | Meaning | Main transitions |
| --- | --- | --- |
| `pending` | Registered, not yet handed to scheduler | `start_all()` -> `gated` |
| `gated` | Waiting for all `when` signals and optional `delay` | gates satisfied -> `ready_to_start`; timeout -> `failed` |
| `ready_to_start` | All gates open; pre-check about to run | pre-check pass -> `starting`; pre-check false -> `failed` or stay gated if reason is retryable |
| `starting` | Spawn requested, PID not yet declared healthy | PID received -> `running`; spawn error -> `died` |
| `running` | Process alive or `oneshot` post-check passed | exit callback -> `died`; manual stop -> `pending` |
| `died` | Process exited or failed health check | retries left -> `restart_pending`; none left -> `failed` |
| `restart_pending` | Backoff timer active | timer fires -> `starting` |
| `failed` | Scheduler gave up for this generation | manual `restart(name)` -> `gated` |

Side effects:

- Entering `gated` allocates a gate-timeout timer.
- Entering `starting` clears gate timers and records `attempt`.
- Entering `running` cancels startup timeout and updates `last_pid`, `started_at`.
- Entering `died` records `exit_reason`, `exit_code`, `runtime_ms`.
- Entering `restart_pending` allocates one backoff timer only.
- Entering `failed` clears all outstanding timers.

Log format:

```text
2026-04-26T14:21:03.418+02:00 [autostart] entry=synology-drive state=starting attempt=2 pid=43129 gates=xwayland::ready,tray::ready msg=spawn
```

## 5. Library choices

- `lgi` with `GLib` and `Gio` for D-Bus name watching. This is already used in `awful.systray.lua`, `awful.statusnotifierwatcher.lua`, and `fishlive.startup_timer.lua`. Reusing it avoids a second D-Bus stack.
- `gears.timer` for gate delays, entry timeouts, and restart backoff. It is already the normal timing primitive in this tree and integrates with the GLib main loop.
- `gears.protected_call` around provider callbacks, exit handlers, and user `pre_check`/`post_check`. This matches existing `awful.spawn` and systray code and prevents one broken callback from poisoning the scheduler.
- `awful.spawn` for the default backend because it already exposes PID, stdout/stderr streams, and exit callbacks through `awesome.spawn`.
- Direct `awesome.spawn` under the hood only inside the backend wrapper when extra control is needed. The public module should not talk to compositor internals directly.
- Do not add a POSIX FFI spawn path. It is unnecessary here, harder to hot-reload safely, and duplicates existing somewm process plumbing.

## 6. Spawn / supervision details

Default policy:

- Replace `awful.spawn.once` for managed autostarts.
- Keep `~/bin/start_process` only as an explicit compatibility backend for legacy commands that depend on `nohup` and `pgrep -f`.

Stdout/stderr capture:

- Use `awful.spawn.with_line_callback`.
- Write merged lines to `~/.local/log/somewm-autostart/<entry>.log`.
- Rotate by size, not time: keep `entry.log`, `entry.log.1`, `entry.log.2`; rotate when file exceeds 1 MiB.
- Also write a summary line to `~/.local/log/somewm-autostart.log`.

Death detection:

- Primary path: `callbacks.exit(reason, code)` from `awful.spawn.with_line_callback`.
- No separate SIGCHLD glue is needed in Lua for default-managed children.

Backoff:

- Exponential with cap.
- Formula: `delay_n = min(base * 2^(attempt-1), 60)`, with `base = max(spec.delay, 1)`.
- Reset the backoff counter if the process stayed alive for 30 seconds or passed `post_check`.

Already-running detection:

- First choice: internal PID tracking for processes spawned by this module.
- Second choice: `pre_check` calling `ctx.is_running("pattern")`.
- Third choice: `pidfile`.
- Fourth choice: D-Bus name presence for D-Bus apps.
- Do not hardcode `pgrep -f` as the default rule. It is too fuzzy and was one of the problems with the old helper.

Shutdown semantics:

- The module keeps a list of managed PIDs and connects to `awesome.connect_signal("exit", ...)` or the equivalent compositor shutdown signal path.
- On shutdown, send `SIGTERM`, wait 2 seconds, then `SIGKILL` only for entries with `mode="respawn"` and only if they were spawned by this module.
- This is the Lua-level replacement for `PartOf=` semantics.

`start_process` interaction:

- Keep it as `backend="start_process"` for migration only.
- New entries should default to the native backend.
- Long-term goal is to retire it for desktop daemons that can be supervised directly.

## 7. Test strategy

### Unit (`busted`, `plans/project/somewm-one/spec/`)

Concrete cases:

- Gate resolution with one, many, and duplicate signals.
- Sticky ready-state replay for late `on_ready()` subscribers.
- Entry timeout while waiting for a missing gate.
- `respawn` backoff progression and cap.
- `pre_check` skip, `post_check` fail, and retry transitions.
- Manual `restart(name)` from `failed` and `running`.
- Log record formatting.
- D-Bus watcher name appeared, vanished, and reappeared with mocked `Gio`.

### Integration (`tests/`)

Concrete cases:

- `somewm::ready` fires after screen scan and before autostarted fake entry spawn.
- `xwayland::ready` gate blocks a fake X11 entry until signal is emitted.
- `tray::ready` gate blocks entry until `org.kde.StatusNotifierWatcher` is owned.
- `portal::ready` gate blocks entry until `org.freedesktop.portal.Desktop` is owned.
- `autostart.status()` returns stable tables over IPC.
- Re-emitted D-Bus readiness does not relaunch completed `oneshot` entries.
- `respawn` entry restarts after forced kill and status reflects attempts.
- Manual `stop(name)` kills only the targeted managed PID.

### Smoke

Run in nested compositor first:

- `~/git/github/somewm/plans/scripts/somewm-sandbox.sh`
- Register real `blueman-applet`, `synology-drive`, and `nm-applet`.
- Assert `nm-applet` launches after `tray::ready`.
- Assert `synology-drive` launches only after `xwayland::ready`.
- Assert each starts once and produces one managed status entry.
- Repeat once in the real TTY session because nested mode cannot reproduce every NVIDIA and DRM timing edge.

## 8. C-side hooks needed in somewm

- `somewm.c:run()` immediately after the first `some_refresh()`: emit `luaA_emit_signal_global("somewm::ready")`.
- `xwayland.c:xwaylandready()` after successful XCB connection, EWMH atom init, and `ewmh_init_lua()`: emit `luaA_emit_signal_global("xwayland::ready")`.
- `luaa.c` hot-reload completion path immediately after `some_refresh()`: emit `luaA_signal_emit(L, "somewm::ready", 0)` so reload and cold boot share semantics.
- Add `awesome.compositor_ready()` returning a cached bool that flips true at the same point as `somewm::ready`.

The bool API is worth adding. `awesome.startup == false` only means the main loop is running; it does not mean the compositor finished its first visual flush.

## 9. Migration plan

1. Land `fishlive.autostart` and C/Lua readiness signals behind an opt-in require in `rc.lua`. No behavior change yet.
2. Move `nm-applet`, `synology-drive`, and `blueman-applet` from XDG or ad hoc startup into `fishlive.autostart`.
3. Verify logs, status IPC, and restart behavior in nested mode, then in the real TTY session.
4. Migrate `conky`, `volctl`, and `polkit-agent`, using `backend="start_process"` only where native supervision still fails.
5. Remove `Wants=xdg-desktop-autostart.target` from `contrib/systemd/somewm.service.in`.
6. Disable or delete overlapping `~/.config/autostart/*.desktop` files once the Lua entries prove stable.
7. Keep a short temporary compatibility window where `start_process`-backed entries can coexist, but do not let both systems launch the same app.

## 10. Risks & open questions

- Race between ready emission and module load. Mitigation: sticky provider state plus immediate replay in `on_ready()`.
- `screen::ready` depends on `fishlive.config.screen` cooperation. If that module is bypassed, the gate never fires.
- D-Bus name watchers can flap during portal or tray service restarts. Scheduler must treat readiness as edge-triggered but not blindly relaunch completed one-shots.
- `lgi` object lifetime during hot reload can bite if closures survive old module generations. Keep providers generation-tagged and disconnect watchers on reload.
- `post_check` design can become ad hoc if overused. Keep it for a few problematic apps only.
- Legacy apps that daemonize twice or hide behind wrapper processes may make PID ownership fuzzy. That is the main remaining case for `pidfile` or `start_process`.
- Real startup timing on NVIDIA/DRM may still differ from nested Wayland backend results. The final validation must be in the real session.
- If `xwayland::ready` fires but the X11 app still crashes due to icon theme or tray assumptions, add `tray::ready` and `screen::ready` to that entry rather than broadening the global readiness definition.
