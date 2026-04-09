---------------------------------------------------------------------------
--- Wallpaper service — per-tag wallpaper management with override support.
--
-- Replaces inline wallpaper code in rc.lua with a proper service.
-- Supports per-tag user wallpapers and theme wallpapers with a 4-tier
-- resolution chain:
--   0. In-memory override (runtime preview, not persisted)
--   1. user-wallpapers/{tag}.{ext} (user choice, per-theme, HIGHEST disk)
--   2. wallpapers/{tag}.{ext} (theme default)
--   3. themes/default/wallpapers/{tag}.{ext} (global fallback, LOWEST)
--
-- IPC API (via somewm-client eval):
--   require('fishlive.services.wallpaper').save_to_theme(tag_name, path)
--   require('fishlive.services.wallpaper').set_override(tag_name, path)
--   require('fishlive.services.wallpaper').clear_override(tag_name)
--   require('fishlive.services.wallpaper').get_overrides_json()
--   require('fishlive.services.wallpaper').get_current()
--   require('fishlive.services.wallpaper').get_browse_dirs_json()
--   require('fishlive.services.wallpaper').get_tags_json()
--   require('fishlive.services.wallpaper').get_theme_wallpapers_dir()
--   require('fishlive.services.wallpaper').view_tag(tag_name)
--
-- @module fishlive.services.wallpaper
-- @author Antonin Fischer (raven2cz) & Claude
-- @copyright 2026 MIT License
---------------------------------------------------------------------------

local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local broker = require("fishlive.broker")

local wallpaper = {}

-- State
wallpaper._overrides = {}         -- { [tag_name] = "/absolute/path.jpg" } (runtime only)
wallpaper._wppath = nil           -- themes/{active}/wallpapers/
wallpaper._user_wppath = nil      -- themes/{active}/user-wallpapers/
wallpaper._default_wppath = nil   -- themes/default/wallpapers/ (global fallback)
wallpaper._default = "1.jpg"      -- fallback wallpaper filename
wallpaper._browse_dirs = {}       -- dirs for folder browsing in picker
wallpaper._initialized = false

-- Image extensions to try when resolving tag wallpapers
local IMG_EXTENSIONS = { ".jpg", ".png", ".webp", ".jpeg" }

-- Whitelisted extensions for save operations
local SAFE_EXT = { jpg = true, jpeg = true, png = true, webp = true }

--- Try to find a wallpaper for a tag in a given directory.
-- @tparam string dir Directory path (must end with /)
-- @tparam string tag_name Tag name
-- @treturn string|nil Absolute path if found, nil otherwise
local function find_in_dir(dir, tag_name)
	if not dir then return nil end
	for _, ext in ipairs(IMG_EXTENSIONS) do
		local path = dir .. tag_name .. ext
		if gears.filesystem.file_readable(path) then
			return path
		end
	end
	return nil
end

--- Apply wallpaper to a screen using awful.wallpaper API (HiDPI-aware).
-- Reuses existing wallpaper widget to avoid flicker on image swap.
-- @tparam screen scr The screen object
-- @tparam string path Absolute path to wallpaper image
local function apply_wallpaper(scr, path)
	if not path or not gears.filesystem.file_readable(path) then
		return false
	end

	-- Skip redundant updates
	if scr._current_wallpaper == path then return true end

	if scr._wallpaper_widget then
		-- Reuse existing widget and repaint root surface
		scr._wallpaper_widget.image = path
		if scr._wallpaper_obj then scr._wallpaper_obj:repaint() end
	else
		-- First time: create wallpaper object and store references
		local imgbox = wibox.widget {
			image     = path,
			upscale   = true,
			downscale = true,
			widget    = wibox.widget.imagebox,
		}
		scr._wallpaper_obj = awful.wallpaper {
			screen = scr,
			widget = {
				imgbox,
				valign = "center",
				halign = "center",
				tiled  = false,
				widget = wibox.container.tile,
			}
		}
		scr._wallpaper_widget = imgbox
	end
	scr._current_wallpaper = path
	return true
end

--- Resolve wallpaper path for a tag using the 4-tier priority chain.
-- 0. In-memory override (runtime preview)
-- 1. user-wallpapers/{tag}.{ext} (user choice, per-theme)
-- 2. wallpapers/{tag}.{ext} (theme default)
-- 3. themes/default/wallpapers/{tag}.{ext} (global fallback)
-- @tparam string tag_name The tag name (e.g. "1", "2", ...)
-- @treturn string|nil Absolute path to the wallpaper file, or nil
function wallpaper._resolve(tag_name)
	-- 0. Check in-memory override (runtime preview)
	if wallpaper._overrides[tag_name] then
		local path = wallpaper._overrides[tag_name]
		if gears.filesystem.file_readable(path) then
			return path
		end
		-- Override file disappeared — clear it
		wallpaper._overrides[tag_name] = nil
	end

	-- 1. User wallpapers: user-wallpapers/{tag}.{ext}
	local found = find_in_dir(wallpaper._user_wppath, tag_name)
	if found then return found end

	-- 2. Theme wallpapers: wallpapers/{tag}.{ext}
	found = find_in_dir(wallpaper._wppath, tag_name)
	if found then return found end

	-- 3. Global fallback: themes/default/wallpapers/{tag}.{ext}
	found = find_in_dir(wallpaper._default_wppath, tag_name)
	if found then return found end

	-- 4. Last resort: default file in theme wallpapers
	if wallpaper._wppath then
		local path = wallpaper._wppath .. wallpaper._default
		if gears.filesystem.file_readable(path) then
			return path
		end
	end

	-- 5. Very last resort: default file in global fallback
	if wallpaper._default_wppath then
		local path = wallpaper._default_wppath .. wallpaper._default
		if gears.filesystem.file_readable(path) then
			return path
		end
	end

	return nil
