# Upstream Sync Plan — 2026-04-16

Selective adoption of upstream commits from `trip-zip/somewm` into our fork
`raven2cz/somewm`. Broken into rounds by risk/priority. Each round is a
separate branch, tested locally (build + unit + nested sandbox) and merged
to `main` only after verification.

**Starting state:** `main` is 89 commits behind `upstream/main` (2026-04-16).

## Scope and principles

- **One branch per round.** Never mix rounds. Each round is independently
  reviewable and revertable.
- **Build + test before merge to main.** `make` (ASAN) + nested sandbox
  smoke test + hot-reload where applicable.
- **Sandbox testing is mandatory.** Run nested compositor with
  `WLR_BACKENDS=wayland SOMEWM_SOCKET=/run/user/1000/somewm-socket-test`
  after each round. See "Test procedure" below.
- **No selective cherry-pick on the refactor split.** Kolo 6 is all-or-nothing.
- **No deprecation removal without a grep.** Kolo 4 requires verifying our
  `rc.lua` + plugins (layout-machi, etc.) do not call removed APIs.
- **Halt on regression.** If any round breaks something, stop the series and
  diagnose before continuing.

## Current state — hot-reload/lgi is COMPLETE

Earlier rounds (branches `fix/upstream-hotreload-cherrypick`,
`fix/reload-libffi-lgi-crash`, `fix/lgi-guard-autoload`) already brought in
the entire lgi/hot-reload series from upstream. Verified 2026-04-16:

| Upstream commit | Our commit | Status |
|---|---|---|
| `98a9525` in-process hot-reload | `a79042b` (merge) | OK |
| `3c519b5` systray cleanup | `8614a28` | OK |
| `b57433e` review cleanup | `533ec5d` | OK |
| `a85c538` sweep stale GLib sources | `7fe1a73` | OK |
| `71d39f3` revert mutex poison | `8253c96` | OK |
| `b43b26f` LD_PRELOAD closure guard | `a79042b` | OK |
| `1d19500` auto-load closure guard | `5185398` | OK |
| `c40eb9f` destroy titlebar scene buffers | `3efb424` | OK |
| `a07990b` destroy old drawin scene trees | `0ac2238` | OK |
| `5617c20` restore systray items | `dfead9e` | OK |
| `7be1148` bypass GDBus singleton | `d7c6a94` | OK |
| `a76a018` clear LD_PRELOAD | `05b7f21` | OK |
| `7a8e0cf` preserve tiled client order | `6bb31f1` | OK |
| `1e42b13` recreate output objects | `5d6c2d6` | OK |
| `b6b2e78` clean up log noise | `a2af764` | OK |
| `e00d011` search multiple paths | `a47a06c` | OK |

**Only one lgi/hot-reload commit is still missing:** `0deb9d2` (handled in Kolo 3).

**Our unique addition (not in upstream):** `e87926b` rewire stale Lgi closures.
Filed upstream as issue trip-zip/somewm#465.

---

## Kolo 1 — bezpečné bugfixy (LOW risk)

**Branch:** `chore/upstream-sync-bugfixes`
**Strategy:** `git cherry-pick` each commit, build + test after every 2–3.

| # | Commit | Summary | Files |
|---|---|---|---|
| 1 | `bdff787` | keyboardlayout: off-by-one in next_layout() wrap-around | `objects/keyboardlayout.c` |
| 2 | `4eff245` | null-ptr deref in `wlr_xdg_surface` | `somewm.c` |
| 3 | `f5e62fd` | use-after-free in `screen.name` setter | `objects/screen.c` |
| 4 | `1ec33c8` | SEGV in `screen.fake_add()` missing env metatable | `objects/screen.c` |
| 5 | `65f9643` | keygrabber: route key release events | `somewm.c` |
| 6 | `cb6c2c1` | stop key repeat when keygrabber starts mid-press | `somewm.c` |
| 7 | `183da9a` | `root._remove_key()` immediate keybinding removal | `objects/…` |
| 8 | `5eb31e1` | drawin: shadow + border refresh on resize | `objects/drawin.c` |
| 9 | `98c3207` | `ewmh_update_net_client_list_stacking()` in `stack_refresh()` | `somewm.c` |
| 10 | `9e05267` | xdg: restore set_bounds hint for initial configure | `somewm.c` |
| 11 | `411cb42` | use set_bounds instead of set_size for initial XDG | `somewm.c` |

