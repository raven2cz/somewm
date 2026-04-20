---------------------------------------------------------------------------
--- Tag slide animation (KDE-style Desktop Slide).
--
-- Clients and wallpaper slide horizontally on Super+Left/Right tag switch.
-- Wibar stays stationary. Per-tag wallpapers supported via preload cache.
--
-- Design: Two wallpaper overlays (copies of old/new WP) handle the visual
-- slide. The real wallpaper is changed by the rc.lua tag signal handler
-- (set_wallpaper) independently — this module never touches wallpaper
-- switching, only the visual animation.
--
-- Configuration priority (most specific wins):
--   1. beautiful.tag_slide_<param>  (theme override, read at call time)
--   2. config passed to enable()
--   3. Module defaults
--
-- Usage:
--   require("somewm.tag_slide").enable({
--       duration  = 0.25,
--       easing    = "ease-out-cubic",
--       wallpaper = { enabled = true },
--   })
--
-- @module somewm.tag_slide
---------------------------------------------------------------------------

local capi = {
	awesome = awesome,
	client  = client,
	root    = root,
}

local awful = require("awful")
local beautiful = require("beautiful")

local _anim_client
local function get_anim_client()
	if _anim_client == nil then
		local ok, mod = pcall(require, "awful.anim_client")
		_anim_client = ok and mod or false
	end
	return _anim_client
end

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------

local defaults = {
	enabled   = true,
	duration  = 0.25,
	easing    = "ease-out-cubic",
	wallpaper = { enabled = true },
}

local config = {}

--- Read a config value with beautiful.tag_slide_* theme override.
local function cfg(key, sub_key)
	if sub_key then
		local theme_key = "tag_slide_" .. key .. "_" .. sub_key
		local tv = beautiful[theme_key]
		if tv ~= nil then return tv end
		local sec = config[key]
		if sec and sec[sub_key] ~= nil then return sec[sub_key] end
		return defaults[key] and defaults[key][sub_key]
	end
	local theme_key = "tag_slide_" .. key
	local tv = beautiful[theme_key]
	if tv ~= nil then return tv end
	if config[key] ~= nil then return config[key] end
	return defaults[key]
end

---------------------------------------------------------------------------
-- Feature detection: graceful degradation if C helpers missing
---------------------------------------------------------------------------

local has = {
	scene   = type(capi.awesome._client_scene_set_enabled) == "function",
	snap    = type(capi.root.wp_snapshot) == "function",
	snap_p  = type(capi.root.wp_snapshot_path) == "function",
	ovmove  = type(capi.root.wp_overlay_move) == "function",
	ovdest  = type(capi.root.wp_overlay_destroy) == "function",
}

local tag_slide = {}
tag_slide.enabled = false

local state_for = setmetatable({}, { __mode = "k" })
local orig_viewidx

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

local function ov_destroy(id)
	if id and has.ovdest then pcall(capi.root.wp_overlay_destroy, id) end
end

local function ov_move(id, x, y)
	if id and has.ovmove then pcall(capi.root.wp_overlay_move, id, x, y) end
end

local function cleanup(st)
	ov_destroy(st.old_wp)
	ov_destroy(st.new_wp)
	st.old_wp = nil
	st.new_wp = nil
	-- Destroy cover overlays placed on non-focused monitors (see
	-- create_covers below for the rationale).
	if st.covers then
		for _, id in ipairs(st.covers) do ov_destroy(id) end
		st.covers = nil
	end
end