end

--- Initialize the wallpaper service for a screen.
-- Call this inside awful.screen.connect_for_each_screen.
--
-- @tparam screen scr The screen object
-- @tparam string wppath Base wallpaper directory (themes/name/wallpapers/)
-- @tparam[opt="1.jpg"] string default_wallpaper Default fallback filename
-- @tparam[opt] table opts Options: { browse_dirs = {"/path1", "/path2"} }
function wallpaper.init(scr, wppath, default_wallpaper, opts)
	wallpaper._wppath = wppath
	wallpaper._user_wppath = wppath:gsub("wallpapers/$", "user-wallpapers/")
	wallpaper._default_wppath = gears.filesystem.get_configuration_dir()
		.. "themes/default/wallpapers/"
	wallpaper._default = default_wallpaper or "1.jpg"
	wallpaper._browse_dirs = opts and opts.browse_dirs or {}

	-- Expose wppath for tag_slide animation overlays
	scr._wppath = wppath

	-- Initial wallpaper: use screen's first tag name
	local first_tag = scr.tags and scr.tags[1]
	local init_tag = first_tag and first_tag.name or "1"
	local path = wallpaper._resolve(init_tag)
	if path then apply_wallpaper(scr, path) end

	-- Pre-cache all wallpapers for tag_slide animation overlays
	if root.wallpaper_cache_preload then
		local paths = {}
		for i = 1, 9 do
			local wp = wppath .. i .. ".jpg"
			if gears.filesystem.file_readable(wp) then
				table.insert(paths, wp)
			end
		end
		if #paths > 0 then root.wallpaper_cache_preload(paths, scr) end
	end

	-- Switch wallpaper on tag selection
	for _, tag in ipairs(scr.tags) do
		tag:connect_signal("property::selected", function(t)
			if t.selected then
				local wp = wallpaper._resolve(t.name)
				if wp then apply_wallpaper(t.screen, wp) end
			end
		end)
	end
end

--- Set a wallpaper override for a tag (runtime preview, not persisted).
-- The override persists in memory until cleared or save_to_theme is called.
-- If the tag is currently selected, the wallpaper is applied immediately.
--
-- @tparam string tag_name Tag name (e.g. "1")
-- @tparam string path Absolute path to wallpaper image
function wallpaper.set_override(tag_name, path)
	if not path or path == "" then return end
	wallpaper._overrides[tag_name] = path

	-- Apply immediately if this tag is currently selected on any screen
	for scr in screen do
		local sel = scr.selected_tag
		if sel and sel.name == tag_name then
			apply_wallpaper(scr, path)
		end
	end

	-- Notify shell of change
	broker.emit_signal("data::wallpaper", wallpaper._get_state())
end

--- Clear a wallpaper override for a tag, reverting to resolved wallpaper.
-- @tparam string tag_name Tag name
function wallpaper.clear_override(tag_name)
	wallpaper._overrides[tag_name] = nil

	-- Revert to resolved wallpaper if this tag is currently selected
	for scr in screen do
		local sel = scr.selected_tag
		if sel and sel.name == tag_name then
			local wp = wallpaper._resolve(tag_name)
			if wp then apply_wallpaper(scr, wp) end
		end
	end

	broker.emit_signal("data::wallpaper", wallpaper._get_state())
end

