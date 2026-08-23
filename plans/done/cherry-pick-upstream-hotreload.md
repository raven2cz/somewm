# Cherry-pick: upstream hot-reload + drawin/systray fixes

**Branch:** `fix/upstream-hotreload-cherrypick` (mergnuto do main 2026-04-16, smazáno)
**Date:** 2026-04-15
**Status:** DONE pro Stage 1a/1b/1c. Stage 2 a deferred přesunuto do samostatných plánů.

## Final outcome (2026-04-16)

Merge commit `1670e4b` na main. 7 cherry-picků aplikováno:

| Stage | Upstream hash | Náš hash | Co |
|-------|---------------|----------|-----|
| 1a    | c40eb9f | `3efb424` | destroy stale titlebar scene buffers |
| 1a    | a07990b | `0ac2238` | destroy old drawin scene trees |
| 1a    | 23282a9 | `0c2cc85` | shadow refresh on resize, border_width=0 |
| 1b    | 5617c20 | `dfead9e` | systray snapshot + re-probe |
| 1b    | 7be1148 | `d7c6a94` | bypass stale GDBus singleton cache |
| 1c    | 1e42b13 | `5d6c2d6` | recreate output objects in new Lua state |
| 1c    | 7a8e0cf | `6bb31f1` | preserve tiled client order across reload |

**Smoke test výsledek (2026-04-16):** 4 sekvenční reload → stabilní wibar shadow,
systray, outputs, tag→client mapping. Viz konkrétní session notes v merge commitu.

**Regressiony odhalené po merge:**
- Wibar shadow na startu chybí, když `theme.shadow_drawin_color` je nil → opraveno
  v `3cc986c` (somewm-one theme), generický C-side fix otevřený v
  `plans/investigate-shadow-nil-color-render.md`.
- 5. reload + sliding tags animation → SIGSEGV v libffi.so (PID 90539). Nový plán
  `plans/investigate-reload-libffi-lgi-crash.md`.

## Follow-ups z tohoto plánu (nezmergované)

- **Stage 2** (commity 67d7899 + ace15ed + b6b2e78): `plans/stage2-lgi-guard-autoload.md`
- **Deferred 0deb9d2** (GLib source sweep refactor): `plans/forward-port-glib-timeout-sweep.md`

---

## Původní plán (pro referenci)


## Framing (důležité upřesnění po Codex review)

Upstream hot-reload **NEobnovuje `lua_close`** — Lua-state leak zůstává
záměrnou architekturou (kvůli stale Lgi FFI closures). Upstream commits
řeší **resource-specific teardown kolem leaknutého state** + GLib source
sweep + closure guard. Plán nevytváří iluzi že se root cause mizí — jen
přidává cleanup staré scene/systray/output resources před Lua state reset.

## Cíl

Vyřešit dva pozorované buggy ve fork raven2cz/somewm cestou cherry-picků
z upstream/main + upstream/feat/hot-reload místo psaní vlastních fixů:

1. **Wibar shadow se s každým reloadem nasčítává** (občas zmizí). Root cause
   je leaknutý scene_tree starých drawins při hot-reload — `drawin_wipe()`
   neběží protože se starý Lua state leakuje (kvůli stale Lgi closures).
2. **Systray prázdný po reload/hotplug.** Stejný root cause + D-Bus
   StatusNotifierWatcher restart bez snapshot/re-probe item listu.

Předchozí pokus o vlastní fix (`fix/wibar-duplicity-on-reload`, smazaný
2026-04-15) selhal — měl jsem se nejdřív podívat do upstreamu.

## Audit upstreamu

`upstream/feat/hot-reload` je live development branch hot-reload práce.
Většina relevantních fixů je již mergnuta do `upstream/main`, několik
ještě žije jen na branch.

### Inventář upstream commitů (chronologicky, jen hot-reload/drawin/systray related)

