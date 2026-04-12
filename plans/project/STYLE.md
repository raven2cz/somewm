# Style Guide — somewm-one & somewm-shell

This single guide covers both projects so new files stay consistent.

## Lua file headers (somewm-one)

Every file under `fishlive/` (except vendored `rubato/`, `layout-machi/`) and
every `themes/*/theme.lua` gets a full LDoc header:

```lua
---------------------------------------------------------------------------
--- <One-line purpose>.
--
-- <2–4 lines: what the module exposes, how it is consumed, any init
-- convention (auto-init-on-require vs .setup()).>
--
-- @module fishlive.<path>
-- @author Antonin Fischer (raven2cz) & Claude
-- @copyright 2026 MIT License
---------------------------------------------------------------------------
```

For services (`fishlive/services/*.lua`) also state the broker signal, payload
shape, and poll interval (or "event-driven"):

```
-- Signal: data::<name> — { field1, field2, ... }
-- Interval: Ns (or event-driven).
```

For components (`fishlive/components/*.lua`) document the single public
contract `M.create(screen, config)` with `@tparam`/`@treturn`.

`rc.lua` carries the project signature header (raven ASCII) — not an LDoc
block.

## QML file headers (somewm-shell)

QML has no LDoc, so use a compact C++-style block at the top of the file. If
the file has `pragma Singleton`, keep pragma on line 1 (Quickshell requires
it) and place the header immediately after:

```qml
pragma Singleton

// <Component> — <one-line purpose>.
//
// <2–3 lines: what it renders / what it exposes / how it is wired>.
// IPC: somewm-shell:<name> {methods} — OR omit if none.
// Reads: awesome._foo  (if the component reads compositor state).

import QtQuick
...
```

Files without pragma just start with the header on line 1, imports after.

Scope:
- All `services/*.qml` — must have header.
- All `components/*.qml` — must have header + short doc on public properties.
- Module roots (e.g. `modules/sidebar/Sidebar.qml`) — must have header.
- Module leaves (tabs, sub-components) — optional. Rely on module-root context.

## Module init conventions

### somewm-one (Lua)
- **All config modules** (`fishlive/config/*.lua`) export `M.setup(args)`
  called explicitly from `rc.lua`. No side effects at require time. Each
  setup() is idempotent — guarded by `if M._initialized then return end` so
  `somewm-client reload` is safe.
- **Load order is a property of `rc.lua`, not of `require` ordering.** The
  critical invariant is: `rules.setup()` runs before `titlebars.setup()` and
  `client_fixes.setup()` — those modules attach `request::titlebars` /
  `property::*` handlers that assume the rule set is in place. This is
  enforced by the test suite (section "Config Module Init Convention").
- **Services** (`fishlive/services/*.lua`) auto-register with
  `broker.register_producer()` on require. Bootstrap by requiring the
  `fishlive.services` registry once.
- **Components** (`fishlive/components/*.lua`) never run code at require time.
  Only expose `M.create(screen, config) -> wibox.widget`.
- **Utilities** (`fishlive/config/recording.lua`, `fishlive/menu.lua` etc.) —
  export a table of functions; no setup.

### somewm-shell (QML)
- Services are QML singletons — no explicit setup; lazy-load via `Core.<Name>`.
- Panels / modules are instantiated by `core/Panels.qml` `Variants` per screen.
- New components go under `components/`; new services under `services/`.

## IPC conventions

See `somewm-shell/IPC.md` for the current catalogue. Two rules:

1. **Lua → Shell**: always `qs ipc -c somewm call somewm-shell:<module> <method> [args]`.
   Module names are kebab-case-free (no dashes in the `<module>` slot), each
   target defined as a `IpcHandler { target: "somewm-shell:<module>" }` in a
   single QML owner file.
2. **Shell → Lua**: always `somewm-client eval "<lua>"`. Globals the shell reads
   or writes MUST be namespaced to `awesome._<name>` (never bare `_G.name`).
   Keep payloads small and typed — no multi-line eval, no dynamic code
   construction from user input.

## Verification

`plans/scripts/check-headers.sh` runs the minimum-viable lint for header
presence. Re-run after adding new files.
