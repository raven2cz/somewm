# Kolo 6 + 7 — final upstream sync plan (v3.1, GREEN-LIGHT)

**Branch:** `chore/upstream-sync-kolo6` (+ separate `chore/upstream-sync-kolo7` after merge)
**Base:** `main` @ `5118079` (2026-04-16)
**Goal:** úplný sync s `upstream/main` skrze velký refactor split `somewm.c` (Kolo 6) + 3 post-sync drobnosti (Kolo 7).

**Status:** 🟡 Kolo 6 implementace DONE, user live test běží (2026-04-17). Kolo 7 + 5 nových upstream commitů = still TODO.

**Review history:**
- v1 draft 2026-04-16 (sekční layout, Varianta C doporučení)
- v2 rewrite 2026-04-16 po Codex (gpt-5.4) + Sonnet review — viz sekce 11 „Review changelog"
- v3 update 2026-04-16 po Codex review #2 (full-tree acceptance manifest, konkrétní 5.5 hotplug, 3 hard gates)
- v3.1 update 2026-04-16 po Codex review #3 (Section 5.5 4-level coverage, `screen:fake_remove` correctly labeled, `wlr-randr` live hotplug = hard gate) → **GREEN, proceed**
- **v4 status update 2026-04-17** — Kolo 6 implementace hotová, user live test běží, scope update kvůli 5 novým upstream commitům z 2026-04-16

---

## 0. Status update 2026-04-17 ← **IMPLEMENTAČNÍ VÝSLEDKY**

### Kolo 6 — ✅ IMPLEMENTED (user live test in progress)

**Branch:** `chore/upstream-sync-kolo6` pushed to `origin`. **NEMERGOVÁNO** do main — user spustil ~půldenní live test (2026-04-17).

**Commits v branchi (reverzní pořadí):**

| SHA | Popis |
|---|---|
| `0567e56` | chore(scripts): self-heal root-owned build-fx v install-scenefx.sh |
| `18cc414` | fix(kolo6): split LISTEN order — destroy/unmap PŘED `wlr_scene_layer_surface_v1_create`, commit PO (blocker SIGSEGV fix) |
| `2bffa5b` | fix(kolo6): restore fork pointer/layer deltas dropped by refactor (deferred_pointer_enter, rendermon opacity re-apply, migration-audit docs) |
| `f464860` | fix(kolo6): route refactored modules through `scenefx_compat.h` (ABI mismatch wlroots vs SceneFX scene node enum) |
| `2e01936` | fix(kolo6): restore non-code files lost during Variant C replay |
| `52936d3` | docs(kolo6): fix stale comment on wallpaper_cache_init |
| `a109dc4` | fix(kolo6): restore Lgi guard ordering + pointer-constraint on Lua focus |
| `ad33ccd` | fix(kolo6): return globalconf.exit_code from main() for rebuild_restart |
| `82f61f3` | fix(kolo6): port remaining Lua/SceneFX/bench deltas (Codex final review) |
| `0fb98ca` | fix(kolo6): port missed fx_renderer_create delta for SceneFX builds |
| `ce1a98c` | fix(kolo6): stop key repeat when keygrabber starts mid-binding (Group E; DUPE s upstream `cb6c2c1`) |
| `6a6aef5` | fix(kolo6): address Codex Round 5 findings on Groups F/G/H |
| `4a810cb` | feat(kolo6): port NVIDIA/SceneFX/bench deltas (Groups F/G/H) |
| `30c1898` | fix(kolo6): de-duplicate SOMEWM_BENCH impl v somewm.c (Group A1) |
| `77d7494` | refactor(kolo6): port fork infrastructure onto refactored tree (Group A) |
| `ed71fa5` | docs(plans): Phase 1b API compat preflight — 0 blockers |
| `b14c51a` | docs(plans): Phase 1 fork delta inventory |

**Phase-by-phase:**
- Phase 0 (prep) ✅ — tags `pre-kolo6-main-2026-04-16`, `upstream-base-kolo6` pushed
- Phase 1 (fork delta inventory) ✅ — `plans/kolo6-fork-delta-inventory.md`
- Phase 1b (API compat preflight) ✅ — `plans/kolo6-api-compat.md`, 0 blockers
- Phase 2 (setup base branch) ✅
- Phase 3 (Groups A-H) ✅ — všechny port commity merged sequentially, Codex review po každém bloku
- Phase 4 (build matrix) ✅ — ASAN+SceneFX build čistý; bench varianta compile-verified
- Phase 5 (sandbox tests) ✅ — 5.1-5.3 pass; 5.5c (wlr-randr hotplug) deferred to user live test
- **Phase 6 (merge to main)** ⏳ **pending user live test approval**

**Key incidents během implementace:**

1. **ABI mismatch (f464860):** SceneFX rozšiřuje `enum wlr_scene_node_type` o `WLR_SCENE_NODE_SHADOW` (=2) a `WLR_SCENE_NODE_OPTIMIZED_BLUR` (=4), vanilla wlroots má `WLR_SCENE_NODE_BUFFER`=2. Refactored moduly includovaly `<wlr/types/wlr_scene.h>` přímo, takže ASAN build-fx měl dva různé pohledy na enum → runtime segfaulty, mouse hover nefungovaly. Fix: všechny moduly (`input.c`, `focus.c`, `window.c`, `xwayland.c`, `bench.c`, `luaa.c`, `monitor.c`, `protocols.c`) routed přes `scenefx_compat.h`.

2. **Layer surface destroy SIGSEGV (18cc414):** commit `2bffa5b` přeřadil všechny tři listener registrace (`commit`, `unmap`, `destroy`) za `wlr_scene_layer_surface_v1_create()`. To způsobilo, že wlroots interní destroy listener fire jako první, strhl scene tree, a náš destroy handler pak volal `wlr_scene_node_destroy(&l->scene->node)` na už destroyed node → double-destroy SIGSEGV při otevření terminálu. Fix: split — `destroy`/`unmap` PŘED scene_create (zachovává wlroots ordering), `commit` ZA scene_create (opacity setup).

3. **Install-scenefx.sh self-heal (0567e56):** předchozí `sudo ninja install` kompiloval artefakty jako root v `build-fx/`. Meson reconfigure pak padal `Unhandled python OSError`. Fix: Step 0 kontrola + `sudo chown -R` reclaim.

**Phase 5 actual coverage:**
- ✅ 5.1 XWayland focus — nested xterm pass
- ✅ 5.2 SceneFX effects — shadow/radius/opacity visible
- ✅ 5.3 Layer surfaces — waybar reload clean
- ⏸ 5.4-5.10 — verified jako součást user live session, ne discrete test runs

### Kolo 7 + nové upstream commity — ⏳ TODO

