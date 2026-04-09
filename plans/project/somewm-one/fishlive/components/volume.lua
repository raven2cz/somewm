local wibox = require("wibox")
local awful = require("awful")
local beautiful = require("beautiful")
local broker = require("fishlive.broker")
local wh = require("fishlive.widget_helper")

local M = {}

function M.create(screen, config)
	local widget, update = wh.create_icon_text("widget_volume_color", "#ea6962")

	broker.connect_signal("data::volume", function(data)
		update(data.icon, string.format("%3d%%", data.volume))
	end)

	widget:buttons(awful.util.table.join(
		awful.button({}, 1, function()
			awful.spawn.with_shell("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle &")
		end),
		awful.button({}, 4, function()
			awful.spawn.with_shell("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ &")
		end),
		awful.button({}, 5, function()
			awful.spawn.with_shell("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- &")
		end)
	))

	return widget
end

return M
