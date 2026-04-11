---------------------------------------------------------------------------
--- Menus — start menu, desktop context menu, and launcher widget.
--
-- Usage from rc.lua:
--   local menus = require("fishlive.config.menus").setup({
--       terminal     = terminal,
--       editor_cmd   = editor_cmd,
--       modkey       = modkey,
--   })
--   -- menus.start_menu, menus.desktop_menu, menus.launcher
--
-- @module fishlive.config.menus
-- @author Antonin Fischer (raven2cz) & Claude
-- @copyright 2026 MIT License
---------------------------------------------------------------------------

local awful = require("awful")
local beautiful = require("beautiful")
local naughty = require("naughty")
local hotkeys_popup = require("awful.hotkeys_popup")
local menubar = require("menubar")
local dpi = require("beautiful.xresources").apply_dpi
local fmenu = require("fishlive.menu")
local recording = require("fishlive.config.recording")

local M = {}

function M.setup(args)
	local terminal = args.terminal
	local editor_cmd = args.editor_cmd

	menubar.utils.terminal = terminal

	local start_menu = fmenu.new({
		items = {
			{ icon = "󰌌", label = "Hotkeys",
			  on_activate = function() hotkeys_popup.show_help(nil, awful.screen.focused()) end },
			{ icon = "󰏫", label = "Edit Config",
			  on_activate = function() awful.spawn(editor_cmd .. " " .. awesome.conffile) end },
			{ icon = "󰆍", label = "Terminal",
			  on_activate = function() awful.spawn(terminal) end },
			{ separator = true },
			{ icon = "󰑓", label = "Rebuild & Restart",
			  on_activate = function() awesome.rebuild_restart() end },
			{ icon = "󰗼", label = "Quit",
			  on_activate = function() awesome.quit() end },
		},
		close_on = "escape",
		placement = "under_mouse",
		width = dpi(220),
	})

	local desktop_menu = fmenu.new({
		items = {
			{ icon = "󰆍", label = "Terminal",
			  on_activate = function() awful.spawn(terminal) end },
			{ icon = "󰝰", label = "File Manager",
			  on_activate = function() awful.spawn("dolphin") end },
			{ icon = "󰖟", label = "Browser",
			  on_activate = function() awful.spawn("firefox-developer-edition") end },
			{ separator = true },
			{ icon = "󰹑", label = "Screenshot",
			  on_activate = function()
				  awful.spawn.with_shell("grim ~/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png")
			  end },
			{ icon = "󰩬", label = "Screenshot (select)",
			  on_activate = function()
				  awful.spawn.with_shell("grim -g \"$(slurp)\" ~/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png")
			  end },
			{ separator = true },
			{ icon = "󰑊", label = "Start Recording",
			  on_activate = function() recording.toggle() end },
			{ separator = true },
			{ icon = "󰜉", label = "Restart", on_activate = awesome.restart },
			{ icon = "󰗼", label = "Quit", on_activate = awesome.quit },
		},
		close_on = "escape",
		placement = "under_mouse",
		width = dpi(260),
	})

	local launcher = awful.widget.launcher({
		image = beautiful.awesome_icon,
		menu = start_menu,
	})

	return {
		start_menu   = start_menu,
		desktop_menu = desktop_menu,
		launcher     = launcher,
	}
end

return M
