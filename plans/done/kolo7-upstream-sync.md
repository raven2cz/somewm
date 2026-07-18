# Kolo 7 — final upstream sync plan (v1, DRAFT)

**Branch:** `chore/upstream-sync-kolo7` (nad `chore/upstream-sync-kolo6`)
**Base:** `chore/upstream-sync-kolo6` HEAD @ `0567e56`
**Goal:** Full sync s `upstream/main` — 8 commitů (3 původně plánovaných + 5 nových z 2026-04-16). Po merge: `git log upstream/main..main` = prázdné.

**Status:** v2 po Codex review 2026-04-17. GREEN-LIGHT, proceed to implementation.

**Review history:**
- v1 draft 2026-04-17 — initial scope + conflict analysis
- v2 2026-04-17 — Codex (gpt-5.4) review applied: 1 HIGH (UAF !globalconf_L path gap), 3 MEDIUM (UAF test surface, sync verification command, titlebar update post-destroy), 3 LOW addressed.

**Related docs:**
- `plans/kolo6-7-final-sync.md` — původní plán, sekce 0 „Status update 2026-04-17" popisuje kolo6 completion + kolo7 scope
- `plans/kolo6-api-compat.md`, `plans/kolo6-fork-delta-inventory.md` — Phase 1/1b artefakty (relevantní pro konzistenci)

---

## 1. Executive summary

Kolo 6 (refactor split) úspěšně implementován a pushnutý (`chore/upstream-sync-kolo6` na origin), čeká na user live test (2026-04-17). Během kola 6 přistálo na upstream 5 dalších commitů, které jsme zařadili do Kola 7 — scope rozšířen z 3 na 8 commitů.

**Branch strategy:** `chore/upstream-sync-kolo7` založený nad aktuální `chore/upstream-sync-kolo6` HEAD. Po user live testu Kola 6 zmerguje se kolo6 do main, pak FF-merge kolo7 (nebo rebase kolo7 na main pokud kolo6 dostane merge commit).

**Cherry-pick order:** chronologické (upstream commit date) — zachovává logické provázání bugfixů.

## 2. Scope — 8 commitů

### 2.1 NEW — originálně plánované Kolo 7 (3)

| SHA | Datum | Popis | Target files | Risk |
|---|---|---|---|---|
| `64fe6a7` | 2026-04-13 | protocols: Simplify unmaplayersurfacenotify() | `protocols.c` | **MEDIUM** — conflict expected s fork lua_object cleanup branch |
| `c510efa` | 2026-04-15 | send exit signal parameter | `luaa.c`, `somewm.c` | LOW — forward-compat check done (rc.lua bez exit handleru) |
| `44f842b` | 2026-04-16 | Kill trailing whitespace | `spawn.c` | TRIVIAL |

### 2.2 NEW — post-v3.1 (5, 2026-04-16)

| SHA | Popis | Target files | Risk |
|---|---|---|---|
| `df53154` | client: Guard client->scene access | `client.h` | LOW — 2-line null check |
| `9774101` | client: Remove obsolete client_is_rendered_on_mon() | `client.h` | LOW — dead code; naše tree má 0 call sites (jen v `plans/done/` doc) |
| `bad997d` | fix: UAF of wlr_scene_tree via wlr_surface->data | `client.h`, `monitor.c`, `window.c`, `window.h` | **HIGH** — konflikt v window.c mapnotify/unmapnotify (fork deltas) |
| `901e363` | fix: re-evaluate pointer focus after banning refresh | `somewm.c` | **MEDIUM** — somewm.c má bench stage records wrapping `banning_refresh()`, patch inserts between them |
| `d27fa2b` | fix: static inline for scene-tree surface helpers | `window.c`, `window.h` | LOW — follow-up na `bad997d` (style/linkage fix) |

### 2.3 SKIP — už v našem forku (5 duplikátů)

