/* somewm_memory.c — read-only memory introspection API for the
 * `somewm.memory` Lua namespace.
 *
 * Exposes three helpers used to separate somewm-owned allocations
 * from driver / wlroots / libc fragmentation when investigating RSS
 * growth. All functions are observation-only; live counter book-keeping
 * for SHM/wibox surfaces lives next to the producing call sites
 * (drawable.c, wibox.c) and writes into globalconf.memory_stats.
 *
 * Lua surface (registered as a global `somewm` table at startup):
 *
 *   somewm.memory.stats(force_gc)        -> aggregate snapshot table
 *   somewm.memory.wallpaper_cache(deep)  -> per-entry cache breakdown
 *   somewm.memory.drawables()            -> drawin/titlebar surface bytes
 *
 * History: this API originally lived under `root.*` (see issue #508).
 * It was moved here per maintainer review (JimmyCozza) — `root.*`
 * mirrors the AwesomeWM-compatible surface and exists for portability,
 * while observation helpers belong with the somewm-specific extensions
 * that 2.x cleanup is consolidating under `somewm.*`.
 */

#include "somewm_memory.h"
#include "globalconf.h"
#include "luaa.h"
#include "objects/drawable.h"
#include "objects/drawin.h"
#include "objects/client.h"
#include <cairo.h>
#include <stdbool.h>
#include <wayland-util.h>
#ifdef __GLIBC__
#include <malloc.h>
#endif

/* wallpaper_cache_entry_is_current() lives in root.c with the rest of
 * the wallpaper cache machinery; its prototype is in globalconf.h. */

static size_t
cairo_image_surface_bytes(cairo_surface_t *surface)
{
	if (!surface || cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS ||
			cairo_surface_get_type(surface) != CAIRO_SURFACE_TYPE_IMAGE)
		return 0;
	return (size_t)cairo_image_surface_get_stride(surface) *
		(size_t)cairo_image_surface_get_height(surface);
}

static void
lua_set_size_field(lua_State *L, const char *key, size_t value)
{
	lua_pushinteger(L, (lua_Integer)value);
	lua_setfield(L, -2, key);
}

static void
lua_set_int_field(lua_State *L, const char *key, int value)
{
	lua_pushinteger(L, value);
	lua_setfield(L, -2, key);
}

static void
push_wallpaper_cache_stats(lua_State *L, bool details)
{
	wallpaper_cache_entry_t *entry;
	int count = 0, current = 0;
	size_t cairo_bytes = 0, shm_bytes = 0;

	lua_newtable(L);

	if (globalconf.wallpaper_cache.next) {
		wl_list_for_each(entry, &globalconf.wallpaper_cache, link) {
			count++;
			if (wallpaper_cache_entry_is_current(entry))
				current++;
			cairo_bytes += entry->cairo_bytes ? entry->cairo_bytes :
				cairo_image_surface_bytes(entry->surface);
			shm_bytes += entry->shm_bytes;
		}
	}

	lua_set_int_field(L, "entries", count);
	lua_set_int_field(L, "current_entries", current);
	lua_set_int_field(L, "max_entries", WALLPAPER_CACHE_MAX);
	lua_set_size_field(L, "cairo_bytes", cairo_bytes);
	lua_set_size_field(L, "shm_bytes", shm_bytes);
	lua_set_size_field(L, "estimated_bytes", cairo_bytes + shm_bytes);
	lua_set_size_field(L, "current_wallpaper_bytes",
		cairo_image_surface_bytes(globalconf.wallpaper));

	if (details) {
		int idx = 1;
		lua_createtable(L, count, 0);
		if (globalconf.wallpaper_cache.next) {
			wl_list_for_each(entry, &globalconf.wallpaper_cache, link) {
				lua_createtable(L, 0, 8);
				lua_pushstring(L, entry->path ? entry->path : "");
				lua_setfield(L, -2, "path");
				lua_set_int_field(L, "screen_index", entry->screen_index + 1);
				lua_set_int_field(L, "width", entry->width);
				lua_set_int_field(L, "height", entry->height);
				lua_set_size_field(L, "cairo_bytes", entry->cairo_bytes);
				lua_set_size_field(L, "shm_bytes", entry->shm_bytes);
				lua_pushboolean(L, wallpaper_cache_entry_is_current(entry));
				lua_setfield(L, -2, "current");
				lua_rawseti(L, -2, idx++);
			}
		}
		lua_setfield(L, -2, "items");
	}
}

static void
accumulate_drawable_surface(drawable_t *drawable, int *count, size_t *surface_bytes)
{
	if (!drawable)
		return;
	(*count)++;
	*surface_bytes += cairo_image_surface_bytes(drawable->surface);
}