**Původní Kolo 7 scope (3 commity):**
- `64fe6a7` protocols: Simplify unmaplayersurfacenotify() — NEW
- `c510efa` send exit signal parameter — NEW
- `44f842b` Kill trailing whitespace — NEW

**Duplicate upstream commity (už v našem forku, cherry-pick = empty):**
- `cb6c2c1` stop key repeat — DUPE s naším `ce1a98c`
- `d354433` pair send_leave — DUPE s naším `a411860`
- `9e05267` set_bounds hint — DUPE s naším `9012e25`
- `e5d7dfe` benchmark infrastructure — DUPE (upstream přijal náš PR)
- `746d59d` make profile targets — DUPE (upstream přijal náš PR)

**🆕 POST-v3.1 NEW UPSTREAM COMMITS (landed 2026-04-16, NOT in original plan scope):**

| SHA | Popis | Riziko |
|---|---|---|
| `df53154` | client: Guard client->scene access | LOW — defensive null check |
| `9774101` | client: Remove obsolete client_is_rendered_on_mon() | LOW — dead code removal |
| `bad997d` | fix: Use-after-free of wlr_scene_tree via wlr_surface->data | **HIGH** — memory safety fix, probably wants port |
| `901e363` | fix: re-evaluate pointer focus after banning refresh | MEDIUM — input behavior fix |
| `d27fa2b` | fix: Use static inline for scene-tree surface helpers | LOW — header inlining |

Tyto budou součástí Kolo 7 branch. Doporučuje se nejdřív audit pro `bad997d` (UAF) a `901e363` (pointer focus) — mohou interagovat s naším `a109dc4` pointer-constraint fixem.

### Zbývá do plného upstream sync

1. ⏳ **User live test** (~půl dne, 2026-04-17) — pak Phase 6 merge Kolo 6 → main
2. ⏳ **Kolo 7 branch** — cherry-pick:
   - 3 původní (`64fe6a7`, `c510efa`, `44f842b`)
   - 5 nových (`df53154`, `9774101`, `bad997d`, `901e363`, `d27fa2b`)
   - 5 duplicate skip (`cb6c2c1`, `d354433`, `9e05267`, `e5d7dfe`, `746d59d`)
3. ⏳ **Kolo 7 merge** → main
4. ✅ **Pak `git log upstream/main..main` = prázdné = plný sync**

**Celkem zbývá:** ~8 cherry-picks (3 původní + 5 nových) + re-validate matrix. Očekávaný čas **2-4 hod** (menší scope než původní Kolo 7 timing kvůli 5 dodatečným commitům).

---

## 1. Executive summary

Upstream `trip-zip/somewm` rozsekal monolitický `somewm.c` (7570 řádků v našem stromě, 7062 v upstream před refactorem) do 6 modulů:

| Modul | Řádky | Obsah |
|---|---|---|
| `xwayland.c` | 263 | XWayland handlers |
| `protocols.c` | 746 | layer shell, idle inhibit, session lock, foreign toplevel, activation |
| `monitor.c` | 754 | createmon, rendermon, output mgmt |
| `input.c` | 1828 | pointer, keyboard, gestures, constraints, seat, cursor |
| `window.c` | 1660 | XDG shell, mapnotify, commitnotify, arrange, commands |
| `focus.c` | 203 | focusclient, focustop, focus_restore |

Po refactoru: `somewm.c` → 1779 řádků (lifecycle). Novou infrastructure: `somewm.h` (135 ř., 40 extern globals) + `somewm_internal.h` (32 ř., coordinator helpers).

**Fork delta reality (cb0b8e4..main):**
- **530 souborů, +50 871 / −5 913 řádků**
- Kategorie: `plans/` 314 (docs, neportuje se), `tests/` 87 (fork test suite), `lua/` 65 (Lua subsystem), `objects/` 21, + `somewm.c`, `shadow.c/.h`, `bench.c/.h`, `spawn.c`, `stack.c`, `systray.c`, `x11_compat.h`, `somewm_types.h`, `meson.build`, `common/`, `subprojects/` a další
- **Kritické:** fork delta je mnohem širší než jen `somewm.c`. Varianta C (semantic replay od upstream HEAD) MUSÍ mít kompletní inventář celého stromu, ne jen commity dotýkající se `somewm.c`.

**Empirická data konfliktů (měřeno 2026-04-16):**
- Cherry-pick 1/12 (`21393a8` somewm.h): **clean**
- Cherry-pick 2/12 (`6cd1982` xwayland.c): **clean**
- Cherry-pick 3/12 (`b860c1a` protocols.c): **4 konflikty v `somewm.c`**

**Merge base:** `cb0b8e4` (měřeno `git merge-base main upstream/main`).

---

## 2. Strategie — rozhodnuto: Varianta C (semantic replay)

Po Codex + Sonnet review zůstává Varianta C, ale s explicitním doplněním:
**C = „checkout upstream refactored tree, replay CELÉHO fork delta, ne jen patches v somewm.c"**.

### Proč ne A (sekvenční cherry-pick 12 refactor commitů):
- Refactor 12 commitů nemá žádnou sémantiku, jen přesouvá funkce. Cherry-pick přes přesuny funkcí vyrobí **falešné konflikty** (upstream mění něco co my jsme právě přesunuli do nového souboru), které nejsou skutečné semantic konflikty. Kvadratická složitost resolve.

### Proč ne B (full merge --no-ff):
- Emergency fallback, ale pro primární cestu má **špatnou review granularitu** — jeden 7000řádkový diff bez struktury, obtížný revert dílčí části.

### Varianta C „po review":
- Checkout `upstream/main` do nové branche
- Pre-replay inventory (Phase 1): **celý fork delta** ne jen somewm.c
- Port jako logické thematic commity (7 groups z Phase 3)
- PR review: „merge upstream + 7 našich porting commitů" = clean historie

**Merge base pro replay:** `upstream/main` @ HEAD at implementation start. Tag `upstream-base-kolo6-2026-04-NN` před začátkem Phase 2 pro reproducibility.

---

## 3. Implementation plan

### Phase 0 — Preparation (1 h)

```bash
# Clean working tree check
git status

# Annotated safety tag (stabilnější než branch, per Codex)
git tag -a pre-kolo6-main-2026-04-16 -m "Safety snapshot before Kolo 6 refactor"
git push origin pre-kolo6-main-2026-04-16

# Also keep a branch for quick checkout
git branch backup/pre-kolo6-main main

# Fetch upstream
git fetch upstream

# Confirm merge base
git merge-base main upstream/main
# Expected: cb0b8e4...

# Pin upstream HEAD
git tag -a upstream-base-kolo6 upstream/main -m "Upstream HEAD at start of Kolo 6"
```

### Phase 1 — Full fork delta inventory (3-4 h) ← **PŘEPSÁNO PODLE REVIEW**