| Hash | Datum | Soubory | Konflikt v dry-run? | Status |
|------|-------|---------|---------------------|--------|
| c40eb9f | 03-23 | luaa.c | ✅ CLEAN | titlebar scene buffers |
| a07990b | 03-24 | luaa.c | ✅ CLEAN | drawin scene trees |
| 5617c20 | 03-24 | systray.lua, luaa.c, systray.c | ✅ CLEAN | systray re-probe |
| 7a8e0cf | 03-26 | luaa.c, test | ✅ CLEAN | tiled client order |
| 67d7899 | 03-23 | meson.build, somewm.c | ✅ CLEAN | auto-load Lgi guard |
| ace15ed | 03-27 | somewm.c | ⚠️ závisí na 67d7899 | search paths for guard |
| b6b2e78 | 04-01 | luaobject.c, globalconf.h, luaa.c, spawn.h, somewm.c, spawn.c | ⚠️ závisí na ace15ed | log noise + guard search |
| 23282a9 | 04-03 | drawin.c | ✅ CLEAN | shadow refresh border_width=0 |
| **5eb31e1** | 04-03 | — | 🚫 prázdný changeset | **DUPLICATE našeho 0dae9b2** — ověřeno `cherry-pick --strategy=theirs` → zero diff; patch-id liší (jen wording), net-effect identický — SKIP |
| **d9e7481** | (feat/HR) | somewm.c | 🚫 prázdný changeset | **DUPLICATE našeho 05b7f21** (unsetenv LD_PRELOAD na line 7129) — SKIP |
| 7be1148 | (main) | statusnotifierwatcher.lua, systray.lua | ✅ CLEAN | GDBus singleton cache — **použít 7be1148 z upstream/main místo 706aeab (stejný patch po rebase)** |
| 1e42b13 | 04-09 | luaa.c, output.c/h | ✅ CLEAN | recreate output objects |
| 0deb9d2 | 04-09 | luaa.c, test-floating-layout.lua | ❌ CONFLICT | lgi: stale GLib sources timeout — **DEFER** (viz nový plán) |
| 635c2c9 | (main) | objects/drawin.c (-429 řádků) | ℹ️ NOTE | upstream dead code removal; neřešíme, ale executor by měl vědět že existuje — diff base na drawin.c po `0deb9d2` se posune |

### Klíčové zjištění o duplicitách

- **`5eb31e1` JSEM AUTOREM JÁ.** Jde o upstream verzi naší vlastní `0dae9b2 fix(wibar): enable SceneFX shadow support for drawins/wibar` (Apr 3, 10:42 → 11:07; trip-zip přijal jako PR a vyhodil project-specific části). Cherry-pick produkuje prázdný changeset — bezpečné přeskočit.
- **Lgi GLib source sweep:** Náš `b43b26f` má jednu variantu, upstream `a85c538` má jinou (už v upstream/main). Konflikt v `0deb9d2` je z toho, že upstream rozšiřuje upstream verzi, která se liší od naší — vyžaduje manuální merge.

### Stav našeho Lgi guard handling vs upstream

| Schopnost | Upstream (67d7899+ace15ed+b6b2e78) | Naše (current) |
|-----------|------------------------------------|----------------|
| `liblgi_closure_guard.so` knihovna | ✅ identický kód (společný původ) | ✅ máme |
| Auto-load při startu (re-exec s LD_PRELOAD) | ✅ ano | ❌ NE — vyžaduje manuální setup v `start.sh` |
| Multi-path search (lib64, system paths) | ✅ ano | ❌ NE |
| Graceful fallback bez guardu | ✅ ano | ❌ NE — selže němě |
| `unsetenv("LD_PRELOAD")` aby ho nedědili klienti | ✅ d9e7481 | ✅ máme (somewm.c:7129) |

Upstream guard auto-load (3 commity) je **funkční nadstavba**, ne náhrada
naší knihovny. Po cherry-picku odpadne nutnost `start.sh` LD_PRELOAD setupu
— compositor se sám re-execne s LD_PRELOAD, najde guard v `lib/lib64/system`
paths, varuje pokud chybí. Pro distros (Gentoo lib64, jiné package manageři)
to znamená out-of-the-box funkční hot-reload.