static void
push_drawable_stats(lua_State *L)
{
	int drawin_drawables = 0, titlebar_drawables = 0;
	size_t drawin_surface_bytes = 0, titlebar_surface_bytes = 0;
	size_t shape_bytes = 0;

	for (int i = 0; i < globalconf.drawins.len; i++) {
		drawin_t *drawin = globalconf.drawins.tab[i];
		if (!drawin)
			continue;
		accumulate_drawable_surface(drawin->drawable,
			&drawin_drawables, &drawin_surface_bytes);
		shape_bytes += cairo_image_surface_bytes(drawin->shape_bounding);
		shape_bytes += cairo_image_surface_bytes(drawin->shape_clip);
		shape_bytes += cairo_image_surface_bytes(drawin->shape_input);
		shape_bytes += cairo_image_surface_bytes(drawin->shape_border);
	}

	for (int i = 0; i < globalconf.clients.len; i++) {
		client_t *client = globalconf.clients.tab[i];
		if (!client)
			continue;
		for (client_titlebar_t bar = CLIENT_TITLEBAR_TOP;
				bar < CLIENT_TITLEBAR_COUNT; bar++) {
			accumulate_drawable_surface(client->titlebar[bar].drawable,
				&titlebar_drawables, &titlebar_surface_bytes);
		}
	}

	lua_newtable(L);
	lua_set_int_field(L, "drawin_drawables", drawin_drawables);
	lua_set_size_field(L, "drawin_surface_bytes", drawin_surface_bytes);
	lua_set_int_field(L, "titlebar_drawables", titlebar_drawables);
	lua_set_size_field(L, "titlebar_surface_bytes", titlebar_surface_bytes);
	lua_set_size_field(L, "shape_surface_bytes", shape_bytes);
	lua_set_size_field(L, "surface_bytes",
		drawin_surface_bytes + titlebar_surface_bytes + shape_bytes);
	lua_set_size_field(L, "drawable_shm_count",
		globalconf.memory_stats.drawable_shm_count);
	lua_set_size_field(L, "drawable_shm_bytes",
		globalconf.memory_stats.drawable_shm_bytes);
}

static int
luaA_somewm_memory_wallpaper_cache(lua_State *L)
{
	bool details = lua_toboolean(L, 1);
	push_wallpaper_cache_stats(L, details);
	return 1;
}

static int
luaA_somewm_memory_drawables(lua_State *L)
{
	push_drawable_stats(L);
	return 1;
}

static int
luaA_somewm_memory_stats(lua_State *L)
{
	if (lua_toboolean(L, 1)) {
		lua_gc(L, LUA_GCCOLLECT, 0);
		lua_gc(L, LUA_GCCOLLECT, 0);
	}

	int lua_kb = lua_gc(L, LUA_GCCOUNT, 0);
	int lua_b = lua_gc(L, LUA_GCCOUNTB, 0);

	lua_newtable(L);
	lua_set_size_field(L, "lua_bytes", (size_t)lua_kb * 1024 + (size_t)lua_b);
	lua_set_int_field(L, "clients", globalconf.clients.len);
	lua_set_int_field(L, "screens", globalconf.screens.len);
	lua_set_int_field(L, "tags", globalconf.tags.len);
	lua_set_int_field(L, "drawins", globalconf.drawins.len);
	lua_set_size_field(L, "drawable_shm_count",
		globalconf.memory_stats.drawable_shm_count);
	lua_set_size_field(L, "drawable_shm_bytes",
		globalconf.memory_stats.drawable_shm_bytes);
	lua_set_size_field(L, "wibox_count", globalconf.memory_stats.wibox_count);
	lua_set_size_field(L, "wibox_surface_bytes",
		globalconf.memory_stats.wibox_surface_bytes);

#ifdef __GLIBC__
	struct mallinfo2 mi = mallinfo2();
	lua_set_size_field(L, "malloc_arena_bytes", (size_t)mi.arena);
	lua_set_size_field(L, "malloc_used_bytes", (size_t)mi.uordblks);
	lua_set_size_field(L, "malloc_free_bytes", (size_t)mi.fordblks);
	lua_set_size_field(L, "malloc_releasable_bytes", (size_t)mi.keepcost);
#endif

	push_wallpaper_cache_stats(L, false);
	lua_setfield(L, -2, "wallpaper");
	push_drawable_stats(L);
	lua_setfield(L, -2, "drawables");

	return 1;
}

static const luaL_Reg somewm_memory_methods[] = {
	{ "stats", luaA_somewm_memory_stats },
	{ "wallpaper_cache", luaA_somewm_memory_wallpaper_cache },
	{ "drawables", luaA_somewm_memory_drawables },
	{ NULL, NULL }
};

/** Register the `somewm` global with a `memory` subtable.
 *
 * Layout:
 *   _G.somewm        -> table
 *   _G.somewm.memory -> { stats, wallpaper_cache, drawables }
 *
 * Lua-side modules under lua/somewm/ (e.g. tag_slide, layout_animation)
 * remain accessible via the standard `require("somewm.<name>")` module
 * path; the global table and the Lua module path are independent
 * namespaces — same convention AwesomeWM uses for `awesome` (global)
 * vs `awful` / `gears` (modules). */
void
luaA_somewm_memory_setup(lua_State *L)
{
	/* Build the memory subtable on the stack first. */
	lua_newtable(L);
	luaA_setfuncs(L, somewm_memory_methods);

	/* Reuse an existing _G.somewm table if another somewm.<...> setup
	 * ran before us; otherwise (nil or any non-table) install a fresh
	 * table. The non-table guard avoids a runtime error from
	 * lua_setfield below if user config or a future patch ever shadows
	 * the global with a non-table value. */
	lua_getglobal(L, "somewm");
	if (!lua_istable(L, -1)) {
		lua_pop(L, 1);
		lua_newtable(L);
		lua_pushvalue(L, -1);
		lua_setglobal(L, "somewm");
	}

	/* Stack: [ ... ; memory ; somewm ]. Move memory under somewm.memory. */
	lua_pushvalue(L, -2);
	lua_setfield(L, -2, "memory");

	lua_pop(L, 2); /* somewm + memory */
}
