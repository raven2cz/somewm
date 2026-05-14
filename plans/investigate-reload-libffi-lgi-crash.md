# Investigate: Reload crash v libffi.so po sliding tags animaci

## Status: IMPLEMENTED 2026-04-16 (branch `fix/reload-libffi-lgi-crash`)

Po Codex reviewu strategie A1+B1 zamítnuta (A1 měla fundamentální bugy),
nahrazena kombinací **B1 (ready boolean + přesun začátku)** +
**closure rewiring** (rewire existing closures na safe CIF).

**Validace:** 6× reload v řadě bez crashe. Guard logy:
```
begin_reload gen=1 (rewired 347 closures; blocked 0)
begin_reload gen=2 (rewired 910 closures; blocked 0)
...
begin_reload gen=6 (rewired 1495 closures; blocked 0)
```
`blocked 0` napříč všemi reloady = rewiring chytá stale closures
**před** tím, než se dostanou do libffi `classify_argument` walk.
Compositor funkční (eval test, client/screen counts správné).

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

### Stack trace (resolved via debuginfod 2026-04-16)

```
#0 classify_argument + 29           (libffi — reads cif->arg_types[i]->size)
#1 examine_argument + 30            (libffi — iterates cif->arg_types)
#2 ffi_closure_unix64_inner + 442   (libffi — C entry for closure trampoline)
#3 ffi_closure_unix64 + 76          (libffi — asm trampoline ENTRY, no GP yet)
#4 g_timeout_dispatch + 33          (GLib — **GTimeout SOURCE**)
#5 g_main_dispatch + 397            (GLib)
#6 g_main_context_iterate_unlocked.isra + 727
#7 g_main_loop_run + 311
#8 run (somewm)
#9 main
```

### Klíčová zjištění z resolved stacku (Fáze 1)

1. Dispatch je přes **GTimeout source** (`g_timeout_add`, NE GSignal, NE
   GDBus). Tzn. nějaký TIMER přežil reload a jeho tick se dispatched.
2. Crash je v **`classify_argument`** — libffi čte `cif->arg_types[i]->size`.
   To se děje **PŘED** zavoláním user callbacku. Náš guard (generation
   counter wrapper) se vůbec nespustil, protože sežral to už sám cif.
3. **Důsledek pro fix strategii:** Náš `liblgi_closure_guard.so` chrání
   callback body, ne cif metadata. Freed cif → classify_argument ještě
   před guardem. Fix musí buď:
   - (a) zabránit dispatchi freed timeout source (GLib sweep perfektně),
   - (b) chránit cif samotný (detection of freed arg_types → return zero),
   - (c) kombinace.

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

### Fáze 2: Inventory lgi callbacků přes reload — DONE 2026-04-16

**Primární persistent GLib timeout source:** `gears.timer` (`lua/gears/timer.lua:102`):

```lua
self.data.source_id = glib.timeout_add(glib.PRIORITY_DEFAULT, timeout_ms,
    function()
        protected_call(self.emit_signal, self, "timeout")
        return glib.SOURCE_CONTINUE
    end)
```

Tohle přesně sedí na frame #4 = `g_timeout_dispatch`. Každý `gears.timer:start()`
= jeden FFI closure registered do GLib main contextu.

**Secondary sources** (potvrzené grep přes rc.lua + somewm-shell):
- `awful.spawn(cmd, callback)` — exit callbacks přes `GLib.child_watch_add` (fixed
  v d7c6a94 bypass GDBus singleton — ale child_watch_add je jiná cesta).
- GIO file monitors (wallpaper reload, config watchers) — potenciálně.
- GDBus signal handlery na session bus (systray, notifikace) — částečně řešeno v d7c6a94.

**GSource sweep count z debug.log.1 (4 reloady před pádem):**

| Reload | baseline | upper | removed |
|--------|----------|-------|---------|
| 1      | 58       | 2390  | 12      |
| 2      | 2390     | 3797  | 17      |
| 3      | 3797     | 4916  | 19      |
| 4      | 4916     | 5674  | 19      |

Sweep odstraňuje ~15 sources/reload — numerika vypadá správně pro
`gears.timer` instance (v somewm-one je ~10-20 aktivních timerů).

**Pozorování z crashlog:** crash nastal **během runtime po 4. reloadu**, NE
během 5. reloadu. Uptime 2min 18s, trigger `[LS-DESTROY] ns=somewm-shell:collage
lua_obj=(nil)`. Tzn. nějaký timer přežil sweep — buď mimo baseline-range,
nebo registrovaný mezi bumps.

### Fáze 3: Cleanup strategie — DRAFT 2026-04-16

**Root cause konsolidace (3 úrovně rizika):**

1. **Neúplný sweep** (vysoké riziko, potvrzené): Baseline-range sweep
   (`for id = baseline+1; id < upper; id++`) závisí na tom, že všechny
   Lua-registered sources dostaly ID v ohraničeném rozsahu. Pokud lgi
   zaregistruje source po bumpu baseline nebo přes async path (thread,
   idle_add_full s custom context), source ID může být mimo range
   a sweep ho ignoruje.