| Upstream | Náš fork | Evidence |
|---|---|---|
| `cb6c2c1` stop key repeat | `ce1a98c` | `git patch-id` shodný (oba z upstream `787bd80`) |
| `d354433` pair send_leave | `a411860` | Identický 3-line delta |
| `9e05267` xdg set_bounds | `9012e25` | Identická semantika |
| `e5d7dfe` benchmark infrastructure | `12fb825` | Upstream přijal náš PR |
| `746d59d` make profile targets | `87cdd69` | Upstream přijal náš PR |

### 2.4 SKIP — docs (2)

| Upstream | Důvod |
|---|---|
| `fb74146` revert bug report template | Docs only |
| `8a64a43` YAML issue templates | Docs only |

---

## 3. Pre-flight conflict analysis

### 3.1 `64fe6a7` — protocols.c unmaplayersurfacenotify

**Náš fork state:** `unmaplayersurfacenotify` má fork-specific `lua_object` cleanup (emit `request::unmanage`, unref). Upstream patch restrukturalizuje pouze horní část funkce (send_leave + arrangelayers).

**Expected conflict:** patch kontext skupinou podmínek před `lua_object` blokem — pravděpodobně resolvable ručně, možná automaticky.

**Strategy:** cherry-pick, pokud conflict → zachovat upstream strukturu nahoře + fork lua_object blok dole.

### 3.2 `c510efa` — exit signal parameter

**Náš fork state:** `cleanup()` v somewm.c používá `luaA_emit_signal_global("exit")`. Upstream mění na ruční `lua_pushboolean + luaA_signal_emit`. `luaa.c` mění `luaA_hot_reload` podobně.

**Expected conflict:** žádný — naše verze používá globální helper, upstream přímo. Cherry-pick pravděpodobně čistý.

**Forward-compat check (z kolo6 plánu, sekce 8.4):** `grep -n 'connect_signal.*exit' plans/project/somewm-one/rc.lua` = prázdno. Extra boolean arg Lua callbacks ignorují. Bezpečné pro standardní handlery; vararg handlery mohou nový boolean argument pozorovat (by design).

**Broader grep (Codex LOW):** kromě rc.lua zkontrolovat všechny potenciální konfigurační cesty:
```bash
grep -rn 'connect_signal.*exit\|signal_emit.*exit' lua/ plans/project/ ~/.config/somewm/ 2>/dev/null
```

### 3.3 `44f842b` — whitespace

**Strategy:** cherry-pick, pokud už trailing whitespace odstraněn → `--skip`.

### 3.4 `df53154` — client.h scene guard

**Náš fork state:** máme `client_is_rendered_on_mon` v client.h:284. Patch přidá null check.

**Expected:** clean cherry-pick (přidává bez modifikace okolí).

**Sequencing:** Musí být PŘED `9774101` (který funkci odstraňuje), jinak empty patch.

### 3.5 `9774101` — remove client_is_rendered_on_mon

**Usage check:** `git grep client_is_rendered_on_mon` v working tree = 0 call sites (jen definice + stará plan doc). Odstranění bezpečné.

**Strategy:** cherry-pick clean. Smaže 18 řádků v client.h.

**Ordering (Codex LOW):** aplikovat `df53154` PŘED `9774101` *should*, ne *must* — zachovává upstream patch sequence + code review traceability, ale reverse = empty `df53154`. OK tak jak je.

### 3.6 `bad997d` — UAF fix (CRITICAL)

**Náš fork state v window.c:**
- `mapnotify` má fork-specific scene_surface failure handler s explicit cleanup: `wlr_scene_node_destroy(&c->scene->node); c->scene = NULL; client_surface(c)->data = NULL;`
- `unmapnotify` má dvě cleanup sites (globalconf_L == NULL safety path + normal path), obě s fork-specific titlebar scene buffer clearing
- Fork má bench hooks ve stejných funkcích

