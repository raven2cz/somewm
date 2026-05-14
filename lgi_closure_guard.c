/* lgi_closure_guard.c — LD_PRELOAD interposition for Lgi FFI closures.
 *
 * Two-layer defense against stale Lgi FFI closures surviving Lua hot-reload:
 *
 * 1. Closure wrapper (existing): ffi_prep_closure_loc is interposed so each
 *    Lgi-originated closure is tagged with a generation + routed through a
 *    wrapper callback. The wrapper blocks dispatch when the guard is not
 *    ready or the wrapper's generation is stale, and validates Lgi internal
 *    state (thread_ref, callable_ref) before invoking the real function.
 *
 * 2. Closure rewiring (new): during hot-reload the guard iterates every
 *    wrapped closure and re-calls ffi_prep_closure_loc on it with a safe
 *    CIF (void return, zero args) and a no-op user function. After this,
 *    any subsequent dispatch of that closure goes through libffi with the
 *    safe CIF — classify_argument cannot fault because there are no args
 *    to classify, and the no-op is plain C (no libffi re-entry).
 *
 * Rationale: libffi's closure_unix64_inner calls examine_argument /
 * classify_argument BEFORE invoking our wrapper, reading cif->arg_types.
 * If that memory is freed (confirmed in crash dump 2026-04-16 PID 90539),
 * the crash happens before the generation check can run. Rewiring replaces
 * the closure's CIF pointer with a guard-owned safe CIF so the walk is
 * safe regardless of what happened to Lgi's original CIF.
 *
 * Entry points (resolved via dlsym from the compositor):
 *   lgi_guard_begin_reload()  — call early in hot-reload (after lua_gc STOP).
 *   lgi_guard_mark_ready()    — call at very end of hot-reload.
 *   lgi_guard_bump_generation() — legacy alias, calls begin_reload.
 *
 * Build: shared_library in meson.build
 * Usage: LD_PRELOAD=/usr/local/lib/liblgi_closure_guard.so somewm
 */

#define _GNU_SOURCE
#include <ffi.h>
#include <glib.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include <lua.h>
#include <lauxlib.h>

/* ================================================================
 * Lgi internal structures (from lgi/callable.c, version 0.9.2)
 * Replicated here to validate closure state before dispatch.
 * ================================================================ */

typedef struct _LgiCallback {
	lua_State *L;
	int thread_ref;
	gpointer state_lock;
} LgiCallback;

typedef struct _LgiFfiClosureBlock LgiFfiClosureBlock;

typedef struct _LgiFfiClosure {
	ffi_closure ffi_closure_inner;
	LgiFfiClosureBlock *block;
	union {
		struct {
			int callable_ref;
			int target_ref;
		};
		gpointer call_addr;
	};
	guint autodestroy : 1;
	guint created : 1;
} LgiFfiClosure;

struct _LgiFfiClosureBlock {
	LgiFfiClosure ffi_closure;  /* first closure inline */
	LgiCallback callback;
	int closures_count;
	LgiFfiClosure *ffi_closures[1];
};

/* ================================================================
 * Guard state
 * ================================================================ */

/* generation: bumped on each begin_reload. Wrappers store the generation
 * they were created under; mismatch = stale.
 * ready_gen: snapshot of generation at mark_ready. A wrapper may run iff
 * w->generation == ready_gen (plus ready == 1). */
static volatile gint lgi_guard_generation = 0;
static volatile gint lgi_guard_ready_gen = 0;

/* ready: 0 during reload window, 1 otherwise. Belt + suspender with
 * generation check. Starts 1 so initial startup closures can run. */
static volatile gint lgi_guard_ready = 1;

/* Counters for observability */
static volatile gint lgi_guard_wrapped = 0;
static volatile gint lgi_guard_total = 0;
static volatile gint lgi_guard_blocked = 0;
static volatile gint lgi_guard_rewired_total = 0;