2. **Generation race v guardu** (střední riziko, confirmed by code read):
   `lgi_closure_guard.c` má dva čítače — `lgi_guard_generation` (inc při
   `bump`) a `lgi_guard_ready_gen` (set na aktuální při `mark_ready`).
   Během reload window (~500ms mezi `bump` v `luaa.c` a `mark_ready`
   na konci reload) staré closures mají `w->gen == ready_gen_old`, takže
   **PASS check** a spustí se na freed state. Opraveno by mělo být
   set `ready_gen = MAX_GUINT` na bump, takže žádná gen nematch během
   reload, a na `mark_ready` set na aktuální.

3. **classify_argument před guardem** (architektonické, potvrzené):
   libffi `ffi_closure_unix64_inner` volá `examine_argument` →
   `classify_argument` **PŘED** zavoláním user-function pointeru (naše
   `lgi_guard_callback`). `classify_argument` čte `cif->arg_types[i]->size`
   na freed memory = crash před tím, než můžeme cokoli blockovat.
   Důsledek: **guard samotný nikdy nemůže úplně ochránit — jediná
   cesta je zabránit dispatchi vůbec** (remove GSource, nebo
   global dispatch barrier).

**Navrhované fix strategie (ranked by impact):**

#### A. Prevent dispatch (PRIMARY — jediné co skutečně řeší classify_argument)

A1. **Reload barrier via custom GSource prepare**:
   - V `some_glib_poll` (nebo custom GMainContext wrapper) přidat
     `volatile gboolean globalconf.reload_in_progress`.
   - Během reload window: `some_glib_poll` vrací 0 ready events, GLib
     main loop iteruje, ale `dispatch` žádné source nespouští.
   - Pros: univerzální ochrana pro všechny GLib dispatch cesty
     (timeout, idle, I/O, child_watch, dbus).
   - Cons: blokuje i Wayland dispatch — risk: compositor během reload
     nereaguje na input. Reload je rychlý (~500ms), akceptovatelné.

A2. **Exakt source ID tracking přes lgi hook**:
   - V `lgi_closure_guard.so` wrapper na `g_source_attach` /
     `g_idle_source_new` / `g_timeout_source_new` — každé source ID
     přidat do guard-maintained setu `g_hash_table`.
   - Při `bump_generation()`: iterovat set, `g_source_destroy()` každý.
   - Pros: přesný, žádný range-baseline heuristic, catches i sources
     mimo baseline range.
   - Cons: více kódu v guardu, nutno track source unref.

#### B. Fix guard race (SECONDARY — sníží risk okna během reloadu)

B1. Upravit `lgi_closure_bump_generation()`:
```c
void lgi_guard_bump_generation(void) {
    /* set ready_gen to unreachable value BEFORE incrementing gen —
     * během reload window, no closure matches, all blocked */
    g_atomic_int_set(&lgi_guard_ready_gen, G_MAXINT);
    g_atomic_int_inc(&lgi_guard_generation);
}
```
Nyní `lgi_guard_mark_ready()` volá `set(ready_gen, current_generation)`
teprve když je state safe.

Efekt: starý closure s `w->gen == old_ready_gen` během reload window
**neprojde equality check** → block (if guard vůbec doběhne před
classify_argument).

#### C. Belt-and-suspenders (COMBINED)

Implementovat A1 **a** B1 současně:
- A1 řeší classify_argument bypass (žádný dispatch → žádný cif read).
- B1 brání edge cases kdy reload window uzavřen ale stále-drifting
  closures z předchozího reload fire (mimo dispatch barrier).

**Doporučení:** C. varianta. A1 je cca 50 LOC v `somewm.c` +
`globalconf.h`, B1 je 5 LOC v `lgi_closure_guard.c`. Nízká rizikovost,
high payoff.

### Fáze 4: Implementation + validation

1. **B1 first** (malý diff, okamžitý partial fix):
   - Upravit `lgi_closure_guard.c` — `bump_generation` nastaví `ready_gen`
     na `G_MAXINT`.
   - Build guard: `cd build-fx && ninja lgi_closure_guard` + sudo
     install-scenefx.sh pro reloadable install.
   - Test: 10 po sobě jdoucích reloadů + sliding tags + collage overlay.

2. **A1 second** (reload barrier):
   - Přidat `globalconf.reload_in_progress` atomický flag.
   - V `luaA_hot_reload()` set flag před bump, clear po mark_ready.
   - Modify `some_glib_poll` (v `somewm.c`): pokud flag set, return 0
     ready fds + timeout = 1ms (keep loop alive bez dispatch).
   - Test: stress reload test + sliding tags + collage overlay 20x.

3. **Validation criteria:**
   - Žádný coredump během 50 po sobě jdoucích reloadů.
   - IPC eval `#client.get()` funguje po každém reloadu.
   - `somewm-shell:collage` layer surface destroyne se bez SEGV.
   - Debug log neobsahuje nové `[LGI-GUARD] blocked` záznamy (pokud
     by jich bylo mnoho, signál, že něco stále fires na stale state).

4. **Fallback (A2 — exact source tracking)** pokud A1+B1 neřeší:
   - Přidat `g_source_attach` / `g_timeout_add` hook do
     `lgi_closure_guard.c` s `g_hash_table` trackerem.
   - V `bump_generation()` iterovat tracker a `g_source_destroy()`.
   - Tohle je významná změna guardu; udělat jen po empirickém failu
     A1+B1.

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
