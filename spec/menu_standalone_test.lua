#!/usr/bin/env lua
---------------------------------------------------------------------------
-- Standalone unit test: fishlive.menu popup menu component
--
-- Runs without busted or lgi. Uses plain assert() calls.
-- Execute: lua spec/menu_standalone_test.lua
---------------------------------------------------------------------------

-- Add paths. somewm-one is a sibling repo (raven2cz/somewm-one); override
-- the checkout location with SOMEWM_ONE_PATH (defaults to $HOME/git/github/somewm-one).
local home = os.getenv("HOME") or "."
local somewm_one = os.getenv("SOMEWM_ONE_PATH")
    or (home .. "/git/github/somewm-one")
package.path = somewm_one .. "/?.lua;"
    .. somewm_one .. "/?/init.lua;"
    .. "lua/?.lua;lua/?/init.lua;"
    .. "spec/?.lua;"
    .. package.path

-- =========================================================================
-- Mocks
-- =========================================================================

_G.mouse = { current_wibox = nil }
_G.awesome = { version = "v9999", api_level = 9999 }

local function mock_widget(args)
    local w = args or {}
    w._signals = {}
    w.connect_signal = function(self, name, fn)
        self._signals[name] = self._signals[name] or {}
        self._signals[name][#self._signals[name] + 1] = fn
    end
    w.disconnect_signal = function(self, name, fn)
        if self._signals[name] then
            for i, f in ipairs(self._signals[name]) do
                if f == fn then table.remove(self._signals[name], i); break end
            end
        end
    end
    w.emit_signal = function() end
    w.buttons = function() end
    return w
end

package.loaded["beautiful"] = {
    menu_bg_normal = "#181818",
    menu_bg_focus = "#232323",
    menu_fg_normal = "#888888",
    menu_fg_focus = "#d4d4d4",
    menu_border_color = "#c49a3a",
    border_color_active = "#e2b55a",
    fg_minimize = "#555555",
    menu_radius = 8,
    menu_icon_font = "Symbols Nerd Font Mono 14",
    menu_font = "Geist 11",
    font = "Geist 10",
}
package.loaded["beautiful.xresources"] = {
    apply_dpi = function(v) return v end,
}
package.loaded["gears"] = {
    string = {
        xml_escape = function(text)
            if not text then return nil end
            return text:gsub("['&<>\"]", {
                ["'"] = "&apos;", ["\""] = "&quot;",
                ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;",
            })
        end,
    },
    shape = { rounded_rect = function() end },
    table = { join = function(...) return {} end },
    timer = {
        start_new = function(timeout, fn)
            return { stop = function() end }
        end,
        delayed_call = function(fn) fn() end,
    },
    color = {
        recolor_image = function(img, color) return img end,
    },
}

local wibox_mod = {
    widget = {
        textbox = "textbox",
        imagebox = "imagebox",
        base = {},
    },
    container = {
        background = "background",
        margin = "margin",
    },
    layout = {
        fixed = {
            horizontal = "horizontal",
            vertical = function()
                local l = {
                    _children = {},
                    spacing = 0,
                    reset = function(self) self._children = {} end,
                    add = function(self, w) self._children[#self._children + 1] = w end,
                }
                return l
            end,
        },
    },
}
setmetatable(wibox_mod.widget, {
    __call = function(_, args) return mock_widget(args) end,
})
package.loaded["wibox"] = wibox_mod

package.loaded["awful"] = {
    popup = function(args)
        local p = mock_widget(args)
        p.visible = args.visible or false
        p.bg = args.bg
        p.border_color = args.border_color
        p.border_width = args.border_width
        p.shape = args.shape
        p.ontop = args.ontop
        p.maximum_width = args.maximum_width
        p._apply_size_now = function() end
        p.geometry = function() return { x = 0, y = 0, width = 200, height = 300 } end
        return p
    end,
    placement = {
        under_mouse = function() end,
        no_offscreen = function() end,
    },
    button = function(mods, btn, fn)
        return { mods = mods, button = btn, fn = fn }
    end,
    keygrabber = function(args)
        return { stop = function() end, is_running = true }
    end,
    mouse = {
        append_global_mousebinding = function() end,
        remove_global_mousebinding = function() end,
    },
}

local broker_signals = {}
package.loaded["fishlive.broker"] = {
    connect_signal = function(name, fn)
        broker_signals[name] = broker_signals[name] or {}
        broker_signals[name][fn] = true
    end,
    disconnect_signal = function(name, fn)
        if broker_signals[name] then broker_signals[name][fn] = nil end
    end,
}

-- =========================================================================
-- Load module
-- =========================================================================

local fmenu = require("fishlive.menu")

-- =========================================================================
-- Test helpers
-- =========================================================================

local pass_count, fail_count = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        pass_count = pass_count + 1
        io.write("  PASS  " .. name .. "\n")
    else
        fail_count = fail_count + 1
        io.write("  FAIL  " .. name .. "\n")
        io.write("        " .. tostring(err) .. "\n")
    end
end

local function eq(a, b, msg)
    if a ~= b then error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2) end
end

local function neq(a, b, msg)
    if a == b then error(string.format("%s: expected not %s", msg or "neq", tostring(a)), 2) end
end

local function is_true(v, msg)
    if v ~= true then error(string.format("%s: expected true, got %s", msg or "is_true", tostring(v)), 2) end
end

local function is_false(v, msg)
    if v ~= false then error(string.format("%s: expected false, got %s", msg or "is_false", tostring(v)), 2) end
end

local function is_nil(v, msg)
    if v ~= nil then error(string.format("%s: expected nil, got %s", msg or "is_nil", tostring(v)), 2) end
end

local function is_not_nil(v, msg)
    if v == nil then error((msg or "is_not_nil") .. ": expected non-nil", 2) end
end

-- =========================================================================
-- Tests
-- =========================================================================

print("\n=== menu.new ===")

test("creates a menu with static items", function()
    local m = fmenu.new({
        items = {
            { icon = "A", label = "Alpha", on_activate = function() end },
            { icon = "B", label = "Beta" },
        },
    })
    is_not_nil(m, "menu")
    eq(m._focused_index, 0, "focused_index")
    is_false(m._just_closed, "_just_closed")
end)

test("creates a menu with items_source (dynamic)", function()
    local call_count = 0
    local m = fmenu.new({
        items_source = function()
            call_count = call_count + 1
            return {{ icon = "D", label = "Dynamic " .. call_count }}
        end,
    })
    eq(call_count, 0, "not called yet")
    local items = m:_resolve_items()
    eq(call_count, 1, "called once")
    eq(#items, 1, "one item")
    eq(items[1].label, "Dynamic 1", "label")
end)

test("returns empty table when no items configured", function()
    local m = fmenu.new({})
    local items = m:_resolve_items()
    eq(#items, 0, "empty")
end)

print("\n=== theme broker lifecycle ===")

test("registers a theme signal on creation", function()
    local m = fmenu.new({ items = {} })
    is_not_nil(m._theme_fn, "theme_fn")
    is_true(broker_signals["data::theme"][m._theme_fn] == true, "registered")
end)

test("disconnects theme signal on destroy", function()
    local m = fmenu.new({ items = {} })
    local fn = m._theme_fn
    m:destroy()
    is_nil(m._theme_fn, "theme_fn nil")
    is_true(not (broker_signals["data::theme"] and broker_signals["data::theme"][fn]), "disconnected")
end)

test("cleans up popup and layout on destroy", function()
    local m = fmenu.new({ items = {} })
    m:destroy()
    is_nil(m._popup, "popup")
    is_nil(m._layout, "layout")
    eq(#m._rows, 0, "rows empty")
end)

print("\n=== keyboard navigation ===")

local function make_nav_menu()
    local m = fmenu.new({
        items = {
            { icon = "A", label = "Alpha", on_activate = function() end },
            { separator = true },
            { icon = "B", label = "Beta", on_activate = function() end },
            { icon = "C", label = "Gamma", on_activate = function() end },
        },
    })
    m:_ensure_popup()
    m:_rebuild()
    m._focused_index = 0
    return m
end

test("builds correct number of rows", function()
    local m = make_nav_menu()
    eq(#m._rows, 4, "4 rows")
end)

test("assigns sequential nav indices skipping separators", function()
    local m = make_nav_menu()
    local indices = {}
    for _, row in ipairs(m._rows) do
        if not row.is_separator then indices[#indices + 1] = row.index end
    end
    eq(#indices, 3, "3 nav items")
    eq(indices[1], 1); eq(indices[2], 2); eq(indices[3], 3)
end)

test("separator rows have is_separator=true", function()
    local m = make_nav_menu()
    local sep_count = 0
    for _, row in ipairs(m._rows) do
        if row.is_separator then sep_count = sep_count + 1 end
    end
    eq(sep_count, 1, "1 separator")
end)

test("focus_next wraps from end to start", function()
    local m = make_nav_menu()
    m._focused_index = 3
    m:_focus_next()
    eq(m._focused_index, 1, "wrapped to 1")
end)

test("focus_next advances from 0 to 1", function()
    local m = make_nav_menu()
    m:_focus_next()
    eq(m._focused_index, 1, "advanced to 1")
end)

test("focus_prev wraps from 1 to end", function()
    local m = make_nav_menu()
    m._focused_index = 1
    m:_focus_prev()
    eq(m._focused_index, 3, "wrapped to 3")
end)

test("focus_prev from 0 goes to end", function()
    local m = make_nav_menu()
    m:_focus_prev()
    eq(m._focused_index, 3, "went to 3")
end)

test("activate_focused does nothing when index is 0", function()
    local m = make_nav_menu()
    m:_activate_focused()  -- should not crash
end)

test("activate_focused calls on_activate", function()
    local m = make_nav_menu()
    local activated = false
    m._rows[1].item.on_activate = function() activated = true end
    m._focused_index = 1
    m._popup.visible = true
    m:_activate_focused()
    is_true(activated, "activated")
end)

test("handles empty items gracefully", function()
    local empty = fmenu.new({ items = {} })
    empty:_ensure_popup()
    empty:_rebuild()
    empty:_focus_next()
    empty:_focus_prev()
    empty:_activate_focused()
    eq(#empty._rows, 0, "no rows")
end)

print("\n=== toggle and debounce ===")

test("toggle opens a closed menu", function()
    local m = fmenu.new({
        items = { { icon = "X", label = "Test" } },
        close_on = "mouse_leave",
    })
    m:toggle()
    is_true(m._popup.visible, "visible")
end)

test("toggle closes an open menu", function()
    local m = fmenu.new({
        items = { { icon = "X", label = "Test" } },
        close_on = "mouse_leave",
    })
    m:toggle()
    is_true(m._popup.visible, "open")
    m:toggle()
    is_false(m._popup.visible, "closed")
end)

test("_just_closed NOT set for mouse_leave mode", function()
    local m = fmenu.new({
        items = { { icon = "X", label = "Test" } },
        close_on = "mouse_leave",
    })
    m:toggle()
    m:hide()
    is_false(m._just_closed, "not set")
end)

test("_just_closed IS set for escape mode", function()
    local m = fmenu.new({
        items = { { icon = "X", label = "Test" } },
        close_on = "escape",
    })
    m:toggle()
    m:hide()
    is_true(m._just_closed, "is set")
end)

test("toggle blocks re-open when _just_closed", function()
    local m = fmenu.new({
        items = { { icon = "X", label = "Test" } },
        close_on = "escape",
    })
    m:toggle()   -- open
    m:hide()     -- close, sets _just_closed
    m:toggle()   -- should NOT re-open
    is_false(m._popup.visible, "blocked")
end)

print("\n=== _ensure_popup ===")

test("creates popup only once", function()
    local m = fmenu.new({ items = {} })
    m:_ensure_popup()
    local p1 = m._popup
    m:_ensure_popup()
    eq(m._popup, p1, "same popup")
end)

print("\n=== click-outside ===")

test("registers only button-1 (not button-3)", function()
    local m = fmenu.new({
        items = { { icon = "X", label = "Test" } },
        close_on = "escape",
    })
    m:_start_click_outside()
    is_not_nil(m._root_btn, "btn1 registered")
    is_nil(m._root_btn_r, "btn3 not registered")
    m:_stop_click_outside()
    is_nil(m._root_btn, "btn1 cleaned up")
end)

print("\n=== hide ===")

test("safe to call multiple times", function()
    local m = fmenu.new({
        items = { { icon = "X", label = "Test" } },
        close_on = "escape",
    })
    m:toggle()
    m:hide()
    m:hide()
    is_false(m._popup.visible, "still closed")
end)

test("safe to call before show", function()
    local m = fmenu.new({ items = { { icon = "X", label = "Test" } } })
    m:hide()  -- no popup yet
end)

test("cleans up mouse_leave signals", function()
    local m = fmenu.new({
        items = { { icon = "X", label = "Test" } },
        close_on = "mouse_leave",
    })
    m:toggle()
    is_not_nil(m._mouse_leave_fn, "leave fn")
    is_not_nil(m._mouse_enter_fn, "enter fn")
    m:hide()
    is_nil(m._mouse_leave_fn, "leave cleaned")
    is_nil(m._mouse_enter_fn, "enter cleaned")
    is_nil(m._ml_timer, "timer cleaned")
end)

print("\n=== xml escaping ===")

test("escapes ampersand in label", function()
    local m = fmenu.new({
        items = { { icon = "X", label = "Rebuild & Restart" } },
    })
    m:_ensure_popup()
    m:_rebuild()
    local row = m._rows[1]
    is_not_nil(row.label, "label widget")
    local markup = row.label.markup
    assert(markup:find("&amp;"), "Expected &amp; in: " .. markup)
    assert(not markup:find("& R"), "Raw & should not appear in: " .. markup)
end)

print("\n=== checked items ===")

test("checked_fn evaluated during rebuild", function()
    local checked = true
    local m = fmenu.new({
        items = {{ icon = "X", label = "Toggle",
                   checked_fn = function() return checked end }},
    })
    m:_ensure_popup()
    m:_rebuild()
    is_false(m._rows[1].is_separator, "not separator")
    checked = false
    m:_rebuild()
    eq(#m._rows, 1, "still 1 row")
end)

-- =========================================================================
-- Summary
-- =========================================================================

print(string.format("\n=== Results: %d passed, %d failed ===\n",
    pass_count, fail_count))

if fail_count > 0 then os.exit(1) end
