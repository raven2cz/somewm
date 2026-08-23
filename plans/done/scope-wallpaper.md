# Scope-aware wallpaper resolution (per-monitor orientation)

Branch: `feat/monitor-portrait-wallpaper` (merged into main 2026-04-20)
Started: 2026-04-20
Status: **DONE** — shipped 2026-04-20. Live-verified on DELL + HP portrait.
Follow-up stabilization (edge cases, polish) tracked separately.

## 1. Problem

A tag's resolved wallpaper depends implicitly on the screen it renders on.
A landscape image (say 3840×2160) on a portrait output (2160×3840 after
transform 90°) is cover-scaled and heavily cropped — the center slice rarely
contains the subject. The old AwesomeWM X11 config had a parallel list
`wp_portrait[]` picked via `scr.geometry.width < scr.geometry.height`; we
want the same affordance in somewm, but integrated cleanly with the existing
4-tier resolution chain (override / user / theme / global-default).

## 2. Design summary — "scope" as an ordered set per screen

Introduce **scope** as an orthogonal layer above the existing resolution
chain. Critically, **a screen carries a SET of active scopes**, not a
single value — directly analogous to AwesomeWM tags (a client can have
multiple tags; multiple tags can be selected at once).

Two kinds of scope:

- **Auto-scope** — derived by a rule from screen state. Shipped in v1:
  `portrait` auto-added when `geo.height > geo.width`. Future additions
  like `ultrawide` can register new rules without schema changes.
- **Manual scope** — user-toggled labels for specialized views. Example:
  `presentation` on the Samsung TV when showing ads; `gaming`, `cinema`,
  etc. Persisted per screen name.

Both kinds coexist. For Samsung with landscape orientation + presentation
turned on, the active scope set is `{presentation}` (landscape is the
**implicit baseline** — no scope name needed). For HP in portrait with
presentation on, the set is `{presentation, portrait}` — both active,
resolved in priority order.

**Resolution**: walk active scopes in priority order, each scope gets its
own scoped resolution chain; fall through to unscoped (= landscape
baseline) if no scope matches.

**Invariants**
- Empty scope set == current behavior (backward compat).
- Auto-scopes re-derive on every `property::geometry` fire.
- Manual scopes persist across restarts in
  `~/.config/somewm/screen_scopes.json`, keyed by `<make>|<model>` (or
  `screen.name` fallback when make/model absent).
- Override state keyed as `_overrides[scope][tag]` — each scope is an
  independent namespace of overrides.
- Priority order: **manual scopes first (LIFO — most recently added
  wins), auto-scopes after** (user intent wins over automatic
  derivation, and *latest* user intent wins within manual set).
  Rationale: `add_scope_to_screen("cinema")` followed by
  `add_scope_to_screen("presentation")` should mean "presentation
  overrides cinema" — matches user mental model of toggling the latest
  mode.

## 3. Priority chain (new)

Active scope set for a screen = `scopes = [manual..., auto...]` (ordered,
highest priority first). Resolver pseudocode:

```python
def resolve(tag, scopes):
    # 1) Exhaust each scope FULLY before trying the next.
    #    Within a scope, tag-specific beats default-file beats next-scope.
    for S in scopes:
        # Tag-specific lookups inside this scope
        if _overrides[S][tag]:                              return ...
        if themes/{active}/user-wallpapers/{S}/{tag}.*:     return ...
        if themes/{active}/wallpapers/{S}/{tag}.*:          return ...
        if themes/default/wallpapers/{S}/{tag}.*:           return ...
        # Scoped default file — preserves orientation when tag is absent
        if themes/{active}/user-wallpapers/{S}/1.jpg:       return ...
        if themes/{active}/wallpapers/{S}/1.jpg:            return ...
        if themes/default/wallpapers/{S}/1.jpg:             return ...

    # 2) Fall through to unscoped baseline (== landscape)
    if _overrides[unscoped][tag]:                           return ...
    if themes/{active}/user-wallpapers/{tag}.*:             return ...
    if themes/{active}/wallpapers/{tag}.*:                  return ...
    if themes/default/wallpapers/{tag}.*:                   return ...
    if themes/{active}/wallpapers/1.jpg:                    return ...
    if themes/default/wallpapers/1.jpg:                     return ...
    return nil
```

