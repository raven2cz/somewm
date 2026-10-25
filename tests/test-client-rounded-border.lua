-- A rounded client with a border: the border follows the shape. Its outer
-- edge takes the shape's radius, its inner edge that radius less the width,
-- and the surface the same inner radius, so the frame's corner pixel shows
-- the wallpaper, a pixel on the arc the border colour and one further in
-- the client. Stock 2.1 drew a square border around the cut surface: the
-- frame's corner pixel was border-coloured and the arc showed the
-- wallpaper. shape = nil draws the square border again.
local runner = require('_runner')
local awful = require('awful')
local utils = require('_utils')
local capture = require('_widget_capture')
local gsurface = require('gears.surface')
local gcolor = require('gears.color')

local wallpaper, client_color, border_color = '#123456', '#204060', '#ff0000'
local x, y, w, h, r, bw = 100, 100, 300, 200, 24, 4
local c, report

local function pixel(px, py)
    local red, green, blue = capture.read(gsurface(screen[1].content), px, py)
    return string.format('#%02x%02x%02x', red, green, blue)
end

local function expect(points, name)
    for _, p in ipairs(points) do
        local got = pixel(p[1], p[2])
        assert(got == p[3], string.format('%s: %s at %d,%d is %s, want %s',
            name, p[4], p[1], p[2], got, p[3]))
    end
    io.stderr:write('[PASS] ' .. name .. '\n')
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
        awful.spawn{'./build-test/test-transient-client', 'rounded_border_client', report, '0', 'ff204060'}
        return true
    end,
    function(n)
        c = utils.find_client_by_class('rounded_border_client')
        if not c then assert(n < 30, 'client did not map'); return end
        c.floating = true
        c.shadow = false
        c.border_width = bw
        c.border_color = border_color
        c:geometry{x = x, y = y, width = w, height = h}
        c.shape = r
        mouse.coords{x = 640, y = 360}
        return true
    end,
    -- The frame is x..x+w+2*bw; the outer arc's centre is (x+r, y+r), the
    -- ring runs from r-bw to r. Pixel centres sit half a pixel in.
    wait(function()
        local g = c:geometry()
        assert(g.x == x and g.y == y and g.width == w and g.height == h, 'geometry pending')
        expect({
            {x + 1, y + 1, wallpaper, 'frame corner, outside the arc'},
            {x + 3, y + 3, wallpaper, 'three in from the corner, outside the arc'},
            {x + 8, y + 8, border_color, 'on the ring (22 px from the centre)'},
            {x + 12, y + 12, client_color, 'inside the ring (16 px from the centre)'},
            {x + math.floor(w / 2), y + 1, border_color, 'top edge'},
            {x + w + 2 * bw - 2, y + h + 2 * bw - 2, wallpaper, 'bottom-right frame corner'},
            {x + w + 2 * bw - 9, y + h + 2 * bw - 9, border_color, 'bottom-right ring'},
        }, 'rounded border')
    end),
    function()
        c.shape = nil
        return true
    end,
    wait(function()
        expect({
            {x + 1, y + 1, border_color, 'frame corner'},
            {x + 8, y + 8, client_color, 'inside the square border'},
        }, 'square border again')
    end),
    function()
        c:kill()
        os.remove(report)
        return true
    end,
}, {kill_clients = false})
