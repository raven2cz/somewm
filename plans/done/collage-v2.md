# Collage v2 — Desktop Portrait Decorations

## Context

The current collage module (`modules/collage/CollagePanel.qml`) is a **modal overlay gallery** — wrong UX entirely. It blocks the compositor, steals keyboard focus, and acts as an image picker, not desktop decoration.

The user previously had a working collage system in AwesomeWM (`fishlive/collage/init.lua`) where portrait images sat directly on the desktop as `wibox type="desktop"` surfaces — above wallpaper, below windows, with mouse scroll to cycle images. This approach doesn't work in somewm because **tag slide animations** cause static layer-shell surfaces to blink/glitch.

**Goal:** Rebuild collage as passive desktop decoration on `WlrLayer.Bottom` with:
- Per-tag layouts (images at configured positions)
- View/Edit mode toggle
- Instant hide before tag slide, fade-in after
- Portrait collection selection from `~/Pictures/wallpapers/public-wallpapers/portrait/`

---

## Architecture

### Key Design Decisions

1. **NOT a Panel** — Remove from `Panels.qml` exclusive list. Collage visibility is driven by active tag state, not panel toggle. Edit mode uses its own IPC handler.

2. **New `Portraits` service** — Singleton scanning portrait directories, providing images per collection. No global `activeCollection` — collection is per-tag in the layout JSON.

3. **Active tag tracking** — Add `activeTag` property to `Services.Compositor`, pushed from rc.lua on `tag::selected` signal. **Must filter `t.selected == true`** — the signal fires for both select and deselect.

4. **Dedicated layout JSON** — `~/.config/quickshell/somewm/collage-layouts.json` for per-tag slot positions/sizes/image indices. Separate from `config.json` to avoid churn.

5. **Tag slide IPC signals** — Two `qs ipc` calls added to `tag_slide.lua`: `slideStart` (with new tag name) before animation, `slideEnd` after completion.

### Race Condition Fix (from Sonnet review)

**Problem:** `slideStart` and `setTag` are two separate async IPC calls. If `setTag` arrives first, collage tries to show the new tag's layout while `sliding` is still false — visible flash.

**Solution:** Bundle the new tag name in `slideStart`:
```
qs ipc call somewm-shell:collage slideStart <newTagName>
```
The collage module receives both "hide now" and "next tag is X" atomically. The `setTag` IPC from `tag::selected` arrives later but is idempotent — `activeTag` is already set correctly.

---

## Component Breakdown

### 1. `services/Portraits.qml` (new singleton)

Scans `~/Pictures/wallpapers/public-wallpapers/portrait/` for subdirectories.

**Properties:**
- `collections: [{name, path, imageCount}]` — available portrait collections
- `portraitBasePath: string` — base directory path

**Functions:**
- `getImagesForCollection(name): []` — returns cached image paths for a collection (scans on first access, then caches)
- `getImage(collection, index): string` — wrapping index access for a specific collection
- `randomImage(collection): string` — for notification fallback
- `refresh()` — rescan base directory for collections

**IPC:** `somewm-shell:portraits` with `refresh()` for external trigger

**Pattern:** Same as `Wallpapers.qml` — `Process` + `find` for scanning, `StdioCollector` for parsing. Per-collection image lists cached in a JS object (`_imageCache: {}`).

### 2. `modules/collage/Collage.qml` (replaces CollagePanel.qml)

Main module — one `WlrLayer.Bottom` surface per screen.

**MUST use `Variants { model: Quickshell.screens }` wrapper** (same pattern as BorderFrame, HotEdges).

**Layer shell:**
```qml
WlrLayershell.layer: WlrLayer.Bottom
WlrLayershell.namespace: "somewm-shell:collage"
WlrLayershell.keyboardFocus: editMode
    ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
WlrLayershell.exclusionMode: ExclusionMode.Ignore
anchors { top: true; bottom: true; left: true; right: true }
color: "transparent"
```

**Visibility:**
```qml
property bool tagActive: {
    var tag = Services.Compositor.activeTag
    return tag !== "" && layoutData[tag] !== undefined
}
property bool sliding: false
property bool editMode: false

// visible controls rendering entirely — opacity alone is not enough
visible: tagActive && !sliding
opacity: _showOpacity  // animated 0→1 on show, instant 0 on hide
```

