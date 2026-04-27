/* somewm_memory.h — public entry point for the somewm.memory Lua API.
 *
 * The setup function builds `_G.somewm.memory` with three observation
 * helpers: stats / wallpaper_cache / drawables. See somewm_memory.c
 * for the full surface and rationale.
 */

#ifndef SOMEWM_MEMORY_H
#define SOMEWM_MEMORY_H

#include <lua.h>

void luaA_somewm_memory_setup(lua_State *L);

#endif /* SOMEWM_MEMORY_H */
