---------------------------------------------------------------------------
--- Test: XWayland override-redirect surfaces (issue #415 and the rewrite)
--
-- Override-redirect (OR) X11 surfaces -- Wine menus, Steam popups, Qt
-- tooltips -- are not window-manager clients. They have no tags, no layout,
-- no rules and no Lua object; they live in their own scene layer
-- (LyrUnmanaged) above everything except the session lock.
--
-- History: they used to be managed as clients, which produced two bugs.
-- #415: stack_refresh() ran them through client_layer_translator(), which
-- dropped them into LyrTile below their parent. The follow-up: even after
-- being pinned to LyrOverlay, the drawin raise loop in the same function put
-- the wibar, notifications and any ontop client on top of an open menu,
-- because LyrOverlay was shared.
--
-- This test asserts, via root.xwayland_unmanaged():
--  1. an OR surface lands in LyrUnmanaged on map,
--  2. it stays there across stack_refresh() cycles driven by parent
--     property toggles,
--  3. an ontop drawin created over it does NOT end up above it,
--  4. it never appears in client.get() and emits no mouse::enter.
---------------------------------------------------------------------------

local runner = require("_runner")
local x11_client = require("_x11_client")
local utils = require("_utils")

if utils.is_headless() then
    io.stderr:write("SKIP: override_redirect test requires visual mode (HEADLESS=0)\n")
    io.stderr:write("Test finished successfully.\n")
    awesome.quit()
    return
end

if not x11_client.is_available() then
    io.stderr:write("SKIP: no X11 application available (install xterm)\n")
    io.stderr:write("Test finished successfully.\n")
    awesome.quit()
    return
end

local python3_check = os.execute("which python3 >/dev/null 2>&1")
if not python3_check then
    io.stderr:write("SKIP: python3 not available for X11 helper\n")
    io.stderr:write("Test finished successfully.\n")
    awesome.quit()
    return
end

local awful = require("awful")
local wibox = require("wibox")

local PARENT_CLASS = "or_stacking_parent"
local POPUP_CLASS  = "or_stacking_popup"

local script_dir = debug.getinfo(1, "S").source:match("@(.*/)")
local helper_path = script_dir .. "helpers/x11_override_redirect.py"

local parent_client   = nil
local popup_window    = nil
local popup_pid       = nil
local ontop_box       = nil
local mouse_enter_windows = {}

client.connect_signal("request::manage", function(c)
    if x11_client.is_xwayland(c) and
       (c.class == PARENT_CLASS or c.class == PARENT_CLASS:lower()) then
        parent_client = c
        io.stderr:write(string.format(
            "[TEST] Managed parent client appeared: class=%s\n", tostring(c.class)
        ))
    end
end)

-- An OR surface must never reach the Lua client model, so it must never be
-- able to emit mouse::enter either.
client.connect_signal("mouse::enter", function(c)
    mouse_enter_windows[#mouse_enter_windows + 1] = c.window or -1
end)

--- Find the mapped unmanaged surface, if any.
local function find_mapped_unmanaged()
    for _, u in ipairs(root.xwayland_unmanaged()) do
        if u.mapped then return u end
    end
    return nil
end

local function unmanaged_by_window(window)
    for _, u in ipairs(root.xwayland_unmanaged()) do
        if u.window == window then return u end
    end
    return nil
end

local function assert_popup_in_layer(context)
    local u = unmanaged_by_window(popup_window)
    assert(u, context .. ": popup vanished from root.xwayland_unmanaged()")
    assert(u.mapped, context .. ": popup should still be mapped")
    assert(u.layer == "unmanaged", string.format(
        "%s: expected popup in LyrUnmanaged, got %q", context, tostring(u.layer)
    ))
    io.stderr:write(string.format("[TEST] PASS %s: popup is in %s layer\n",
        context, u.layer))
end

local steps = {
    -- Step 1: Spawn managed X11 parent client
    function(count)
        if count == 1 then
            io.stderr:write("[TEST] Spawning managed X11 parent client...\n")
            x11_client(PARENT_CLASS)
        end

        if parent_client then return true end

        if count > 80 then
            error("Managed X11 parent client did not appear within timeout")
        end
        return nil
    end,

    -- Step 2: Make the parent floating, so it sits in LyrFloat. The #415
    -- regression surfaced the popup below exactly this.
    function()
        parent_client.floating = true
        assert(parent_client.floating, "Parent should be floating")
        io.stderr:write("[TEST] Parent set floating\n")
        return true
    end,

    -- Step 3: Spawn the override_redirect popup.
    function(count)
        if count == 1 then
            io.stderr:write("[TEST] Spawning override_redirect popup helper...\n")
            popup_pid = awful.spawn("python3 " .. helper_path ..
                " " .. POPUP_CLASS .. " 50 50 200 150")

            if not popup_pid or type(popup_pid) ~= "number" or popup_pid <= 0 then
                error("Failed to spawn override_redirect helper: " ..
                    tostring(popup_pid))
            end
        end

        local u = find_mapped_unmanaged()
        if u then
            popup_window = u.window
            io.stderr:write(string.format(
                "[TEST] Override-redirect popup appeared: window=%d %dx%d+%d+%d\n",
                u.window, u.width, u.height, u.x, u.y))
            return true
        end

        if count > 80 then
            error("Override-redirect popup did not appear within timeout")
        end
        return nil
    end,

    -- Step 4: Right after map it must be in LyrUnmanaged.
    function()
        assert_popup_in_layer("after-map")
        return true
    end,

    -- Step 5: The popup is not a client, and produced no mouse::enter.
    function()
        for _, c in ipairs(client.get()) do
            assert(c.window ~= popup_window, string.format(
                "override-redirect window %d must not appear in client.get()",
                popup_window))
        end
        for _, window in ipairs(mouse_enter_windows) do
            assert(window ~= popup_window,
                "override-redirect window must not emit mouse::enter")
        end
        io.stderr:write("[TEST] PASS: popup absent from client.get(), no mouse::enter\n")
        return true
    end,

    -- Step 6: Drive stack_refresh() through parent property toggles.
    function()
        local toggles = {
            { prop = "ontop",      sequence = { true, false } },
            { prop = "above",      sequence = { true, false } },
            { prop = "floating",   sequence = { false, true } },
            { prop = "fullscreen", sequence = { true, false } },
        }
        for _, t in ipairs(toggles) do
            io.stderr:write("[TEST] Toggling parent " .. t.prop .. "...\n")
            for _, value in ipairs(t.sequence) do
                parent_client[t.prop] = value
                assert_popup_in_layer(
                    string.format("after-%s-%s", t.prop, tostring(value)))
            end
        end
        return true
    end,

    -- Step 7: An ontop drawin must not be raised above the popup. Before the
    -- dedicated layer, stack_refresh()'s drawin loop raised the wibar and
    -- notifications over open menus.
    function()
        ontop_box = wibox {
            x = 60, y = 60, width = 150, height = 100,
            visible = true, ontop = true, bg = "#ff0000",
        }
        assert_popup_in_layer("after-ontop-drawin")

        -- The drawin is in LyrOverlay; the popup is in LyrUnmanaged, which is
        -- strictly above it. Verifying the layer identity is enough: nothing
        -- else is ever parented into LyrUnmanaged.
        assert(ontop_box.ontop, "test drawin should be ontop")
        io.stderr:write("[TEST] PASS: ontop drawin cannot outrank the popup\n")
        return true
    end,

    -- Step 8: Cleanup
    function()
        if ontop_box then
            ontop_box.visible = false
            ontop_box = nil
        end
        if popup_pid and popup_pid > 0 then
            awful.spawn("kill " .. tostring(popup_pid))
        end
        if parent_client and parent_client.valid then
            parent_client:kill()
        end
        return true
    end,
}

runner.run_steps(steps)