--- Save a wallpaper into the user-wallpapers directory for the active theme.
-- Copies the source file to user-wallpapers/{tag_name}.{ext}.
-- Does NOT overwrite theme default wallpapers in wallpapers/.
-- Each theme has its own user-wallpapers/ directory.
--
-- @tparam string tag_name Tag name (e.g. "3")
-- @tparam string source_path Absolute path to source wallpaper image
-- @treturn boolean True if saved and applied successfully
function wallpaper.save_to_theme(tag_name, source_path)
	if not source_path or source_path == "" then return false end
	if not wallpaper._user_wppath then return false end
	-- Validate tag_name: only safe basenames (no path traversal)
	if not tag_name or tag_name == "" then return false end
	if tag_name:match("[/\\]") or tag_name == ".." or tag_name == "." then return false end
	if not gears.filesystem.file_readable(source_path) then return false end

	-- Determine extension from source, whitelist only image extensions
	local ext = source_path:match("%.([^%.]+)$") or "jpg"
	ext = ext:lower()
	if not SAFE_EXT[ext] then ext = "jpg" end

	-- Ensure user-wallpapers/ directory exists
	-- Use Lua's lfs or fallback to safe os.execute with single-quote escaping
	local safe_path = wallpaper._user_wppath:gsub("'", "'\\''")
	os.execute("mkdir -p -- '" .. safe_path .. "'")

	-- Remove any existing file for this tag in user-wallpapers/ (different ext)
	for _, e in ipairs({ "jpg", "jpeg", "png", "webp" }) do
		local old = wallpaper._user_wppath .. tag_name .. "." .. e
		os.remove(old)
	end

	-- Copy source to user-wallpapers dir
	local dest = wallpaper._user_wppath .. tag_name .. "." .. ext
	local src_file = io.open(source_path, "rb")
	if not src_file then return false end
	local data = src_file:read("*a")
	src_file:close()

	local dst_file = io.open(dest, "wb")
	if not dst_file then return false end
	dst_file:write(data)
	dst_file:close()

	-- Clear any in-memory override (user-wallpapers file is the source now)
	wallpaper._overrides[tag_name] = nil

	-- Apply immediately on all screens showing this tag
	for scr in screen do
		local sel = scr.selected_tag
		if sel and sel.name == tag_name then
			scr._current_wallpaper = nil  -- force re-apply
			apply_wallpaper(scr, dest)
		end
	end

	broker.emit_signal("data::wallpaper", wallpaper._get_state())
	return true
end

--- Set the main wallpaper (tag "1" override).
-- Convenience function for the shell wallpaper picker.
-- @tparam string path Absolute path to wallpaper image
function wallpaper.set_main_wallpaper(path)
	wallpaper.set_override("1", path)
end

--- Get current wallpaper state as a table.
-- @treturn table { current, overrides, wppath, user_wppath, browse_dirs }
function wallpaper._get_state()
	local current = nil
	local focused = awful.screen.focused()
	if focused then
		current = focused._current_wallpaper
	end
	return {
		current = current or "",
		overrides = wallpaper._overrides,
		wppath = wallpaper._wppath or "",
		user_wppath = wallpaper._user_wppath or "",
		browse_dirs = wallpaper._browse_dirs,
	}
end

--- Get overrides as JSON string (for IPC).
-- @treturn string JSON representation of override map
function wallpaper.get_overrides_json()
	local parts = {}
	for k, v in pairs(wallpaper._overrides) do
		local ek = k:gsub('\\', '\\\\'):gsub('"', '\\"')
		local ev = v:gsub('\\', '\\\\'):gsub('"', '\\"')
		table.insert(parts, '"' .. ek .. '":"' .. ev .. '"')
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

--- Get the current wallpaper path for the focused screen (for IPC).
-- @treturn string Current wallpaper path or empty string
function wallpaper.get_current()
	local focused = awful.screen.focused()
	return focused and focused._current_wallpaper or ""
end

--- Get browse directories as JSON array (for IPC).
-- @treturn string JSON array of directory paths
function wallpaper.get_browse_dirs_json()
	local parts = {}
	for _, dir in ipairs(wallpaper._browse_dirs) do
		local ed = dir:gsub('\\', '\\\\'):gsub('"', '\\"')
		table.insert(parts, '"' .. ed .. '"')
	end
	return "[" .. table.concat(parts, ",") .. "]"
end

--- Get tag names from the focused screen as JSON array (for IPC).
-- @treturn string JSON array of tag name strings
function wallpaper.get_tags_json()
	local focused = awful.screen.focused()
	if not focused then return "[]" end
	local parts = {}
	for _, tag in ipairs(focused.tags) do
		local et = tag.name:gsub('\\', '\\\\'):gsub('"', '\\"')
		table.insert(parts, '"' .. et .. '"')
	end
	return "[" .. table.concat(parts, ",") .. "]"
end

--- Get the active theme wallpapers directory path (for IPC).
-- @treturn string Path to active theme's wallpapers/ directory
function wallpaper.get_theme_wallpapers_dir()
	return wallpaper._wppath or ""
end

--- Switch to a specific tag on the focused screen (for IPC).
-- Used by the wallpaper picker tag selector.
-- @tparam string tag_name Tag name to switch to
function wallpaper.view_tag(tag_name)
	local focused = awful.screen.focused()
	if not focused then return end
	for _, tag in ipairs(focused.tags) do
		if tag.name == tag_name then
			tag:view_only()
			return
		end
	end
end

--- Apply a wallpaper to a screen (public wrapper for theme switching).
-- @tparam screen scr The screen object
-- @tparam string path Absolute path to wallpaper image
-- @treturn boolean True if applied
function wallpaper.apply(scr, path)
	return apply_wallpaper(scr, path)
end

return wallpaper