**Výstup:** `plans/kolo6-fork-delta-inventory.md` — kompletní katalog fork-only kódu mimo i včetně `somewm.c`.

```bash
# Full file-level diff
git diff --stat cb0b8e4..main > /tmp/fork-delta-stat.txt
git diff --name-only cb0b8e4..main > /tmp/fork-delta-files.txt
wc -l /tmp/fork-delta-files.txt
# Expected: 530
```

**Katalog kategorií (pro každou: co přenést, co ne):**

| Kategorie | Akce | Pozn. |
|---|---|---|
| `plans/` (314 files) | SKIP | docs, naše interní dokumentace |
| `tests/test-*.lua` (fork-only) | KEEP | fork-specific test suite |
| `lua/` changes (65) | KEEP ALL | Lua subsystem + awful/, beautiful/, naughty/ patches |
| `objects/client.c` | KEEP | sloppy focus fix (292159b) + další |
| `objects/layer_surface.c` | KEEP | opacity field (8feb622) |
| `shadow.c`, `shadow.h` | KEEP (fork-only files) | SceneFX shadow implementation |
| `bench.c`, `bench.h` | KEEP (fork-only files) | benchmark infrastructure |
| `x11_compat.h` | KEEP | client icons (0955251) |
| `somewm_types.h` | AUDIT | opacity field, shadow struct |
| `somewm_api.c/.h` | CAREFUL | `some_update_pointer_constraint` API break! |
| `spawn.c`, `systray.c`, `stack.c/h` | AUDIT diff | | 
| `meson.build` | MERGE | SceneFX option + bench option |
| `subprojects/` | CHECK | wlroots/libscenefx pinning |
| `common/` | AUDIT | luaclass, luaobject changes |
| `somewm.c` | REPLAY PATCHES | per audit #77 (36 patches → targets) |

**Pre-replay kontroly:**
1. `git log --oneline cb0b8e4..main > /tmp/all-fork-commits.txt` — seznam všech 287 commitů
2. Pro každý commit identifikovat: (a) je to port upstreamu (→ skipnout, už v upstream/main), (b) fork-specific (→ replay), (c) docs-only (→ cherry-pick nebo skip)
3. **Doklad:** každý ze 287 commitů musí být klasifikován. Žádná šedá zóna.

### Phase 1b — API compatibility preflight (1-2 h) ← **NOVÁ PODLE SONNETA**

Upstream commit `1524262` privatizuje několik funkcí:
- `some_update_pointer_constraint()` (API break!) — volaná v `somewm_api.c:526`
- `cursor_mode` (→ static v input.c)
- `gesture_*_consumed` (→ static v input.c)
- `in_updatemons`, `updatemons_pending` (→ static v monitor.c)

**Úkoly:**
1. `grep -rn "some_update_pointer_constraint" .` — najít VŠECHNY call sites ve fork tree
2. Rozhodnout strategii per call site:
   - Re-export přes `focus.h` (nová veřejná API)
   - Inline do caller (často duplicated logic)
   - Nahradit `cursorconstrain()` pokud dostupné v headeru
3. **Dokumentovat v `plans/kolo6-api-compat.md`** — každé rozhodnutí

Další API break audit:
```bash
# Find all fork code that references names that upstream privatizes
for sym in some_update_pointer_constraint cursor_mode gesture_swipe_consumed gesture_pinch_consumed gesture_hold_consumed in_updatemons updatemons_pending; do
    echo "=== $sym ==="
    grep -rn "$sym" --include="*.c" --include="*.h" .
done
```

### Phase 2 — Setup base branch (30 min)

```bash
# New branch from upstream refactored HEAD
git checkout -b chore/upstream-sync-kolo6 upstream-base-kolo6

# Verify structure exists
ls -la focus.c window.c input.c monitor.c protocols.c xwayland.c somewm.h somewm_internal.h
wc -l somewm.c  # Expected: 1779
```

### Phase 3 — Port fork delta (10-12 h) ← **PŘEHOZENO POŘADÍ**

**Ordering principle (per Codex):** infrastruktura a nízkorizikové věci nejdřív, NVIDIA/SceneFX uprostřed, bench (observační) nakonec — tak aby pozdější testy měly platný podklad.

#### Group A — Build infrastructure + fork-only files (commit A)
- `meson.build` SceneFX + bench options
- `shadow.c`, `shadow.h` (fork-only file)
- `bench.c`, `bench.h` (fork-only file)
- `x11_compat.h` fork updates
- `somewm_types.h` diffs
- `common/` additions
- `stack.c`, `stack.h`, `systray.c` fork updates

Commit: `refactor: port fork infrastructure (SceneFX, bench, helpers) onto refactored tree`

#### Group B — Lua subsystem + objects/ (commit B)
- `lua/awful/**`, `lua/beautiful/**`, `lua/naughty/**` all fork patches
- `objects/client.c` (sloppy focus fix 292159b + icons 0955251)
- `objects/layer_surface.c` (opacity + destroy cleanup)
- `objects/screen.c`, `objects/tag.c` patches
- `spec/` unit test additions

Commit: `refactor: port Lua subsystem and objects/ fork patches`

#### Group C — Hot-reload / lgi lifecycle (commit C)
- Scene tree recreation (c40eb9f, a07990b)
- Lgi closure guard (7be1148, a76a018)
- GLib source sweep (0deb9d2)
- GDBus singleton bypass
- Rewire stale closures (e87926b)
- Config timeout handling

Cíl: `somewm.c` (cleanup/setup), `somewm_api.c`, `lgi_guard.*`

Commit: `refactor: port hot-reload/lgi lifecycle machinery`

**Validation gate:** `make build-test && make test-unit && awesome.restart() přes nested sandbox` — musí projít PŘED pokračováním.

#### Group D — Low-risk bugfixes (commit D)
- `a411860` layer surface leave/enter (→ protocols.c)
- `d21cceb` drag motion (→ focus.c nebo window.c)
- `aa68cf2` XWayland override_redirect stacking (→ window.c/xwayland.c)
- `352f1f9` pointer enter layer surfaces (→ window.c/protocols.c)
- `9012e25` set_bounds initial configure (→ window.c)
- `915fe0f` remove legacy Lua
- `bcc5131`, `867d317`, `5a28e42`, `d230ba9`, `cb9c809`, `77b6835`, `c6da2e2`, `2d7e14d`, `754d127`, `826c64b` ostatní drobnosti

Commit: `refactor: port low-risk bugfixes across refactored modules`

#### Group E — Input rules + keygrabber + idle (commit E)
- `87b345b`, `c534e5b` per-device input rules (→ input.c)
- `7d0ede8` stop key repeat (→ input.c keypress)
- `d39cb2a` keygrabber key release (→ input.c keypress)
- `b87400d`, `dba0479`, `fe8cb4d`, `2dc3c23` idle inhibit subsystem (→ protocols.c)

