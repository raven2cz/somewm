-- Test: transient stacking across different scene layers.
--
-- Bug: Opening transient windows (e.g. Thunar F1 help dialogs) caused a
-- compositor crash:
--   wlr_scene_node_place_above: Assertion `node->parent == sibling->parent' failed
--
-- The crash scenario:
-- 1. Parent client gets above=true (reparented to LyrTop)
-- 2. Its transient child stays in LyrTile
-- 3. stack_refresh() calls wlr_scene_node_place_above with nodes in different
--    scene layers -> assertion failure
--
-- The fix in stack.c:stack_client_relative() reparents transients to their
-- parent's scene layer before calling wlr_scene_node_place_above.
--
-- This test verifies the fix by reproducing the exact crash scenario:
-- parent with above=true + transient child spawned after.

local runner = require("_runner")
local utils = require("_utils")
local awful = require("awful")

-- Path to test-transient-client (built by meson)
local TEST_TRANSIENT_CLIENT = "./build-test/test-transient-client"

-- Check if test-transient-client exists
local function is_test_client_available()
    local f = io.open(TEST_TRANSIENT_CLIENT, "r")
    if f then
        f:close()
        return true
    end
    return false
end

if not is_test_client_available() then
    io.stderr:write("SKIP: test-transient-client not found (run make build-test)\n")
    io.stderr:write("Test finished successfully.\n")
    awesome.quit()
    return
end

local parent_client
local child_client
local proc_pid

local steps = {
    -- Step 1: Spawn test-transient-client (creates parent toplevel)
    function(count)
        if count == 1 then
            io.stderr:write("[TEST] Spawning test-transient-client...\n")
            proc_pid = awful.spawn(TEST_TRANSIENT_CLIENT)
        end

        -- Wait for parent client to appear
        parent_client = utils.find_client_by_class("transient_test_parent")
        if parent_client then
            io.stderr:write("[TEST] Parent client appeared\n")
            return true
        end
    end,

    -- Step 2: Set parent.above = true (moves parent to LyrTop)
    -- This is the key setup: parent is now in a different scene layer than
    -- where the child will initially be placed.
    function()
        io.stderr:write("[TEST] Setting parent.above = true\n")
        parent_client.above = true
        assert(parent_client.above, "parent.above should be true")
        return true
    end,

    -- Step 3: Send SIGUSR1 to trigger child creation
    function(count)
        if count == 1 then
            io.stderr:write(string.format(
                "[TEST] Sending SIGUSR1 to pid %s\n", tostring(proc_pid)))
            awesome.kill(proc_pid, 10) -- SIGUSR1 = 10
        end

        -- Wait for the transient child to appear.
        -- We find it by transient_for relationship rather than class, because
        -- the transient path in mapnotify() skips property_register_wayland_listeners()
        -- so the child's class is not populated from app_id.
        for _, c in ipairs(client.get()) do
            if c.transient_for == parent_client then
                child_client = c
                io.stderr:write("[TEST] Child client appeared (transient of parent)\n")
                return true
            end
        end
    end,

    -- Step 4: Exercise more stack_refresh cycles to stress the fix.
    -- Toggle ontop which causes additional reparenting + stacking.
    -- Without the fix, any of these could trigger the assertion failure.
    function()
        io.stderr:write("[TEST] Toggling parent.ontop to stress stack_refresh...\n")

        parent_client.ontop = true
        assert(parent_client.ontop, "parent.ontop should be true")

        parent_client.ontop = false
        assert(not parent_client.ontop, "parent.ontop should be false")

        -- Also toggle above back and forth
        parent_client.above = false
        parent_client.above = true

        io.stderr:write("[TEST] PASS: stack_refresh survived all toggles (no crash)\n")
        return true
    end,

    -- Step 5: A floating transient belongs in LyrFloat, not in its parent's
    -- layer.
    --
    -- Transients used to be forced into whatever layer the parent lived in,
    -- on the theory that they must stack directly above it. For a floating
    -- dialog of a tiled parent that meant LyrTile: below every unrelated
    -- floating window, and unraisable -- clicking it gave it focus and
    -- changed nothing on screen. Sierra Chart's dialogs are the reproducer.
    function(count)
        if count == 1 then
            parent_client.above = false
            parent_client.ontop = false
            parent_client.floating = false
            child_client.floating = true
            assert(child_client.floating, "child should be floating")
            -- stack_refresh() runs on the next refresh cycle, so give it one.
            return nil
        end

        if parent_client._scene_layer ~= "tile" then
            if count > 20 then
                error(string.format("parent never returned to LyrTile, got %q",
                    tostring(parent_client._scene_layer)))
            end
            return nil
        end

        assert(child_client._scene_layer == "float", string.format(
            "floating transient should live in LyrFloat, got %q",
            tostring(child_client._scene_layer)))

        io.stderr:write("[TEST] PASS: floating transient is in LyrFloat\n")
        return true
    end,

    -- Step 6: A non-floating transient still follows its parent, which is
    -- what keeps dialogs of an ontop parent visible.
    function(count)
        if count == 1 then
            child_client.floating = false
            parent_client.ontop = true
            return nil
        end

        if child_client._scene_layer ~= parent_client._scene_layer then
            if count > 20 then
                error(string.format(
                    "non-floating transient should follow its parent: child=%q parent=%q",
                    tostring(child_client._scene_layer),
                    tostring(parent_client._scene_layer)))
            end
            return nil
        end

        io.stderr:write("[TEST] PASS: tiled transient still follows the parent\n")
        parent_client.ontop = false
        return true
    end,

    -- Step 7: Cleanup
    function(count)
        if count == 1 then
            io.stderr:write("[TEST] Cleanup: killing test-transient-client\n")
            if proc_pid then
                awful.spawn("kill " .. proc_pid)
            end
        end

        if #client.get() == 0 then
            io.stderr:write("[TEST] Cleanup: done\n")
            return true
        end

        if count >= 10 then
            io.stderr:write("[TEST] Cleanup: force killing\n")
            if proc_pid then
                os.execute("kill -9 " .. proc_pid .. " 2>/dev/null")
            end
            os.execute("pkill -9 test-transient-client 2>/dev/null")
            return true
        end
    end,
}

runner.run_steps(steps, { kill_clients = false })

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
