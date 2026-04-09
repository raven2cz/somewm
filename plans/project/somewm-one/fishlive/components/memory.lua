local wibox = require("wibox")
local beautiful = require("beautiful")
local broker = require("fishlive.broker")
local wh = require("fishlive.widget_helper")

local M = {}

function M.create(screen, config)
	local widget, update = wh.create_icon_text("widget_memory_color", "#d3869b")

	broker.connect_signal("data::memory", function(data)
		local used_g = data.used / 1024
		local total_g = data.total / 1024
		update(data.icon, string.format("%.1f/%.0f GB", used_g, total_g))
	end)

	return widget
end

return M
