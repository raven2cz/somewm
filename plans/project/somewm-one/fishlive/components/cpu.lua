local wibox = require("wibox")
local beautiful = require("beautiful")
local broker = require("fishlive.broker")
local wh = require("fishlive.widget_helper")

local M = {}

function M.create(screen, config)
	local widget, update = wh.create_icon_text("widget_cpu_color", "#7daea3")

	broker.connect_signal("data::cpu", function(data)
		if data.temp then
			update(data.icon, string.format("%3d%% %2d°C", data.usage, data.temp))
		else
			update(data.icon, string.format("%3d%%", data.usage))
		end
	end)

	return widget
end

return M
