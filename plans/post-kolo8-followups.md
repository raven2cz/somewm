# Post-kolo8 follow-ups

Date opened: 2026-05-14
Status: OPEN

The kolo8 upstream sync is complete, merged to `main`, live-tested, and all
regressions found were fixed (see `plans/done/kolo8-STATUS.md` for the closed
record). These three items were surfaced during kolo8 but are **not** kolo8
regressions — each is pre-existing and deferred to a future session.

---

## 1. Six pre-existing failing integration tests

The full 136-test integration suite was run during kolo8 Phase 6: **130 pass,
6 fail**. All six were verified pre-existing (run against pre-sync fork `main`
`5ccffad` and, where relevant, pristine `upstream/main` `48e19a0` — they fail
there too). **Zero sync regressions.**

Failing tests:
- `test-keyboard-focus-sync` — "Expected >= 2 focus signals, got 0" (fork-only test)
- `test-layer-shell-focus-escape` — timeout; Escape on layer surface doesn't close it
- `test-layer-shell-pointer-enter` — `wl_pointer.enter` not delivered to layer
  surface under a stationary cursor (fails on pristine upstream too — likely a
  headless-backend limitation, not a fork bug)
- `test-keyboardlayout-cycle` — timeout after "next_layout from group 0"
- `test-numlock-setting` — timeout after "Re-enabling NumLock"
- `test-xkb-multi-layout` — timeout after "set_layout_group persists"

**What a future session should do:** investigate each (3 are xkb/keyboard
tests that hang in headless — may be a test-env limitation rather than a real
bug; 2 are layer-shell; 1 is the fork-only focus-sync test). Run the disciplined
test harness pattern from kolo8 (isolated headless sandbox, one compositor per
test, RSS cap). See memory `project_kolo8_phase6_baseline` for the full per-test
baseline.

## 2. busted unit specs blocked on broken luarocks env

The `spec/` busted unit tests cannot run: the system lua 5.3→5.5 update
fragmented the rocks — busted is only available for 5.4/5.5, penlight/lfs are
split across versions, lgi is 5.1-only. The compositor runs luajit (5.1) and
lgi is 5.1-only, so the consistent target is probably a luajit/5.1
`busted + penlight + lfs + lgi` stack.

Pre-existing, **not** a sync regression — but it does mean the kolo8
`tests/test-event-queue-*.lua` could only be exercised as integration tests,
not busted units.

**What a future session should do:** this needs the user to install a
consistent rocks stack first (environment fix, not a code change). Once busted
runs again, re-confirm the unit specs pass on `main`.

## 3. Hot-reload memory leak (~88 MB per reload)

`awesome.restart()` hot-reload leaks roughly 88 MB of host RSS per reload
(measured with the live somewm-one config: RSS 559 MB → 1031 MB over 5
reloads). **Confirmed NOT a sync regression** — pre-sync fork `main` leaks an
identical amount (+461 MiB vs +463 MiB over 5 reloads, side-by-side).

`lua_bytes` stays flat across reloads (the Lua heap GCs fine), so the growth is
**C-side anonymous / private-dirty memory**. This is partly by design — the
hot-reload path intentionally leaks the old Lua state (the whole
`lgi_closure_guard` machinery exists because of it; `cold_restart` /
`rebuild_restart` are the non-leaking alternatives). But ~88 MB/reload is large
enough to be worth a closer look.

**What a future session should do:** profile the C-side anonymous growth across
a hot-reload (`plans/scripts/somewm-memory-trend.sh --reload 5`, then attribute
the anonymous/private-dirty delta — drawable buffers, scene graph, wlroots
internals, glibc allocator retention). Decide whether any of it is a real leak
vs. expected hot-reload cost. Low priority — the workaround is to prefer
`cold_restart` for heavy reload loops.
