---------------------------------------------------------------------------
--- Client fixes — app-specific workarounds for Steam and mpv.
--
-- Auto-initializes on require. Connects client property signals
-- to fix known app-specific issues.
--
-- Usage from rc.lua:
--   require("fishlive.config.client_fixes")
--
-- @module fishlive.config.client_fixes
-- @author Antonin Fischer (raven2cz) & Claude
-- @copyright 2026 MIT License
---------------------------------------------------------------------------

local naughty = require("naughty")

-- Steam bug: windows positioned outside screen bounds
client.connect_signal("property::position", function(c)
	if c.class == "Steam" then
		local g = c.screen.geometry
		if c.y + c.height > g.height then
			c.y = g.height - c.height
			naughty.notify { text = "restricted window: " .. c.name }
		end
		if c.x + c.width > g.width then
			c.x = g.width - c.width
		end
	end
end)

-- mpv: update aspect ratio when video changes (playlist advancement).
-- mpv resizes the window to match the new video's native dimensions,
-- which emits property::size. We recapture the ratio so subsequent
-- user resizes maintain the new video's proportions.
client.connect_signal("property::size", function(c)
	if c.class == "mpv" and c.floating and not c.fullscreen
			and not c.maximized and c.width > 0 and c.height > 0 then
		local bw2 = 2 * (c.border_width or 0)
		local cw = c.width - bw2
		local ch = c.height - bw2
		if cw > 0 and ch > 0 then
			c.aspect_ratio = cw / ch
		end
	end
end)

return {}
