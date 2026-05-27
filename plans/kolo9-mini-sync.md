# Kolo 9 — Mini upstream sync (2026-05-27)

Date opened: 2026-05-27
Status: PLAN v2 — Codex YELLOW findings addressed (Sonnet GREEN). Awaiting user approval before execution.

v1 → v2: enumerated all CLAUDE.md sections touched by `aaf7fb5`; expanded
Makefile verification (clean / asan / build-test / test-asan); acknowledged
busted blocked for `permissions_spec.lua` (followup #2); added
`make test-orchestrator` gate; documented Nix verification as unavailable
on this host; switched merge mechanic from kolo8's strategy A to a normal
`--no-ff` merge (sync branch is `main` + cherry-picks, same base, no
divergent-tree risk); softened `a5be13f` wording from "identical" to
"behaviorally duplicate" (Jimmy's cherry-pick added a one-line comment edit).

## Context

Upstream `trip-zip/somewm` has 6 new commits since the kolo8 merge
(`0583e82`, 2026-05-14). The gap is small enough for a proportional
"mini-sync" rather than a full kolo-style sync, but the **process stays the
same**: branch, inventory, audit, plan with Codex + Sonnet review,
feature-by-feature execution, sandbox runtime checks per phase, user live
DRM test gate before merge.

The 6 upstream commits, and their fork-interaction surface (since our
kolo8 merge `0583e82`):

| commit | title | files | our changes to those files since 0583e82 |
|---|---|---|---|
| `747ab98` | fix(hotplug): bail out of createmon when output commit fails | `monitor.c` | none |
| `1eefa3b` | feat: client icon 256x256 sizes & drop scalable | `lua/menubar/utils.lua` | none |
| `df51e45` | build: handle GLib 2.88 lgi enum-class break | `lgi-check.c`, `lgi-glib-2.88-enum.patch` (new), `meson.build`, `package.nix` | none |
| `aaf7fb5` | build: make default build optimized release, no sanitizers | `Makefile`, `test_orchestrator.c` | none |
| `a5be13f` | fix(permissions): restore transient_for.screen nil-guard | `lua/awful/permissions/init.lua` | `89f09eb` (our own version) |
| `6c9b83b` | test(permissions): cover request::tag nil transient_for.screen fallback | `spec/awful/permissions_spec.lua` (new) | none |

Net interaction surface: only `permissions/init.lua` overlaps, and it
overlaps with our own fix that Jimmy cherry-picked, so the upstream variant
is essentially our commit.

## Per-commit verdict

### 747ab98 — hotplug createmon bail — CHERRY-PICK
- Adds `wlr_output_commit_state` failure path in `createmon` (frees `Monitor`,
  removes listeners, returns) and a NULL-guard in `outputmgrapplyortest`.
- Our `monitor.c:259` still has the unguarded `wlr_output_commit_state`
  call; we have not touched `monitor.c` since the kolo8 merge.
- Directly relevant to multi-monitor stability — the user runs Dell + HP
  portrait + Samsung TV (see `project_monitor_hp_portrait`,
  `project_multimonitor_samsung`). Worth taking.

### 1eefa3b — client icon 256x256 — CHERRY-PICK
- Comments out `'scalable'` (no SVG Pixbuf loader in somewm) and adds
  `'256x256'` to the menubar icon size list.
- Untouched file; clean apply.

### df51e45 — GLib 2.88 lgi enum-class break — CHERRY-PICK
- Forward-compat for GLib 2.88: splits `lgi-check.c` into a 2-phase probe
  (is lgi installed vs is it usable), adds upstream-recommended
  `lgi-glib-2.88-enum.patch` and wires it via `meson.build`/`package.nix`.
- Untouched files. `meson.build` interaction with our scenefx setup needs
  a quick look during execution to confirm no overlap.

### aaf7fb5 — default build release + test_orchestrator truncation — CHERRY-PICK, with CLAUDE.md update
- Makefile change: `make` default is now optimized release (`build/`),
  `make asan` is a separate target into `build-asan/`, `make clean` removes
  all three. `test-asan` consumes `build-asan/`.
- This conflicts with our CLAUDE.md, which describes `make` as ASAN. Three
  sections of `CLAUDE.md` must be updated to match the new layout:
  - Build commands section (`make` line, `make asan` line, `make clean`
    line, `make test-asan` line)
  - `~line 123` — "plain `make install` uses the ASAN dev build" — must be
    rewritten (plain `make install` now uses the release `build/`)
  - `~line 302` (ASAN section) — "Default `make` build includes ASAN." —
    update to "`make asan` builds ASAN into `build-asan/`."
- Less divergence from upstream is worth this doc update. `install-scenefx.sh`
  is unaffected — it builds into `build-fx/`, which the Makefile does not
  touch.
- The `test_orchestrator.c` change is a small truncation-safety improvement
  (value snprintf when length exceeds capacity); harmless.

### a5be13f — permissions nil-guard — SKIP (already ours)
- Behaviorally duplicate of our `89f09eb`. Jimmy's cherry-pick has a
  one-line comment edit (punctuation only — "— index — indexing" → "—
  index. Indexing"); patch-id differs slightly but the code is the same.
- Skipping keeps our authored commit canonical in our history.

### 6c9b83b — permissions test — CHERRY-PICK
- New file `spec/awful/permissions_spec.lua` (56 lines). Pure addition,
  no conflict.

## Execution plan

Branch `sync/kolo9-2026-05-27` **from `main`** (the upstream gap is small;
cherry-picking 5 upstream commits onto `main` is far cleaner than rebuilding
all 190 fork commits onto upstream HEAD).

1. `git checkout -b sync/kolo9-2026-05-27 main`
2. Cherry-pick in this order (low-risk first, build-touching last):
   1. `6c9b83b` (new file, zero risk)
   2. `1eefa3b` (single-line Lua tweak)
   3. `747ab98` (hotplug, our highest-value commit)
   4. `df51e45` (build + lgi-check + new patch file)
   5. `aaf7fb5` (Makefile + test_orchestrator), then update `CLAUDE.md`
      Makefile section to reflect new layout
3. After each cherry-pick:
   - Lua-touching: `luajit -bl <file> /dev/null` syntax check.
   - C-touching (`747ab98`, `df51e45`, `aaf7fb5`):
     `meson setup --reconfigure build-fx -Dscenefx=enabled` (after
     `df51e45` and `aaf7fb5`, to catch meson.build interaction), then
     `ninja -C build-fx` and `ninja -C build-test`.
   - After `aaf7fb5` specifically — Codex flagged that ninja alone does
     NOT validate the renamed Makefile targets. Run the full Makefile
     dance: `make clean && make && make asan && make build-test &&
     make test-asan` (each should succeed and produce the right tree).
     Also `make test-orchestrator` (the changed `test_orchestrator.c`
     deserves its own gate; the target exists at `Makefile:62`).
4. Sandbox runtime check after each C-touching commit:
   `plans/scripts/somewm-sandbox.sh`, IPC ping, spawn a client, exercise
   the path under change where reasonable (hotplug-failure paths from
   `747ab98` are hard to repro in the headless sandbox — the live DRM
   test is the meaningful gate there, see open items). Per
   `feedback_sandbox_runtime_testing`: one compositor at a time, RSS cap,
   immediate cleanup.
5. Run the 4 `test-hot-reload-*` and `test-event-queue-*` integration
   tests against the sync branch's `build-test/somewm` after the C
   commits, to confirm no regression in the kolo8 baseline (130/136).
6. Busted unit specs: the new `spec/awful/permissions_spec.lua` lands but
   CANNOT be exercised by us — busted/luarocks env is broken (see
   `plans/post-kolo8-followups.md` item #2). The spec file is taken as
   pure addition; it will be validated once the rocks env is rebuilt.
7. Nix verification: `package.nix` is touched by `df51e45`. `nix` is not
   available on this host, so `nix build` / `nix flake check` are NOT
   exercised. Documented as untested; upstream itself maintains the Nix
   path so the risk of a broken-on-Nix-only fork is low.
8. Codex review of each cherry-picked diff against `main`, and one final
   pass on the full kolo9 diff. Sonnet review of the same.
9. Hand off to the user for the live DRM test. **No merge to `main` until
   the user's live test passes.** This is also the only meaningful gate
   for `747ab98`'s hotplug-failure path.
10. Merge mechanic: a normal `git merge --no-ff sync/kolo9-2026-05-27`
    into `main` (Codex flagged that kolo8's strategy A — `merge -s ours`
    + `read-tree --reset` — would silently flatten any newer `main`
    movement between branch creation and merge; for kolo9 the sync branch
    is `main` + 5 cherry-picks, same base, so a normal merge is both
    simpler and safer). Then `git push origin main` (no force).

## Open items / things to verify during execution

- `meson.build` overlap between `df51e45` and our scenefx setup.
- Hotplug repro: with the sandbox we can simulate output failure by adding
  a fake headless output and forcing commit failure; if too fiddly, the
  live DRM test catches it on real hardware.
- After Makefile change: confirm `~/git/github/somewm/plans/scripts/install-scenefx.sh`
  still works unchanged (it uses `build-fx/`, separate from
  `build`/`build-asan`).
- CLAUDE.md edit: just the Build commands section.
