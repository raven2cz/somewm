# Investigate: Reload crash v libffi.so po sliding tags animaci

## Status: TODO (otevřený plán — navazuje na `fix-reload-crash-exit-callbacks.md`)

## Vztah k existujícím plánům

Doplňuje `plans/fix-reload-crash-exit-callbacks.md` konkrétními daty z
2026-04-16. Starší plán popisoval obecně "exit callback nil value" při
reloadu. Tento plán má konkrétní stack trace, crash ID, a identifikovaný
trigger (sliding tags animation).

## Pozorovaný problém

Po **5. opakovaném `somewm-client reload`** + sliding tags animation
compositor spadne (SIGSEGV, general protection fault) v `libffi.so.8`.

Reprodukce není deterministická — občas přežije víc reloadů, ale sliding
tags animation v kombinaci s quickshell collage overlay increased risk.

## Konkrétní incident 2026-04-16

- **Session PID:** 90539 (`/usr/local/bin/somewm`)
- **Start:** 08:11:23
- **Crash:** 08:13:00 (uptime 2min 18s, 5. reload)
- **Signal:** SIGSEGV, general protection fault
- **Core dump:** `/var/lib/systemd/coredump/core.somewm.1000.*.90539.*.zst`
  (962 MB, tail of reload-pollinated memory)
- **Crash snapshot:** `~/.local/log/somewm-crashlogs/20260416-075726/`
  (starší stejného typu) — compositor.txt, debug-tail.log, errors.log,
  journal.log

### Stack trace

```
#0  libffi.so.8 + 0x22ed   (ffi_call_int)
#1  libffi.so.8 + 0x274e
#2  libffi.so.8 + 0x75ba   (ffi_call vs ffi_prep_cif)
#3  libffi.so.8 + 0x7ce8
#4  libglib-2.0.so.0 + 0x60e41  (g_main_context_dispatch internals)
#5  libglib-2.0.so.0 + 0x5ef4d
#6  libglib-2.0.so.0 + 0x60607
#7  libglib-2.0.so.0 g_main_loop_run
#8  /usr/local/bin/somewm run
#9  main
```

= GLib GSource callback triggered cez libffi trampoline ukazuje na
neplatnou memory → SIGSEGV.

### Trigger sekvence v debug.log.1

Těsně před pádem (uptime 00:02:18.086):

```
[LS-UNMAP] ns=somewm-shell:collage lua_obj=0x7fb807e83718 scene=0x557a9e220180
[LS-DESTROY] ns=somewm-shell:collage lua_obj=(nil) scene=0x557a9e220180 popups=0x7fb85c03ceb0
info(glib): MESSAGE: Gdk: Lost connection to Wayland compositor.
```

**`lua_obj=(nil)` při LS-DESTROY**: mezi unmap a destroy Lua objekt zmizel
(GC), ale C/libffi callback ho pořád drží.

## Hypotéza (dosud neověřená)

`lgi` (Lua GObject Introspection) registruje GLib/GObject signal handlery
přes libffi trampoline. Tyto handlery se registrují na **vnější** GObject
instance (GDBus proxy, GIO file monitor, systray service proxy, atd.) —
objekty, které přežijí reload.

Při `awesome.restart()`:
1. Starý `lua_State` se destroyne.
2. GObject instance zůstávají alive (žijí mimo compositor — v systray apps,
   GDBus daemon, atd.).
3. Nové `lua_State` nahraje rc.lua, lgi přeregistruje handlery.
4. **Starý libffi trampoline v přeživším GObject ukazuje na stale
   lua_State memory**.
5. Jakýkoli GLib event (např. signal z GDBus proxy, damage z file monitor,
   sliding tags vytvoří collage layer surface který commitne) volá starý
   callback → segfault.

Cherry-pick `d7c6a94` ("bypass stale GDBus singleton cache after reload")
**částečně** řeší jen GDBus singleton cache. Neřeší obecný pattern lgi
handler lifecycle.

## Co udělat

### Fáze 1: Potvrzení hypotézy

1. `coredumpctl debug 90539` + načíst symboly pro libffi/libglib/lgi.
2. V gdb: `bt full`, `frame 3`, podívat se co volá (která GObject/GIO class).
3. Cross-referencovat s lgi registered callbacks v momentě pádu.

### Fáze 2: Inventory lgi callbacků přes reload

Najít všechna místa v Lua kde se používá lgi callback, který přežije
reload:
- `fishlive/services/*` — zejména `systray`, `notifications`, `shell_ipc`
- `fishlive/config/shell_ipc.lua`
- `components/notifications.lua`
- `awful.spawn` — exit callbacks (ty sedí s původním fix-reload-crash-*.md)
- `gears.timer` — jakýkoli timer s `weak_ref` nebo GIO backend
- Any `lgi.Gio`, `lgi.GLib`, `lgi.GObject` import

### Fáze 3: Cleanup strategie

Při `awesome.restart()`:
1. Enumerate all lgi signal handlers registered on GObject instances.
2. Disconnect them BEFORE `lua_close(L)`.
3. Alternativa: přidat C-side "reload barrier" — blokovat GLib dispatch
   během restart window (zmrazit g_main_context) aby žádný callback
   neproběhl na stale memory.

### Fáze 4: Safety net

Pokud úplné cleanup je náročné, minimální safety:
- V C `awesome_restart`: po destroy starý lua_State **zrušit GSource**
  které měly Lua callback (`g_source_remove` on tracked GSource IDs).
- Track GSource IDs přes existing `awesome.connect_signal("exit", ...)`
  handlers.

## Kontext upstream

Tohle je pravděpodobně problem i v upstream `trip-zip/somewm`, pokud
používá lgi + reload. Upstream reload je recent feature (cherry-picks
z 2026-03/04). Stojí za PR/issue na `trip-zip/somewm` s analýzou — po
ověření.

## Proč to není blocker pro hot-reload cherry-pick branch

- Crash je **občasný** (5.+ reload + sliding tags trigger), ne pokaždé.
- **Nezávislý bug** — není to regrese z cherry-picks, existoval už dřív
  (viz `plans/fix-reload-crash-exit-callbacks.md` z 2026-04-11).
- Cherry-picks hot-reload které tato branch dodává (`dfead9e`, `d7c6a94`,
  `5d6c2d6`, `6bb31f1`, `0c2cc85`) fungují korektně v 1-4 reloadech
  (ověřeno IPC eval 2026-04-16).

## Artefakty pro další session

- Core dump: `coredumpctl list somewm` → PID 90539
- Crash snapshot: `~/.local/log/somewm-crashlogs/20260416-075726/`
- Journal: `journalctl --since "2026-04-16 08:10" --until "08:15"` filter
  `traps: somewm`
- Debug log (předchozí rotovaný): `~/.local/log/somewm-debug.log.1`
  — hledat `[LS-DESTROY]` a `lua_obj=(nil)` před pádem.

## Kdo by to měl dělat

Claude Opus 4.6 + Sonnet review (C/Lua lifecycle je složitý, potřebuje
druhý pohled). Pokud Fáze 1 vede k jasnému fix — gpt-5.4 codex jako third
opinion před implementací, hlavně na GSource cleanup correctness.
