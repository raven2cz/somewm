# Fix: Reload crash — exit callback nil value

## Status: SUPERSEDED (2026-04-16)

Po cherry-pick merge (viz `plans/done/cherry-pick-upstream-hotreload.md`)
se symptom "exit callback: attempt to call a nil value" už neopakuje.
Zbývající crash při 5. reload + sliding tags je SIGSEGV v libffi.so
(jiný symptom, pravděpodobně překrývající se root cause) a má vlastní plán
s konkrétním stack tracem:

→ **`plans/investigate-reload-libffi-lgi-crash.md`** (2026-04-16)

Crashlog infrastruktura z tohoto plánu (snapshot script, log rotace,
Claude Code hook, post-mortem analyzer) ZŮSTÁVÁ V PROVOZU — v
`plans/scripts/somewm-snapshot.sh`, `somewm-log-rotate.sh`,
`somewm-hook-pre-reload.sh`, `somewm-postmortem.sh`.

## Původní popis (pro referenci)

## Status: TODO (podklady, neopravovat teď)

## Pozorovaný problém

Při `somewm-client reload` compositor spadne s opakující se chybou:

```
somewm: error in exit callback: attempt to call a nil value
somewm: error in exit callback: attempt to call a nil value
... (opakuje se 20-30x)
Error raised while calling 'lgi.cbk (number): Gio': attempt to call a number value
```

Poté všechny Wayland klienty obdrží `Broken pipe`:

```
nm-applet: Error reading events from display: Broken pipe
xdg-desktop-portal-gtk: Error reading events from display: Broken pipe
electron: Error reading events from display: Broken pipe
```

Compositor se zřejmě ukončí a session spadne.

## Kdy k tomu dochází

- Při `somewm-client reload` (Lua hot-reload)
- Stává se **často**, ne pokaždé — race condition
- Pozorováno 2026-04-11 07:45:22 (journalctl)
- Nesouvisí s konkrétní změnou v rc.lua — stává se i bez úprav

## Analýza příčiny

### 1. Exit callbacks volají nil

Při reloadu se:
1. Compositor emituje `exit` signál na starém Lua state
2. Moduly registrované přes `awesome.connect_signal("exit", ...)` dostávají callback
3. Některé callbacky odkazují na funkce, které už v tu chvíli neexistují (garbage collected nebo unloaded)
4. `attempt to call a nil value` → Lua error v exit callbacku

### 2. LGI closure callback

```
Error raised while calling 'lgi.cbk (number): Gio': attempt to call a number value
```

LGI (Lua GObject Introspection) má registrované GIO callbacky. Při reloadu se Lua state resetuje, ale GIO eventy stále přicházejí a pokoušejí se volat staré Lua closure, které už neexistují.

Toto souvisí s existujícím plánem `fix-hot-reload-lgi-closures.md` — máme `liblgi_closure_guard.so` v `start.sh`, ale zjevně nepokrývá všechny případy.

### 3. Kde se exit callbacky registrují

Potenciální zdroje exit callbacků v rc.lua/modulech:

- `fishlive/exit_screen.lua` — registruje `exit_screen::open/close/toggle` (ne přímo exit, ale může mít závislosti)
- Timery (`gears.timer`) — při reloadu se pokoušejí zastavit, ale callback už neexistuje
- `naughty` notification daemon — interní exit cleanup
- `awful.spawn` — child process watchers s GIO callbacky

### 4. Proč se to děje občas, ne vždy

Race condition: záleží na tom, jestli GIO event loop stihne doručit pending eventy **mezi** unloadem starého Lua state a inicializací nového. Na NVIDIA s GPU-bound operacemi (wallpaper rendering) je pravděpodobnost vyšší.

## Navrhované řešení

### Krok 1: Audit exit callbacků

```bash
grep -rn "connect_signal.*exit\|atexit\|awesome\.connect_signal" \
  ~/.config/somewm/ --include="*.lua" | grep -v ".bak"
```

Identifikovat všechny moduly, které registrují exit signály.

### Krok 2: Ochrana exit callbacků pcall wrapperem

V `somewm.c` (nebo `somewm_api.c`) — wrappovat volání exit callbacků v `lua_pcall`:

```c
// Místo přímého volání exit signálu:
// emit_signal("exit")
// Wrappovat každý callback:
lua_pushcfunction(L, error_handler);
// ... pcall wrapper pro každý exit callback
```

### Krok 3: LGI closure guard rozšíření

Zkontrolovat `liblgi_closure_guard.so` — pokrývá `lgi.override` closures, ale možná ne `lgi.cbk` (GIO async callbacky). Potřeba rozšířit guard o:
- `g_io_channel` watchers
- `g_child_watch` callbacky
- `g_timeout`/`g_idle` sources registrované přes LGI

### Krok 4: Graceful cleanup před reloadem

Před emitováním exit signálu:
1. Zastavit všechny gears.timer instance
2. Odpojit GIO watchers
3. Flushnout pending signály
4. Teprve potom emitovat exit + unload Lua state

## Souvislosti

- `plans/fix-hot-reload-lgi-closures.md` — předchozí práce na LGI closure guard
- `plans/scripts/start.sh` — `LD_PRELOAD=liblgi_closure_guard.so`
- Upstream issue: hot-reload je obecně nestabilní v AwesomeWM/somewm

## Workaround (aktuální)

Místo `somewm-client reload` použít:
```bash
# Bezpečnější: rebuild + restart celé session
~/git/github/somewm/plans/scripts/install-scenefx.sh && sudo reboot
```

Nebo pro menší změny (jen rc.lua/Lua moduly):
```bash
# Restart bez rebootu — ale ztratíš rozložení oken
somewm-client exec somewm
```

## Crashlog infrastruktura (DONE — 2026-04-11)

Implementováno v `feat/mebox-menus` branchi:

1. **Pre-reload snapshot** — `plans/scripts/somewm-snapshot.sh`
   - journalctl, debug-tail, errors, dmesg, compositor state
   - `~/.local/log/somewm-crashlogs/YYYYMMDD-HHMMSS/`
   - Auto-prune >30 dní

2. **Rotace logů** — `plans/scripts/somewm-log-rotate.sh`
   - 5 kopií (`.1` až `.5`), voláno z `start.sh`

3. **Claude Code hook** — `plans/scripts/somewm-hook-pre-reload.sh`
   - PreToolUse hook v `.claude/projects/.../settings.json`
   - Automatický snapshot před `somewm-client reload/restart/exec`

4. **Post-mortem analyzer** — `plans/scripts/somewm-postmortem.sh`
   - Čte poslední snapshot, filtruje SEGFAULT/GPU/Lua chyby
   - Výstup vhodný pro paste do Claude Code