**Progress tracking (check off as merged):**
- [x] 1 keyboardlayout off-by-one — `947b442`
- [x] 2 xdg null-ptr — `042401a`
- [x] 3 screen.name UAF — `104e944`
- [x] 4 screen.fake_add SEGV — `f4bcbbb`
- [x] 5 keygrabber release — `d39cb2a`
- [x] 6 stop key repeat — `7d0ede8` (manual port of cb6c2c1)
- [x] 7 root._remove_key — `0509133`
- [~] 8 drawin shadow refresh — SKIPPED (already in fork: border_need_update, luaA_drawin_set_shadow, wibar.lua "shadow" whitelist all present)
- [x] 9 ewmh stack refresh — `fb4d3ad`
- [~] 10 xdg set_bounds initial — SKIPPED (duplicate of item 11)
- [~] 11 set_bounds vs set_size — SKIPPED (already in fork as `9012e25`)

**Test plan per batch:**
1. After every 2–3 cherry-picks: `make` (ASAN build).
2. Unit tests: `make test-unit`.
3. Nested sandbox smoke test (see "Test procedure" below).
4. If any cherry-pick fails to apply cleanly, stop and resolve manually;
   document conflict in commit message.

**Merge criteria:** all 11 picks green, nested sandbox starts + ping works +
can hot-reload without crash + no ASAN errors on shutdown.

---

## Kolo 2 — AwesomeWM sync ports

**Branch:** `chore/upstream-sync-ports`
**Strategy:** cherry-pick batch, no testing between because they are library-level.

| # | Commit | Summary |
|---|---|---|
| 1 | `cc10e83` | port AwesomeWM #4060 — `luaA_class_add_properties` batch API |
| 2 | `5839e25` | port AwesomeWM #4066 — `lua_pushliteral` for string constants |
| 3 | `28a6e52` | port AwesomeWM #4017 — `override_label_bgs` in hotkeys_popup |
| 4 | `c0cbf22` | port AwesomeWM #4079 — group support for `append_client_keybindings` |
| 5 | `ae877ad` | docs: update `UPSTREAM_PORTS.md` |

**Progress:**
- [x] 1 #4060 properties batch — `6970d53` (conflicts resolved: layer_surface opacity, output added::connected)
- [x] 2 #4066 pushliteral — `3d6f8ea`
- [x] 3 #4017 override_label_bgs — `921e1b3`
- [x] 4 #4079 keybinding groups — `009ce50`
- [x] 5 UPSTREAM_PORTS.md — `00dc560`

**Test plan:**
1. `make` + `make test-unit`.
2. Nested sandbox: launch alacritty, verify hotkeys popup renders.
3. Verify `append_client_keybindings` in our rc.lua still works.

---

## Kolo 3 — medium-risk bugfixy

**Strategy:** každý commit v samostatné mini-branch s vlastním testem.
Commit `0deb9d2` = manuální port, ne cherry-pick (konflikt s naším `e87926b` rewire patchem).

