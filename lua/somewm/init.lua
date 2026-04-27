---------------------------------------------------------------------------
--- somewm extensions namespace.
--
-- Modules under somewm.* are compositor-specific additions that do not exist
-- in upstream AwesomeWM.  They must never modify the sacred awful/gears/wibox
-- libraries.
--
-- Lua submodules (layout_animation, tag_slide, ...) are loaded lazily so
-- that `require("somewm")` does not install signal handlers or other side
-- effects until a submodule is actually used.
--
-- C-side extensions (compositor-internal observation, e.g. `memory`) live
-- on the global `somewm` table that the compositor populates at startup
-- (see `somewm_memory.c::luaA_somewm_memory_setup`). The metatable below
-- proxies them through, so `require("somewm").memory.stats(true)` works
-- the same way as the bare global `somewm.memory.stats(true)`.
--
-- @module somewm
---------------------------------------------------------------------------

local submodules = {
    layout_animation = "somewm.layout_animation",
    tag_slide        = "somewm.tag_slide",
}

return setmetatable({}, {
    __index = function(self, key)
        -- 1. C-side bindings on the global somewm table (memory, future).
        local global_somewm = rawget(_G, "somewm")
        if global_somewm ~= nil then
            local v = global_somewm[key]
            if v ~= nil then
                rawset(self, key, v)
                return v
            end
        end
        -- 2. Lazy Lua submodules.
        local mod_path = submodules[key]
        if mod_path then
            local mod = require(mod_path)
            rawset(self, key, mod)
            return mod
        end
    end,
})
