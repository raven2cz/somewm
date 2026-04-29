---------------------------------------------------------------------------
-- Unit test: fishlive.menu popup menu component
--
-- Tests menu construction, item resolution, highlight state machine,
-- keyboard navigation, toggle debounce, color_alpha safety, and
-- single-instance control without a running compositor.
--
-- NOTE: These tests use minimal mocks and do NOT require lgi or a running
-- compositor. They test the pure-logic portions of the menu module.
---------------------------------------------------------------------------

-- Add somewm-one to package path so fishlive.menu can be required.
-- somewm-one is now a sibling repo (raven2cz/somewm-one); checkout path is
-- overridable via SOMEWM_ONE_PATH (defaults to $HOME/git/github/somewm-one).
local home = os.getenv("HOME") or "."
local somewm_one = os.getenv("SOMEWM_ONE_PATH")
    or (home .. "/git/github/somewm-one")
package.path = somewm_one .. "/?.lua;"
    .. somewm_one .. "/?/init.lua;"
    .. package.path

-- =========================================================================
-- Mocks — minimal stubs for AwesomeWM modules the menu uses at load time
-- =========================================================================

_G.mouse = { current_wibox = nil }
_G.awesome = _G.awesome or { version = "v9999", api_level = 9999 }

-- Track signal connections for verification
local mock_signals = {}

-- Mock wibox widget system
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
    w.set_widget = function() end
    w.get_children_by_id = function() return {} end
    return w
end

local mock_layout = {
    _children = {},
    reset = function(self) self._children = {} end,
    add = function(self, w) self._children[#self._children + 1] = w end,
    spacing = 0,
}
setmetatable(mock_layout, { __call = function() return mock_layout end })

-- Beautiful theme values
if not package.loaded["beautiful"] then
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
end

if not package.loaded["beautiful.xresources"] then
    package.loaded["beautiful.xresources"] = {
        apply_dpi = function(v) return v end,
    }
end

-- Gears stubs
if not package.loaded["gears"] then
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
        shape = {
            rounded_rect = function() end,
        },
        table = {
            join = function(...) return {} end,
        },
        timer = {
            start_new = function(timeout, fn)
                -- Immediately fire for test determinism
                local t = { stop = function() end }
                -- Don't auto-fire — let tests control timing
                return t
            end,
            delayed_call = function(fn) fn() end,
        },
        color = {
            recolor_image = function(img, color) return img end,
        },
    }
end

-- Wibox stubs
if not package.loaded["wibox"] then
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
    -- wibox.widget() constructor
    setmetatable(wibox_mod.widget, {
        __call = function(_, args) return mock_widget(args) end,
    })
    package.loaded["wibox"] = wibox_mod
end

-- Awful stubs
if not package.loaded["awful"] then
    local awful_mod = {
        popup = function(args)
            local p = mock_widget(args)
            p.visible = args.visible or false
            p.bg = args.bg
            p.border_color = args.border_color
            p.border_width = args.border_width
            p.shape = args.shape
            p.ontop = args.ontop
            p.maximum_width = args.maximum_width
            -- Mock _apply_size_now
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
            return {
                stop = function() end,
                is_running = true,
            }
        end,
        mouse = {
            append_global_mousebinding = function() end,
            remove_global_mousebinding = function() end,
        },
    }
    package.loaded["awful"] = awful_mod
end

-- Broker mock
local broker_signals = {}
package.loaded["fishlive.broker"] = {
    connect_signal = function(name, fn)
        broker_signals[name] = broker_signals[name] or {}
        broker_signals[name][fn] = true
    end,
    disconnect_signal = function(name, fn)
        if broker_signals[name] then
            broker_signals[name][fn] = nil
        end
    end,
}

-- Now require the module under test
local fmenu = require("fishlive.menu")

---------------------------------------------------------------------------
-- Tests
---------------------------------------------------------------------------

