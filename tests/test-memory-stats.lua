---------------------------------------------------------------------------
-- Test: somewm.memory diagnostics API
--
-- Verifies the read-only memory stats helpers used by leak diagnostics.
-- The API previously lived under root.* and was moved to somewm.memory.*
-- per issue #508 review.
---------------------------------------------------------------------------

local runner = require("_runner")
local awful = require("awful")
local wibox = require("wibox")

local memory = require("somewm").memory or somewm and somewm.memory
assert(memory, "somewm.memory namespace not available — C setup missing?")

local test_wibox = nil
local before = nil

local function assert_number(tbl, key)
    assert(type(tbl[key]) == "number", key .. " should be a number")
    assert(tbl[key] >= 0, key .. " should be non-negative")
end

local function assert_memory_stats_shape(stats)
    assert(type(stats) == "table", "somewm.memory.stats() should return a table")

    for _, key in ipairs({
        "lua_bytes",
        "clients",
        "screens",
        "tags",
        "drawins",
        "drawable_shm_count",
        "drawable_shm_bytes",
        "wibox_count",
        "wibox_surface_bytes",
    }) do
        assert_number(stats, key)
    end

    assert(type(stats.wallpaper) == "table", "stats.wallpaper should be a table")
    assert_number(stats.wallpaper, "entries")
    assert_number(stats.wallpaper, "current_entries")
    assert_number(stats.wallpaper, "max_entries")
    assert_number(stats.wallpaper, "cairo_bytes")
    assert_number(stats.wallpaper, "shm_bytes")
    assert_number(stats.wallpaper, "estimated_bytes")
    assert(
        stats.wallpaper.estimated_bytes ==
            stats.wallpaper.cairo_bytes + stats.wallpaper.shm_bytes,
        "wallpaper estimated_bytes should equal cairo_bytes + shm_bytes"
    )

    assert(type(stats.drawables) == "table", "stats.drawables should be a table")
    assert_number(stats.drawables, "drawin_drawables")
    assert_number(stats.drawables, "drawin_surface_bytes")
    assert_number(stats.drawables, "titlebar_drawables")
    assert_number(stats.drawables, "titlebar_surface_bytes")
    assert_number(stats.drawables, "shape_surface_bytes")
    assert_number(stats.drawables, "surface_bytes")
    assert(
        stats.drawables.surface_bytes ==
            stats.drawables.drawin_surface_bytes +
            stats.drawables.titlebar_surface_bytes +
            stats.drawables.shape_surface_bytes,
        "drawable surface_bytes should equal drawin + titlebar + shape bytes"
    )
    assert(
        stats.drawables.drawable_shm_bytes == stats.drawable_shm_bytes,
        "nested drawable_shm_bytes should match top-level value"
    )
end

local steps = {
    function()
        assert(type(memory.stats) == "function",
            "somewm.memory.stats should be available")
        assert(type(memory.wallpaper_cache) == "function",
            "somewm.memory.wallpaper_cache should be available")
        assert(type(memory.drawables) == "function",
            "somewm.memory.drawables should be available")

        before = memory.stats(true)
        assert_memory_stats_shape(before)

        local wallpaper = memory.wallpaper_cache(true)
        assert(type(wallpaper) == "table",
            "somewm.memory.wallpaper_cache(true) should return a table")
        assert_number(wallpaper, "entries")
        assert_number(wallpaper, "max_entries")
        assert(type(wallpaper.items) == "table",
            "detailed wallpaper stats should include items table")

        local drawables = memory.drawables()
        assert(type(drawables) == "table",
            "somewm.memory.drawables() should return a table")
        assert_number(drawables, "surface_bytes")

        return true
    end,

    function()
        test_wibox = wibox {
            x = 10,
            y = 10,
            width = 64,
            height = 32,
            visible = true,
            screen = awful.screen.focused(),
        }
        assert(test_wibox, "wibox creation failed")
        return true
    end,

    function()
        local after = memory.stats(true)
        assert_memory_stats_shape(after)
        assert(after.drawins >= before.drawins + 1,
            "creating a wibox should add a drawin")
        assert(after.drawables.drawin_drawables >= before.drawables.drawin_drawables + 1,
            "creating a wibox should add a drawin drawable")
        assert(after.drawables.drawin_surface_bytes >=
            before.drawables.drawin_surface_bytes + 64 * 32 * 4,
            "drawin surface bytes should include the created wibox surface")
        return true
    end,

    function()
        if test_wibox then
            test_wibox.visible = false
            test_wibox = nil
        end
        collectgarbage("collect")
        collectgarbage("collect")

        local stats = memory.stats(true)
        assert_memory_stats_shape(stats)
        return true
    end,
}

runner.run_steps(steps)

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