**Edit mode:**
- Toggle via IPC `somewm-shell:collage editToggle`
- In edit mode: `KeyboardFocus.Exclusive` (allows Escape to exit)
- On entering edit mode: push `_somewm_shell_overlay = true` to rc.lua (blocks desktop scroll)
- On exiting: push `_somewm_shell_overlay = false`, save layout JSON
- Visual indicator: accent borders on slots

**Edit mode interactions per slot:**
- **Scroll** = next/previous image from collection (same as view mode)
- **Middle click** = open collection picker popup (changes collection for entire tag)
- **Right click** = open current image in qimgv viewer
- **Drag** = reposition slot on screen
- **Corner drag** = resize slot (change maxHeight)
- **Escape** = exit edit mode and save

**Collection picker popup** (on middle click):
- Compact dropdown anchored to clicked slot
- Lists all portrait subdirectories with image count: `"joy (133)"`, `"witcher (315)"`
- Current collection highlighted with accent color
- Click on entry = change `collection` for this tag (all slots switch)
- Scrollable if list is long
- Auto-close after selection
- Uses `GlassCard` styling, `Components.ScrollArea`

**Mask strategy:**
- `mask: Region { item: interactiveArea }`
- `interactiveArea` is a single `Item` containing:
  - View mode: per-slot `Rectangle` children (positioned to match each CollageSlot)
  - Edit mode: one full-screen `Rectangle` (captures all input for drag/escape)

**Layout loading:**
- `FileView` watching `collage-layouts.json` with `watchChanges: true`
- Parse with try/catch, default to `({})` if missing/invalid
- `Repeater { model: currentTagSlots }` instantiates `CollageSlot` items

**Layout saving:**
- Queued write via `Process` (same pattern as `Compositor._run()` queue) to prevent concurrent writes
- Debounced: collect changes for 1s before writing

**Startup:**
- `Component.onCompleted`: fetch active tag via `somewm-client eval "return awful.screen.focused().selected_tag.name"` to initialize `activeTag`

**IPC Handler:**
```qml
IpcHandler {
    target: "somewm-shell:collage"
    function editToggle(): void { ... }
    function slideStart(newTag: string): void {
        // Atomic: hide + set pending tag
        root.sliding = true
    }
    function slideEnd(): void {
        root.sliding = false
        // Timer 200ms → fade-in
    }
}
```

### 3. `modules/collage/CollageSlot.qml` (new)

Single image frame on the desktop.

**Properties:** `slotX`, `slotY`, `maxHeight`, `imageIndex`, `collectionName`, `editMode`

**Visual:**
- **Two stacked `Image` items** for crossfade (front/back swap on index change)
- `fillMode: Image.PreserveAspectFit`, async loading
- **`sourceSize.height: maxHeight * 2`** — cap loaded resolution (prevents full-res GPU memory waste)
- Rounded corners: `Core.Theme.radius.lg`
- Drop shadow: `MultiEffect { shadowEnabled: true; blurMax: 20; shadowColor: Qt.rgba(0,0,0,0.5) }`
- Edit mode: 2px accent border

**Crossfade implementation:**
```qml
Image {
    id: imgFront
    opacity: 1.0
    source: currentImagePath
}
Image {
    id: imgBack
    opacity: 0.0
}
// On imageIndex change: swap source to imgBack, animate opacity crossfade
```

**Interactions:**
- View mode: `MouseArea` with `onWheel` — scroll cycles images (only interaction)
- Edit mode:
  - Scroll = cycle images
  - Middle click = emit signal to parent → open collection picker
  - Right click = `awful.spawn("qimgv <path>")` via Compositor.spawn()
  - Drag = reposition (DragHandler)
  - Corner handles = resize maxHeight
- All sizes multiplied by `Core.Theme.dpiScale`

### 4. Layout JSON format

File: `~/.config/quickshell/somewm/collage-layouts.json`

