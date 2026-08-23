---------------------------------------------------------------------------
--- Test: override-redirect surface lifecycle events
--
-- Two events the compositor used to ignore completely:
--
--  set_geometry           Xwayland moves override-redirect windows on its
--                         own and only reports it afterwards. Wine submenus
--                         and menus flipped to fit the screen do this, and
--                         without tracking it the popup stays painted where
--                         it first appeared.
--
--  set_override_redirect  A live window can change role. Before, the
--                         classification made at create time was permanent:
--                         a window that stopped being override-redirect
--                         never became a managed client.
--
-- The scene node position is checked, not just the X11 geometry: the point
-- of the fix is what gets painted.
---------------------------------------------------------------------------

local runner = require("_runner")
local utils = require("_utils")
local awful = require("awful")

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

local script_dir = debug.getinfo(1, "S").source:match("@(.*/)")
local helper = script_dir .. "helpers/x11_or_scenarios.py"

local START_X, START_Y = 100, 100
local MOVE_X,  MOVE_Y  = 400, 300

local move_pid, flip_pid = nil, nil
local move_steps, flip_steps = {}, {}

local function spawn_scenario(mode, class, args, steps, on_pid)
    local cmd = { "python3", helper, mode, class }
    for _, a in ipairs(args) do cmd[#cmd + 1] = tostring(a) end

    awful.spawn.with_line_callback(cmd, {
        stdout = function(line)
            io.stderr:write("[HELPER " .. mode .. "] " .. line .. "\n")
            local pid = line:match("^pid: (%d+)")
            if pid then on_pid(tonumber(pid)) end
            local step, window = line:match("^step: (%S+) (%d+)")
            if step then steps[step] = tonumber(window) end
        end,
        stderr = function(line)
            io.stderr:write("[HELPER " .. mode .. " ERR] " .. line .. "\n")
        end,
    })
end

local function unmanaged_by_class(class)
    for _, u in ipairs(root.xwayland_unmanaged()) do
        if u.class == class and u.mapped then return u end
    end
    return nil
end

local steps = {
    -- Step 1: map an override-redirect window at a known position
    function(count)
        if count == 1 then
            spawn_scenario("move", "or_move", { START_X, START_Y, 200, 150,
                MOVE_X, MOVE_Y }, move_steps,
                function(pid) move_pid = pid end)
        end

        local u = unmanaged_by_class("or_move")
        if u then
            assert(u.layer == "unmanaged",
                "popup should map into LyrUnmanaged, got " .. tostring(u.layer))
            assert(u.scene_x == START_X and u.scene_y == START_Y, string.format(
                "scene node should be at %d,%d, got %d,%d",
                START_X, START_Y, u.scene_x, u.scene_y))
            io.stderr:write("[TEST] PASS: mapped at the requested position\n")
            return true
        end

        if count > 100 then error("override-redirect window never mapped") end
        return nil
    end,

    -- Step 2: let the helper move it, then check the scene node followed
    function(count)
        if count == 1 then
            assert(move_pid, "helper pid unknown")
            awful.spawn({ "kill", "-USR1", tostring(move_pid) })
            return nil
        end

        local u = unmanaged_by_class("or_move")
        assert(u, "popup disappeared during the move")

        if u.scene_x == MOVE_X and u.scene_y == MOVE_Y then
            assert(u.x == MOVE_X and u.y == MOVE_Y,
                "X11 geometry should agree with the scene node")
            io.stderr:write("[TEST] PASS: scene node followed set_geometry\n")
            return true
        end

        if count > 100 then
            error(string.format(
                "scene node did not follow the move: expected %d,%d got %d,%d "
                .. "(X11 says %d,%d) -- set_geometry not handled",
                MOVE_X, MOVE_Y, u.scene_x, u.scene_y, u.x, u.y))
        end
        return nil
    end,

    -- Step 3: clean up the move scenario
    function()
        if move_pid then awful.spawn({ "kill", tostring(move_pid) }) end
        return true
    end,

    -- Step 4: map an override-redirect window for the flip scenario
    function(count)
        if count == 1 then
            spawn_scenario("flip", "or_flip", { 150, 150, 180, 120 },
                flip_steps, function(pid) flip_pid = pid end)
        end

        if unmanaged_by_class("or_flip") then
            io.stderr:write("[TEST] PASS: flip candidate mapped as unmanaged\n")
            return true
        end

        if count > 100 then error("flip scenario window never mapped") end
        return nil
    end,

    -- Step 5: clearing override_redirect must hand the surface to the
    -- managed path: it leaves root.xwayland_unmanaged() and shows up as a
    -- client.
    function(count)
        if count == 1 then
            assert(flip_pid, "helper pid unknown")
            awful.spawn({ "kill", "-USR1", tostring(flip_pid) })
            return nil
        end

        local still_unmanaged = unmanaged_by_class("or_flip")
        local as_client = nil
        for _, c in ipairs(client.get()) do
            if c.class == "or_flip" then as_client = c end
        end

        if not still_unmanaged and as_client then
            io.stderr:write("[TEST] PASS: surface moved to the managed path\n")
            return true
        end

        if count > 100 then
            error(string.format(
                "override_redirect flip not handled: unmanaged=%s client=%s",
                tostring(still_unmanaged ~= nil), tostring(as_client ~= nil)))
        end
        return nil
    end,

    -- Step 6: cleanup
    function()
        if flip_pid then awful.spawn({ "kill", tostring(flip_pid) }) end
        return true
    end,
}

runner.run_steps(steps)
