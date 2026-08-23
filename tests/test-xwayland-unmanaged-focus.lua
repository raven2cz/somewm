---------------------------------------------------------------------------
--- Test: keyboard focus across an override-redirect menu chain
--
-- X11 menus keep the keyboard while they are open and dismiss themselves on
-- FocusOut, so the compositor has two obligations:
--
--  1. While a menu is up, nothing else may take focus. Sloppy focus reaches
--     the Lua focus path on every pointer motion, and before the guard that
--     was enough to close Wine menus by moving the mouse.
--
--  2. When a submenu closes, focus goes back to the parent menu -- not
--     through the deferred request::focus_restore signal, which could land
--     after the next menu had already opened and steal focus from it.
--
-- Also covers what used to be a dangling pointer: the focus holder going
-- away without a clean unmap.
---------------------------------------------------------------------------

local runner = require("_runner")
local utils = require("_utils")
local awful = require("awful")
local x11_client = require("_x11_client")

if utils.is_headless() then
    io.stderr:write("SKIP: override-redirect tests require visual mode (HEADLESS=0)\n")
    io.stderr:write("Test finished successfully.\n")
    awesome.quit()
    return
end

if not os.execute("python3 -c 'import Xlib' >/dev/null 2>&1") then
    io.stderr:write("SKIP: python-xlib not available\n")
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

local script_dir = debug.getinfo(1, "S").source:match("@(.*/)")
local helper = script_dir .. "helpers/x11_or_scenarios.py"

local CLIENT_CLASS = "or_focus_client"
local chain_pid    = nil
local managed      = nil

client.connect_signal("request::manage", function(c)
    if x11_client.is_xwayland(c) and
       (c.class == CLIENT_CLASS or c.class == CLIENT_CLASS:lower()) then
        managed = c
    end
end)

local function unmanaged_by_class(class)
    for _, u in ipairs(root.xwayland_unmanaged()) do
        if u.class == class and u.mapped then return u end
    end
    return nil
end

local function focused_unmanaged()
    for _, u in ipairs(root.xwayland_unmanaged()) do
        if u.focused then return u end
    end
    return nil
end

local steps = {
    -- Step 1: a managed X11 client to hold focus before any menu opens
    function(count)
        if count == 1 then
            x11_client(CLIENT_CLASS)
        end
        if managed then
            client.focus = managed
            return true
        end
        if count > 80 then error("managed X11 client never appeared") end
        return nil
    end,

    -- Step 2: open the parent menu; it must take the keyboard
    function(count)
        if count == 1 then
            awful.spawn.with_line_callback(
                { "python3", helper, "chain", "or_focus", "120", "120", "200", "150" }, {
                stdout = function(line)
                    io.stderr:write("[HELPER chain] " .. line .. "\n")
                    local pid = line:match("^pid: (%d+)")
                    if pid then chain_pid = tonumber(pid) end
                end,
                stderr = function(line)
                    io.stderr:write("[HELPER chain ERR] " .. line .. "\n")
                end,
            })
        end

        local menu = unmanaged_by_class("or_focus_menu")
        if menu and menu.focused then
            io.stderr:write("[TEST] PASS: parent menu holds the keyboard\n")
            return true
        end

        if count > 100 then
            error("parent menu never took focus (mapped=" ..
                tostring(menu ~= nil) .. ")")
        end
        return nil
    end,

    -- Step 3: with the menu up, a focus request for the client is ignored
    function()
        local before = focused_unmanaged()
        assert(before, "a menu should hold focus here")

        client.focus = managed
        local after = focused_unmanaged()
        assert(after and after.window == before.window,
            "focusing a client while a menu is open must not take the keyboard")

        -- The same path sloppy focus uses.
        managed:activate { context = "mouse_enter", raise = false }
        after = focused_unmanaged()
        assert(after and after.window == before.window,
            "sloppy focus must not close an open menu")

        io.stderr:write("[TEST] PASS: menu keeps focus against client requests\n")
        return true
    end,

    -- Step 4: open the submenu; focus moves to it
    function(count)
        if count == 1 then
            awful.spawn({ "kill", "-USR1", tostring(chain_pid) })
            return nil
        end

        local sub = unmanaged_by_class("or_focus_submenu")
        if sub and sub.focused then
            assert(sub.parent ~= 0,
                "submenu should report its parent (WM_TRANSIENT_FOR)")
            io.stderr:write("[TEST] PASS: submenu took focus\n")
            return true
        end

        if count > 100 then
            error("submenu never took focus (mapped=" .. tostring(sub ~= nil) .. ")")
        end
        return nil
    end,

    -- Step 5: close the submenu; focus returns to the parent menu, not to a
    -- client and not to nothing
    function(count)
        if count == 1 then
            awful.spawn({ "kill", "-USR1", tostring(chain_pid) })
            return nil
        end

        local sub = unmanaged_by_class("or_focus_submenu")
        if sub then
            if count > 100 then error("submenu never unmapped") end
            return nil
        end

        local menu = unmanaged_by_class("or_focus_menu")
        assert(menu, "parent menu should still be mapped")

        if menu.focused then
            io.stderr:write("[TEST] PASS: focus returned to the parent menu\n")
            return true
        end

        if count > 100 then
            error("focus did not return to the parent menu after the submenu closed")
        end
        return nil
    end,

    -- Step 6: kill the helper outright. Both menus disappear without an
    -- orderly teardown; focus must come back to the client and stay usable.
    function(count)
        if count == 1 then
            awful.spawn({ "kill", "-9", tostring(chain_pid) })
            return nil
        end

        if unmanaged_by_class("or_focus_menu") then
            if count > 100 then error("menus never went away after kill -9") end
            return nil
        end

        -- Focus must be grantable again: the old code could leave a dangling
        -- exclusive_focus that blocked every later focus change.
        client.focus = managed
        assert(client.focus == managed,
            "focus must work again after the menu holder died")
        io.stderr:write("[TEST] PASS: focus recovered after an abrupt menu death\n")
        return true
    end,

    -- Step 7: cleanup
    function()
        if managed and managed.valid then managed:kill() end
        return true
    end,
}

runner.run_steps(steps)
