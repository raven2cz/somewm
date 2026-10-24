---------------------------------------------------------------------------
-- Test rc.lua for hot-reload re-emission of compositor readiness signals.
--
-- Loaded into a headless somewm session via XDG_CONFIG_HOME override.
-- The driver script (test-hot-reload-ready-signals.sh) sets
-- READY_SIGNAL_LOG to a file path that this rc.lua appends to whenever
-- somewm::ready or xwayland::ready fires. Each line is one of:
--     somewm <vm_id>
--     xwayland <vm_id>
-- where <vm_id> is a uuid-ish string set by the driver (different per
-- restart cycle so the driver can prove the second emission landed in
-- the new Lua VM, not the original one).
---------------------------------------------------------------------------

pcall(require, "luarocks.loader")

local _ = require("gears")
local awful = require("awful")
require("awful.autofocus")

modkey = "Mod4"
awful.layout.layouts = { awful.layout.suit.floating }
awful.screen.connect_for_each_screen(function(s)
    awful.tag({ "test" }, s, awful.layout.layouts[1])
end)

local log_path = os.getenv("READY_SIGNAL_LOG")
local vm_id    = os.getenv("READY_VM_ID") or "?"
assert(log_path and log_path ~= "",
    "READY_SIGNAL_LOG env var required by ready-signals-rc.lua")

local function append(name)
    local f = io.open(log_path, "a")
    if not f then return end
    f:write(name .. " " .. vm_id .. "\n")
    f:close()
end

awesome.connect_signal("somewm::ready", function() append("somewm") end)
awesome.connect_signal("xwayland::ready", function() append("xwayland") end)

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