### Konflikty s naší fork-specific implementací

Audit pokrytí (potvrzeno dry-run):

- **SceneFX shadow path** (`shadow.c` `sfx_shadow` + `scenefx_compat.h`) —
  ŽÁDNÝ konflikt s upstream commits. 5eb31e1/23282a9 modifikují drawin.c
  resize hook (border_need_update flag), ne shadow.c samotný. Resize trigger
  funguje pro 9-slice i SceneFX path stejně.
- **Focus path** (`focusclient()`, `some_set_seat_keyboard_focus()`) — ŽÁDNÝ
  upstream hot-reload commit nešahá do focus path. Bez konfliktu.
- **Tag slide animation** (`lua/somewm/tag_slide.lua`, `root.c` wp_overlay
  helpers) — ŽÁDNÝ upstream hot-reload commit nešahá do animation/wp overlay
  cesty. Bez konfliktu.

## Plán cherry-picků (pořadí podle závislostí + risk)

Po Codex review Stage 1 rozdělena na 1a/1b/1c — kvůli bisect-friendly
regression attribution (drawin vs systray vs output jsou nezávislé subsystémy).

### Stage 1a: Drawin lifecycle (primární wibar shadow fix)

1. **`c40eb9f`** — fix(hot-reload): destroy stale titlebar scene buffers during client restore
   - `luaa.c` Phase E client restore — clears `scene_buffer` + `size` po memcpy ze snapshotu
   - **Ordering hazard (Codex):** musí být PO `memcpy` restore v Phase E, tak jak upstream má
2. **`a07990b`** — fix(hot-reload): destroy old drawin scene trees to prevent duplicate wibars
   - `luaa.c` Phase C — foreach drawin → drop shadow textures + destroy scene_tree
   - **Hlavní fix pro wibar shadow accumulation bug.**
   - **Ordering hazard (Codex):** musí běžet DOKUD `globalconf.drawins` obsahuje staré drawins. Cokoli co clearne `drawins.len` před tímto loopem fix defeatuje.
   - **Shadow subtree poznámka (Sonnet):** `wlr_scene_node_destroy(&scene_tree->node)` recursively zničí i shadow subtree; stale `shadow.tree` pointer je po `scene_tree = NULL` neškodný. Žádný konflikt s naším SceneFX sfx_shadow.
3. **`23282a9`** — fix(drawin): shadow not refreshed on resize when border_width is 0
   - `objects/drawin.c::drawin_border_refresh_single()` — shadow block na konci funkce (line ~1808 v našem souboru), patch-context match s naším 0dae9b2

**Smoke test po 1a:** 5× `somewm-client reload` → wibar shadow intenzita konstantní, scene_tree count stabilní.

### Stage 1b: Systray/GDBus (nezávislý subsystém)

4. **`5617c20`** — fix(hot-reload): restore systray items by snapshotting and re-probing after reload
   - `lua/awful/systray.lua`, `luaa.c`, `objects/systray.c`
   - Snapshot D-Bus item names před teardown, re-probe po reload — pokrývá Slack/Discord co se sami nepřiregistrují
5. **`7be1148`** — fix(hot-reload): bypass stale GDBus singleton cache after reload
   - `lua/awful/statusnotifierwatcher.lua` + `lua/awful/systray.lua` — pure Lua, komplementární k 5617c20
   - Použít z `upstream/main` (rebased equivalent 706aeab z feat/hot-reload)

**Smoke test po 1b:** Slack/Discord ikony po reload stále v systray; hotplug monitoru nezničí systray.

### Stage 1c: Output recreate + tiled client order