/* Registry of wrapped closures for rewiring on reload.
 * Keyed by codeloc (the executable address returned from ffi_closure_alloc).
 * Value is LgiGuardWrapper * (also contains closure + codeloc for rewire). */
static GHashTable *closure_registry = NULL;
static GMutex registry_mutex;

/* Safe CIF used to rewire stale closures: void return, zero arguments.
 * classify_argument walks zero args = no read of invalid arg_types. */
static ffi_cif safe_cif;
static gboolean safe_cif_ready = FALSE;

/* Original function pointers resolved via dlsym. Needed both for interpose
 * fall-through and for closure rewiring at reload time. */
static ffi_status (*real_ffi_prep)(
	ffi_closure *, ffi_cif *,
	void (*)(ffi_cif *, void *, void **, void *), void *, void *) = NULL;
static void (*real_ffi_free)(void *) = NULL;

/* ================================================================
 * Closure wrapper + safe no-op
 * ================================================================ */

typedef struct {
	void (*real_fn)(ffi_cif *, void *, void **, void *);
	void *real_user_data;
	gint generation;
	ffi_closure *closure;   /* writable pointer for real_ffi_prep on rewire */
	void *codeloc;          /* executable address, also registry key */
	gboolean freed;         /* set by ffi_closure_free interpose */
} LgiGuardWrapper;

/* Safe no-op used after rewiring. Takes a zero-arg void-return CIF, so
 * classify_argument has nothing to walk. Any `ret` passed is just zeroed
 * as a defensive paranoia (safe_cif says void rtype, so ret should be
 * ignored by callers). */
static void
lgi_guard_safe_noop(ffi_cif *cif, void *ret, void **args, void *user_data)
{
	(void)cif;
	(void)args;
	(void)user_data;
	if (ret)
		*(guintptr *)ret = 0;
}

static void
prepare_safe_cif_if_needed(void)
{
	if (safe_cif_ready)
		return;
	/* void(void) signature — ffi_prep_cif uses static ffi_type_void pointer
	 * which lives for process lifetime. nargs = 0 means atypes is unused. */
	ffi_status st = ffi_prep_cif(&safe_cif, FFI_DEFAULT_ABI, 0,
				     &ffi_type_void, NULL);
	if (st != FFI_OK) {
		fprintf(stderr, "somewm: lgi_guard: failed to prep safe_cif "
			"(status %d); rewiring disabled\n", (int)st);
		return;
	}
	safe_cif_ready = TRUE;
}

/* Validate that the Lgi closure's internal state is usable.
 * Returns TRUE if the closure can safely be dispatched.
 * Mirrors the checks closure_callback does before calling into Lua. */
static gboolean
lgi_closure_is_valid(void *closure_arg)
{
	LgiFfiClosure *closure = closure_arg;
	if (!closure || !closure->block)
		return FALSE;

	LgiFfiClosureBlock *block = closure->block;
	lua_State *L = block->callback.L;
	if (!L)
		return FALSE;

	int top = lua_gettop(L);

	/* Check thread_ref — closure_callback does this first */
	lua_rawgeti(L, LUA_REGISTRYINDEX, block->callback.thread_ref);
	if (lua_type(L, -1) != LUA_TTHREAD) {
		lua_settop(L, top);
		return FALSE;
	}
	lua_State *thread_L = lua_tothread(L, -1);
	lua_settop(L, top);
	if (!thread_L)
		return FALSE;

	/* Check callable_ref — this is what crashes as NULL */
	int thread_top = lua_gettop(thread_L);
	lua_rawgeti(thread_L, LUA_REGISTRYINDEX, closure->callable_ref);
	gboolean valid = (lua_touserdata(thread_L, -1) != NULL);
	lua_settop(thread_L, thread_top);

	return valid;
}

