# Forward-port: GLib source sweep na config timeout path (cherry-pick 0deb9d2)

## Status: TODO (deferred ze Stage 3 cherry-pick plánu — riziko manuálního merge)

Navazuje na `plans/done/cherry-pick-upstream-hotreload.md`. V původní analýze
Stage 3 = upstream commit `0deb9d2` byl označen jako CONFLICT v dry-run a
přesunut do samostatného plánu podle Codex doporučení.

## Co 0deb9d2 dělá

**Upstream commit:** `0deb9d2 fix(lgi): clean up stale GLib sources on config timeout`
**Datum:** 2026-04-09
**Soubory:** `luaa.c` + `tests/test-floating-layout.lua`

1. Refactoruje inline GLib sweep logiku z reload path do funkce
   `luaA_cleanup_stale_glib_sources()`.
2. Volá tu funkci i z **config-timeout path** (když rc.lua loaduje > N sekund
   a compositor ho killne, aktuálně neprobíhá sweep → next dispatch hitne
   freed state).
3. Přidává test case `test-floating-layout.lua` ověřující behavior.

## Proč je to důležité (Codex varování)

Failure mode je reálný: když rc.lua timeoutne **po** registraci Lgi/GDBus
sources, current timeout-recovery path:

1. Zavře/recreatne Lua state (free callback memory).
2. **Neudělá GLib source sweep** (což reload path dělá).
3. Next GLib dispatch zavolá stale callback na freed state → SEGV.

Náš `liblgi_closure_guard.so` to teoreticky zachytí, ale pokud se timeout
stane brzy (před tím než guard zaregistruje některé callbacky), ochrana
může chybět.

## Proč CONFLICT

Upstream `0deb9d2` je postavený nad upstream `a85c538` (jejich varianta
GLib sweep funkce). Náš ekvivalent je `b43b26f` (naše varianta, jiná
struktura — byla dřív a sólo). Takže upstream refactor se nenapojí čistě.

## Možné přístupy

### A. Manuální merge (risk: hybrid silently breaks one path)

1. Cherry-pick `0deb9d2` s `--strategy-option=theirs` do staging.
2. Merge manuálně konflikt v `luaa.c`:
   - Zachovat naši strukturu sweep logiky (aby neovlivnilo reload path co
     funguje).
   - Extractovat do funkce `luaA_cleanup_stale_glib_sources()` s API jako upstream.
   - Přidat call site v config-timeout path.
3. Přidat test case.
4. Extensivní test obou path (reload i config timeout).

**Codex varování:** "Manuální merge může produkovat hybrid co silently zlomí
jednu z obou cest."

### B. Re-implementovat čistě (preferováno)

Místo cherry-picku identifikovat:
1. Kde přesně je v našem `luaa.c` config-timeout path (kde se rc.lua
   loading timeoutne).
2. Vložit tam volání naší existing sweep funkce z `b43b26f`.
3. Přidat test case inspirovaný `test-floating-layout.lua` upstreamu.

Výhoda: žádný konflikt, jasnější diff pro review, zachování naší struktury.

### C. Forward-port pozdě (aktuální stav = sledovat upstream)

Necháme volný, dokud neuvidíme konkrétní crash který by tento fix řešil.
Dnes máme `liblgi_closure_guard.so` ochranu, která timeout path
pravděpodobně (ale neověřeno) kryje.

## Reprodukce / test

Jak dostat rc.lua do timeout path:

```lua
-- Na začátek rc.lua, před lgi importy:
local lgi = require("lgi")
local Gio = lgi.Gio
-- Registrovat nějaký GIO watcher...
-- Pak infinite busy-wait přesahující config timeout:
local t0 = os.clock()
while os.clock() - t0 < 100 do end
```

Compositor má hardcoded config timeout (hledat v `luaa.c::config_timer`
nebo podobně). Po timeout ho killne, next GLib event bez sweep → crash.

## Akce

1. Najít náš config-timeout code path a zjistit jestli sweep opravdu chybí.
2. Pokud chybí: varianta B (re-implement), NE varianta A (cherry-pick).
3. Napsat test case který timeout reprodukuje.
4. Ověřit ochranu přes guard (jestli dnes to tichče nechytá).

## Riziko nicnedělání

Pokud se objeví bug hlášení "compositor crash po delším rc.lua loadu",
tohle je pravděpodobná příčina. Dokud ne, low priority.

## Reference

- Původní plán: `plans/done/cherry-pick-upstream-hotreload.md` (sekce "Deferred")
- Náš sweep baseline: commit `7fe1a73 fix(hot-reload): sweep stale GLib sources to prevent Lgi FFI closure SEGV`
- Upstream variant: `a85c538` (ekvivalent), `0deb9d2` (extension)