6. **`1e42b13`** — fix(hot-reload): recreate output objects in new Lua state
   - `luaa.c` + `objects/output.c/h` — output objekty se musí znovu vytvořit v novém Lua state, jinak signální handlery referují dead state
   - **Ordering hazard (Codex):** musí recreatnout outputs PO fresh state fresh-up ale PŘED rc.lua load (Lua startup může volat output API)
   - **Test plan add:** `awful.screen.focused()` musí vrátit non-nil po reload
7. **`7a8e0cf`** — fix(hot-reload): preserve tiled client order across reload
   - `luaa.c` save/restore `globalconf.clients` kolem `request::manage` loop
   - **Loop hazard (Codex):** manage loop nesmí být invalidated restored order — upstream to řeší append v Phase E

**Smoke test po 1c:** reload na multi-monitoru zachová tag → client mapping i tile pořadí.

### Stage 2: Lgi guard auto-load (řetězec, musí v pořadí)

Tyto 3 commity dohromady fungují, jednotlivě dávají somewm.c konflikt
(závisejí na sobě):

7. **`67d7899`** — fix(hot-reload): auto-load Lgi closure guard without user configuration
   - `meson.build` (přidá `-DSOMEWM_LIBDIR`) + `somewm.c::main()` (re-exec s LD_PRELOAD)
8. **`ace15ed`** — fix(hot-reload): search multiple paths for lgi_closure_guard.so
   - `somewm.c` — fallback search paths (lib/lib64/system) pro nestandardní distros
9. **`b6b2e78`** — fix(hot-reload): clean up log noise, preserve --search paths, find guard in build dir
   - `common/luaobject.c`, `globalconf.h`, `luaa.c`, `objects/spawn.h`, `somewm.c`, `spawn.c`
   - Polish: méně logu, dev-mode build dir support

Po sequenčním aplikování všechny 3 mergují čistě (ověřeno dry-run).

**Po Stage 2 — `start.sh` upravit:** odstranit manuální LD_PRELOAD setup,
nahradit jednoduchým spuštěním `somewm` (auto-load se postará). Při tom
ověřit, že child procesy (Firefox, alacritty) opravdu nedědí LD_PRELOAD
(náš `unsetenv` v somewm.c:7129 zůstává).

### Deferred: `0deb9d2` config timeout GLib sweep

**Přesunuto ze Stage 3** po Codex review. Plán řešit samostatně později.

- `luaa.c` + `tests/test-floating-layout.lua` — CONFLICT v dry-run proti našemu `b43b26f`
- Upstream refactoruje inline GLib sweep do `luaA_cleanup_stale_glib_sources()`
  a volá ji i z config-timeout path. Refactor je postavený nad upstream
  `a85c538` (jejich GLib sweep), ne nad naším `b43b26f` (jiná struktura).
- **Codex varování:** Manuální merge může produkovat hybrid co silently
  zlomí jednu z obou cest. **Failure mode je reálný**: když rc.lua timeoutne
  po registraci Lgi/GDBus sources, current timeout-recovery path closeuje/recreatne
  Lua bez GLib sweep → next dispatch hitne freed state.
- **Akce:** Založit `plans/forward-port-glib-timeout-sweep.md` po Stage 1+2
  merge. Defer ≠ omit. Do té doby zůstává ochrana přes náš `b43b26f` + closure guard.

### SKIP (ověřeno dry-run + patch-id)

- **`5eb31e1`** — duplicate našeho 0dae9b2. Verifikace:
  - Metadata author match (Antonin Fischer, oba commity 2026-04-03, 25 min apart)
  - `git cherry-pick --no-commit --strategy-option=theirs 5eb31e1` → zero diff proti HEAD
  - Patch-id liší jen kvůli lehce odlišnému commit message wordingu
- **`d9e7481`** — duplicate našeho `05b7f21` (oba unsetenv LD_PRELOAD)

## Test plan po každé Stage