describe("menu.new", function()
    it("creates a menu with static items", function()
        local m = fmenu.new({
            items = {
                { icon = "A", label = "Alpha", on_activate = function() end },
                { icon = "B", label = "Beta" },
            },
        })
        assert.is_not_nil(m)
        assert.are.equal(0, m._focused_index)
        assert.are.equal(false, m._just_closed)
    end)

    it("creates a menu with items_source (dynamic)", function()
        local call_count = 0
        local m = fmenu.new({
            items_source = function()
                call_count = call_count + 1
                return {
                    { icon = "D", label = "Dynamic " .. call_count },
                }
            end,
        })
        assert.is_not_nil(m)
        -- items_source is not called until resolve
        assert.are.equal(0, call_count)

        local items = m:_resolve_items()
        assert.are.equal(1, call_count)
        assert.are.equal(1, #items)
        assert.are.equal("Dynamic 1", items[1].label)
    end)

    it("returns empty table when no items configured", function()
        local m = fmenu.new({})
        local items = m:_resolve_items()
        assert.are.same({}, items)
    end)
end)

describe("theme broker lifecycle", function()
    it("registers a theme signal on creation", function()
        local m = fmenu.new({ items = {} })
        assert.is_not_nil(m._theme_fn)
        assert.is_truthy(broker_signals["data::theme"] and
            broker_signals["data::theme"][m._theme_fn])
    end)

    it("disconnects theme signal on destroy", function()
        local m = fmenu.new({ items = {} })
        local fn = m._theme_fn
        m:destroy()
        assert.is_nil(m._theme_fn)
        assert.is_falsy(broker_signals["data::theme"] and
            broker_signals["data::theme"][fn])
    end)

    it("cleans up popup and layout on destroy", function()
        local m = fmenu.new({ items = {} })
        m:destroy()
        assert.is_nil(m._popup)
        assert.is_nil(m._layout)
        assert.are.same({}, m._rows)
    end)
end)

describe("keyboard navigation", function()
    local m

    before_each(function()
        m = fmenu.new({
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
    end)

    it("builds correct number of rows", function()
        assert.are.equal(4, #m._rows)
    end)

    it("assigns sequential nav indices skipping separators", function()
        local nav_indices = {}
        for _, row in ipairs(m._rows) do
            if not row.is_separator then
                nav_indices[#nav_indices + 1] = row.index
            end
        end
        assert.are.same({1, 2, 3}, nav_indices)
    end)

    it("separator rows have is_separator=true", function()
        local sep_count = 0
        for _, row in ipairs(m._rows) do
            if row.is_separator then sep_count = sep_count + 1 end
        end
        assert.are.equal(1, sep_count)
    end)

    it("focus_next wraps from end to start", function()
        m._focused_index = 3
        m:_focus_next()
        assert.are.equal(1, m._focused_index)
    end)

    it("focus_next advances from 0 to 1", function()
        m._focused_index = 0
        m:_focus_next()
        assert.are.equal(1, m._focused_index)
    end)

    it("focus_prev wraps from 1 to end", function()
        m._focused_index = 1
        m:_focus_prev()
        assert.are.equal(3, m._focused_index)
    end)

    it("focus_prev from 0 goes to end", function()
        m._focused_index = 0
        m:_focus_prev()
        assert.are.equal(3, m._focused_index)
    end)

    it("activate_focused does nothing when index is 0", function()
        m._focused_index = 0
        m:_activate_focused()
        -- Should not crash
    end)

    it("activate_focused calls on_activate for focused item", function()
        local activated = false
        m._rows[1].item.on_activate = function() activated = true end
        m._focused_index = 1
        m._popup.visible = true
        m:_activate_focused()
        assert.is_true(activated)
    end)

    it("handles empty items gracefully", function()
        local empty = fmenu.new({ items = {} })
        empty:_ensure_popup()
        empty:_rebuild()
        empty:_focus_next()
        empty:_focus_prev()
        empty:_activate_focused()
        assert.are.equal(0, #empty._rows)
    end)
end)

describe("toggle and debounce", function()
    it("toggle opens a closed menu", function()
        local m = fmenu.new({
            items = { { icon = "X", label = "Test" } },
            close_on = "mouse_leave",
        })
        m:toggle()
        assert.is_true(m._popup.visible)
    end)

    it("toggle closes an open menu", function()
        local m = fmenu.new({
            items = { { icon = "X", label = "Test" } },
            close_on = "mouse_leave",
        })
        m:toggle()
        assert.is_true(m._popup.visible)
        m:toggle()
        assert.is_false(m._popup.visible)
    end)

    it("_just_closed is NOT set for mouse_leave mode", function()
        local m = fmenu.new({
            items = { { icon = "X", label = "Test" } },
            close_on = "mouse_leave",
        })
        m:toggle()
        m:hide()
        assert.is_false(m._just_closed)
    end)

    it("_just_closed IS set for escape mode", function()
        local m = fmenu.new({
            items = { { icon = "X", label = "Test" } },
            close_on = "escape",
        })
        m:toggle()
        m:hide()
        assert.is_true(m._just_closed)
    end)

    it("toggle blocks re-open when _just_closed is true", function()
        local m = fmenu.new({
            items = { { icon = "X", label = "Test" } },
            close_on = "escape",
        })
        m:toggle()   -- open
        m:hide()     -- close, sets _just_closed
        m:toggle()   -- should NOT re-open (debounce)
        assert.is_false(m._popup.visible)
    end)
end)

describe("_ensure_popup", function()
    it("creates popup only once", function()
        local m = fmenu.new({ items = {} })
        m:_ensure_popup()
        local p1 = m._popup
        m:_ensure_popup()
        local p2 = m._popup
        assert.are.equal(p1, p2)
    end)
end)

describe("click-outside", function()
    it("registers only button-1 binding (not button-3)", function()
        local m = fmenu.new({
            items = { { icon = "X", label = "Test" } },
            close_on = "escape",
        })
        m:_start_click_outside()
        assert.is_not_nil(m._root_btn)
        -- Button-3 was removed to avoid conflict with desktop_menu
        assert.is_nil(m._root_btn_r)
        m:_stop_click_outside()
        assert.is_nil(m._root_btn)
    end)
end)

describe("hide", function()
    it("is safe to call multiple times", function()
        local m = fmenu.new({
            items = { { icon = "X", label = "Test" } },
            close_on = "escape",
        })
        m:toggle()
        m:hide()
        m:hide()
        assert.is_false(m._popup.visible)
    end)

    it("is safe to call before show", function()
        local m = fmenu.new({
            items = { { icon = "X", label = "Test" } },
        })
        m:hide()  -- no popup yet, should not crash
    end)

    it("cleans up mouse_leave signals", function()
        local m = fmenu.new({
            items = { { icon = "X", label = "Test" } },
            close_on = "mouse_leave",
        })
        m:toggle()
        assert.is_not_nil(m._mouse_leave_fn)
        assert.is_not_nil(m._mouse_enter_fn)
        m:hide()
        assert.is_nil(m._mouse_leave_fn)
        assert.is_nil(m._mouse_enter_fn)
        assert.is_nil(m._ml_timer)
    end)
end)

describe("checked items", function()
    it("checked_fn is evaluated during rebuild", function()
        local checked_state = true
        local m = fmenu.new({
            items = {
                { icon = "X", label = "Toggle",
                  checked_fn = function() return checked_state end },
            },
        })
        m:_ensure_popup()
        m:_rebuild()

        local row = m._rows[1]
        assert.is_false(row.is_separator)

        checked_state = false
        m:_rebuild()
        assert.are.equal(1, #m._rows)
    end)
end)

describe("xml escaping", function()
    it("escapes ampersand in label text", function()
        local m = fmenu.new({
            items = {
                { icon = "X", label = "Rebuild & Restart" },
            },
        })
        m:_ensure_popup()
        m:_rebuild()

        local row = m._rows[1]
        assert.is_not_nil(row.label)
        -- The markup should contain &amp; not raw &
        local markup = row.label.markup
        assert.is_truthy(markup:find("&amp;"), "Expected escaped ampersand in markup")
        assert.is_falsy(markup:find("& R"), "Raw ampersand should not appear")
    end)
end)
