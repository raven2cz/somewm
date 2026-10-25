-- A client's shadow is painted around it, never under it: through a
-- translucent client the wallpaper shows evenly, with no fade near the
-- edges the shadow is offset away from. The shadow still shows outside the
-- client on the offset side.
local runner = require('_runner')
local awful = require('awful')
local utils = require('_utils')
local capture = require('_widget_capture')
local gsurface = require('gears.surface')
local gcolor = require('gears.color')

local wallpaper = '#c0c0c0'
local x, y, w, h = 200, 150, 400, 300
local c, report

local function pixel(px, py)
    local red, green, blue = capture.read(gsurface(screen[1].content), px, py)
    return string.format('#%02x%02x%02x', red, green, blue)
end

local function wait(fn)
    return function(n)
        local ok, err = pcall(fn)
        if ok then return true end
        assert(n < 40, err)
    end
end

runner.run_steps({
    function()
        root.wallpaper(gcolor(wallpaper))
        screen[1].selected_tag.layout = awful.layout.suit.floating
        report = os.tmpname()
        -- Half-transparent client.
        awful.spawn{'./build-test/test-transient-client', 'translucent_client', report, '0', '80204060'}
        return true
    end,
    function(n)
        c = utils.find_client_by_class('translucent_client')
        if not c then assert(n < 30, 'client did not map'); return end
        c.floating = true
        c.border_width = 0
        c:geometry{x = x, y = y, width = w, height = h}
        -- The v1-like theme shadow: a solid box shrunk inside the client and
        -- offset to the bottom right, fading across the client's edge.
        c.shadow = {radius = 50, spread = -35, offset_x = 10, offset_y = 10,
            opacity = 1, color = '#000000'}
        mouse.coords{x = 1000, y = 700}
        return true
    end,
    wait(function()
        local g = c:geometry()
        assert(g.x == x and g.y == y and g.width == w and g.height == h, 'geometry pending')
        local inner = pixel(x + w / 2, y + h / 2)
        assert(inner ~= wallpaper, 'the client is not painted yet')
        -- Near the top-left edges the stock nine-patch fade sat under the
        -- client and showed through it.
        for _, p in ipairs {{x + 3, y + h / 2}, {x + w / 2, y + 3}, {x + 20, y + 20}} do
            local got = pixel(p[1], p[2])
            assert(got == inner, string.format('inside the client at %d,%d: %s, centre %s',
                p[1], p[2], got, inner))
        end
        -- Outside, on the offset side, the shadow still darkens the wallpaper.
        local below = pixel(x + w / 2, y + h + 4)
        assert(below ~= wallpaper, 'no shadow below the client: ' .. below)
        io.stderr:write('[PASS] even inside a translucent client, shadow outside it\n')
    end),
    function()
        c:kill()
        os.remove(report)
        return true
    end,
}, {kill_clients = false})
