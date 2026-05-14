# Kolo 6 — API Compatibility Preflight (Phase 1b)

**Date:** 2026-04-16
**Branch:** `chore/upstream-sync-kolo6`

## Privatized symbols audit

Upstream commit `1524262 refactor: privatize module-local state` converted
several symbols from extern to static. Our fork tree uses some of these.
This document decides the per-call-site strategy.

## Symbol: `some_update_pointer_constraint()`

### Status: **REMOVED in upstream** (implicit break)

Our fork added `some_update_pointer_constraint()` as a public wrapper in
`somewm_api.c` → `somewm.c`. Upstream does NOT have this function at all;
the equivalent `cursorconstrain()` is public in `input.h`.

### Fork call sites

```
main:somewm.c:2894      : implementation (4-line wrapper)
main:somewm_api.c:526   : single caller (Lua API bridge)
main:somewm_api.h:53    : declaration
```

### Our implementation

```c
void
some_update_pointer_constraint(struct wlr_surface *surface)
{
    if (!surface)
        return;
    cursorconstrain(wlr_pointer_constraints_v1_constraint_for_surface(
        pointer_constraints, surface, seat));
}
```

### Upstream equivalents (available in refactored tree)

```
input.h:101:  void cursorconstrain(struct wlr_pointer_constraint_v1 *constraint);
somewm.h:91:  extern struct wlr_seat *seat;
somewm.h:97:  extern struct wlr_pointer_constraints_v1 *pointer_constraints;
```

All three symbols are public and accessible from any `.c` file that
includes the right headers.

### Decision: **INLINE** the call at `somewm_api.c:526`

Replace:
```c
some_update_pointer_constraint(surface);
```

With:
```c
if (surface) {
    cursorconstrain(wlr_pointer_constraints_v1_constraint_for_surface(
        pointer_constraints, surface, seat));
}
```

**Rationale:**
- Single call site — wrapper adds no encapsulation value
- Keeps upstream API surface clean (no fork-specific exported symbol)
- Avoids future upstream API drift

### Cleanup needed in Group F (NVIDIA focus port)

When porting `somewm_api.c` changes in Group F:
1. Remove `some_update_pointer_constraint()` declaration from `somewm_api.h`
2. Remove implementation from `somewm.c` (it won't be ported to any refactored module)
3. Update call site in `somewm_api.c` with inline version above

## Symbol: `cursor_mode`

### Status: **Private static in upstream** (`input.c:68`)

Our fork uses it only in `somewm.c` (cursor state machine bits).
After Kolo 6 port, cursor-related code moves to `input.c` where
`cursor_mode` is already static. **No API break** — direct access.

### Action: NONE (transparent after port)

Our cursor code ported to `input.c` will use the same local `cursor_mode`
that upstream already declared static.

## Symbols: `gesture_swipe_consumed`, `gesture_pinch_consumed`, `gesture_hold_consumed`

### Status: **Private static in upstream** (`input.c`)

Our fork uses them only in `somewm.c` (gesture handlers). Same as
`cursor_mode` — moves to `input.c` transparently.

### Action: NONE

## Symbols: `in_updatemons`, `updatemons_pending`

### Status: **Private static in upstream** (`monitor.c`)

Our fork uses them only in `somewm.c` (updatemons reentrancy guard).
After port to `monitor.c`, direct access to static vars.

### Action: NONE

## Symbol verification post-build

After Group A build, before Group E/F (input-heavy ports), verify:

```bash
nm build/somewm | grep -E "cursor_mode|gesture_.*_consumed|in_updatemons|updatemons_pending|some_update_pointer_constraint"
```

**Expected output:**
- `some_update_pointer_constraint` — NOT PRESENT (we removed it)
- `cursor_mode`, `gesture_*_consumed`, `in_updatemons`, `updatemons_pending` — all shown as `t` (local text) or not exported at all (static symbols do not appear in default nm output without `-a`)

If `some_update_pointer_constraint` appears → port incomplete, remove it.
If any of the static vars show as `T` (global) → duplicate definition, fix.

## Summary

| Symbol | Upstream status | Action during port |
|---|---|---|
| `some_update_pointer_constraint` | REMOVED | **Inline at call site**, delete wrapper + declaration |
| `cursor_mode` | static | Transparent (our code moves to same module) |
| `gesture_swipe_consumed` | static | Transparent |
| `gesture_pinch_consumed` | static | Transparent |
| `gesture_hold_consumed` | static | Transparent |
| `in_updatemons` | static | Transparent |
| `updatemons_pending` | static | Transparent |

**Blocker count: 0.** Only `some_update_pointer_constraint` needs explicit
work, and the fix is a 3-line inline expansion at a single call site.