```json
{
  "4": {
    "collection": "joy",
    "slots": [
      { "x": 100, "y": 100, "maxHeight": 600, "imageIndex": 42 },
      { "x": 100, "y": 800, "maxHeight": 600, "imageIndex": 17 }
    ]
  },
  "9": {
    "collection": "witcher",
    "slots": [
      { "x": 100, "y": 100, "maxHeight": 800, "imageIndex": 3 },
      { "x": 870, "y": 100, "maxHeight": 400, "imageIndex": 12 },
      { "x": 870, "y": 530, "maxHeight": 800, "imageIndex": 7 }
    ]
  }
}
```

- Values are logical (unscaled) pixels. DPI scaling applied at render time.
- `collection` is **per-tag** — no global `activeCollection` (avoids dual source of truth).
- Empty/missing file → `({})` → no collage on any tag.

---

## Data Flow

### Tag change (no slide):
```
rc.lua: tag::selected (t.selected == true only!)
  → qs ipc call somewm-shell:compositor setTag <name>
  → Compositor.activeTag updated
  → Collage.qml: tagActive re-evaluates → show/hide with fade
```

### Tag slide:
```
tag_slide.lua: animated_viewidx()
  1. qs ipc call somewm-shell:collage slideStart <newTagName>
     → Collage.qml: sliding=true, visible=false (INSTANT, no animation)
  2. slide animation runs (0.25s)
  3. qs ipc call somewm-shell:collage slideEnd
     → sliding=false → visible=tagActive
     → Timer(200ms) → fade opacity 0→1 (250ms, ease.decel)
  (setTag IPC arrives separately but is idempotent — no race)
```

### Scroll cycling:
```
User scrolls on CollageSlot
  → imageIndex += delta (wraps via modulo on collection size)
  → Two-Image crossfade: back loads new, front fades out
  → Debounce 1s → persist imageIndex to layout JSON (queued write)
```

### Edit mode:
```
Super+Shift+O → qs ipc call somewm-shell:collage editToggle
  → editMode=true:
    - KeyboardFocus.Exclusive (allows Escape to exit)
    - Push _somewm_shell_overlay=true to rc.lua
    - Accent borders, drag/resize enabled
    - Full-screen mask (captures all input)
  → editMode=false (Escape or keybind again):
    - Save layout JSON (queued write)
    - KeyboardFocus.None
    - Push _somewm_shell_overlay=false
    - Restore per-slot mask
```

### Tag slide while in edit mode:
```
slideStart arrives → force editMode=false first, then sliding=true
```

---

## Files to Create

| File | Purpose |
|------|---------|
| `services/Portraits.qml` | Portrait collection scanner/provider |
| `modules/collage/Collage.qml` | Main collage module (Bottom layer, Variants per screen) |
| `modules/collage/CollageSlot.qml` | Individual image frame with crossfade |
| `modules/collage/CollectionPicker.qml` | Dropdown popup for collection selection (edit mode, middle click) |

## Files to Modify

| File | Change |
|------|--------|
| `services/qmldir` | Register `Portraits` singleton |
| `services/Compositor.qml` | Add `activeTag` property + `setTag(name)` to existing IpcHandler |
| `modules/collage/qmldir` | Register `Collage` and `CollageSlot` (remove old entries) |
| `shell.qml` | Change ModuleLoader from `CollageModule.CollagePanel` to `CollageModule.Collage` |
| `core/Panels.qml` | Remove `"collage"` from exclusive panel list |
| `config.default.json` | Add `collage` config section with `portraitBasePath` |
| `lua/somewm/tag_slide.lua` | Add `slideStart <newTag>` / `slideEnd` IPC at lines ~336 and ~317 |
| `plans/project/somewm-one/rc.lua` | Add `setTag` IPC on `tag::selected` (filtered `t.selected==true`), change collage keybind to `editToggle` |
| `tests/test-all.sh` | Update checks: new component names, new keybind pattern |

## Files to Delete

| File | Reason |
|------|--------|
| `modules/collage/CollagePanel.qml` | Old modal prototype |
| `modules/collage/MasonryGrid.qml` | Old masonry grid |
| `modules/collage/Lightbox.qml` | Old lightbox |

---

## Implementation Order

### Phase 1: Foundation + Cleanup
1. **Delete old files** (CollagePanel, MasonryGrid, Lightbox) — remove immediately to avoid qmldir conflicts
2. Create `services/Portraits.qml` — scan dirs, expose collections/images, cache per-collection
3. Register in `services/qmldir`
4. Add `activeTag` property + `setTag()` to `Compositor.qml` IpcHandler (shell side only)

