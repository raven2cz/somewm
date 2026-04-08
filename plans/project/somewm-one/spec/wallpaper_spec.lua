---------------------------------------------------------------------------
--- Tests for fishlive.services.wallpaper
---------------------------------------------------------------------------

package.path = "./plans/project/somewm-one/?.lua;" .. package.path

-- Mock dependencies
local mock_broker_signals = {}
package.preload["fishlive.broker"] = function()
	return {
		emit_signal = function(name, data)
			table.insert(mock_broker_signals, { name = name, data = data })
		end,
	}
end

package.preload["awful"] = function()
	return {
		wallpaper = function(args)
			return { screen = args.screen, widget = args.widget }
		end,
		screen = { focused = function() return nil end },
	}
end

package.preload["gears"] = function()
	return {
		filesystem = {
			file_readable = function(path)
				-- Mock: files in test_wallpapers/ are "readable"
				return path and path:match("test_wallpapers/") ~= nil
			end,
		},
	}
end

package.preload["gears.filesystem"] = function()
	return require("gears").filesystem
end

local mock_imagebox = {}
package.preload["wibox"] = function()
	return {
		widget = {
			imagebox = function(...)
				local w = { image = select(1, ...) or "", _type = "imagebox" }
				table.insert(mock_imagebox, w)
				return w
			end,
		},
		container = {
			tile = "tile_container",
		},
	}
end

package.preload["wibox.widget"] = function()
	return require("wibox").widget
end

package.preload["wibox.widget.imagebox"] = function()
	return require("wibox").widget.imagebox
end

-- Stub global screen iterator
local mock_screens = {}
_G.screen = setmetatable({}, {
	__call = function()
		local i = 0
		return function()
			i = i + 1
			return mock_screens[i]
		end
	end,
})

describe("wallpaper service", function()
	local wallpaper

	before_each(function()
		-- Reset module
		package.loaded["fishlive.services.wallpaper"] = nil
		mock_broker_signals = {}
		mock_imagebox = {}
		mock_screens = {}
		wallpaper = require("fishlive.services.wallpaper")
	end)

	describe("_resolve", function()
		it("returns nil when not initialized", function()
			assert.is_nil(wallpaper._resolve("1"))
		end)

		it("returns default fallback when wppath set", function()
			wallpaper._wppath = "test_wallpapers/"
			wallpaper._default = "1.jpg"
			local result = wallpaper._resolve("1")
			assert.equals("test_wallpapers/1.jpg", result)
		end)

		it("returns theme-based path when file exists", function()
			wallpaper._wppath = "test_wallpapers/"
			wallpaper._default = "1.jpg"
			local result = wallpaper._resolve("3")
			-- 3.jpg would be tried first
			assert.equals("test_wallpapers/3.jpg", result)
		end)

		it("returns override when set", function()
			wallpaper._wppath = "test_wallpapers/"
			wallpaper._default = "1.jpg"
			wallpaper._overrides["3"] = "test_wallpapers/custom.jpg"
			local result = wallpaper._resolve("3")
			assert.equals("test_wallpapers/custom.jpg", result)
		end)

		it("override takes priority over theme-based", function()
			wallpaper._wppath = "test_wallpapers/"
			wallpaper._default = "1.jpg"
			wallpaper._overrides["1"] = "test_wallpapers/override.jpg"
			local result = wallpaper._resolve("1")
			assert.equals("test_wallpapers/override.jpg", result)
		end)

		it("falls back to default when override file is gone", function()
			wallpaper._wppath = "test_wallpapers/"
			wallpaper._default = "1.jpg"
			wallpaper._overrides["3"] = "/nonexistent/file.jpg"
			local result = wallpaper._resolve("3")
			-- Override cleared, falls through to theme-based
			assert.equals("test_wallpapers/3.jpg", result)
			assert.is_nil(wallpaper._overrides["3"])
		end)
	end)

	describe("set_override", function()
		it("stores override and emits signal", function()
			wallpaper._wppath = "test_wallpapers/"
			wallpaper.set_override("5", "test_wallpapers/new.jpg")
			assert.equals("test_wallpapers/new.jpg", wallpaper._overrides["5"])
			assert.equals(1, #mock_broker_signals)
			assert.equals("data::wallpaper", mock_broker_signals[1].name)
		end)

		it("ignores empty path", function()
			wallpaper.set_override("1", "")
			assert.is_nil(wallpaper._overrides["1"])
		end)
	end)

	describe("clear_override", function()
		it("removes override and emits signal", function()
			wallpaper._wppath = "test_wallpapers/"
			wallpaper._overrides["3"] = "test_wallpapers/old.jpg"
			wallpaper.clear_override("3")
			assert.is_nil(wallpaper._overrides["3"])
			assert.equals(1, #mock_broker_signals)
		end)
	end)

	describe("save_to_theme", function()
		it("returns false when wppath not set", function()
			assert.is_false(wallpaper.save_to_theme("1", "test_wallpapers/new.jpg"))
		end)

		it("returns false for empty source_path", function()
			wallpaper._wppath = "test_wallpapers/"
			assert.is_false(wallpaper.save_to_theme("1", ""))
		end)

		it("returns false for unreadable source", function()
			wallpaper._wppath = "test_wallpapers/"
			assert.is_false(wallpaper.save_to_theme("1", "/nonexistent/file.jpg"))
		end)

		-- Note: full save_to_theme test requires filesystem access
		-- which is tested in integration tests
	end)

	describe("get_overrides_json", function()
		it("returns empty object when no overrides", function()
			assert.equals("{}", wallpaper.get_overrides_json())
		end)

		it("returns JSON with overrides", function()
			wallpaper._overrides["1"] = "/path/to/wall.jpg"
			local json = wallpaper.get_overrides_json()
			assert.truthy(json:match('"1"'))
			assert.truthy(json:match('wall%.jpg'))
		end)
	end)

	describe("get_current", function()
		it("returns empty string when no screen focused", function()
			assert.equals("", wallpaper.get_current())
		end)
	end)

	describe("apply", function()
		it("is a public function", function()
			assert.is_function(wallpaper.apply)
		end)
	end)
end)