static void
lgi_guard_callback(ffi_cif *cif, void *ret, void **args, void *user_data)
{
	LgiGuardWrapper *w = user_data;

	/* Gate 1: ready flag — 0 during reload window regardless of generation. */
	if (!g_atomic_int_get(&lgi_guard_ready)) {
		g_atomic_int_add(&lgi_guard_blocked, 1);
		if (ret && cif->rtype && cif->rtype->size > 0)
			memset(ret, 0, cif->rtype->size);
		return;
	}

	/* Gate 2: generation check — stale closures from previous state. */
	gint ready = g_atomic_int_get(&lgi_guard_ready_gen);
	if (w->generation != ready) {
		g_atomic_int_add(&lgi_guard_blocked, 1);
		if (ret && cif->rtype && cif->rtype->size > 0)
			memset(ret, 0, cif->rtype->size);
		return;
	}

	/* Gate 3: Lgi internal state still valid */
	if (!lgi_closure_is_valid(w->real_user_data)) {
		g_atomic_int_add(&lgi_guard_blocked, 1);
		if (ret && cif->rtype && cif->rtype->size > 0)
			memset(ret, 0, cif->rtype->size);
		return;
	}

	w->real_fn(cif, ret, args, w->real_user_data);
}

/* ================================================================
 * Reload entry points (called from compositor via dlsym)
 * ================================================================ */

/* Rewire every tracked (non-freed) closure to the safe no-op.
 * Safe to call multiple times; safe if registry is empty. */
static int
rewire_all_closures_locked(void)
{
	if (!closure_registry)
		return 0;
	if (!real_ffi_prep)
		return 0;
	prepare_safe_cif_if_needed();
	if (!safe_cif_ready)
		return 0;

	int rewired = 0;
	GHashTableIter iter;
	gpointer key, val;
	g_hash_table_iter_init(&iter, closure_registry);
	while (g_hash_table_iter_next(&iter, &key, &val)) {
		LgiGuardWrapper *w = val;
		if (w->freed || !w->closure || !w->codeloc)
			continue;
		ffi_status st = real_ffi_prep(w->closure, &safe_cif,
					      lgi_guard_safe_noop, NULL,
					      w->codeloc);
		if (st == FFI_OK)
			rewired++;
	}
	return rewired;
}

void lgi_guard_begin_reload(void)
{
	/* Gate all dispatch immediately */
	g_atomic_int_set(&lgi_guard_ready, 0);
	gint new_gen = g_atomic_int_add(&lgi_guard_generation, 1) + 1;

	/* Rewire closures so libffi cannot fault on stale CIFs during/after
	 * the reload teardown window. */
	g_mutex_lock(&registry_mutex);
	int rewired = rewire_all_closures_locked();
	g_mutex_unlock(&registry_mutex);

	g_atomic_int_add(&lgi_guard_rewired_total, rewired);

	fprintf(stderr, "somewm: lgi_guard: begin_reload gen=%d "
		"(rewired %d closures; wrapped %d/%d; blocked %d; "
		"rewired_total %d)\n",
		new_gen, rewired,
		g_atomic_int_get(&lgi_guard_wrapped),
		g_atomic_int_get(&lgi_guard_total),
		g_atomic_int_get(&lgi_guard_blocked),
		g_atomic_int_get(&lgi_guard_rewired_total));
}

/* Backward compatible alias — callers using the old entry point still work. */
void lgi_guard_bump_generation(void)
{
	lgi_guard_begin_reload();
}

void lgi_guard_mark_ready(void)
{
	gint gen = g_atomic_int_get(&lgi_guard_generation);
	g_atomic_int_set(&lgi_guard_ready_gen, gen);
	g_atomic_int_set(&lgi_guard_ready, 1);
	fprintf(stderr, "somewm: lgi_guard: generation %d marked ready\n", gen);
}

/* ================================================================
 * Lgi detection + interposition
 * ================================================================ */

static gboolean
is_lgi_function(void (*fun)(ffi_cif *, void *, void **, void *))
{
	Dl_info info;
	if (!dladdr((void *)(fun), &info))
		return FALSE;
	if (!info.dli_fname)
		return FALSE;
	return strstr(info.dli_fname, "corelgi") != NULL;
}

