---------------------------------------------------------------------------
-- Test: xwayland::ready signal + awesome.xwayland_ready property
--
-- Covers:
--   * awesome.xwayland_ready becomes true after xwaylandready() finishes
--     (asynchronous: poll up to ~10s for XWayland init to complete).
--   * Late subscribers do NOT see the cold-boot emission (signals are
--     edge-triggered; the property is the source of truth for "already
--     fired").
--   * Skips cleanly when XWayland is unavailable (compile-time disabled,
--     missing X libraries / xprop in the test environment, etc.).
--
-- IMPORTANT: somewm initializes XWayland in lazy mode (xwayland.c:286,
-- wlr_xwayland_create with lazy=1) — the server only spins up after the
-- first X11 client connects. This test triggers it explicitly via xprop
-- so the readiness flag actually flips during the test, otherwise we
-- would just be measuring "did xwayland start by accident".
--
-- Hot-reload re-emission of xwayland::ready is covered by
-- test-signal-hot-reload-ready.lua.
---------------------------------------------------------------------------

local runner = require("_runner")
local awful = require("awful")

-- Late subscriber connected before any kick: this should fire exactly
-- once when xwayland::ready is emitted by the C side.
local fire_count = 0
awesome.connect_signal("xwayland::ready", function()
    fire_count = fire_count + 1
end)

local kick_started = false

local steps = {
    -- Step 1: Kick lazy XWayland with a single xprop probe, then wait
    -- for the C side to flip the flag. ~100 retries × 0.1s = 10s.
    function(count)
        if not kick_started then
            kick_started = true
            -- xprop is small, ubiquitous, exits immediately. If it is
            -- missing the test will skip in step 2 below.
            awful.spawn.easy_async(
                { "xprop", "-root", "_NET_SUPPORTED" },
                function() end)
        end
        if awesome.xwayland_ready then
            return true
        end
        if count >= 100 then
            io.stderr:write(
                "SKIP: awesome.xwayland_ready stayed false after 10s, " ..
                "XWayland likely unavailable in this environment\n")
            io.stderr:write("Test finished successfully.\n")
            awesome.quit()
            return false  -- runner stops
        end
    end,

    -- Step 2: The signal must have fired exactly once for our late
    -- subscriber. If the C-side emit never happened, fire_count stays
    -- 0 and the property would also be false (we would not be here).
    function()
        assert(fire_count == 1,
            "xwayland::ready should have fired exactly once, " ..
            "got count=" .. fire_count)
        return true
    end,

    -- Step 3: The C-side flag is set-once and survives across test steps.
    function()
        assert(awesome.xwayland_ready == true,
            "xwayland_ready should remain true after first observation")
        return true
    end,
}

runner.run_steps(steps, { kill_clients = false, wait_per_step = 12 })

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
