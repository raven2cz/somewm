---------------------------------------------------------------------------
--- Shell IPC — push client/tag state to somewm-shell (QuickShell).
--
-- Connects Lua signals → QuickShell IPC calls so the shell sidebar,
-- collage, and panel widgets stay in sync with compositor state.
--
-- Usage from rc.lua:
--   require("fishlive.config.shell_ipc").setup()
--
-- Order-independent w.r.t. rules/titlebars/client_fixes. Call last in
-- rc.lua after autostart so we don't spam IPC before the shell exists.
--
-- @module fishlive.config.shell_ipc
-- @author Antonin Fischer (raven2cz) & Claude
-- @copyright 2026 MIT License
---------------------------------------------------------------------------

local awful = require("awful")

local M = { _initialized = false }

-- Push client/tag state to shell on every change (debounced on QML side)
local function push_state()
	awful.spawn.easy_async(
		"qs ipc -c somewm call somewm-shell:compositor invalidate",
		function() end  -- fire and forget
	)
end

function M.setup()
	if M._initialized then return end
	M._initialized = true

	-- Client lifecycle
	client.connect_signal("manage", push_state)
	client.connect_signal("unmanage", push_state)
	client.connect_signal("focus", push_state)
	-- Client property changes
	client.connect_signal("property::name", push_state)
	client.connect_signal("property::urgent", push_state)
	client.connect_signal("property::minimized", push_state)
	client.connect_signal("tagged", push_state)
	client.connect_signal("untagged", push_state)
	-- Tag changes
	tag.connect_signal("property::selected", push_state)
	tag.connect_signal("property::activated", push_state)
	tag.connect_signal("property::name", push_state)

	-- Focused screen tracking (for multi-monitor panel targeting)
	-- NOTE: screen::focus is a global signal with NO arguments (somewm.c:1107)
	-- Must get focused screen via awful.screen.focused()
	awesome.connect_signal("screen::focus", function()
		local s = awful.screen.focused()
		if s then
			awful.spawn.easy_async(
				"qs ipc -c somewm call somewm-shell:compositor setScreen " .. (s.name or tostring(s.index)),
				function() end
			)
		end
	end)

	-- Active tag tracking (for collage per-tag visibility)
	-- Only push on select (signal fires for both select and deselect)
	tag.connect_signal("property::selected", function(t)
		if t.selected then
			awful.spawn({"qs", "ipc", "-c", "somewm", "call",
				"somewm-shell:compositor", "setTag", t.name or tostring(t.index)})
		end
	end)

	-- Tag slide signals -> QuickShell collage IPC
	awesome.connect_signal("tag_slide::start", function(_, new_tag_name)
		if new_tag_name then
			awful.spawn({"qs", "ipc", "-c", "somewm", "call",
				"somewm-shell:collage", "slideStart", new_tag_name})
		end
	end)
	awesome.connect_signal("tag_slide::end", function()
		awful.spawn({"qs", "ipc", "-c", "somewm", "call",
			"somewm-shell:collage", "slideEnd"})
	end)
end

return M