__asm__(".symver ffi_prep_closure_loc_impl,ffi_prep_closure_loc@@LIBFFI_CLOSURE_8.0");

ffi_status
ffi_prep_closure_loc_impl(ffi_closure *closure, ffi_cif *cif,
	void (*fun)(ffi_cif *, void *, void **, void *),
	void *user_data, void *codeloc)
{
	if (!real_ffi_prep) {
		real_ffi_prep = dlvsym(RTLD_NEXT, "ffi_prep_closure_loc",
			"LIBFFI_CLOSURE_8.0");
	}
	if (!real_ffi_prep)
		real_ffi_prep = dlsym(RTLD_NEXT, "ffi_prep_closure_loc");

	g_atomic_int_add(&lgi_guard_total, 1);

	/* If fun is our own safe_noop, this is a rewire call from
	 * lgi_guard_begin_reload — pass through unwrapped. */
	if (fun == lgi_guard_safe_noop)
		return real_ffi_prep(closure, cif, fun, user_data, codeloc);

	if (!is_lgi_function(fun))
		return real_ffi_prep(closure, cif, fun, user_data, codeloc);

	LgiGuardWrapper *w = malloc(sizeof(*w));
	if (!w)
		return real_ffi_prep(closure, cif, fun, user_data, codeloc);

	w->real_fn = fun;
	w->real_user_data = user_data;
	w->generation = g_atomic_int_get(&lgi_guard_generation);
	w->closure = closure;
	w->codeloc = codeloc;
	w->freed = FALSE;

	g_atomic_int_add(&lgi_guard_wrapped, 1);

	/* Register in closure tracker for future rewiring. Keyed by codeloc
	 * because ffi_closure_free gives us the writable closure pointer and
	 * we need a lookup key that matches what we stored. We store by
	 * codeloc and also keep closure in the wrapper; on free we iterate
	 * to find the matching closure (free is infrequent). */
	g_mutex_lock(&registry_mutex);
	if (!closure_registry)
		closure_registry = g_hash_table_new(g_direct_hash, g_direct_equal);

	/* Replace any prior wrapper at this codeloc (ffi_prep_closure_loc is
	 * allowed to be called repeatedly on the same closure). */
	LgiGuardWrapper *old = g_hash_table_lookup(closure_registry, codeloc);
	if (old) {
		g_hash_table_remove(closure_registry, codeloc);
		free(old);
	}
	g_hash_table_insert(closure_registry, codeloc, w);
	g_mutex_unlock(&registry_mutex);

	return real_ffi_prep(closure, cif, lgi_guard_callback, w, codeloc);
}

__asm__(".symver ffi_closure_free_impl,ffi_closure_free@@LIBFFI_CLOSURE_8.0");

void
ffi_closure_free_impl(void *closure)
{
	if (!real_ffi_free) {
		real_ffi_free = dlvsym(RTLD_NEXT, "ffi_closure_free",
			"LIBFFI_CLOSURE_8.0");
	}
	if (!real_ffi_free)
		real_ffi_free = dlsym(RTLD_NEXT, "ffi_closure_free");

	/* Remove any matching wrapper from the registry so rewiring does not
	 * touch freed closure memory. Linear scan: free is rare compared to
	 * prep, so O(n) here is fine. */
	if (closure) {
		g_mutex_lock(&registry_mutex);
		if (closure_registry) {
			GHashTableIter iter;
			gpointer key, val;
			g_hash_table_iter_init(&iter, closure_registry);
			while (g_hash_table_iter_next(&iter, &key, &val)) {
				LgiGuardWrapper *w = val;
				if (w->closure == closure) {
					g_hash_table_iter_remove(&iter);
					free(w);
					break;
				}
			}
		}
		g_mutex_unlock(&registry_mutex);
	}

	if (real_ffi_free)
		real_ffi_free(closure);
}