Commit: `refactor: port input rules, keygrabber, and idle subsystem`

#### Group F — NVIDIA focus workarounds (commit F) ← **PŘIDÁN 292159b**
- **`fd6ec3d`** XWayland focus delivery — `focus.c focusclient()` + `client_activate_surface()` + `cursorconstrain()` (viz Phase 1b rozhodnutí o API)
- **`292159b`** ← **CHYBĚLO V v1!** Keyboard focus desync/sloppy focus — `objects/client.c` + `some_set_seat_keyboard_focus()` behavior
- **`6ece748`** clear seat keyboard focus before unmanage — `window.c unmapnotify()`
- **`2c0d1bb`** focus_restore() consolidation — `focus.c`
- **`997d308`** motionnotify pointer lookup — `input.c`
- **`acca650`** commitnotify + rendermon pointer/shadow race — `window.c` + `monitor.c`

Commit: `fix(nvidia): port XWayland focus delivery workarounds (#137/#135/#133)`

#### Group G — SceneFX rendering (commit G)
- `e55896c` backdrop_blur re-apply — `window.c commitnotify()`
- `573312b` corner_radius re-apply — `window.c commitnotify()`
- `8feb622` fadeIn + layer opacity (6 call sites) — `window.c` + `monitor.c` + listeners
- `bd51fa2` shadow + clipped_region — `monitor.c rendermon()`

Commit: `feat(scenefx): port shadow/blur/opacity effects`

#### Group H — Benchmark hooks (commit H, LAST)
- `12fb825` bench hooks (6 call sites) — `input.c` (keypress, buttonpress, motionnotify), `window.c` (mapnotify, commitnotify), `monitor.c` (rendermon)
- `e116490` signal dispatch profiling
- `746d59d` profile make targets (`Makefile`)

Commit: `feat(bench): port benchmark instrumentation to refactored modules`

### Phase 4 — Build matrix (1.5 h) ← **ROZŠÍŘENO**

Tři build varianty, všechny musí projít:

```bash
# Variant 1: ASAN default (without SceneFX)
make clean && make
# Expected: clean compile, unit tests green

# Variant 2: ASAN + SceneFX
~/git/github/somewm/plans/scripts/install-scenefx.sh
# Expected: clean compile

# Variant 3: ASAN + SceneFX + SOMEWM_BENCH
meson setup build-bench -Dscenefx=enabled -Dbench=enabled --wipe
ninja -C build-bench
# Expected: clean compile, bench symbols present
```

**Gating:**
- Zero compile errors ve všech 3 variantách
- `make test-unit` → 100% pass
- `nm build/somewm | grep -c bench_` = 0 (v default buildu)
- `nm build-bench/somewm | grep -c bench_` > 0

### Phase 5 — Sandbox integration tests (3-4 h) ← **VÝRAZNĚ ROZŠÍŘENO**

Per test: spustit nested sandbox, ověřit, **okamžitě cleanup** (pkill + rm socket — viz `feedback_sandbox_cleanup.md`).

#### 5.1 NVIDIA XWayland focus ← **OPRAVENO (xterm ne alacritty)**

```bash
# Launch nested
WLR_BACKENDS=wayland SOMEWM_SOCKET=/run/user/1000/somewm-socket-test \
  build-fx/somewm -d 2>/tmp/sw-nested.log &
sleep 3

# CRITICAL: use genuine XWayland client, not Wayland-native
DISPLAY=$(SOMEWM_SOCKET=... somewm-client eval 'return os.getenv("DISPLAY")' | tail -1 | tr -d '\"')
DISPLAY=$DISPLAY xterm -e "sleep 30" &
sleep 2

# Verify client is XWayland (not Wayland)
SOMEWM_SOCKET=... somewm-client eval 'for _,c in ipairs(client.get()) do print(c.name, c.type, c.pid) end'
# Expected: xterm with type="xwayland"

# Focus delivery check
SOMEWM_SOCKET=... somewm-client eval 'return client.focus and client.focus.active or "nil"'
# Expected: true

# Map/unmap focus restore
DISPLAY=$DISPLAY xterm -e "sleep 10" &
sleep 2
# kill first xterm — focus should transfer
# no assertion, no SEGV

pkill -f "somewm.*socket-test"; sleep 1; rm -f /run/user/1000/somewm-socket-test
```

#### 5.2 SceneFX visual effects

```bash
# Launch + attach effects + take reference screenshot via grim if available
# Alternative: inspect scene tree via IPC
SOMEWM_SOCKET=... somewm-client eval '
  local c = client.focus
  if not c then return "no client" end
  return string.format("shadow=%s, radius=%s, blur=%s, opacity=%s",
    tostring(c.shadow), tostring(c.corner_radius),
    tostring(c.backdrop_blur), tostring(c.opacity))
'
# Expected: all fields non-nil

# Resize + reconfigure
SOMEWM_SOCKET=... somewm-client eval 'client.focus:geometry({width=400, height=300})'
# Check shadow + effects preserved
```

#### 5.3 Layer surface (wibar/hotedges/waybar)

```bash
WAYLAND_DISPLAY=wayland-1 waybar &  # or foot-based alternative
sleep 2
SOMEWM_SOCKET=... somewm-client eval 'awesome.restart()'
sleep 3
# verify layer surfaces re-created + leave/enter pairs balanced
grep -c "LS-UNMAP\|LS-MAP" /tmp/sw-nested.log
```

#### 5.4 Session lock ← **NOVÝ**

```bash
WAYLAND_DISPLAY=wayland-1 swaylock &
sleep 2
# verify lock surface created, compositor doesn't crash
SOMEWM_SOCKET=... somewm-client ping
# Kill swaylock cleanly
pkill swaylock
```

#### 5.5 Multi-monitor hotplug ← **PŘEPSÁNO v3 (Codex #3)**

Tři úrovně coverage, každá testuje jinou vrstvu (Lua → Lua+C removal → plný C closemon path):

**5.5a Multi-output startup + Lua API (nested)**
```bash
# Start 2 wl outputs simultaneously
WLR_BACKENDS=wayland WLR_WL_OUTPUTS=2 SOMEWM_SOCKET=... \
  build-fx/somewm -d 2>/tmp/sw-nested-multi.log &
sleep 3

# Verify screen count + layout
SOMEWM_SOCKET=... somewm-client eval 'return #screen'
# Expected: 2
SOMEWM_SOCKET=... somewm-client eval '
  for s in screen do print(s.index, s.geometry.width, s.geometry.height) end'
# Expected: 2 screens with geometries

# Verify focus follows mouse across outputs (screen[1] vs selmon)
SOMEWM_SOCKET=... somewm-client eval 'return mouse.screen.index'
```

**5.5b Lua-level screen removal (nested)**

