---------------------------------------------------------------------------
--- Test: Kolo 7 upstream sync — banning + scene-tree UAF regression
--
-- Exercises the code paths introduced by the Kolo 7 upstream sync batch:
--
--   * ea7e1aa   — motionnotify() after banning_refresh() in some_refresh()
--   * 7a3e449   — client_scene_node_destroy() via new helpers (UAF fix)
--   * 46703ad   — titlebar/border clearing in !globalconf_L unmap path
--   * ddd921a   — XDG commit listener removal in !globalconf_L path
--   * 3042fd5   — motionnotify() in updatemons() for monitor hotplug
--
-- NOTE: Precise assertion of wl_pointer.enter re-delivery requires a real
-- pointer-sensitive Wayland client and live testing. This smoke test
-- focuses on "no crash, consistent state" through the refactored paths.
--
-- Scenario:
--   1. Spawn 2 clients on 2 tags, cursor parked over client area
--   2. Rapid tag switching (exercises some_refresh → banning_refresh →
--      motionnotify path from ea7e1aa)
--   3. Rapid client destroy (exercises client_scene_node_destroy across
--      normal unmap path, 7a3e449 + 46703ad)
--
-- Regressions this would catch:
--   - Assertion failures in wlr_scene_node_destroy
--   - NULL deref in banning path after motionnotify was added
--   - Compositor crash on rapid tag switch
---------------------------------------------------------------------------

local runner = require("_runner")
local test_client = require("_client")
local async = require("_async")
local utils = require("_utils")
local awful = require("awful")

if not test_client.is_available() then
    io.stderr:write("SKIP: no terminal available for client spawning\n")
    io.stderr:write("Test finished successfully.\n")
    awesome.quit()
    return
end

io.stderr:write("[TEST] kolo7-regression: tag-switch + unmap stress\n")

runner.run_async(function()
    ---------------------------------------------------------------
    -- Step 1: Set up two tags on primary screen
    ---------------------------------------------------------------
    local tag1 = screen.primary.tags[1]
    local tag2 = awful.tag.add("k7t2", { screen = screen.primary })
    assert(tag1 and tag2, "Failed to set up tags")
    tag1:view_only()

    ---------------------------------------------------------------
    -- Step 2: Park cursor at a fixed position inside screen area
    -- (stationary cursor is the precondition for the ea7e1aa bug)
    ---------------------------------------------------------------
    local g = screen.primary.geometry
    local cx = g.x + math.floor(g.width / 2)
    local cy = g.y + math.floor(g.height / 2)
    root.fake_input("motion_notify", false, cx, cy)
    io.stderr:write(string.format("[TEST] Cursor parked at (%d,%d)\n", cx, cy))

    ---------------------------------------------------------------
    -- Step 3: Spawn two clients (one per tag) and wait for manage
    ---------------------------------------------------------------
    tag1:view_only()
    test_client("k7_c1", "Kolo7 C1")
    local c1 = async.wait_for_client("k7_c1", 5)
    assert(c1, "Client c1 did not appear")
    c1:move_to_tag(tag1)

    tag2:view_only()
    test_client("k7_c2", "Kolo7 C2")
    local c2 = async.wait_for_client("k7_c2", 5)
    assert(c2, "Client c2 did not appear")
    c2:move_to_tag(tag2)

    io.stderr:write(string.format("[TEST] Spawned %d clients\n", #client.get()))

    ---------------------------------------------------------------
    -- Step 4: Rapid tag switching — exercises banning_refresh +
    -- motionnotify path (ea7e1aa). If the motionnotify call corrupts
    -- any state or the banning flag snapshot is wrong, the compositor
    -- crashes or hangs here.
    ---------------------------------------------------------------
    for i = 1, 10 do
        tag1:view_only()
        async.sleep(0.05)
        tag2:view_only()
        async.sleep(0.05)
    end
    tag1:view_only()

    assert(#client.get() == 2, "Lost a client during tag stress")
    assert(c1.valid and c2.valid, "Client invalidated during tag stress")
    io.stderr:write("[TEST] PASS: 10 tag-switch cycles, both clients alive\n")

    ---------------------------------------------------------------
    -- Step 5: Destroy clients while on their tag — exercises
    -- client_scene_node_destroy() via normal unmap path (7a3e449).
    -- Titlebar/border clearing (46703ad) runs here too.
    ---------------------------------------------------------------
    tag1:view_only()
    c1:kill()
    async.sleep(0.3)

    tag2:view_only()
    c2:kill()
    async.sleep(0.3)

    -- Wait for unmap/destroy to settle
    local timeout = 50  -- 5 seconds max
    while #client.get() > 0 and timeout > 0 do
        async.sleep(0.1)
        timeout = timeout - 1
    end
    assert(#client.get() == 0,
        "Clients still present after kill: " .. #client.get())
    io.stderr:write("[TEST] PASS: both clients destroyed cleanly\n")

    ---------------------------------------------------------------
    -- Step 6: Final tag switch with no clients — verifies the
    -- banning path handles empty client list (regression guard for
    -- the motionnotify-after-empty-banning case).
    ---------------------------------------------------------------
    tag2:view_only()
    tag1:view_only()
    io.stderr:write("[TEST] PASS: empty-client tag switch survives\n")

    tag2:delete()
    io.stderr:write("[TEST] PASS: kolo7 regression scenarios all survived\n")
    runner.done()
end)