--- Create stationary snapshot overlays on every non-focused screen so the
-- focused-screen slide overlays cannot bleed visually into neighbouring
-- outputs. Rationale: wp_snapshot/wp_snapshot_path create scene buffers
-- parented to the global LyrBottom layer; wlroots renders any scene node
-- whose bbox intersects an output's geometry. During the slide animation
-- the focused overlays are moved by ov_move() across the screen, and once
-- their bbox crosses the boundary into a neighbouring monitor that
-- monitor renders them too — on top of its real wallpaper (LyrBg),
-- producing a "ghost" slide with foreign wallpaper texture on e.g. a
-- Samsung TV secondary output. Because wp_overlay_create() calls
-- wlr_scene_node_raise_to_top() on every overlay it creates, overlays
-- created AFTER the focused pair sit above them in z-order. Placing a
-- stationary snapshot of each other screen's own current wallpaper on
-- top therefore masks any bleed-through — each monitor keeps showing
-- its own wallpaper for the duration of the animation.
local function create_covers(focused_s)
	if not has.snap then return nil end
	local covers = {}
	local ok_screen, screen_cap = pcall(function() return _G.screen end)
	if not ok_screen or not screen_cap then return nil end
	for other in screen_cap do
		if other ~= focused_s then
			local id = nil
			pcall(function() id = capi.root.wp_snapshot(other) end)
			if id then covers[#covers + 1] = id end
		end
	end
	return covers
end

local function cancel_and_snap(s)
	local st = state_for[s]
	if not st or not st.animating then return end

	if st.handle then pcall(function() st.handle:cancel() end) end
	st.handle = nil

	if st.old then
		for _, e in ipairs(st.old) do
			if e.c.valid then
				e.c:_set_geometry_silent(e.geo)
				if has.scene then
					capi.awesome._client_scene_set_enabled(e.c, false)
				end
			end
		end
	end
	if st.new then
		for _, e in ipairs(st.new) do
			if e.c.valid then e.c:_set_geometry_silent(e.target) end
		end
	end

	cleanup(st)
	st.old = nil
	st.new = nil
	st.animating = false

	local ac = get_anim_client()
	if ac then ac._tag_slide_active = false end
end

local function snap_clients(s)
	local list = {}
	for _, c in ipairs(capi.client.get()) do
		if c.screen == s and not c.minimized and not c.hidden and not c.sticky then
			for _, t in ipairs(c:tags()) do
				if t.selected then
					local g = c:geometry()
					list[#list + 1] = {
						c = c,
						geo = { x = g.x, y = g.y, width = g.width, height = g.height },
					}
					break
				end
			end
		end
	end
	return list
end

--- Predict wallpaper path for the tag at offset from current.
-- Filters hidden tags to match awful.tag.viewidx cycling behavior.
-- Uses wallpaper service _resolve() when available, falls back to
-- s._wppath + tag_name + ".jpg" for backwards compatibility.
--- Predict the tag name at offset from current (for IPC signals).
-- Reuses the same hidden-tag filtering as awful.tag.viewidx.
local function predict_tag_name(s, offset)
	local tags = {}
	for _, t in ipairs(s.tags) do
		if not t.hide then tags[#tags + 1] = t end
	end
	local sel = s.selected_tag
	if not sel or #tags == 0 then return nil end
	local idx
	for i, t in ipairs(tags) do if t == sel then idx = i; break end end
	if not idx then return nil end
	local ni = ((idx - 1 + offset) % #tags) + 1
	return tags[ni].name
end

local function predict_wp_path(s, offset)
	-- Filter to visible (non-hidden) tags, same as awful.tag.viewidx
	local tags = {}
	for _, t in ipairs(s.tags) do
		if not t.hide then tags[#tags + 1] = t end
	end
	local sel = s.selected_tag
	if not sel or #tags == 0 then return nil end
	local idx
	for i, t in ipairs(tags) do if t == sel then idx = i; break end end
	if not idx then return nil end
	local ni = ((idx - 1 + offset) % #tags) + 1
	local tag_name = tags[ni].name

	-- Try the per-screen resolver first so scoped variants (e.g. a
	-- portrait monitor's wallpapers/portrait/<tag>) win. Fall back to
	-- the unscoped _resolve() for older wallpaper services, and to
	-- direct path construction for configs that don't load the service
	-- at all. Each layer is a separate check so that a nil return
	-- from the scoped resolver still lets the unscoped path have a
	-- chance to match.
	local ok, wp_service = pcall(require, "fishlive.services.wallpaper")
	if ok and wp_service then
		if wp_service._resolve_for_screen then
			local path = wp_service._resolve_for_screen(s, tag_name)
			if path then return path end
		end
		if wp_service._resolve then
			local path = wp_service._resolve(tag_name)
			if path then return path end
		end
	end

	-- Fallback: direct path construction
	local wppath = s._wppath
	if not wppath then return nil end
	return wppath .. tag_name .. ".jpg"
end

---------------------------------------------------------------------------
-- Animation core
---------------------------------------------------------------------------

local function run_animation(s, old_snap, dir, old_wp, new_wp)
	local st = state_for[s]
	if not st then return end

	local dur = cfg("duration")
	local ease = cfg("easing")
	local sw = s.geometry.width
	local ox, oy = s.geometry.x, s.geometry.y

	local ac = get_anim_client()
	if ac then ac._tag_slide_active = true end

	-- Collect new clients (layout done, positions final)
	local new_snap = snap_clients(s)

	-- Build set of clients shared between old and new tags.
	-- These must NOT be animated (they stay put on both tags).
	local shared = {}
	do
		local old_set = {}
		for _, e in ipairs(old_snap) do old_set[e.c] = true end
		for _, e in ipairs(new_snap) do
			if old_set[e.c] then shared[e.c] = true end
		end
	end

	-- Remove shared clients from both snap lists
	local function filter_shared(snap)
		local out = {}
		for _, e in ipairs(snap) do
			if not shared[e.c] then out[#out + 1] = e end
		end
		return out
	end
	old_snap = filter_shared(old_snap)
	new_snap = filter_shared(new_snap)

	-- Re-enable old clients for slide-out
	if has.scene then
		for _, e in ipairs(old_snap) do
			if e.c.valid then
				capi.awesome._client_scene_set_enabled(e.c, true)
				e.c:_set_geometry_silent(e.geo)
			end
		end
	end

	-- New clients start off-screen
	for _, e in ipairs(new_snap) do
		if e.c.valid then
			e.target = { x = e.geo.x, y = e.geo.y,
			             width = e.geo.width, height = e.geo.height }
			e.c:_set_geometry_silent({
				x = e.target.x + sw * dir, y = e.target.y,
				width = e.target.width, height = e.target.height,
			})
		end
	end

	-- New WP overlay starts off-screen
	if new_wp then ov_move(new_wp, ox + sw * dir, oy) end

	st.old = old_snap
	st.new = new_snap
	st.animating = true

	if dur <= 0 then
		cancel_and_snap(s)
		capi.awesome.emit_signal("tag_slide::end", s)
		return
	end

	st.handle = capi.awesome.start_animation(
		dur,
		ease,
		function(p)
			local off = math.floor(sw * dir * p + 0.5)
			local rem = math.floor(sw * dir * (1 - p) + 0.5)

			for _, e in ipairs(old_snap) do
				if e.c.valid then
					e.c:_set_geometry_silent({
						x = e.geo.x - off, y = e.geo.y,
						width = e.geo.width, height = e.geo.height,
					})
				end
			end
			for _, e in ipairs(new_snap) do
				if e.c.valid then
					e.c:_set_geometry_silent({
						x = e.target.x + rem, y = e.target.y,
						width = e.target.width, height = e.target.height,
					})
				end
			end

			ov_move(old_wp, ox - off, oy)
			ov_move(new_wp, ox + rem, oy)
		end,
		function()
			for _, e in ipairs(old_snap) do
				if e.c.valid then
					e.c:_set_geometry_silent(e.geo)
					if has.scene then
						capi.awesome._client_scene_set_enabled(e.c, false)
					end
				end
			end
			for _, e in ipairs(new_snap) do
				if e.c.valid then e.c:_set_geometry_silent(e.target) end
			end

			cleanup(st)
			st.old = nil
			st.new = nil
			st.handle = nil
			st.animating = false

			local ac2 = get_anim_client()
			if ac2 then ac2._tag_slide_active = false end

			capi.awesome.emit_signal("tag_slide::end", s)

		end
	)
end

---------------------------------------------------------------------------
-- viewidx wrapper
---------------------------------------------------------------------------

local function animated_viewidx(i, s)
	if not tag_slide.enabled then return orig_viewidx(i, s) end

	s = s or awful.screen.focused()
	if not s then return orig_viewidx(i, s) end
	if math.abs(i) ~= 1 then return orig_viewidx(i, s) end

	cancel_and_snap(s)
	if not state_for[s] then state_for[s] = {} end
	local st = state_for[s]

	-- 1. Snapshot old clients
	local old_snap = snap_clients(s)

	-- 2. Create overlay of old wallpaper (in LyrBottom, above real WP)
	local old_wp = nil
	if cfg("wallpaper", "enabled") and has.snap then
		old_wp = capi.root.wp_snapshot(s)
	end
	st.old_wp = old_wp

	-- 3. Create overlay of new wallpaper from preload cache
	local new_wp = nil
	if cfg("wallpaper", "enabled") and has.snap_p then
		local new_path = predict_wp_path(s, i)
		if new_path then
			new_wp = capi.root.wp_snapshot_path(new_path, s)
		end
	end
	st.new_wp = new_wp

	-- 3a. Create stationary cover overlays on every OTHER screen. These
	-- sit above the focused-screen slide overlays in z-order (because
	-- wp_overlay_create raises each new node to the top) and therefore
	-- mask any bleed-through when the moving old_wp/new_wp cross a
	-- monitor boundary during the animation. See create_covers() docstring.
	if cfg("wallpaper", "enabled") then
		st.covers = create_covers(s)
	end

	-- 3b. Signal slide start (consumers like shell overlays can hide)
	local new_tag_name = predict_tag_name(s, i)
	capi.awesome.emit_signal("tag_slide::start", s, new_tag_name)

	-- 4. Execute real tag switch.
	--    The rc.lua tag handler fires synchronously and changes the
	--    wallpaper via set_wallpaper(). Our overlays cover the screen
	--    so the instant change is invisible.
	local dir = i
	orig_viewidx(i, s)

	-- 5. Start animation immediately after viewidx returns
	--    (layout + banning already happened synchronously inside viewidx)
	run_animation(s, old_snap, dir, old_wp, new_wp)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Enable tag slide animation.
-- @tparam[opt] table user_config Configuration overrides:
--   duration (number), easing (string), wallpaper = { enabled (bool) }
function tag_slide.enable(user_config)
	if tag_slide.enabled then return end
	-- Merge user config over defaults
	config = {}
	if user_config then
		for k, v in pairs(user_config) do config[k] = v end
	end
	tag_slide.enabled = true
	if not orig_viewidx then
		orig_viewidx = awful.tag.viewidx
		awful.tag.viewidx = animated_viewidx
	end
end

--- Disable tag slide animation and restore original viewidx.
function tag_slide.disable()
	if not tag_slide.enabled then return end
	tag_slide.enabled = false
	for s in pairs(state_for) do cancel_and_snap(s) end
	if orig_viewidx then
		awful.tag.viewidx = orig_viewidx
		orig_viewidx = nil
	end
end

return tag_slide
