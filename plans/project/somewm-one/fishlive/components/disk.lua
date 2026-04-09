local wibox = require("wibox")
local beautiful = require("beautiful")
local broker = require("fishlive.broker")
local wh = require("fishlive.widget_helper")

local M = {}

function M.create(screen, config)
	local widget, update = wh.create_icon_text("widget_disk_color", "#e2b55a")

	broker.connect_signal("data::disk", function(data)
		update(data.icon, string.format("%s/%s GB %2d%%", data.used, data.total, data.percent))
	end)

	return widget
end

return M
