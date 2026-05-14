---------------------------------------------------------------------------
-- Test rc.lua for fishlive.autostart integration tests.
--
-- Loaded into a headless somewm session via XDG_CONFIG_HOME override.
-- The driver script (plans/tests/test-autostart-lifecycle.sh) sets
-- FISHLIVE_ROOT to the directory that contains fishlive/init.lua so this
-- file does not depend on user installs.
--
-- Two test entries are registered:
--   lifecycle-sleep  long-running sleep gated on ready::somewm; should
--                    transition pending -> gated -> running quickly because
--                    awesome.somewm_ready is true by the time rc.lua runs.
--   lifecycle-fail   /bin/false oneshot with retries=1; the spawned child
--                    exits non-zero immediately, exhausting retries and
--                    landing in `failed`.
---------------------------------------------------------------------------

pcall(require, "luarocks.loader")

local _    = require("gears")
local awful = require("awful")
require("awful.autofocus")

-- Make fork-local fishlive.* requireable.
local fishlive_root = os.getenv("FISHLIVE_ROOT")
assert(fishlive_root and fishlive_root ~= "", "FISHLIVE_ROOT env var required")
package.path = fishlive_root .. "/?.lua;"
            .. fishlive_root .. "/?/init.lua;"
            .. package.path

modkey = "Mod4"

awful.layout.layouts = {
	awful.layout.suit.floating,
	awful.layout.suit.tile,
}

awful.screen.connect_for_each_screen(function(s)
	awful.tag({ "test" }, s, awful.layout.layouts[1])
end)

awesome.connect_signal("debug::error", function(err)
	io.stderr:write("ERROR: " .. tostring(err) .. "\n")
end)

local autostart = require("fishlive.autostart")

autostart.add{
	name    = "lifecycle-sleep",
	cmd     = { "sleep", "60" },
	when    = { "ready::somewm" },
	mode    = "oneshot",
	timeout = 5,
}

autostart.add{
	name    = "lifecycle-fail",
	cmd     = { "/bin/false" },
	when    = { "ready::somewm" },
	mode    = "oneshot",
	retries = 1,
	delay   = 0,
	timeout = 5,
}

-- Launcher contract: oneshot exits 0 within milliseconds. The entry
-- must land in `done`, NOT `failed` (regression from synology-drive bug
-- where exit=0 was misclassified as a crash).
autostart.add{
	name    = "lifecycle-success",
	cmd     = { "/bin/true" },
	when    = { "ready::somewm" },
	mode    = "oneshot",
	delay   = 0,
	timeout = 5,
}

autostart.start_all()

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