### 3a. `chore/upstream-focus-before-unmanage` ✅ MERGED (317e05d)
- **Commit:** `e102096` fix(focus): clear seat keyboard focus before unmanage
- **Risk:** dotýká se našich NVIDIA focus workaroundů (issues #137, #135, #133)
- **Test:** nested sandbox — 2 alacritty launched, focused killed, compositor survived, focus transferred cleanly; 3× awesome.restart() clean; 9 unmap events, 0 assertions
- [x] Port (6 lines, clean merge into our unmapnotify)
- [x] Test
- [x] Merge

### 3b. `chore/upstream-layer-surface-enter-leave` ✅ MERGED (5194d75)
- **Commit:** `d354433` fix: pair `send_leave` with `send_enter` for layer surfaces
- **Port note:** MANUAL — upstream touches `protocols.c` which doesn't exist in our monolithic fork; same 3-line change applied to `unmaplayersurfacenotify` in `somewm.c`
- **Risk:** layer shell — wibox, exit screen, notifications
- **Test:** nested sandbox — 3× awesome.restart(), 9 LS-UNMAP events (3 hotedges × 3 reloads), no aborts/assertions
- [x] Port
- [x] Test
- [x] Merge

### 3c. `chore/upstream-drag-motion-with-helpers` ✅ MERGED (269ba64)
- **Commit:** `34ff92a` fix: Drag motion notification of drag source client #318
- **Prerequisites (pulled from 3e):** `4c765d5` (is_client_valid helper), `ca22c8e` (cursor-to-client coord transform)
- **Risk:** low — DnD is rarely used
- **Test:** nested sandbox — 3× awesome.restart(), lgi_guard gen1-3 clean (0 blocked), QS hotedges remap, 1 client preserved
- [x] Port (3 cherry-picks clean)
- [x] Test
- [x] Merge

### 3d. `chore/upstream-lgi-config-timeout` ✅ MERGED (e12ec44)
- **Commit:** `0deb9d2` fix(lgi): clean up stale GLib sources on config timeout
- **Port approach:** MANUAL (our `e87926b` rewire/begin_reload architecture differs from upstream bump_generation). Helper does ONLY the source sweep; caller gates the guard separately. Config-timeout path calls `lgi_guard_begin_reload()` + helper, skipping GDBus close.
- **Test (nested sandbox):**
  - Normal hot-reload: helper logs 'hot-reload: removed N stale GLib sources', baselines advance (56 → 799 → 1043 → 1287), no crashes across 3× reload
  - Deliberate config-timeout via infinite-loop rc.lua under `XDG_CONFIG_HOME`: SIGALRM fires, begin_reload runs (gen=1), 3 sources swept, fallback config loads, compositor responds to IPC
  - Naughty assertion in fallback is orthogonal preexisting issue (previously masked by SEGV)
- `test-floating-layout.lua` flaky-fix deferred (separate concern)
- [x] Port
- [x] Test hot-reload
- [x] Test config-timeout path
- [x] Merge

### 3e. `chore/upstream-small-refactors`
- **Commits:** ~~`4c765d5`~~ (already merged with 3c), ~~`ca22c8e`~~ (already merged with 3c), `ad87e23` (consolidate `focus_restore()`)
- **Risk:** refactors in hot code paths (focus restoration — 48 lines in `permissions/init.lua` + 60 in `somewm.c`)
- **Test:** full nested sandbox workflow, pointer movement across monitors, game focus rules
- [ ] Port `ad87e23`
- [ ] Test
- [ ] Merge

---

## Kolo 4 — deprecation sweep

**Precondition:** grep our rc.lua + plugins + themes for deprecated API uses BEFORE cherry-pick.

```bash
grep -rn "awful.util" plans/project/somewm-one/ ~/.config/somewm/ 2>/dev/null
grep -rn "awful.tag\.\(viewonly\|gettags\|delete\|move\)" plans/project/somewm-one/ 2>/dev/null
# etc. — one grep per removed function
```

**Candidate commits:**
- `d0d0a00` remove 12 deprecated Lua redirect shims
- `563d30a` delete `awful.util` module (498 lines)
- `2ded594` remove deprecated `awful.tag` and `awful.client` functions
- `bb72461` remove 9 deprecated `naughty.core` functions
- `765c84a` remove all remaining Lua deprecation calls
- `635c2c9` remove legacy Lua subsystem and C dead code
- `fd070d0` remove stale declaration and duplicate forward decl

**Decision gate:** if ANY removed API is used in our config, either skip that
commit OR update our config first and add config change as separate commit
before taking upstream removal.

- [ ] Grep audit completed
- [ ] rc.lua updates (if needed)
- [ ] Cherry-picks
- [ ] Test

---

## Kolo 5 — features (podle potřeby)

Low priority — přijmout až když feature chceme. Každý feature balík = samostatná branch.

| Feature | Commits | Branch |
|---|---|---|
| idle inhibit Lua API | `4b5c927`, `9ac6a75`, `a640e73`, `086c4fe` | `feat/upstream-idle-inhibit` |
| client icons from desktop-entry | `83766e4` | `feat/upstream-client-icons` |
| per-device input rules | `b89e886`, `0975aa7` | `feat/upstream-input-rules` |
| retroactive output signal | `637f34e`, `0a48f61`, `a436844` | `feat/upstream-output-retroactive` |
| benchmark + profiling | `e5d7dfe`, `746d59d`, `0e7b1eb` | `feat/upstream-benchmarks` |

- [ ] Idle inhibit
- [ ] Client icons
- [ ] Input rules
- [ ] Output retroactive signal
- [ ] Benchmarks

---

## Kolo 6 — velký refactor split somewm.c (ODLOŽENO)

**Commits (12):** `21393a8`, `6cd1982`, `b860c1a`, `393d9b7`, `6d88ee6`,
`02528d3`, `18321a9`, `67adca3`, `e2fb60a`, `1524262`, `3562cdf`, `493fda4`.

**What it does:** extracts `focus.c`, `window.c`, `input.c`, `monitor.c`,
`protocols.c`, `xwayland.c` from `somewm.c`, adds `somewm.h` + `somewm_internal.h`,
privatizes module-local state, removes deprecated Lua subsystem and dead code.
`somewm.c` shrinks from 7372 lines to 912.

**Why deferred:** our fork has heavy modifications in `somewm.c` (focus workarounds,
NVIDIA fixes, client animations, SceneFX integration). Selective cherry-pick
would require manually placing each of our patches into the new file layout.
High risk of silent focus/render regressions.

**Options:**
1. Wait for upstream 2.0 release and do a strategic full merge.
2. Spend a dedicated multi-day session doing the split with close testing.

**Decision:** deferred until user initiates. Separate plan
`plans/refactor-somewm-split.md` will be created when we tackle it.

---

## Misc / skip

- `22b226d` prepare main for 2.0 development — version bump, skip (our release is separate).
- `9744f0c` change version command in bug report template — docs only, optional.
- `fb74146` revert bug report template — docs, skip.
- `8a64a43` YAML issue templates — skip (we don't use their templates).
- `3553c29` stylua fix — probably already have, verify then skip.
- `6196ccc` editorconfig #402 — optional, low priority.
- `abdaac8`, `cf34c6d` test harness fixes — take if tests become flaky.
- `bd19e1e` dead code cleanup — low priority.
- `850a126` DEVIATIONS.md update — docs, optional.
- `64fe6a7` simplify `unmaplayersurfacenotify()` — cleanup only.

---

## Test procedure (per round)

### Build
```bash
~/git/github/somewm/plans/scripts/install-scenefx.sh
```

### Unit tests
```bash
make test-unit
```

### Nested sandbox smoke test
```bash
# Launch nested compositor
WLR_BACKENDS=wayland \
SOMEWM_SOCKET=/run/user/1000/somewm-socket-test \
/home/box/git/github/somewm/build-fx/somewm -d 2>/tmp/somewm-nested-debug.log &
sleep 3

# Verify IPC works
SOMEWM_SOCKET=/run/user/1000/somewm-socket-test somewm-client ping

# Discover Wayland display
ls /run/user/1000/wayland-*
# Note: nested display is typically wayland-1 or higher

# Launch test client (set WAYLAND_DISPLAY, NOT SOMEWM_SOCKET — see CLAUDE.md)
WAYLAND_DISPLAY=wayland-1 alacritty &
sleep 2
SOMEWM_SOCKET=/run/user/1000/somewm-socket-test somewm-client eval 'return #client.get()'
# Expected: 1 or more

# Hot-reload test (critical for any commit touching hot-reload or lgi)
SOMEWM_SOCKET=/run/user/1000/somewm-socket-test somewm-client eval 'awesome.restart()'
sleep 3
SOMEWM_SOCKET=/run/user/1000/somewm-socket-test somewm-client ping
# Expected: pong — process survived reload

# Check for crashes in log
grep -E 'SEGV|ASAN|ERROR|assertion|aborted' /tmp/somewm-nested-debug.log
# Expected: no unexpected errors

# Cleanup
SOMEWM_SOCKET=/run/user/1000/somewm-socket-test somewm-client quit 2>/dev/null
pkill -f somewm-socket-test 2>/dev/null
```

### Live session test (for focus/pointer/animation changes only)
After merge to main:
```bash
# Hot-swap running compositor
somewm-client exec somewm

# Deploy rc.lua if touched
plans/project/somewm-one/deploy.sh
somewm-client reload
```

---

## Rollback procedure

If a round introduces a regression after merge:
```bash
git checkout main
git revert -m 1 <merge-commit>
git push origin main
```

Or for a single commit within a round branch before merge:
```bash
git revert <bad-commit>
# or
git reset --hard <last-good>
git push --force-with-lease origin <branch>  # only on our branch, never main
```

---

## Progress dashboard

| Kolo | Branch | Status |
|---|---|---|
| 1 | `chore/upstream-sync-bugfixes` | ✅ merged 2026-04-16 (8 commits, 3 skipped as duplicates) |
| 2 | `chore/upstream-sync-ports` | ✅ merged 2026-04-16 (5 commits, 2 conflicts resolved) |
| 3 | (per commit) | ⏳ not started |
| 4 | `chore/upstream-deprecation-sweep` | 🔒 gated on grep audit |
| 5 | (per feature) | ⏳ not started, on demand |
| 6 | (refactor) | 🛑 deferred |

Update this table as rounds complete. Move plan to `plans/done/` when all
non-deferred rounds are merged or explicitly skipped.