> **Review note (Gemini-3.1 round 2) — CRITICAL FIX:** earlier draft
> ordered "all scopes specific-tag → unscoped specific-tag → scoped
> default-file". Gemini argued "an orientation mismatch is worse than a
> tag mismatch" — a portrait screen should prefer a portrait default
> image over a correctly-named but badly-cropped landscape image. Chain
> now exhausts each scope FULLY (specific tag, then scoped default-file
> fallback) before falling through to unscoped. Orientation integrity
> wins over tag identity.

**Key property**: `landscape` is no longer a named scope — it's the
absence of any named scope. The unscoped baseline IS landscape. This
means a Dell landscape screen with no manual scopes has
`scopes = []`, and resolution goes straight to step 2 (identical to
today's behavior — zero regression).

A portrait screen with no manual scopes has `scopes = ["portrait"]`.
A Samsung with `presentation` turned on has `scopes = ["presentation"]`.
A Samsung rotated portrait with presentation on has
`scopes = ["presentation", "portrait"]` — presentation images win when
they exist, portrait images win for tags presentation doesn't override,
landscape baseline catches everything else.

### Orientation trap (documented limitation)

If a user activates `gaming` on a portrait screen and the `gaming` scope
only ships landscape assets, the resolver picks `gaming/1.jpg` and
crops. User must either provide `gaming/portrait/` assets (future
nested scope combinator — v2) or accept the cropping. For v1, document
that manual scopes should ship orientation-appropriate assets if the
user mixes them across portrait and landscape screens.

## 4. Directory layout (subdirectory, scope-named)

Scope names become reserved subdirectory names. Any scope S gets its
own subdir `{S}/` under `wallpapers/` and `user-wallpapers/`:

```
themes/<theme>/
  wallpapers/                 # unscoped baseline (landscape)
    1.jpg, 2.jpg, ...
    portrait/                 # scope=portrait (opt-in, auto-scope)
      1.jpg, ...
    presentation/             # scope=presentation (manual)
      1.jpg, ...
  user-wallpapers/            # user wallpapers (rsync-excluded)
    1.jpg, ...                # unscoped
    portrait/
      1.jpg, ...
    presentation/
      1.jpg, ...
themes/default/
  wallpapers/
    1.jpg, ...                # global unscoped fallback
    portrait/                 # global portrait fallback
    presentation/             # global presentation fallback
```

`deploy.sh` rsync exclude **stays unchanged** at
`themes/*/user-wallpapers/` — it already excludes everything under the
dir including any scope subdir.

**Reserved scope names** (cannot be used as tag names): `portrait`,
`presentation`, plus anything a user registers. Existing tag names are
numeric "1".."9" so there's no collision today. The resolver does NOT
enforce this programmatically — users are trusted not to name a tag
`portrait`. **Future validation hook**: when named tags become common
(`"web"`, `"chat"`), `wallpaper.register_scope(name)` should reject
names that collide with any existing `tag.name` across all screens, and
`tag.name` mutations should reject collisions with registered scopes.
Tracked as v2 work.

## 5. Data model — `fishlive.services.wallpaper`

### State changes

```lua
-- OLD
wallpaper._overrides = {}            -- [tag_name] = path
wallpaper._wppath, _user_wppath, _default_wppath

-- NEW (additive — no file removals)
wallpaper._overrides = {}            -- [scope] = { [tag_name] = path }
wallpaper._wppath, _user_wppath, _default_wppath   -- unchanged, landscape base

-- Computed on demand per resolve call:
--   user_wppath_scope  = _user_wppath:gsub("/$", "-<scope>/")
--   wppath_scope       = _wppath     :gsub("/$", "-<scope>/")
--   default_wppath_scope = _default_wppath:gsub("/$", "-<scope>/")
```

### New helpers

```lua
-- Active auto-scope rules. List, not map, so rules have a defined order.
-- Each rule: function(scr) -> scope_name or nil.
wallpaper._auto_scope_rules = {
    function(scr)
        local g = scr.geometry
        if not g or g.width == 0 or g.height == 0 then return nil end
        if g.width < g.height then return "portrait" end
        return nil
    end,
}

-- Manual scope state: { [screen_key] = { "presentation", ... } }
-- screen_key = scr.make .. "|" .. scr.model  (preferred — survives port
-- reassignment / cable swap), fallback to scr.name when make/model absent.
-- Loaded from ~/.config/somewm/screen_scopes.json at init; persisted on change.
wallpaper._manual_scopes = {}

-- Compute persistence key for a screen. Prefer make|model so HP plugged
-- into DP-2 today and DP-4 tomorrow keeps its scopes.
function wallpaper._screen_key(scr)
    if scr.make and scr.model and scr.make ~= "" and scr.model ~= "" then
        return scr.make .. "|" .. scr.model
    end
    return scr.name
end

-- Compute ordered active scope list for a screen.
-- Manual scopes first (highest priority), then auto-scopes.
function wallpaper._scopes_for_screen(scr)
    local out = {}
    local seen = {}
    -- Manual (user-set) — stored already in LIFO order (latest-first)
    local manual = wallpaper._manual_scopes[wallpaper._screen_key(scr)] or {}
    for _, s in ipairs(manual) do
        if not seen[s] then table.insert(out, s); seen[s] = true end
    end
    -- Auto (derived)
    for _, rule in ipairs(wallpaper._auto_scope_rules) do
        local s = rule(scr)
        if s and not seen[s] then table.insert(out, s); seen[s] = true end
    end
    return out
end

-- Primary resolver now takes a scope LIST.
function wallpaper._resolve(tag_name, scopes)
    scopes = scopes or {}
    -- walk the priority chain from §3, first readable wins
end

-- Convenience wrapper used by all call sites inside wallpaper.lua.
function wallpaper._resolve_for_screen(scr, tag_name)
    return wallpaper._resolve(tag_name, wallpaper._scopes_for_screen(scr))
end

-- Negative cache for "scope directory does not exist" — avoids stat storms
-- when a theme has no <scope>/ subdir. Key: absolute scope-dir path.
-- Invalidated on theme switch and on explicit directory creation via IPC.
wallpaper._scope_dir_missing = {}  -- { [abs_dir] = true }
```

> **Review note (Gemini):** the resolver can issue up to 4 extensions ×
> ~5 file tiers × 2 scope levels stat calls per tag. With 9 tags × 2
> screens at theme switch the stat count runs into the hundreds. The
> negative cache short-circuits entire scoped tiers when the scope dir
> is absent. Invalidate on `themes.switch()` and on every
> `save_to_theme` that creates a scope dir.
>
> **Trade-off (Gemini round 2):** if the user creates a scope dir
> externally via `mkdir ~/.config/somewm/themes/default/wallpapers/portrait`
> at the shell — not through somewm IPC — the negative cache will not
> invalidate and the resolver continues reporting the directory as
> missing until the next theme switch or session restart. Documented
> workaround: after CLI mkdir, run
> `somewm-client eval 'require("fishlive.services.wallpaper")._scope_dir_missing = {}'`
> to clear the cache, or simply re-switch the theme. Not auto-invalidated
> because a filesystem watcher to monitor N theme dirs × M scopes would
> erase the performance win.

### Startup/hotplug race guard

The `property::geometry` listener already re-applies on final geometry
(commit 51a0e53 on this branch). We additionally:
- Skip initial apply in `init()` if `_scope_for_screen` reports width/height==0,
  and rely on the first `property::geometry` fire to trigger first apply.
- Keep the existing cache-invalidate-on-geometry-change behavior to drop
  stale scope surfaces when a screen flips portrait↔landscape live.

### Updated call sites (same file)

- `init(scr, …)` — use `_resolve_for_screen(scr, init_tag)` and `_resolve_for_screen(scr, tag.name)` in preload loop.
- `tag:connect_signal("property::selected")` — `_resolve_for_screen(t.screen, t.name)`.
- `scr:connect_signal("property::geometry")` — `_resolve_for_screen(s, tag_name)` (scope may have flipped).
- `set_override(tag_name, path)` — **scope-aware**: scope derived from the **focused** screen at call time; writes to `_overrides[scope][tag_name]`. Applies only to screens whose current scope matches.
- `clear_override(tag_name)` — clears entry for the focused-screen scope only. (Unchanged scopes retain their overrides.)
- `save_to_theme(tag_name, source_path)` — scope from focused screen picks target subdir: `user-wallpapers/<scope>/<tag>.<ext>` (for unscoped / landscape baseline the legacy `user-wallpapers/<tag>.<ext>` path, no rename).
- `clear_user_wallpaper(tag_name)` — removes files from `user-wallpapers/<scope>/` matching the focused screen's scope. Unscoped `user-wallpapers/<tag>.<ext>` files are **not** touched unless the scope is unscoped.

### `themes.switch()` updates

`fishlive/services/themes.lua:282–320` — the per-screen apply loop must
resolve using the screen's own scope:

```lua
for scr in screen do
    scr._wppath = wppath
    local sel = scr.selected_tag
    if sel then
        local wp = wp_service._resolve_for_screen(scr, sel.name)
        if wp then
            scr._current_wallpaper = nil
            wp_service.apply(scr, wp)
        end
    end
    if root.wallpaper_cache_preload then
        local paths = {}
        for _, tag in ipairs(scr.tags) do
            local wp = wp_service._resolve_for_screen(scr, tag.name)
            if wp then table.insert(paths, wp) end
        end
        if #paths > 0 then root.wallpaper_cache_preload(paths, scr, {fit="cover"}) end
    end
end
```

## 6. IPC surface (additive, backward-compatible)

All existing methods keep their signatures AND their return shapes. Scope
handling is additive via a new optional `scope` parameter everywhere that
writes, so the shell can **freeze the scope at panel-open time** and pass
it explicitly — avoiding focus-drift bugs where the user opens the picker
on HP, the mouse drifts to Dell, and a "save" accidentally targets
landscape.

### Reader methods

Reader methods take an optional `screen_name?` final argument. When
omitted, the method operates on the focused screen. When provided, it
targets the named output. This halves the reader surface area and
eliminates the confusing `X` vs `X_for_screen` method pairs.

| Method                                     | Status   | Behavior                                                                                   |
|--------------------------------------------|----------|--------------------------------------------------------------------------------------------|
| `get_overrides_json(screen_name?)`         | extended | flat `{<tag>:<path>,…}` for target screen's **primary** scope (= scopes[1] or empty)       |
| `get_resolved_json(screen_name?)`          | extended | resolved per-tag for target screen (walks full scope set)                                  |
| `get_overrides_all_json()`                 | **new**  | nested `{"<scope>":{<tag>:<path>,…},…}` — all scopes, global (no screen arg, screen-agnostic) |
| `get_active_scopes_json(screen_name?)`     | **new**  | target screen scope set: `["presentation","portrait"]`                                     |
| `get_all_screen_scopes_json()`             | **new**  | `{"HP|HP U28":["portrait"],"Samsung|…":["presentation"]}` keyed by persistence key         |
| `get_registered_scopes_json()`             | **new**  | `["portrait","presentation",…]` — all scope names known to the system                      |

> **Review note (Gemini round 2):** the earlier revision shipped method
> pairs — `get_resolved_json()` + `get_resolved_json_for_screen(name)`,
> `get_active_scopes_json()` + `get_active_scopes_for_screen(name)`.
> Gemini flagged this as redundant API surface that invites callers to
> drift between the two forms (e.g. some code paths use the focused
> variant, some pass names — eventually they produce different state
> during focus transitions). Consolidating to a single method with
> optional arg keeps the "defaults to focused" ergonomics while giving
> QS the screen-bound variant it needs.

### Writer methods (scope set mutation)

Writers take `screen_name` as the first argument (required — scope
mutations are never implicit on focus, because focus drift between
keybind and IPC dispatch could retarget the wrong screen).

| Method                                         | Status   | Behavior                                                                                           |
|------------------------------------------------|----------|----------------------------------------------------------------------------------------------------|
| `add_scope_to_screen(screen_name, scope)`      | **new**  | **Prepend** (LIFO — newest wins) to manual set; re-resolve + persist                               |
| `remove_scope_from_screen(screen_name, scope)` | **new**  | Drop from manual set; re-resolve + persist                                                         |
| `set_screen_scopes(screen_name, scopes_list)`  | **new**  | Replace whole manual set (callers pass highest-priority first); re-resolve + persist               |
| `toggle_scope_on_screen(screen_name, scope)`   | **new**  | Convenience flip — used by keybindings. Adds via LIFO prepend if absent, removes if present        |

> **Review note (Gemini round 2):** earlier draft appended on add,
> meaning "first-added wins". If a user toggled `cinema` at startup and
> later toggled `presentation`, the landscape-style presentation pipe
> would be *lower* priority than cinema — opposite of intent. LIFO
> prepend matches "latest action wins", which is the mental model for
> most toggle-style controls.

### Writer methods (wallpaper mutation — now scope-aware)

| Method                                  | Status   | Behavior                                                                             |
|-----------------------------------------|----------|--------------------------------------------------------------------------------------|
| `set_override(tag, path, scope?)`       | extended | scope = arg if given, else focused screen's primary scope (or unscoped)              |
| `clear_override(tag, scope?)`           | extended | scope = arg if given, else focused screen's primary scope                            |
| `save_to_theme(tag, path, scope?)`      | extended | scope = arg if given, else focused screen's primary scope; unscoped == legacy path   |
| `clear_user_wallpaper(tag, scope?)`     | extended | scope = arg if given, else focused screen's primary scope                            |

**Primary scope** = first element of the screen's active scope list
(highest-priority). If scope set is empty, primary scope is unscoped
(== landscape baseline, legacy `user-wallpapers/tag.jpg` path).

> **Review note (Gemini):** the original plan changed `get_overrides_json()`
> to a nested shape and recommended Option A (update QS in lockstep). That
> couples two independently-deployed artifacts (somewm-one Lua + somewm-shell
> QS) — a deploy of one before the other would break the picker. The
> revised plan picks Option B: old method keeps flat semantics (always
> valid for the current screen), a new method exposes the full map when
> future UI wants cross-scope views. Zero regression for a QS deploy lag.

> **Review note (Gemini):** `save_to_theme` is the highest-risk IPC call
> for focus drift — if a user opens the picker on HP portrait, drags the
> mouse, and hits save, Wayland focus can shift to Dell landscape
> mid-operation. The `scope?` parameter lets the QS panel snapshot its
> scope at open and pass it explicitly, eliminating the race.

## 7. QS picker changes (per-screen, scope-chip selector — v1)

Goal: the picker is **bound to the screen it renders on** AND exposes
the screen's active scope set so user can pick which scope to edit.

### Binding design

- `WallpaperPanel.qml` reads its own `screen.name` (Quickshell provides
  this on `PanelWindow`).
- QML property
  `panelScreenScopes: Services.Wallpapers.activeScopesForScreen(screen.name)`
  — list, re-evaluates if panel moves to a different screen or scopes
  change via IPC.
- QML property `activeEditScope: panelScreenScopes[0] || ""` — the scope
  currently being **edited** by writer actions. Defaults to primary
  (highest priority) scope; empty string means unscoped baseline.
- All writer calls pass `activeEditScope` explicitly as the scope arg.
- Carousel + tag bar render
  `get_resolved_json_for_screen(screen.name)` — always reflects the
  panel's own screen, not focused-client screen.

### Scope chips

Horizontal chip row above the tag list:

```
[portrait ●] [presentation] [Base] [+ add]
```

- First chip = currently editing (filled marker). Click another chip to
  switch which scope writer actions target.
- **"Base" pseudo-chip** (always present) targets the landscape baseline
  — lets user edit the default set without activating a manual scope.
  User-facing label is "Base" (or localized equivalent); internal
  identifier remains `unscoped` / empty string. Reason: `unscoped` reads
  as a negative / techy term; "Base" conveys the conceptual role (this
  is the foundation every other scope overrides).
- **"+" button** opens a small prompt to add a new manual scope
  (`add_scope_to_screen(screen.name, "gaming")`), which creates the
  chip. Long-press or right-click on a manual-scope chip removes it
  (`remove_scope_from_screen`).

### Header label

Small screen label above chips: `"HP (DP-2)"` so user sees which
monitor this picker operates on.

### Behavior on rotation / scope-set changes

Shell subscribes to `data::wallpaper` / `data::screen_scopes` broker
events (wallpaper service emits both on relevant changes). QML bindings
re-evaluate automatically; no manual reload needed.

## 8. Persistence + deploy / migration

### Manual scopes persistence

Per-screen manual scope sets persist at:

```
~/.config/somewm/screen_scopes.json
```

Shape (keyed by persistence key `<make>|<model>`, fallback `screen.name`):
```json
{
  "HP|HP U28": ["presentation", "portrait"],
  "Samsung Electric Company|S32D85x": [],
  "DP-5": ["cinema"]
}
```

- Loaded on `wallpaper.init` (once per session).
- Saved on any `add_scope_to_screen` / `remove_scope_from_screen` /
  `set_screen_scopes` mutation.
- **Keyed by `<make>|<model>`** (`wallpaper._screen_key(scr)`) so HP
  plugged into DP-2 today and DP-4 tomorrow keeps its scopes. Only falls
  back to `screen.name` when make or model is empty (rare; some virtual
  outputs).
- Screens missing from the file behave as if they had an empty manual
  set; no migration needed from old installs.
- **Atomic writes**: `os.rename(path..".tmp", path)` pattern — write
  full JSON to `screen_scopes.json.tmp` then rename in place. Guards
  against half-written state if somewm is killed mid-save. Same pattern
  already used by `themes.save_current`.

### Deploy rules

- `deploy.sh` rsync exclude **unchanged** — the subdirectory layout
  means `themes/*/user-wallpapers/` already excludes any scope subdir.
- `screen_scopes.json` lives OUTSIDE the repo (at
  `~/.config/somewm/`) — user-state, not config-state.
- Old installs have only `user-wallpapers/` and `wallpapers/`;
  scope-aware resolver treats those as the unscoped baseline (== no
  change).

### Port user's existing portrait wallpaper set from the old multicolor config

The old `~/.config/awesome/themes/multicolor/theme.lua` shipped a
`wp_portrait[]` list cycled across 9 tags. Carry that setup into somewm
by creating `plans/project/somewm-one/themes/default/wallpapers/portrait/`
and copying the source images (renamed per tag-name convention).

Source dir (confirmed present): `~/Pictures/wallpapers/public-wallpapers/`
Source files → target names in `themes/default/wallpapers/portrait/`:

| Tag | Source                              | Target  |
|-----|-------------------------------------|---------|
| 1   | `00049-cat-in-flowers.jpg`          | `1.jpg` |
| 2   | `00050-the-witcher-ciri.jpg`        | `2.jpg` |
| 3   | `00051-guweiz-shinobi.jpg`          | `3.jpg` |
| 4   | `00052-shadowheart.jpg`             | `4.jpg` |
| 5   | `00049-cat-in-flowers.jpg`          | `5.jpg` |
| 6   | `00050-the-witcher-ciri.jpg`        | `6.jpg` |
| 7   | `00051-guweiz-shinobi.jpg`          | `7.jpg` |
| 8   | `00052-shadowheart.jpg`             | `8.jpg` |
| 9   | `00049-cat-in-flowers.jpg`          | `9.jpg` |

Placing them under **default theme** means every theme (multicolor was
the only user-installed theme in old config; somewm has catppuccin /
dracula / tokyo-night / etc.) inherits the portrait set via tier 5 of
the resolution chain unless a theme explicitly overrides with its own
`wallpapers/portrait/`.

User stays free to swap any of these via the QS picker — `save_to_theme`
with the panel's portrait scope will write to
`themes/<active>/user-wallpapers/portrait/<tag>.jpg` and shadow the
default.

Commit these as part of the somewm-one repo — they're user-config
territory, not system defaults, but sharing somewm-one already commits
wallpapers under `themes/default/wallpapers/1..9.jpg`.

## 9. Test matrix

| Scenario                                                                | Expected                                                                          |
|-------------------------------------------------------------------------|-----------------------------------------------------------------------------------|
| Dell alone, no manual scopes                                            | `scopes=[]`, resolution via unscoped baseline — identical to today                |
| HP portrait, no manual scopes, no `portrait/` dirs                      | `scopes=["portrait"]`, all scoped tiers miss, unscoped baseline serves — same as today |
| HP portrait, `wallpapers/portrait/1.jpg` added to default theme         | HP tag 1 shows portrait image; Dell unchanged                                     |
| Dell + Samsung landscape, no manual scopes                              | Both Dell and Samsung `scopes=[]`, unscoped baseline                              |
| Samsung + `add_scope_to_screen("DP-4","presentation")`                  | Samsung `scopes=["presentation"]`; resolver hits `wallpapers/presentation/*` first |
| HP + Samsung, both with `presentation` added                            | Both re-resolve; HP `["presentation","portrait"]`, Samsung `["presentation"]`     |
| Samsung in presentation, `remove_scope_from_screen("DP-4","presentation")` | Samsung `scopes=[]`, falls back to unscoped                                    |
| Add `cinema`, then add `presentation` on same screen                    | `scopes=["presentation","cinema"]` — LIFO prepend (latest first)                  |
| Restart somewm with `screen_scopes.json` present                        | All persisted scopes re-apply on init, keyed by `make|model`                      |
| Unplug HP from DP-2, replug into DP-4, scopes persist                   | `make|model` keying resolves same scope list on the new port                      |
| Kill somewm mid-save of `screen_scopes.json`                            | File remains valid JSON (atomic rename); no partial writes                        |
| `toggle_scope_on_screen("DP-4","presentation")` keybinding              | Scope flips on/off, wallpaper updates on that screen only                         |
| Focused Samsung, `save_to_theme("1", path)` no explicit scope, presentation active | File written to `user-wallpapers/presentation/1.jpg`                    |
| QS panel on HP, scope chip tap from `portrait` → `Base`                 | `activeEditScope=""`, save writes to `user-wallpapers/1.jpg`                      |
| QS panel on Samsung, click "+" chip, add `"cinema"`                     | `add_scope_to_screen("DP-4","cinema")` called; chip appears; persisted to JSON    |
| Rotate HP portrait→landscape live                                       | Auto-scope `portrait` drops from `scopes`; re-resolve to unscoped baseline        |
| Theme switch with HP+Dell, HP has `portrait` auto-scope                 | Both screens re-apply with their scope sets                                       |
| `get_overrides_json()` on focused HP with `scopes=["portrait"]`         | Returns flat `{tag:path}` for portrait scope (primary)                            |
| `get_overrides_json("DP-3")` from HP-focused session                    | Returns flat map for Dell's primary scope (unscoped) — single method, optional arg |
| `get_overrides_all_json()`                                              | Returns nested `{scope: {tag:path}}` for every scope that has overrides           |
| Theme ships no `portrait/`, 9 tags on HP                                | Negative cache suppresses stat calls for scoped tiers after first miss            |
| `mkdir themes/default/wallpapers/portrait/` via CLI (no IPC)            | Cache still reports missing until `themes.switch` or explicit clear — documented  |
| Hotplug HP, transient 0×0 geometry                                      | Auto-scope rule returns nil for portrait → `scopes=[]`; `property::geometry` re-resolves when final dims arrive |

## 10. Out of scope / deferred

- Explicit scope selector in picker UI (v2).
- Additional scope dimensions beyond orientation (ultrawide, tv,
  time-of-day). API accepts arbitrary scope strings already; resolver
  and scope predicate would need extension.
- Persisting `_overrides` across restart. Today overrides are runtime
  only; that behavior is unchanged.
- Animating scope flip (e.g. fade when rotating screen). Current
  `property::geometry` re-apply is instantaneous.

## 11. Rollout order

Sized small; each step deploys + tests independently. If a step breaks
something, the preceding steps remain stable and testable.

1. **Resolver refactor (auto-scope only)** —
   `fishlive/services/wallpaper.lua`:
   - `_auto_scope_rules` list with portrait rule.
   - `_manual_scopes` (empty placeholder; persistence in step 4).
   - `_scopes_for_screen(scr)`, `_resolve(tag, scopes)`,
     `_resolve_for_screen(scr, tag)`.
   - Nested `_overrides[scope][tag]` state.
   - Negative cache `_scope_dir_missing`.
   - Update all internal call sites to pass scope list.
   - Existing IPC signatures unchanged; focused-screen inference
     updated to use primary scope (= scopes[1] or unscoped).
   - Deploy + reload; HP/Dell with no scope dirs → zero visual change.

2. **Portrait image migration** — create
   `plans/project/somewm-one/themes/default/wallpapers/portrait/` and
   copy 4 images from `~/Pictures/wallpapers/public-wallpapers/` with
   the cycle mapping from §8 (cat / ciri / shinobi / shadowheart × 9
   tags). Deploy. Verify HP picks them up on tag switch, Dell unchanged.

3. **Theme switch loop update** — `fishlive/services/themes.lua`:
   - Call `_resolve_for_screen` in the per-screen loop.
   - Invalidate negative cache on theme switch.

4. **Manual scopes + persistence + IPC** — `wallpaper.lua`:
   - `_screen_key(scr)` helper (`make|model` with `screen.name` fallback).
   - Load/save `~/.config/somewm/screen_scopes.json` with atomic
     `.tmp` + `os.rename` pattern.
   - Implement `add_scope_to_screen` (LIFO prepend),
     `remove_scope_from_screen`, `set_screen_scopes`,
     `toggle_scope_on_screen`.
   - Add reader methods with optional `screen_name?` arg (consolidated
     API from §6).
   - Emit `data::screen_scopes` broker signal on mutation.
   - Add `scope?` optional arg to existing writers.
   - Deploy + smoke-test via `somewm-client eval`.

5. **QS picker — per-screen binding + scope chips** —
   `somewm-shell/services/Wallpapers.qml` +
   `modules/wallpapers/WallpaperPanel.qml`:
   - Read `screen.name` from `PanelWindow`; bind `panelScreenScopes`.
   - Render chip row; default `activeEditScope = panelScreenScopes[0]`.
   - "+" chip opens scope-add prompt → `add_scope_to_screen`.
   - Right-click chip removes manual scope.
   - Writer calls (save/clear/override) pass `activeEditScope`.
   - Deploy QS + restart QS; live-test chip interactions.

6. **Manual live tests** — full scenario matrix from §9 on HP+Dell,
   then Samsung+Dell with manual `presentation` scope.

7. **Independent review** — send combined diff to Gemini + (retry)
   Codex before merge to main.

## 12. Risks + mitigations

| Risk                                                 | Mitigation                                                                                                   |
|------------------------------------------------------|--------------------------------------------------------------------------------------------------------------|
| `_overrides` shape migration breaks running session  | Shape change happens in memory only on first reload; `themes.switch` already wipes `_overrides = {}`         |
| QS deploy lag vs Lua deploy                          | `get_overrides_json()` kept flat (Option B) — old QS code keeps working against new Lua                       |
| Focus drift during `save_to_theme`                   | QS panel freezes scope at open; explicit scope arg passed                                                    |
| Stat storm on tag switch                             | Negative cache for missing scope dirs; invalidated only on theme switch                                      |
| Hotplug with transient 0×0 geometry                  | `_scope_for_screen` guards for zero dims; `property::geometry` re-resolves                                   |
| Surface memory doubling on live rotation             | Existing `root.wallpaper_cache_invalidate_screen(s.index)` on `property::geometry` drops old-scope surfaces  |