**Upstream přidává:**
- `client_has_surface()` static inline
- `client_scene_node_destroy()` extern funkce (definice v window.c)
- `client_surface_get_scene_tree()` + `client_surface_clear_scene_data()` inline helpers (window.h)
- Refactor `client_surface()` (assert mimo #ifdef block)
- Nahrazuje ruční cleanup za `client_scene_node_destroy(c)` na 3 místech
- Změna v `monitor.c updatemons` lock surface path: `surface->data` → `client_surface_get_scene_tree(surface)`

**Expected conflicts:**
1. `client.h client_surface()` — assert restructuring, naše verze identická s upstream PRE-patch → clean
2. `window.c mapnotify` scene_surface failure cleanup — fork má 3-line manuální cleanup, patch nahrazuje za `client_scene_node_destroy(c); assert(client_surface(c)->data == NULL);` → **konflikt probable**
3. `window.c unmapnotify` 2× cleanup paths — obdobný konflikt
4. `window.c` globální scope — `extern inline` deklarace + `client_scene_node_destroy` definice: **kontext conflict** pokud fork přidal nic nového mezi listener deklarace a první funkci
5. `window.h` — pure additions, clean
6. `monitor.c` updatemons — fork má deltas (opacity re-apply), ale lock_surface blok může být netknutý → probably clean

**⚠️ HIGH finding (Codex v2):** Fork `!globalconf_L` early path (window.c:1696-1699) destroys scene BUT returns **bez** titlebar/border pointer clearing — na rozdíl od normal path (window.c:~1755-1760). Upstream `bad997d` nahrazuje tuto řádku za `client_scene_node_destroy(c); return;` — pořád bez fork clearing. Pokud tyto pointery referencovány během shutdown (byť unlikely, Lua je dole), může vzniknout UAF.

**Strategy:**
- Extrahovat fork titlebar/border clearing do `client_clear_scene_child_pointers(Client *c)` (static inline v window.h nebo static v window.c)
- Volat PO `client_scene_node_destroy(c)` ve VŠECH paths: normal unmap + `!globalconf_L` early exit
- Map failure path: skip (titlebary ještě neexistují)
- Cherry-pick, při conflictech:
  - V window.c: zachovat upstream `client_scene_node_destroy` call + přidat volání fork helperu
  - **Pouze pointer nulling, žádné update calls (refresh/re-render) po destroy** (Codex MEDIUM)
- Po resolve: grep že všechny naše manual `wlr_scene_node_destroy(&c->scene->node)` v window.c jsou nahrazeny nebo mají justification

### 3.7 `901e363` — pointer focus after banning

**Náš fork state v somewm.c `some_refresh`:** banning_refresh() je obklopený bench stage records (`BENCH_STAGE_CLIENT` → `banning_refresh()` → `BENCH_STAGE_BANNING`).

**Upstream patch:**
- `bool banning_pending = globalconf.need_lazy_banning;` PŘED `banning_refresh()`
- `if (banning_pending) motionnotify(0, NULL, 0, 0, 0, 0);` PO `banning_refresh()` ale PŘED dalším bench stage

**Expected conflict:** patch kontext zahrnuje `#ifdef SOMEWM_BENCH` bloky — naše verze má další bench stages (BENCH_STAGE_BANNING), upstream je nemá.

**Strategy:**
- Cherry-pick, při conflictu: insert `banning_pending` před banning_refresh(), insert `motionnotify` po banning_refresh() ale PŘED bench_stage_record(BENCH_STAGE_BANNING, ...) — tak aby motionnotify patřil do BANNING stage, ne STACK.
- Alternativně vytvořit novou BENCH_STAGE_POINTER_REEVAL? NE — over-engineering, vložit do BANNING stage.

**Interaction check s naším `a109dc4` (pointer-constraint on Lua focus):** Naše `some_set_seat_keyboard_focus` volá `some_update_pointer_constraint` → tam kde focus se mění skrz Lua, pointer constraint je updated. Upstream `901e363` řeší ORTHOGONÁLNÍ problém (banning tag switch, ne focus change). Žádná interference očekávána. **Validate v testech:** focus follow mouse + tag switch + chromium client.

### 3.8 `d27fa2b` — static inline helpers

**Náš fork state:** nemáme `client_surface_get_scene_tree` / `client_surface_clear_scene_data` helpers (přibudou v `bad997d`).

**Upstream patch:** mění `inline` → `static inline` v window.h, odstraňuje `extern inline` deklarace z window.c. Also Allman braces style pass v `client_scene_node_destroy`.

**Expected conflict:** cherry-pick v pořadí `bad997d` → `d27fa2b` by měl být čistý (bad997d přidává, d27fa2b upravuje).

**Strategy:** cherry-pick clean po `bad997d`.

---

## 4. Implementation plan

### Phase 0 — Preparation (15 min)

```bash
# Verify kolo6 state
git status  # clean working tree
git log --oneline -1  # 0567e56
git branch --show-current  # chore/upstream-sync-kolo6

# Fetch upstream
git fetch upstream

# Verify scope
git log --oneline HEAD..upstream/main  # expect 15 commits

# Create kolo7 branch
git checkout -b chore/upstream-sync-kolo7

# Safety tag
git tag -a pre-kolo7-2026-04-17 -m "Before Kolo 7 cherry-picks"
```

### Phase 1 — Cherry-pick in chronological order (1-2 h)

Order (upstream date ascending):

```bash
# 1. protocols simplification (2026-04-13)
git cherry-pick 64fe6a7
# Resolve conflicts if any (Section 3.1)
make build-test  # quick sanity

# 2. exit signal parameter (2026-04-15)
git cherry-pick c510efa
make build-test

# 3. UAF fix (2026-04-16, 20:17 UTC) — THE BIG ONE
git cherry-pick bad997d
# Resolve conflicts in window.c (Section 3.6)
# Verify grep: all manual wlr_scene_node_destroy(&c->scene->node) accounted for
grep -n "wlr_scene_node_destroy(&c->scene" window.c
make build-test

# 4. df53154 client scene guard (2026-04-16)
# NOTE: sequencing — df53154 PŘED 9774101 (jinak empty)
git cherry-pick df53154

# 5. 9774101 remove client_is_rendered_on_mon
git cherry-pick 9774101

# 6. 901e363 pointer focus after banning
git cherry-pick 901e363
# Resolve bench stage ordering (Section 3.7)
make build-test

# 7. d27fa2b static inline helpers
git cherry-pick d27fa2b
make build-test

# 8. 44f842b trailing whitespace
git cherry-pick 44f842b
```

**Per commit checklist:**
- [ ] Resolve conflicts s ohledem na fork-specific deltas
- [ ] `make build-test` clean compile
- [ ] Žádné unused variables / dead code warnings z cherry-picku
- [ ] `git log --stat` přehled changes = jen očekávané soubory

### Phase 2 — Build matrix (30 min)

```bash
# Variant 1: ASAN + SceneFX (primary)
~/git/github/somewm/plans/scripts/install-scenefx.sh
# Expected: clean install

# Variant 2: ASAN (no SceneFX)
make clean && make
# Expected: clean compile

# Variant 3: ASAN + SceneFX + BENCH
meson setup build-bench -Dscenefx=enabled -Dbench=enabled --wipe
ninja -C build-bench
# Expected: clean, bench symbols present

# Verify
nm build-bench/somewm | grep -c bench_  # > 0
nm build/somewm | grep -c bench_         # = 0
```

### Phase 3 — Sandbox smoke tests (1 h)

#### 3.1 Compositor lifecycle
```bash
pkill -f somewm-socket-test; rm -f /run/user/1000/somewm-socket-test
WLR_BACKENDS=wayland SOMEWM_SOCKET=/run/user/1000/somewm-socket-test \
  build-fx/somewm -d 2>/tmp/sw-kolo7.log &
sleep 3
SOMEWM_SOCKET=/run/user/1000/somewm-socket-test somewm-client ping
# Expected: pong
```

#### 3.2 UAF fix validation (`bad997d`) ← **EXPANDED v2 per Codex MEDIUM**

Upstream UAF byl identifikován v `some_is_idle_inhibited` (protocols.c:364) volající `wlr_scene_node_coords` přes `surface->data` patřící už destroyed scene tree. Test surface musí projít všechny cleanup paths:

**3.2a Rapid client spawn/kill + idle inhibit poll (primary UAF trigger)**
```bash
DISPLAY=$(SOMEWM_SOCKET=... somewm-client eval 'return os.getenv("DISPLAY")' | tail -1 | tr -d '"')
# Spawn idle inhibitor client, destroy it, immediately poll idle state
WAYLAND_DISPLAY=wayland-1 mpv --no-terminal --idle=yes /dev/null &
MPV_PID=$!
sleep 2
kill $MPV_PID
# Immediately poll — tests that some_is_idle_inhibited doesn't walk freed scene tree
SOMEWM_SOCKET=... somewm-client eval 'return awesome.idle_inhibited'
# Repeat to stress
for i in 1 2 3 4 5; do
  WAYLAND_DISPLAY=wayland-1 alacritty -e "sleep 0.$i" &
done
sleep 6
SOMEWM_SOCKET=... somewm-client eval 'return awesome.idle_inhibited'
grep -E 'ASAN|SEGV|use-after-free|heap-use-after-free' /tmp/sw-kolo7.log
# Expected: empty
```

**3.2b Map failure path**
Scene-surface creation failure (XWayland/Electron) triggers `client_scene_node_destroy` v mapnotify. Hard to force without Electron app; minimum: **code review** že `client_scene_node_destroy(c)` replaces manual `wlr_scene_node_destroy + NULL`.

**3.2c Shutdown `!globalconf_L` path**
Po quit, globalconf_L = NULL; unmap events před final teardown musí projít early path bez segfault:
```bash
# Launch clients + immediately quit
WAYLAND_DISPLAY=wayland-1 alacritty &
sleep 1
SOMEWM_SOCKET=... somewm-client eval 'awesome.quit()'
sleep 2
grep -E 'ASAN|SEGV' /tmp/sw-kolo7.log
# Expected: empty
```

**3.2d Session lock surface cleanup (monitor.c updatemons change)**
```bash
WAYLAND_DISPLAY=wayland-1 swaylock &
sleep 2
pkill swaylock
sleep 2
# wlr_randr simulate output change if possible; at minimum verify ping
SOMEWM_SOCKET=... somewm-client ping
```

#### 3.3 Pointer focus after banning (`901e363`)
```bash
# Spawn 2 clients, switch tags, verify pointer focus re-delivery
WAYLAND_DISPLAY=wayland-1 alacritty &  # tag 1
sleep 1
SOMEWM_SOCKET=... somewm-client eval 'awful.tag.viewonly(tags[2])'
sleep 1
WAYLAND_DISPLAY=wayland-1 alacritty &  # tag 2
sleep 1
SOMEWM_SOCKET=... somewm-client eval 'awful.tag.viewonly(tags[1])'
sleep 1
# Check: pointer focus should be on client under cursor, not limbo
SOMEWM_SOCKET=... somewm-client eval 'return mouse.object_under_pointer() and mouse.object_under_pointer().name or "none"'
# Expected: non-"none" if cursor hovers client; smoke-level check
```

#### 3.4 Exit signal parameter (`c510efa`)
```bash
# Hot reload test — emits exit(true)
SOMEWM_SOCKET=... somewm-client eval 'awesome.restart()'
sleep 3
SOMEWM_SOCKET=... somewm-client ping
# Expected: pong (reload survived exit signal with new param)

# Clean quit — emits exit(false)
SOMEWM_SOCKET=... somewm-client eval 'awesome.quit()'
sleep 2
grep -E 'ASAN|SEGV' /tmp/sw-kolo7.log
# Expected: empty
```

#### 3.5 Layer surface + protocols simplification (`64fe6a7`)
```bash
# Restart + spawn layer-shell client (waybar/swaybg), verify arrangelayers triggered
WLR_BACKENDS=wayland SOMEWM_SOCKET=... build-fx/somewm -d 2>/tmp/sw-kolo7.log &
sleep 3
WAYLAND_DISPLAY=wayland-1 swaybg -c '#000000' &
sleep 2
# unmap + remap
pkill swaybg
sleep 1
WAYLAND_DISPLAY=wayland-1 swaybg -c '#111111' &
sleep 2
grep -E 'LS-UNMAP|LS-MAP|SEGV|ASAN' /tmp/sw-kolo7.log
# Expected: LS events, no SEGV
```

#### Cleanup
```bash
pkill -f somewm-socket-test; rm -f /run/user/1000/somewm-socket-test
```

### Phase 4 — Codex review (30 min)

```bash
git log chore/upstream-sync-kolo6..HEAD --stat > /tmp/kolo7-diff.txt
git diff chore/upstream-sync-kolo6..HEAD >> /tmp/kolo7-diff.txt

cat /tmp/kolo7-diff.txt | codex exec -m gpt-5.4 --full-auto \
  "Review this Kolo 7 upstream sync — 8 cherry-picks onto fork tree. Flag:
  (1) any conflict resolution that dropped upstream intent or fork delta,
  (2) UAF fix (bad997d) — verify all wlr_scene_node_destroy(&c->scene->node) sites
      converted to client_scene_node_destroy(c) OR documented why kept,
  (3) pointer focus after banning (901e363) — placement inside bench stage correct?,
  (4) exit signal parameter (c510efa) — forward compat (rc.lua no exit handler)?.
  Report severity per finding."
```

### Phase 5 — User live test + merge (0.5 h)

**Prerequisite:** Kolo 6 live test pass + merge to main (separate workflow).

```bash
# After kolo6 merged to main (Codex LOW — use explicit --onto):
git checkout main
git pull origin main
git rebase --onto main chore/upstream-sync-kolo6 chore/upstream-sync-kolo7
# Alternative (cleaner if 8 commits small): recreate kolo7 from main + re-cherry-pick
git push origin chore/upstream-sync-kolo7 --force-with-lease  # only own branch

# User live test on NVIDIA (1-2 h):
#  - Steam games focus
#  - Multi-monitor Samsung TV hotplug (if available)
#  - Chromium tag switch (pointer focus validation)
#  - Idle inhibit (mpv fullscreen)

# Merge
git checkout main
git merge --ff-only chore/upstream-sync-kolo7
git push origin main
git tag -a kolo7-merged -m "Kolo 7: full upstream sync complete"
git push origin kolo7-merged

# Verify complete sync (Codex MEDIUM fix — cherry-pick equivalence)
git log --cherry-pick --right-only main...upstream/main
# Expected: empty (no upstream commit unported or with no patch equivalent in fork)
git cherry -v main upstream/main
# Expected: all lines start with '-' (= patch-equivalent present) or absent entirely
```

---

## 5. Risk matrix

| Risk | Pravděpodobnost | Dopad | Mitigace |
|---|---|---|---|
| `bad997d` conflict mis-resolution (missed cleanup site) | MEDIUM | HIGH (UAF regresion) | Phase 1 grep post-cherry-pick; Phase 3.2a idle-inhibit test |
| `bad997d` × fork titlebar scene buffer ordering | MEDIUM | HIGH (use-after-free) | Manual review Phase 1; `client_scene_node_destroy` MUST run BEFORE titlebar pointer reset |
| `bad997d` × fork `!globalconf_L` early exit gap (Codex HIGH) | HIGH | HIGH | Extract `client_clear_scene_child_pointers()` fork helper; call in ALL cleanup paths |
| UAF test surface incomplete (Codex MEDIUM) | MEDIUM | MEDIUM (false green) | Phase 3.2a-d explicit covers idle-inhibit, map failure, shutdown, lock surface |
| `901e363` bench stage record ordering | LOW | LOW (bench stats off) | Phase 2 Variant 3 compile + manual inspect |
| `901e363` × our `a109dc4` pointer-constraint interaction | LOW | MEDIUM | Phase 3.3 + user live Chromium test |
| `c510efa` Lua callback breakage (rc.lua) | LOW | MEDIUM | Pre-check grep done; forward-compat Lua ignores extra args |
| `64fe6a7` × fork lua_object cleanup | MEDIUM | MEDIUM | Phase 1 manual resolve; Phase 3.5 waybar smoke |
| Upstream commits during review delay | LOW | LOW | Re-fetch before Phase 5 merge |
| Kolo 6 live test fail → blocks Kolo 7 merge | MEDIUM | HIGH | Kolo 7 připraven ale nemergován — odblokování až po kolo6 zelené |

**Stop-gate:**
- Phase 2 build fail → rollback, diagnose, retry
- Phase 3 sandbox SEGV/ASAN → NOT merge; open bug before retry
- Phase 4 Codex HIGH finding → address before Phase 5

---

## 6. Rollback procedure

### Pre-merge (kolo7 branch only)
```bash
git checkout chore/upstream-sync-kolo6
git branch -D chore/upstream-sync-kolo7
# tag pre-kolo7-2026-04-17 remains
```

### Post-cherry-pick individual revert
```bash
# Inside kolo7 branch, drop one problematic pick
git rebase -i <before-sha>  # NO — interactive not allowed per session rules
# Instead: revert + re-cherry-pick clean
git revert <bad-sha>
```

### Catastrophic (already on main)
```bash
git revert -m 1 <kolo7-merge-commit>
git push origin main
```

---

## 7. Acceptance criteria

**Per-commit gates:**
- [ ] All 8 cherry-picks applied OR explicitly documented skip with justification
- [ ] Each resolve preserves: (a) upstream intent, (b) fork-specific deltas
- [ ] `git diff chore/upstream-sync-kolo6..HEAD --stat` matches expected file list (protocols.c, client.h, window.c, window.h, monitor.c, somewm.c, luaa.c, spawn.c)

**Build gates:**
- [ ] All 3 build variants clean (ASAN, ASAN+SceneFX, ASAN+SceneFX+BENCH)
- [ ] Zero compile warnings from cherry-picked code
- [ ] `nm` bench-symbol gating correct

**Runtime gates (sandbox):**
- [ ] Phase 3.1-3.5 all pass, zero ASAN/SEGV in `/tmp/sw-kolo7.log`
- [ ] Rapid client spawn/destroy (3.2) no UAF
- [ ] Tag switch pointer focus recovery (3.3)
- [ ] Hot reload + clean quit (3.4)

**Review gate:**
- [ ] Codex review clean OR all MEDIUM+ findings addressed

**Full sync verification:**
- [ ] `git log upstream/main..HEAD` = empty after final merge
- [ ] `git log HEAD..upstream/main` = empty
- [ ] Tag `kolo7-merged` on main

---

## 8. Timeline

| Phase | Čas |
|---|---|
| 0 Prep | 15 min |
| 1 Cherry-picks | 1-2 h |
| 2 Build matrix | 30 min |
| 3 Sandbox tests | 1 h |
| 4 Codex review | 30 min |
| 5 Merge (post live test) | 30 min |
| **Total** | **3.5-4.5 h** |

**Note:** Phase 5 blokovaná až do Kolo 6 merge. Ostatní phases lze udělat paralelně (kolo7 branch připravený, čeká jen na merge kolo6 + user live test kolo7 aspects).

---

## 9. Open questions

1. **Merge pořadí:** Kolo 6 → main → kolo7 rebase → kolo7 merge. Alternativně: stack kolo7 nad kolo6 a merge oba jako jednu operaci? → Doporučení: sekvenční (blast radius isolation).
2. **`901e363` bench stage placement:** uvnitř BANNING stage nebo nová stage POINTER_REEVAL? → DRAFT: uvnitř BANNING (konzervativně).
3. **Codex review: před nebo po sandboxu?** → Po sandboxu — sandbox prokáže runtime, codex validuje code-level.