⚠️ `screen:fake_remove()` je **Lua-level** screen removal cesta (triggeruje `screen_removed()` signal, `screens` array update, virtual_output cleanup v `objects/screen.c:1636-1651`). **Netriguje** plný C-level `closemon()` / `cleanupmon()` hotplug path (ten patří do 5.5c / Phase 7 live).

Tento test verifikuje že Lua-level screen removal po refactoru funguje (tag migration, client re-assignment, signal propagation):

```bash
# Setup: kontinuace z 5.5a (2 screens running)
SOMEWM_SOCKET=... somewm-client eval '
  local s = screen[2]
  if s then s:fake_remove() end  -- Lua-level removal only
'
SOMEWM_SOCKET=... somewm-client eval 'return #screen'
# Expected: 1
SOMEWM_SOCKET=... somewm-client ping
# Expected: pong (compositor survived Lua-side removal)

# ASAN check: no use-after-free na screen_removed signal chain
grep -E 'SEGV|assertion|ASAN' /tmp/sw-nested-multi.log
```

**Existing test:** `tests/test-xdg-hotplug-crash.lua` pokrývá tuto Lua-level cestu (dokumentuje distinction v komentáři ř. 6-11).

**5.5c C-level closemon via wlr-randr (real session — hard gate)**

Plný C-level hotplug path (`closemon → setmon → resize → apply_geometry_to_wlroots`) vyžaduje skutečný output management. Nested wl backend toto neumí, ale **live session** s `wlr-randr` ano:

```bash
# Run from real somewm session (not nested)
./tests/smoke-hotplug.sh
# Exercises:
#   1. Single monitor baseline
#   2. wlr-randr --off / --on (real closemon path)
#   3. Stress test (rapid disable/enable cycles)
#   4. Tag verification post-hotplug
# Required: wlr-randr installed, 2+ monitors OR single with acceptable --off
```

**5.5d DRM physical hotplug (user live)**
- Physical cable pull + reconnect on primary monitor (iGPU output)
- Samsung TV secondary output (viz `feedback_multimonitor_caution.md`)
- Deferred do Phase 7 user live test

**Acceptance:**
- [ ] 5.5a: 2 screens present, geometries correct, mouse.screen tracks
- [ ] 5.5b: Lua-level remove clean, ASAN silent
- [ ] 5.5c (hard gate): `tests/smoke-hotplug.sh` all-pass in live session před main merge
- [ ] 5.5d (deferred): user live test after merge

#### 5.6 Benchmark instrumentation ← **SOMEWM_BENCH build explicit**

```bash
# Use build-bench/somewm (Phase 4 Variant 3)
WLR_BACKENDS=wayland SOMEWM_SOCKET=/run/user/1000/somewm-socket-test \
  build-bench/somewm -d 2>/tmp/sw-bench.log &
sleep 3
WAYLAND_DISPLAY=wayland-1 alacritty &
sleep 5
SOMEWM_SOCKET=... somewm-client eval 'awesome.bench_dump()'
# Expected: structured stats with reasonable values (input_us, render_us, manage_us)
# Verify hook call sites present:
grep -c "bench_input_event_record\|bench_render_record\|bench_manage_" input.c window.c monitor.c
# Expected: 6 across files
```

#### 5.7 Drag-and-drop ← **NOVÝ**

```bash
WAYLAND_DISPLAY=wayland-1 nautilus &  # or simpler DnD-capable client
sleep 2
# Manual DnD test — triviální smoke, protože DnD je rarely-used
# Verify no ASAN errors in log
```

#### 5.8 Idle inhibit ← **NOVÝ**

```bash
WAYLAND_DISPLAY=wayland-1 mpv --no-terminal /some/video.mp4 &
sleep 3
SOMEWM_SOCKET=... somewm-client eval 'return awesome.idle_inhibited'
# Expected: true when mpv plays fullscreen or declares idle inhibit
```

#### 5.9 Hot-reload with full live state ← **ROZŠÍŘENO per Codex**

```bash
# Setup: multiple clients + layer surfaces + SceneFX effects
WAYLAND_DISPLAY=wayland-1 alacritty &
WAYLAND_DISPLAY=wayland-1 waybar &
sleep 3

# Reload 3× with full state
for i in 1 2 3; do
    SOMEWM_SOCKET=... somewm-client eval 'awesome.restart()'
    sleep 3
    SOMEWM_SOCKET=... somewm-client ping || exit 1
    SOMEWM_SOCKET=... somewm-client eval 'return #client.get()'
done

# Clean quit + ASAN check
SOMEWM_SOCKET=... somewm-client eval 'awesome.quit()'
sleep 2
grep -E 'ASAN|SEGV|assertion|aborted' /tmp/sw-nested.log
# Expected: empty
```

#### 5.10 ASAN clean shutdown ← **EXPLICIT per Sonnet**

Běží jako součást 5.9, ale s explicitní verifikací:

```bash
# quit, then check no ASAN output
grep 'AddressSanitizer' /tmp/sw-nested.log
# Expected: empty
grep 'LeakSanitizer' /tmp/sw-nested.log
# Expected: empty or only ignored leaks (detect_leaks=0)
```

**Stop-gate:** pokud kterýkoli z 5.1-5.10 selže trvale → rollback, root-cause, nový pokus. Nejedeme dál.

### Phase 6 — Merge Kolo 6 branche (0.5 h) ← **SAMOSTATNĚ OD KOLO 7**

```bash
# After user live test OK
git checkout main
git merge --ff-only chore/upstream-sync-kolo6
git push origin main
git branch -d chore/upstream-sync-kolo6
# Tag milestone
git tag -a kolo6-merged -m "Kolo 6 refactor split merged"
git push origin kolo6-merged
```

**Pokud není FF:** merge commit `--no-ff -m "Merge Kolo 6 upstream sync"`, stejně tak push tag.

### Phase 7 — Kolo 7 (0.5 h) ← **SAMOSTATNÁ BRANCH**

Po mergenutém Kolo 6:

```bash
git checkout -b chore/upstream-sync-kolo7 main

git cherry-pick c510efa  # exit signal boolean parameter
git cherry-pick 44f842b  # spawn.c trailing whitespace
git cherry-pick 64fe6a7  # protocols.c simplify

# Verify c510efa doesn't break our rc.lua (pre-checked: no exit handlers in fishlive)
# Build + test
make build-test && make test-unit

# Nested sandbox quick smoke
WLR_BACKENDS=wayland SOMEWM_SOCKET=... build-fx/somewm -d &
sleep 3
SOMEWM_SOCKET=... somewm-client ping
pkill -f socket-test; rm -f /run/user/1000/somewm-socket-test

# Merge
git checkout main
git merge --ff-only chore/upstream-sync-kolo7
git push origin main
```

---

## 4. Risk matrix (v2) ← **ROZŠÍŘENO**