```bash
# Build
~/git/github/somewm/plans/scripts/install-scenefx.sh
# (ručně — vyžaduje sudo, user spouští)

# Smoke test po reinstall (vyžaduje restart compositoru):
somewm-client eval 'return "drawins="..#drawin.get()'
# Před reload + po 5x reload → musí být stejné číslo

# Wibar shadow vizuální test:
# 1. Reload 3-5x v řadě
# 2. Vizuálně potvrdit, že shadow má stejnou intenzitu jako po čerstvém startu

# Systray test:
# 1. Otevřít Slack / Discord (status notifier ikony)
# 2. somewm-client reload
# 3. Vizuálně potvrdit, že ikony jsou stále v systray

# Hotplug test:
# 1. Otevřít Slack
# 2. Odpojit + připojit sekundární monitor (nebo `wlr-randr`)
# 3. Systray ikony musí stále být

# Po Stage 2 — guard auto-load:
# 1. Edit start.sh — odstranit LD_PRELOAD řádek
# 2. Restart session přes start.sh
# 3. Ověřit přes journalctl: somewm: lgi_guard: ... (potvrzení že guard naloaděn)
# 4. Reload 3x — žádný SEGV
# 5. Otevřít Firefox — `cat /proc/PID/environ` ověřit že LD_PRELOAD není nastaveno
```

## Rollback strategie

Každá Stage je samostatný subset commitů. Pokud něco selže:

```bash
# Rollback poslední Stage:
git reset --hard <hash-před-Stage>
git push --force-with-lease origin fix/upstream-hotreload-cherrypick

# Nebo selektivní revert:
git revert <commit-hash> [--no-edit]
git push origin fix/upstream-hotreload-cherrypick
```

Při selhání Stage 2 (guard auto-load) vrátit `start.sh` z gitu — manuální
LD_PRELOAD setup se vrátí.

## Po-merge cleanup

- Aktualizovat `plans/fix-hot-reload-lgi-closures.md` → archive do `plans/done/`
  (Phase 1 byla naše a79042b/86a374d/b43b26f, Phase 2-3 už řeší upstream
  cherry-picks, plán zastaralý)
- Aktualizovat `plans/fix-reload-crash-exit-callbacks.md` → otestovat zda
  ten "exit callback nil value" race po těchto fixech mizí; pokud ano, archive
- Prodiskutovat s upstreamem (issue/discussion na trip-zip/somewm), zda by
  šlo náš `5eb31e1` označit jako "Co-Authored-By" pro budoucí audit (kosmetické)

## Risk summary

| Stage | Commits | Risk | Co testovat |
|-------|---------|------|-------------|
| 1a | c40eb9f, a07990b, 23282a9 | **Low** | Wibar shadow nakumuluje, scene_tree count stabilní |
| 1b | 5617c20, 7be1148 | **Low** | Systray Slack/Discord ikony po reload + hotplug |
| 1c | 1e42b13, 7a8e0cf | **Low-Medium** | `awful.screen.focused()` non-nil, tile pořadí |
| 2 | 67d7899, ace15ed, b6b2e78 | **Medium** | Auto-load funguje, klienti nedědí LD_PRELOAD — **samostatná branch** |
| Deferred | 0deb9d2 | — | Forward-port plan po Stage 1+2 merge |

## Otevřené otázky pro Sonnet review

1. Je správné cherry-pickovat z `upstream/main` (kde je už merge mergnut) místo
   z `upstream/feat/hot-reload` (kde je live)? Pro 706aeab musíme z feat/HR,
   pro ostatní z main — konzistentnost OK?
2. Stage 2 (guard auto-load) nahrazuje náš `start.sh` LD_PRELOAD setup. Je
   bezpečné to udělat v jedné branchi nebo lépe samostatně?
3. Stage 3 (0deb9d2 conflict resolution) — riziko že náš b43b26f a upstream
   logika dělají totéž jiným způsobem a budou si konkurovat. Stojí za to
   tento commit vůbec vzít, nebo přeskočit a sledovat jen wibar/systray fix?
4. Měl bych nejdřív dokončit Stage 1 (vyřešit primární user-reported bugy),
   ohlásit hotovo, a Stage 2/3 odložit do samostatných branchí?
