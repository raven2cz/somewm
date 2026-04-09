local wibox = require("wibox")
local awful = require("awful")
local beautiful = require("beautiful")
local broker = require("fishlive.broker")
local wh = require("fishlive.widget_helper")

local M = {}

function M.create(screen, config)
	local widget, update = wh.create_icon_text("widget_updates_color", "#d8a657")

	broker.connect_signal("data::updates", function(data)
		update(data.icon, tostring(data.total))
	end)

	widget:buttons(awful.util.table.join(
		awful.button({}, 1, function()
			awful.spawn(string.format("%s -e paru",
				beautiful.terminal or "ghostty"))
		end)
	))

	return widget
end

return M