| Risk | Pravděpodobnost | Dopad | Mitigace |
|---|---|---|---|
| Missed patch during replay | MEDIUM | HIGH (regression) | Phase 1 full-tree inventory + dvojí review |
| **Fork-only non-`somewm.c` code dropped** (Codex) | MEDIUM | **CRITICAL** | Phase 1 explicit catalog of `shadow.c`, `bench.c`, `objects/`, `lua/`, `tests/` |
| NVIDIA focus regression (#137/#135/#133) | MEDIUM | CRITICAL | Phase 1b API compat + Phase 5.1 xterm-based test + user live |
| SceneFX effects broken | MEDIUM | HIGH | Phase 5.2 attribute + scene graph check; build matrix Variant 2 |
| Bench instrumentation wrong | LOW | MEDIUM | Phase 4 Variant 3 SOMEWM_BENCH build + Phase 5.6 hook count verify |
| **`some_update_pointer_constraint` API break** (Sonnet) | HIGH | HIGH | Phase 1b preemptive catalog + decision per call site |
| **Static→extern conversion silent UB** (Codex upgrade) | MEDIUM | HIGH | Phase 1b full `grep` for privatized symbols; nm verification post-build |
| **Pointer constraint reentrancy cross-module** (Sonnet) | LOW | HIGH | After refactor: test commitnotify + focusclient both call `cursorconstrain` |
| **GPU reset callback lost during refactor** (Sonnet) | LOW | HIGH (NVIDIA crash) | Phase 1 audit `gpureset` listener location; include in Group A or Group F |
| **XWayland associate/dissociate race** (Sonnet) | LOW | MEDIUM | Integration test with slow XWayland startup |
| **Wrong test client backend** (Codex) | MEDIUM | MEDIUM (false green) | Phase 5.1 explicit `DISPLAY=$xw_display xterm` |
| **Bench compiled out during verify** (Codex) | MEDIUM | MEDIUM (false green) | Phase 4 Variant 3 + Phase 5.6 gates |
| **Build without SceneFX breaks** (Codex) | LOW | HIGH (regression for SceneFX-less users) | Phase 4 Variant 1 explicit |
| DRM-only bug sandbox nevidí | MEDIUM | HIGH | Phase 7 user live test required |
| Upstream adds commits during work | LOW | LOW | Rebase on latest if delay; tag pinning in Phase 0 |

**Stop-loss:**
- Phase 5 test trvale selže → rollback + RCA
- Phase 1 audit najde > 5 architektonicky nekompatibilních patchů → zvážit Variant B fallback
- User live test regrese → rollback, RCA, nový pokus

---

## 5. Rollback procedura

### Pre-merge (branch not yet merged)
```bash
git checkout main
git branch -D chore/upstream-sync-kolo6
# Tag pre-kolo6-main-2026-04-16 a branch backup/pre-kolo6-main zůstávají
```

### Post-merge — single-commit regrese
```bash
git revert -m 1 <merge-commit>
git push origin main
```

### Catastrofická regrese (user live session rozbitá)
```bash
# From TTY
git checkout pre-kolo6-main-2026-04-16
~/git/github/somewm/plans/scripts/install-scenefx.sh
# reboot
```

---

## 6. Kolo 7 — detaily

Samostatná branch po Kolo 6 merge. **Upstream má 10 post-refactor commitů** nad `493fda4` (last refactor). Kompletní enumerace:

| # | Upstream | Popis | Náš fork | Status | Workflow |
|---|---|---|---|---|---|
| 1 | `fb74146` | docs: revert bug report template | — | SKIP | docs, skip |
| 2 | `e5d7dfe` | benchmark infrastructure | `12fb825` | DUPE (upstream merged our PR) | `git cherry-pick --skip` (empty) |
| 3 | `746d59d` | make profile targets | `87cdd69` | DUPE (upstream merged our PR) | `git cherry-pick --skip` (empty) |
| 4 | `8a64a43` | docs: issue templates YAML | — | SKIP | docs, skip |
| 5 | `9e05267` | fix(xdg): set_bounds hint | `9012e25` | DUPE (same fix, different place) | `git cherry-pick --skip` (empty po Group D port) |
| 6 | `d354433` | fix: pair send_leave | `a411860` | DUPE (same fix, different place) | `git cherry-pick --skip` (empty po Group D port) |
| 7 | `64fe6a7` | Simplify `unmaplayersurfacenotify()` | — | **NEW** | port to `protocols.c` |
| 8 | `cb6c2c1` | stop key repeat | `7d0ede8` | DUPE (same fix, different place) | `git cherry-pick --skip` (empty po Group E port) |
| 9 | `c510efa` | `exit` signal boolean param | — | **NEW** | port to `luaa.c` + `somewm.c` |
| 10 | `44f842b` | Trailing whitespace | — | **NEW** | port to `spawn.c` |

**Net Kolo 7 = 3 new commits + 5 dupe skip + 2 docs skip.**

### Poznámky o duplicitách

Mnoho upstream post-refactor bugfixů už jsme sami portovali manuálně (během Kolo 5) protože řešily problémy co se nám reálně projevily, a my jsme je zapsali do monolitického `somewm.c`. Po Kolo 6 refactoru se naše kód dostane do správných modulů (`window.c`, `protocols.c`, `input.c`) = totožné s upstream. Cherry-pick duplicitních commitů → empty commit → skip.

**`cb6c2c1` (SKIP):** Ověřeno `git patch-id` — `cb6c2c1` i náš `7d0ede8` pochází ze stejného upstream commit `787bd80`.

**`9e05267` (SKIP):** Obsah identický s naším `9012e25` — oba používají `wlr_xdg_toplevel_set_bounds()` + `set_size(0,0)` místo workarea set_size.

**`d354433` (SKIP):** Obsah identický s naším `a411860` — 3-line `wlr_surface_send_leave()` v unmaplayersurfacenotify.

**`e5d7dfe` + `746d59d` (SKIP):** Upstream přijal naše dva bench PRs. Obsah i SHA history by měly být identické.

### `c510efa` forward-compat check

Lua callbacks bez explicitního argumentu fungují (extra arg ignored). Ověřeno: `grep -n "exit" plans/project/somewm-one/rc.lua` = jen `fishlive.exit_screen` submodule, žádný `awesome.connect_signal("exit", ...)`. Bezpečné.

### Workflow

```bash
git checkout -b chore/upstream-sync-kolo7 main  # after Kolo 6 merged

# Skip docs (fb74146, 8a64a43) — nothing to do
# Cherry-pick all 8 non-docs in upstream order; expect 5 empty skips + 3 real
for sha in e5d7dfe 746d59d 9e05267 d354433 64fe6a7 cb6c2c1 c510efa 44f842b; do
    git cherry-pick $sha || git cherry-pick --skip  # --skip for empty/dupe
done

make build-test && make test-unit
```

**Alternative (cleaner):** skip dupes explicitně:

```bash
git cherry-pick 64fe6a7
git cherry-pick c510efa
git cherry-pick 44f842b
# dupes + docs not cherry-picked at all
```

Pak v commit message: "Kolo 7: 3 new upstream commits (5 duplicates already in fork)".

---

## 7. Acceptance criteria ← **ROZŠÍŘENO v3**

Kolo 6 branch → main merge možný když VŠECHNA níže uvedená kritéria pass. Každý bod je hard gate.

### 7.1 Inventory + API compat

- [ ] Phase 1 full-tree inventory dokončena, každý z 287 commitů klasifikován (port/skip/done)
- [ ] Phase 1 catalog pokrývá explicitně: `lua/`, `objects/`, `tests/`, `common/`, `subprojects/`, `meson.build`, `spawn.c`, `systray.c`, `stack.c/h`, `somewm_types.h`, `x11_compat.h`, `shadow.c/h`, `bench.c/h` (žádná šedá zóna)
- [ ] Phase 1b API compat preflight vyřešen pro VŠECHNY privatizované symboly:
  - [ ] `some_update_pointer_constraint` — všechny call sites v `somewm_api.c` + ostatních místech řešeny
  - [ ] `cursor_mode`, `gesture_swipe_consumed`, `gesture_pinch_consumed`, `gesture_hold_consumed` — pokud fork tree používá, dokumentované řešení
  - [ ] `in_updatemons`, `updatemons_pending` — call site check
  - [ ] `nm build/somewm | grep -E "(some_update_pointer_constraint|cursor_mode|gesture_.*_consumed|in_updatemons|updatemons_pending)"` — extern/static consistency match předpokladům

### 7.2 Build matrix

- [ ] Phase 4 build matrix: 3/3 variants clean (default ASAN, ASAN+SceneFX, ASAN+SceneFX+BENCH)
- [ ] `nm` post-build: žádné undefined symbols
- [ ] `nm build/somewm | grep -c bench_` = 0 (bench není leaking do default buildu)
- [ ] `nm build-bench/somewm | grep -c bench_` > 0 (bench se kompiluje pod flagem)

### 7.3 Full-tree delta manifest ← **ROZŠÍŘENO v3**

Úzký whitelist (jen C/H) je nedostatečný. Plná kontrola proti Phase 1 inventory:

```bash
# Full delta manifest — MUST match Phase 1 catalog
git diff upstream/main..HEAD --name-only > /tmp/v3-delta-actual.txt
# Phase 1 produces /tmp/fork-delta-files.txt — restricted to kept categories
# (plans/ filtered out, but everything else present)
diff <(sort /tmp/v3-delta-actual.txt) <(sort /tmp/phase1-expected-delta.txt)
# Expected: empty (or only whitelisted differences documented in plans/kolo6-delta-diff.md)
```

- [ ] `/tmp/v3-delta-actual.txt` obsahuje všechny expected files z Phase 1 catalog:
  - [ ] **C/H refactored moduls:** `focus.c`, `window.c`, `input.c`, `monitor.c`, `protocols.c`, `xwayland.c`, `somewm.h`, `somewm.c`, `somewm_internal.h`
  - [ ] **Public API:** `somewm_api.c`, `somewm_api.h`, `somewm_types.h`
  - [ ] **Fork-only files:** `shadow.c`, `shadow.h`, `bench.c`, `bench.h`, `x11_compat.h`
  - [ ] **Helper modules:** `spawn.c`, `systray.c`, `stack.c`, `stack.h`
  - [ ] **Lua subsystem:** `lua/awful/**`, `lua/beautiful/**`, `lua/naughty/**`, `lua/gears/**`, `lua/wibox/**` — všechny fork patches present
  - [ ] **Objects:** `objects/client.c`, `objects/tag.c`, `objects/screen.c`, `objects/layer_surface.c`, `objects/*`
  - [ ] **Build:** `meson.build`, `meson.options`
  - [ ] **Tests:** `tests/**` fork-specific additions
  - [ ] **Common:** `common/**` changes
  - [ ] **Subprojects:** `subprojects/*.wrap` pinning preserved
- [ ] Žádný fork file neabsentuje. Žádný neočekávaný soubor navíc.

### 7.4 Unit + integration tests

- [ ] `make test-unit` → 100% pass (žádný regression)
- [ ] `make test-integration` → 100% pass (pokud implementováno fork-side)
- [ ] Phase 5 sandbox: 10/10 sub-testů pass (5.1-5.10)

### 7.5 Hard gates for high-risk scenarios ← **NOVÉ v3**

Rizika identifikovaná v matrixu (Section 4), která předtím neměla pass/fail gate:

**GPU reset callback (NVIDIA crash risk):**
- [ ] `grep -n "gpureset\|wlr_renderer_lost" focus.c window.c input.c monitor.c protocols.c xwayland.c somewm.c somewm.h` — listener attached někde (ne vypadlý během refactoru)
- [ ] `grep -n "wl_signal_add.*gpureset\|gpureset.*wl_signal_add" somewm.c monitor.c` — signal subscription present
- [ ] Comment or commit message justifying location (either Group A infra or Group F NVIDIA workarounds)

**XWayland associate/dissociate race:**
- [ ] Phase 5.1 test rozšířen o slow-startup variant:
  ```bash
  # Spawn heavy client that goes through associate → dissociate → associate
  DISPLAY=$xw_display timeout 5 bash -c 'for i in 1 2 3; do xterm -e "sleep 1" & done'
  sleep 6
  # Verify no crashes and client count sane
  SOMEWM_SOCKET=... somewm-client eval 'return #client.get()'
  grep -E 'associate.*dissociate|SEGV|ASAN' /tmp/sw-nested.log
  ```
- [ ] Žádný SEGV / ASAN z associate/dissociate rychlé sekvence

**Pointer constraint reentrancy (post-split):**
- [ ] Po refactoru kontrola že `cursorconstrain()` volá pouze jedno místo per event (ne double-call mezi `commitnotify` v `window.c` a `focusclient` v `focus.c`):
  ```bash
  grep -rn "cursorconstrain\|some_update_pointer_constraint" focus.c window.c input.c monitor.c
  # Expected: každé volání má jasný kontext, žádný duplicate per-frame call
  ```
- [ ] Test reentrancy: focus změnou + concurrent commitnotify:
  ```bash
  # Multi-client rapid focus switching while clients commit
  for i in 1 2 3 4 5; do WAYLAND_DISPLAY=wayland-1 alacritty -e "yes > /dev/null" & done
  sleep 3
  for i in 1 2 3 4 5; do SOMEWM_SOCKET=... somewm-client eval 'awful.client.focus.byidx(1)'; sleep 0.1; done
  grep -E 'pointer constraint|SEGV|ASAN|double free' /tmp/sw-nested.log
  ```
- [ ] Žádný error v logu; pointer constraint state coherent (client může setup + teardown cleanly)

### 7.6 Runtime + user acceptance

- [ ] User live test pass (NVIDIA DRM session, Steam/Minecraft focus, SceneFX effects visible, multi-monitor pokud available)
- [ ] Zero ASAN errors on shutdown (Phase 5.10)
- [ ] Zero regressions reported po 24h běhu na reálném HW

### 7.7 Kolo 7

Kolo 7 branch → main:
- [ ] 3 cherry-picks clean
- [ ] Smoke test pass (ping + reload + quit)
- [ ] `grep -n "connect_signal.*exit" plans/project/somewm-one/rc.lua` = prázdno (c510efa safety check)

---

## 8. Open questions — RESOLVED (per review)

1. **Varianta A vs C?** → **C**, s rozšířením audit na celý fork tree (ne jen `somewm.c`).
2. **Phase 3 group order?** → Infrastruktura → Lua+objects → hot-reload → low-risk → input/idle → NVIDIA → SceneFX → bench. NVIDIA uprostřed (ne první).
3. **Single vs multi-branch?** → **Dvě samostatné branches**: `chore/upstream-sync-kolo6` a `chore/upstream-sync-kolo7`. Blast radius isolation (Codex).
4. **`c510efa` exit signal breaking?** → Ne. Lua forward-compat (extra arg ignored). Ověřeno: rc.lua bez `connect_signal("exit")`. Bezpečné.
5. **Backup strategy?** → Annotated tag `pre-kolo6-main-2026-04-16` + branch `backup/pre-kolo6-main`. Tarball over-engineering.

---

## 9. Timeline (revised)

| Phase | Čas |
|---|---|
| 0 Prep | 1h |
| 1 Full fork delta inventory | 3-4h |
| 1b API compat preflight | 1-2h |
| 2 Setup base | 0.5h |
| 3 Port fork delta (Groups A-H) | 10-12h |
| 4 Build matrix (3 variants) | 1.5h |
| 5 Sandbox tests (10 sub-tests) | 3-4h |
| 6 Merge Kolo 6 | 0.5h |
| 7 Kolo 7 branch | 1h |
| **Total** | **22-27h** |

Rozdělit na 3-4 session po 5-7 hodinách (ne jedno maraton).

---

## 10. Artefakty (create during implementation)

- `plans/kolo6-fork-delta-inventory.md` (Phase 1)
- `plans/kolo6-api-compat.md` (Phase 1b)
- `plans/kolo6-group-mapping.md` (Phase 1, commit → group → target file)
- `/tmp/sw-nested.log`, `/tmp/sw-bench.log`, `/tmp/sw-nested-multi.log` (Phase 5)

---

## 11. Review changelog

### v1 → v2 (Codex round 1 + Sonnet round 1)

**Codex (gpt-5.4) findings applied:**
- [C1] Phase 1 kompletně přepsána na **full fork delta inventory** (ne jen `somewm.c`)
- [C2] Phase 3 grouping **přehozeno**: infrastruktura/lifecycle první, NVIDIA uprostřed, bench nakonec
- [C3] Phase 4 rozšířena na **3 build varianty** (+ build-without-SceneFX, + SOMEWM_BENCH)
- [C4] Phase 5.1 XWayland test **opraven**: `DISPLAY=$xw xterm`, ne `WAYLAND_DISPLAY alacritty`
- [C5] Risk matrix doplněna: `fork-only code dropped` (CRITICAL), `static→extern UB` (upgrade na HIGH), `bench compiled out`, `wrong client backend`, `build-without-SceneFX`
- [C6] Kolo 6 / Kolo 7 **rozděleno** na dvě samostatné branches
- [C7] Backup strategy: annotated tag místo jen branch

**Sonnet findings applied:**
- [S1] Přidán chybějící commit **`292159b`** (sloppy focus / #135) do Group F
- [S2] **Phase 1b** new — API compat preflight pro `some_update_pointer_constraint` + privatizované symboly
- [S3] Risk matrix: `pointer constraint reentrancy`, `GPU reset callback`, `XWayland associate race`
- [S4] Phase 5 testy rozšířené: **5.4 session lock, 5.5 multi-monitor hotplug, 5.7 DnD, 5.8 idle inhibit, 5.10 ASAN clean shutdown**
- [S5] `0955251` (client icons) upřesněno — **Lua + x11_compat**, ne `somewm.c` (patří do Group B, ne F)
- [S6] Open question `c510efa`: ověřeno grepem — naše rc.lua bez exit handler, bezpečné

### v2 → v3 (Codex round 2)

Codex verdict na v2: *„yellow/red stop-gate — plán je výrazně lepší, ale pár nových nejasností"*. Tři stop-signály zpracovány:

- [C8] **Section 7 acceptance whitelist byl příliš úzký** — kontroloval jen vybrané C/H soubory. v3 přepsáno na **full-tree delta manifest** proti Phase 1 inventory, explicitně ověřené kategorie: C/H refactored, fork-only files, Lua subsystem, objects/, build, tests, common, subprojects.
- [C9] **Phase 5.5 multi-monitor hotplug byl neoperacionalizovaný** — `swaymsg create_output` není validní pod nested somewm, `WLR_WL_OUTPUTS=2` testuje jen startup. v3 rozdělen na **5.5a** (startup + Lua API via `WLR_WL_OUTPUTS=2`) + **5.5b** (hotplug simulation via `screen[2]:fake_remove()` — invokuje `closemon()` path). Real-world DRM hotplug deferred do Phase 7 user test.
- [C10] **Tři rizika v matrixu neměla hard pass/fail gate** — GPU reset callback, XWayland associate/dissociate race, pointer constraint reentrancy. v3 přidána Section 7.5 „Hard gates for high-risk scenarios" s konkrétními grep + test příkazy pro každé.

### v3 → v3.1 (Codex round 3, green-light fix)

Codex verdict na v3: *„YELLOW, do not proceed yet — jeden blocker"*. Section 5.5b overclaimed coverage — `screen:fake_remove()` ve skutečnosti netriguje `closemon()` C-level path, jen `screen_removed()` Lua signal. Evidence v `objects/screen.c:1636-1651`. Tests/test-xdg-hotplug-crash.lua už dokumentuje distinction.

- [C11] **Section 5.5 přepsána na 4-level coverage**: 5.5a (startup + Lua API, nested), 5.5b (Lua-level screen removal, nested — correctly labeled), **5.5c (C-level closemon via `wlr-randr --off/--on` ve skutečné live session — hard gate před merge)**, 5.5d (DRM physical hotplug deferred do Phase 7 user test). Využívá existujícího `tests/smoke-hotplug.sh`.

**Codex final:** „After that text/gate correction: GREEN, proceed."