### Phase 2: rc.lua integration
5. Add `tag::selected` handler to rc.lua — push `setTag` IPC (filter `t.selected==true`)
6. Add startup `activeTag` fetch in `Collage.qml` via `somewm-client eval`

### Phase 3: Rendering (view mode)
7. Create `CollageSlot.qml` — dual-Image crossfade, shadow, rounded corners, `sourceSize` constraint
8. Create `Collage.qml` — `Variants`, `WlrLayer.Bottom`, tag-based visibility, Repeater, layout JSON loading
9. Update `modules/collage/qmldir`, `shell.qml`
10. Remove `"collage"` from `Panels.qml` exclusive list

### Phase 4: Interactivity
11. Add scroll cycling to CollageSlot (view mode) with debounced persist
12. Add mask management (per-slot rects in view, full-screen in edit)
13. Add edit mode — drag, resize, Escape exit, KeyboardFocus toggle, overlay guard, layout save

### Phase 5: Tag slide integration
14. Modify `tag_slide.lua` — add `slideStart <newTag>` before `orig_viewidx`, `slideEnd` in completion callback
15. Add slideStart/slideEnd handlers to Collage.qml (instant hide, delayed fade-in)

### Phase 6: Config & Polish
16. Update `config.default.json` with collage section
17. Update rc.lua keybinding from `panels toggle collage` to `somewm-shell:collage editToggle`
18. Update `test-all.sh` — new component names, new keybind patterns, new structural checks

---

## Testing

### Automated (test-all.sh additions)
- Verify `Portraits` singleton has `pragma Singleton` + registered in `services/qmldir`
- Verify `Collage.qml` uses `WlrLayer.Bottom` (not Overlay)
- Verify `Collage.qml` uses `WlrKeyboardFocus.None` (default, non-edit state)
- Verify `Collage.qml` has `Variants { model: Quickshell.screens }`
- Verify `collage/qmldir` registers `Collage` and `CollageSlot`
- Verify `shell.qml` references `CollageModule.Collage` (not `CollagePanel`)
- Verify rc.lua has `somewm-shell:collage editToggle` keybind
- Verify rc.lua has `setTag` IPC push in tag::selected handler
- Verify `tag_slide.lua` has `slideStart` and `slideEnd` IPC calls
- Verify `collage-layouts.json` schema: each tag has `collection` (string) and `slots` (array with x/y/maxHeight/imageIndex)
- Verify old files deleted: no `CollagePanel.qml`, `MasonryGrid.qml`, `Lightbox.qml`

### Manual testing
- **Tag switch:** Switch to configured tag → collage appears with fade. Non-configured → hides.
- **Tag slide:** Super+Left/Right → no blink/flash, instant hide, smooth fade-in after (~450ms total delay).
- **Scroll cycling:** Hover slot, scroll → images crossfade smoothly.
- **Edit mode:** Super+Shift+O → accent borders, drag slots around, resize corners, Escape exits and saves.
- **Input passthrough:** Click between slots in view mode → passes to compositor. Keyboard never captured in view mode.
- **Edit mode overlay guard:** Desktop scroll-to-switch-tags blocked during edit.
- **Tag slide during edit:** Force-exits edit mode, then hides.
- **Empty collection:** 0 images in collection dir → slots hidden.
- **Missing layout JSON:** First launch → no collage, no crash.
- **Multi-screen:** Collage on active screen only (Variants + isActiveScreen check).
- **NVIDIA Bottom layer:** No visual artifacts, correct z-order vs wallpaper on RTX 5070 Ti.
- **Startup:** Collage appears on initially active tag (not just after first tag switch).

### Nested compositor testing
```bash
WLR_BACKENDS=wayland SOMEWM_SOCKET=/run/user/1000/somewm-socket-test \
  /home/box/git/github/somewm/build/somewm -d 2>/tmp/somewm-nested.log &
# Deploy shell, verify:
# 1. Collage visible on configured tags
# 2. Tag switching hides/shows correctly
# 3. Scroll cycling works
# 4. Edit mode drag/resize works
```
