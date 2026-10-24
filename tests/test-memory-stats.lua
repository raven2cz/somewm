---------------------------------------------------------------------------
-- Test: root.memory_stats() debug counters
--
-- Shape and basic bookkeeping of the read-only memory counters used by leak
-- diagnostics: non-negative numbers, gc=true collects before counting, and
-- a new wibox shows up as a drawin.
---------------------------------------------------------------------------

local runner = require("_runner")
local awful = require("awful")
local wibox = require("wibox")

local test_wibox = nil
local before = nil

local function assert_number(tbl, key)
    assert(type(tbl[key]) == "number", key .. " should be a number")
    assert(tbl[key] >= 0, key .. " should be non-negative")
end

local function assert_shape(stats)
    assert(type(stats) == "table", "root.memory_stats() should return a table")
    for _, key in ipairs({ "lua_bytes", "clients", "screens", "tags",
                           "drawins", "wallpaper_bytes" }) do
        assert_number(stats, key)
    end
    -- glibc >= 2.33 only; absent elsewhere, numbers when present.
    for _, key in ipairs({ "malloc_arena_bytes", "malloc_used_bytes",
                           "malloc_free_bytes", "malloc_releasable_bytes" }) do
        if stats[key] ~= nil then assert_number(stats, key) end
    end
end

local steps = {
    function()
        assert(type(root.memory_stats) == "function",
            "root.memory_stats should be available")
        before = root.memory_stats(true)
        assert_shape(before)
        assert(before.screens >= 1, "at least one screen should be counted")
        assert(before.lua_bytes > 0, "the Lua heap should not be empty")

        -- Garbage made now is collected by gc=true, so it must not inflate
        -- the collected count by its size.
        local junk = {}
        for i = 1, 20000 do junk[i] = { i } end
        junk = nil -- luacheck: ignore
        local collected = root.memory_stats(true)
        assert(collected.lua_bytes < before.lua_bytes + 512 * 1024,
            "memory_stats(true) should report the heap after collection")
        return true
    end,

    function()
        test_wibox = wibox {
            x = 10, y = 10, width = 64, height = 32,
            visible = true,
            screen = awful.screen.focused(),
        }
        return true
    end,

    function()
        local after = root.memory_stats(true)
        assert_shape(after)
        assert(after.drawins >= before.drawins + 1,
            "creating a wibox should add a drawin")
        test_wibox.visible = false
        test_wibox = nil
        return true
    end,
}

runner.run_steps(steps)

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
