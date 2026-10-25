-- Flow-bar shadows paint over clients, stop at the inner edge, and disappear
-- when disabled. Exercise theme defaults and overrides on all four edges.
local runner = require('_runner')
local awful = require('awful')
local wibox = require('wibox')
local beautiful = require('beautiful')
local utils = require('_utils')
local capture = require('_widget_capture')
local gsurface = require('gears.surface')
local gcolor = require('gears.color')
local gshape = require('gears.shape')

local s = screen[1]
local client_color, bar_color, thickness = '#204060', '#00ff00', 24
local c, bar, report

local function pixel(x, y)
    local r, g, b = capture.read(gsurface(s.content), x, y)
    return string.format('#%02x%02x%02x', r, g, b), r, g, b
end

local function exact(x, y, want)
    local got = pixel(x, y)
    assert(got == want, string.format('pixel %d,%d: got %s, want %s', x, y, got, want))
end

local function wait(fn)
    return function(n)
        local ok, err = pcall(fn)
        if ok then return true end
        assert(n < 40, err)
    end
end

local steps = {
    function()
        root.wallpaper(gcolor('#ffffff'))
        s.selected_tag.layout = awful.layout.suit.floating
        beautiful.shadow_drawin_enabled = true
        beautiful.shadow_drawin_radius = 8
        beautiful.shadow_drawin_corner_radius = 0
        beautiful.shadow_drawin_offset_x = 0
        beautiful.shadow_drawin_offset_y = 8
        beautiful.shadow_drawin_spread = 0
        beautiful.shadow_drawin_opacity = 0.5
        beautiful.shadow_drawin_color = '#ff00ff'
        awesome.shadow_reload()
        report = os.tmpname()
        awful.spawn{'./build-test/test-transient-client', 'wibar_shadow_client', report, '0', 'ff204060'}
        return true
    end,
    function(n)
        c = utils.find_client_by_class('wibar_shadow_client')
        if not c then assert(n < 30, 'client did not map'); return end
        c.floating, c.border_width, c.shadow = true, 0, false
        mouse.coords{x = 640, y = 360}
        return true
    end,
}

for _, edge in ipairs{'top', 'bottom', 'left', 'right'} do
    -- Capture a distinct edge for Lua 5.1 closures.
    local position = edge
    local horizontal = position == 'top' or position == 'bottom'
    local inward = position == 'top' or position == 'left'
    local ox = horizontal and 0 or (inward and 8 or -8)
    local oy = horizontal and (inward and 8 or -8) or 0
    local function points()
        if position == 'top' then
            return {100, 10}, {{100, thickness + 1}, {100, thickness + 7}}, {100, thickness + 30}
        elseif position == 'bottom' then
            return {100, s.geometry.height - 10}, {{100, bar.y - 2}, {100, bar.y - 8}}, {100, bar.y - 30}
        elseif position == 'left' then
            return {10, 100}, {{thickness + 1, 100}, {thickness + 7, 100}}, {thickness + 30, 100}
        end
        return {s.geometry.width - 10, 100}, {{bar.x - 2, 100}, {bar.x - 8, 100}}, {bar.x - 30, 100}
    end
    steps[#steps + 1] = function()
        local args = {screen = s, position = position, bg = bar_color,
            widget = wibox.widget.textbox('')}
        if horizontal then args.height = thickness else args.width = thickness end
        -- The first bar inherits the drawin theme; the others override it.
        if position ~= 'top' then
            args.shadow = {enabled = true, radius = 8, corner_radius = 0,
                offset_x = ox, offset_y = oy, spread = 0, opacity = 0.5, color = '#ff00ff'}
        end
        if position == 'bottom' then
            args.shape = function(cr, w, h) gshape.rounded_rect(cr, w, h, 8) end
        end
        bar = awful.wibar(args)
        return true
    end
    steps[#steps + 1] = wait(function()
        local wa = s.workarea
        assert((horizontal and wa.height == s.geometry.height - thickness)
            or (not horizontal and wa.width == s.geometry.width - thickness), 'workarea pending')
        c:geometry{x = wa.x, y = wa.y, width = wa.width, height = wa.height}
    end)
    steps[#steps + 1] = wait(function()
        local inside, under, far = points()
        exact(inside[1], inside[2], bar_color)
        for _, p in ipairs(under) do
            local got, r, g, b = pixel(p[1], p[2])
            assert(r > 32 and g < 64 and b > 96,
                string.format('%s shadow missing over client at %d,%d: %s', position, p[1], p[2], got))
        end
        exact(far[1], far[2], client_color)
        assert(awesome._clay_tree(s):find('SHADOW', 1, true), 'missing bar shadow declaration')
        assert(awesome._test_redeclare() == 0, 'idle bar shadow must not mutate the scene')
        io.stderr:write('[PASS] ' .. position .. ' shadow over client, bar colour intact\n')
    end)
    steps[#steps + 1] = function() bar.shadow = false; return true end
    steps[#steps + 1] = wait(function()
        local inside, under = points()
        exact(inside[1], inside[2], bar_color)
        for _, p in ipairs(under) do exact(p[1], p[2], client_color) end
        assert(not awesome._clay_tree(s):find('SHADOW', 1, true), 'disabled shadow still declared')
        io.stderr:write('[PASS] ' .. position .. ' shadow disabled, client colour intact\n')
    end)
    if position == 'top' then
        steps[#steps + 1] = function()
            -- Reuse the drawin as a normal wibox with the same raster style:
            -- changing its role must clear the bar cut even without rerastering.
            bar.drawin.bar = nil
            bar:geometry{x = 100, y = 100, width = 200, height = 100}
            bar.shadow = {enabled = true, radius = 8, corner_radius = 0,
                offset_x = 0, offset_y = 0, spread = 0, opacity = 0.5, color = '#ff00ff'}
            return true
        end
        steps[#steps + 1] = wait(function()
            exact(140, 140, bar_color)
            for _, p in ipairs{{97, 140}, {140, 97}, {302, 140}, {140, 202}} do
                local got, r, g, b = pixel(p[1], p[2])
                assert(r > 32 and g < 64 and b > 96,
                    'bar cut retained after drawin reuse: ' .. got)
            end
            io.stderr:write('[PASS] drawin reused as a wibox has shadows on all edges\n')
        end)
    end
    steps[#steps + 1] = function() bar:remove(); bar = nil; return true end
    steps[#steps + 1] = wait(function()
        assert(s.workarea.width == s.geometry.width and s.workarea.height == s.geometry.height,
            'bar removal pending')
    end)
end

steps[#steps + 1] = function()
    c:kill()
    os.remove(report)
    return true
end

runner.run_steps(steps, {kill_clients = false})
