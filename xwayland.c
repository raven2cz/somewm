/*
 * xwayland.c - XWayland X11 compatibility layer
 *
 * Handles X11 client lifecycle, configuration, activation, and EWMH
 * initialization for XWayland surfaces.
 */
#ifdef XWAYLAND

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <wayland-server-core.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_fractional_scale_v1.h>
#include "scenefx_compat.h"
#include <wlr/types/wlr_xcursor_manager.h>
#include <wlr/xcursor.h>
#include <wlr/xwayland.h>
#include <xcb/xcb.h>
#include <xcb/xcb_icccm.h>

#include "somewm.h"
#include "somewm_api.h"
#include "wlr_compat.h"
#include "focus.h"
#include "window.h"
#include "event_queue.h"
#include "xwayland.h"
#include "globalconf.h"
#include "common/luaobject.h"
#include "objects/signal.h"
#include "client.h"
#include "stack.h"
#include "ewmh.h"
#include "common/util.h"

/* Listener helpers */

#include "window.h"
#include "somewm_internal.h"

/* Forward declarations */
void dissociatex11(struct wl_listener *listener, void *data);
void sethints(struct wl_listener *listener, void *data);
static void unmanaged_set_geometry(struct wl_listener *listener, void *data);

/* Local listeners */
static struct wl_listener new_xwayland_surface;
static struct wl_listener xwayland_ready_listener;

/* ------------------------------------------------------------------------
 * Override-redirect (unmanaged) surfaces
 *
 * X11 clients set override_redirect on windows the window manager must not
 * touch: menus, dropdowns, tooltips, drag icons. They are not clients -- they
 * have no tags, no layout, no rules and no Lua object -- so they live here in
 * their own list and their own scene layer instead of going through the
 * client path. Mirrors sway's sway_xwayland_unmanaged.
 * ------------------------------------------------------------------------ */

static struct wl_list unmanaged_surfaces;  /* UnmanagedSurface.link */
static bool unmanaged_list_ready;

/* The unmanaged surface currently holding keyboard focus, if any.
 *
 * X11 menus keep the keyboard while they are up and close themselves on
 * FocusOut, so focus changes towards clients are suppressed for as long as
 * this is set. That protection used to be spelled `exclusive_focus = c` with
 * a Client; keeping it typed avoids the void * compared against two
 * unrelated types. */
static UnmanagedSurface *unmanaged_focus;

static void unmanaged_create(struct wlr_xwayland_surface *xsurface);
bool unmanaged_wants_focus(UnmanagedSurface *u);

static void
unmanaged_list_init(void)
{
	if (!unmanaged_list_ready) {
		wl_list_init(&unmanaged_surfaces);
		unmanaged_list_ready = true;
	}
}

/** Find the unmanaged surface owning a wlr_surface, or NULL. */
UnmanagedSurface *
unmanaged_from_surface(struct wlr_surface *surface)
{
	struct wlr_xwayland_surface *xsurface;

	if (!surface)
		return NULL;
	xsurface = wlr_xwayland_surface_try_from_wlr_surface(
			wlr_surface_get_root_surface(surface));
	if (!xsurface || !xsurface->override_redirect || !xsurface->data)
		return NULL;
	return (UnmanagedSurface *)xsurface->data;
}

/** True while an override-redirect surface owns the keyboard.
 *
 * Callers use this to leave focus alone: stealing it from an open menu makes
 * Xwayland send FocusOut and the application dismisses the menu. */
bool
unmanaged_holds_focus(void)
{
	return unmanaged_focus != NULL;
}

/** Give the keyboard to an unmanaged surface. */
static void
unmanaged_grant_focus(UnmanagedSurface *u)
{
	struct wlr_keyboard *kb;

	if (session_is_locked())
		return;

	/* Sway pattern: tell Xwayland which seat is active before every focus
	 * change to an X11 surface, or keyboard delivery goes nowhere. */
	wlr_xwayland_set_seat(xwayland, seat);

	kb = wlr_seat_get_keyboard(seat);
	if (kb)
		wlr_seat_keyboard_notify_enter(seat, u->xsurface->surface,
				kb->keycodes, kb->num_keycodes, &kb->modifiers);
	else
		wlr_seat_keyboard_notify_enter(seat, u->xsurface->surface, NULL, 0, NULL);

	unmanaged_focus = u;
}

/** Hand the keyboard back after an unmanaged surface goes away.
 *
 * Synchronous on purpose. Menus close and re-open in bursts (menu -> submenu),
 * and routing this through the deferred request::focus_restore signal let the
 * restore land after the next menu had already mapped, stealing focus from it.
 * Prefers the parent override-redirect surface, like sway does, so submenu
 * chains keep working. */
static void
unmanaged_release_focus(UnmanagedSurface *u)
{
	struct wlr_xwayland_surface *parent;

	if (unmanaged_focus != u)
		return;
	unmanaged_focus = NULL;

	parent = u->xsurface->parent;
	if (parent && parent->override_redirect && parent->surface
			&& parent->surface->mapped && parent->data
			&& unmanaged_wants_focus((UnmanagedSurface *)parent->data)) {
		unmanaged_grant_focus((UnmanagedSurface *)parent->data);
		return;
	}

	/* No parent menu left: the seat still points at the surface we are
	 * tearing down, so clear it before handing focus back to a client. */
	if (seat->keyboard_state.focused_surface == u->xsurface->surface)
		wlr_seat_keyboard_clear_focus(seat);

	focus_restore(selmon);
}

static void
unmanaged_map(struct wl_listener *listener, void *data)
{
	UnmanagedSurface *u = wl_container_of(listener, u, map);

	u->scene_surface = wlr_scene_surface_create(layers[LyrUnmanaged],
			u->xsurface->surface);
	if (!u->scene_surface) {
		warn("failed to create scene surface for unmanaged X11 window");
		return;
	}
	wlr_scene_node_set_position(&u->scene_surface->buffer->node,
			u->xsurface->x, u->xsurface->y);

	/* Xwayland moves override-redirect windows without asking the window
	 * manager and only reports it afterwards, so track it. Without this a
	 * menu that repositions after map (submenus, menus flipped to fit the
	 * screen) stays painted at its original spot. */
	LISTEN(&u->xsurface->events.set_geometry, &u->set_geometry,
			unmanaged_set_geometry);

	if (unmanaged_wants_focus(u))
		unmanaged_grant_focus(u);
}

static void
unmanaged_unmap(struct wl_listener *listener, void *data)
{
	UnmanagedSurface *u = wl_container_of(listener, u, unmap);

	if (u->scene_surface) {
		wl_list_remove(&u->set_geometry.link);
		wlr_scene_node_destroy(&u->scene_surface->buffer->node);
		u->scene_surface = NULL;
	}

	unmanaged_release_focus(u);
}

static void
unmanaged_set_geometry(struct wl_listener *listener, void *data)
{
	UnmanagedSurface *u = wl_container_of(listener, u, set_geometry);

	if (u->scene_surface)
		wlr_scene_node_set_position(&u->scene_surface->buffer->node,
				u->xsurface->x, u->xsurface->y);
}

static void
unmanaged_request_configure(struct wl_listener *listener, void *data)
{
	UnmanagedSurface *u = wl_container_of(listener, u, request_configure);
	struct wlr_xwayland_surface_configure_event *event = data;

	/* Override-redirect windows place themselves; just acknowledge. */
	wlr_xwayland_surface_configure(u->xsurface, event->x, event->y,
			event->width, event->height);
}

static void
unmanaged_request_activate(struct wl_listener *listener, void *data)
{
	UnmanagedSurface *u = wl_container_of(listener, u, request_activate);

	if (!u->xsurface->surface || !u->xsurface->surface->mapped)
		return;
	/* Same predicate as the map path: a surface with ICCCM input model NONE
	 * (tooltips, notification windows) must not be able to take the keyboard
	 * and park unmanaged_focus on itself, which would block every later
	 * focus change while it stays mapped. */
	if (unmanaged_wants_focus(u))
		unmanaged_grant_focus(u);
}

static void
unmanaged_associate(struct wl_listener *listener, void *data)
{
	UnmanagedSurface *u = wl_container_of(listener, u, associate);

	LISTEN(&u->xsurface->surface->events.map, &u->map, unmanaged_map);
	LISTEN(&u->xsurface->surface->events.unmap, &u->unmap, unmanaged_unmap);
}

static void
unmanaged_dissociate(struct wl_listener *listener, void *data)
{
	UnmanagedSurface *u = wl_container_of(listener, u, dissociate);

	wl_list_remove(&u->map.link);
	wl_list_remove(&u->unmap.link);
}

static void
unmanaged_teardown(UnmanagedSurface *u, bool associated)
{
	/* Focus state must go even when the surface never unmapped: a client
	 * that dies with a menu open would otherwise leave unmanaged_focus
	 * pointing at freed memory and block every later focus change. */
	unmanaged_release_focus(u);

	if (u->scene_surface) {
		wl_list_remove(&u->set_geometry.link);
		wlr_scene_node_destroy(&u->scene_surface->buffer->node);
		u->scene_surface = NULL;
	}
	if (associated)
		unmanaged_dissociate(&u->dissociate, NULL);

	wl_list_remove(&u->associate.link);
	wl_list_remove(&u->dissociate.link);
	wl_list_remove(&u->destroy.link);
	wl_list_remove(&u->override_redirect.link);
	wl_list_remove(&u->request_configure.link);
	wl_list_remove(&u->request_activate.link);
	wl_list_remove(&u->link);

	u->xsurface->data = NULL;
}

static void
unmanaged_destroy(struct wl_listener *listener, void *data)
{
	UnmanagedSurface *u = wl_container_of(listener, u, destroy);

	unmanaged_teardown(u, u->xsurface->surface != NULL);
	free(u);
}

/** The client flipped override_redirect on a live window.
 *
 * Wine and Qt do this when a window changes role. The two paths keep
 * completely different state, so hand the surface over instead of trying to
 * mutate it in place (same approach as sway). */
static void
unmanaged_override_redirect(struct wl_listener *listener, void *data)
{
	UnmanagedSurface *u = wl_container_of(listener, u, override_redirect);
	struct wlr_xwayland_surface *xsurface = u->xsurface;
	bool associated = xsurface->surface != NULL;
	bool mapped = associated && xsurface->surface->mapped;

	if (xsurface->override_redirect)
		return;  /* still unmanaged, nothing to do */

	unmanaged_teardown(u, associated);
	free(u);

	/* Re-enter through the managed path. createnotifyx11() attaches the
	 * client listeners; map/unmap follow from associate as usual. */
	createnotifyx11(NULL, xsurface);
	if (associated)
		associatex11(&((Client *)xsurface->data)->associate, NULL);
	if (mapped)
		mapnotify(&((Client *)xsurface->data)->map, NULL);
}

static void
unmanaged_create(struct wlr_xwayland_surface *xsurface)
{
	UnmanagedSurface *u = calloc(1, sizeof(*u));

	if (!u) {
		warn("failed to allocate unmanaged X11 surface");
		return;
	}
	unmanaged_list_init();

	u->type = X11Unmanaged;
	u->xsurface = xsurface;
	xsurface->data = u;
	wl_list_insert(&unmanaged_surfaces, &u->link);

	LISTEN(&xsurface->events.associate, &u->associate, unmanaged_associate);
	LISTEN(&xsurface->events.dissociate, &u->dissociate, unmanaged_dissociate);
	LISTEN(&xsurface->events.destroy, &u->destroy, unmanaged_destroy);
	LISTEN(&xsurface->events.set_override_redirect, &u->override_redirect,
			unmanaged_override_redirect);
	LISTEN(&xsurface->events.request_configure, &u->request_configure,
			unmanaged_request_configure);
	LISTEN(&xsurface->events.request_activate, &u->request_activate,
			unmanaged_request_activate);

	/* wl_list_remove() in teardown runs unconditionally on these two. */
	wl_list_init(&u->map.link);
	wl_list_init(&u->unmap.link);
}

/** Handle a pointer press on an unmanaged surface.
 *
 * Sway does the same in seatop_default's button handler: an override-redirect
 * surface that takes focus gets it on click, everything else is left alone.
 * No Lua signals are emitted -- these are not clients. */
void
unmanaged_click(UnmanagedSurface *u)
{
	if (!u->xsurface->surface || !u->xsurface->surface->mapped)
		return;
	if (unmanaged_focus == u)
		return;
	if (unmanaged_wants_focus(u))
		unmanaged_grant_focus(u);
}

/** A managed window turned into an override-redirect one.
 *
 * Mirror of unmanaged_override_redirect(): unmanage the client and let it come
 * back through the unmanaged path. */
void
managed_override_redirect(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, override_redirect);
	struct wlr_xwayland_surface *xsurface = c->surface.xwayland;
	bool associated = xsurface->surface != NULL;
	bool mapped = associated && xsurface->surface->mapped;

	if (!xsurface->override_redirect)
		return;  /* still managed */

	/* Detach the surface from the client before anything can look it up:
	 * override_redirect already reads true, so unmanaged_from_surface()
	 * would otherwise cast a Client to an UnmanagedSurface. */
	xsurface->data = NULL;

	/* Unmanage before tearing the scene down, the same order unmapnotify()
	 * uses: Lua request::unmanage handlers can still read properties that
	 * walk c->scene_surface (opacity, corner radius, content).
	 *
	 * DESTROYED rather than UNMAP because the window is alive and only
	 * changing role: UNMAP would send XCB unmap/reparent/withdraw to the
	 * very window we are handing over, and would park the Lua object for a
	 * remap that never comes. */
	client_unmanage(c, CLIENT_UNMANAGE_DESTROYED);

	/* mapped does not imply a scene: mapnotify() has a failure path that
	 * destroys and nulls it. */
	if (c->scene) {
		client_scene_node_destroy(c);
		client_clear_scene_child_pointers(c);
	}
	client_remove_all_listeners(c);

	unmanaged_create(xsurface);
	if (associated)
		unmanaged_associate(&((UnmanagedSurface *)xsurface->data)->associate, NULL);
	if (mapped)
		unmanaged_map(&((UnmanagedSurface *)xsurface->data)->map, NULL);
}

/** Whether this surface accepts keyboard focus (ICCCM + EWMH type). */
bool
unmanaged_wants_focus(UnmanagedSurface *u)
{
	return COMPAT_XWAYLAND_OVERRIDE_REDIRECT_WANTS_FOCUS(u->xsurface)
		&& COMPAT_XWAYLAND_ICCCM_INPUT_MODEL(u->xsurface)
		   != WLR_ICCCM_INPUT_MODEL_NONE;
}

/** True if this specific unmanaged surface holds keyboard focus. */
bool
unmanaged_surface_has_focus(UnmanagedSurface *u)
{
	return unmanaged_focus == u;
}

/** Iterate the unmanaged surfaces (introspection for tests). */
void
unmanaged_foreach(void (*cb)(UnmanagedSurface *u, void *data), void *data)
{
	UnmanagedSurface *u, *tmp;

	unmanaged_list_init();
	wl_list_for_each_safe(u, tmp, &unmanaged_surfaces, link)
		cb(u, data);
}

void
activatex11(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, activate);

	/* Guard against stale client: after client_unmanage() invalidates the
	 * client (window = XCB_NONE), this listener may still fire if the
	 * XWayland surface hasn't been destroyed yet (e.g., Discord close-to-tray
	 * then re-launch). Skip to prevent use-after-free and Lua panics. */
	if (c->window == XCB_NONE)
		return;

	/* Tell XWayland the surface is activated at the X11 level */
	wlr_xwayland_surface_activate(c->surface.xwayland, 1);

	/* Emit request::activate signal to Lua so it can grant keyboard focus.
	 * This matches the pattern used by foreign_toplevel_request_activate()
	 * and ensures XWayland clients go through the same focus permission
	 * system as native Wayland clients. */
	lua_State *L = globalconf_get_lua_State();
	luaA_object_push(L, c);
	lua_pushstring(L, "xwayland");  /* context */
	lua_newtable(L);  /* hints table */
	lua_pushboolean(L, true);
	lua_setfield(L, -2, "raise");
	some_event_queue_signal(L, -3, SIG_REQUEST_ACTIVATE, 2);
	lua_pop(L, 1);
}

void
associatex11(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, associate);
	struct wlr_surface *surface = client_surface(c);

	if (!surface) {
		return;
	}

	log_debug("[X11-ASSOC] window 0x%x surface=%p mapped=%d",
			c->window, (void *)surface, surface->mapped);

	LISTEN(&surface->events.map, &c->map, mapnotify);
	LISTEN(&surface->events.unmap, &c->unmap, unmapnotify);

	/* wlroots maps an Xwayland surface from exactly one place: its own
	 * commit handler (xwayland/xwm.c, xwayland_surface_handle_commit ->
	 * wlr_surface_map when the surface has a buffer). That handler is
	 * subscribed inside xwayland_surface_associate(), i.e. during this very
	 * call. A buffer the client committed before that point is never
	 * noticed: the surface holds a buffer, stays unmapped forever, and no
	 * map signal ever arrives. The client then sits in client.get() with no
	 * scene node, no screen, no tags and 0x0 geometry -- invisible until
	 * something forces another commit (an X11 unmap/map cycle does).
	 *
	 * Observed with Sierra Chart under Wine: a dialog would intermittently
	 * not appear at all, with exactly that state. wlroots 0.19 and 0.20
	 * both have the gap, so close it here: mapping the surface makes
	 * wlroots emit the map signal we just subscribed to.
	 *
	 * The mapped-but-no-scene branch covers the mirror case, where the map
	 * signal fired before we could subscribe. */
	if (!c->scene) {
		if (!surface->mapped && wlr_surface_has_buffer(surface)) {
			log_debug("[X11-ASSOC] buffer committed before associate, "
					"mapping surface for 0x%x", c->window);
			wlr_surface_map(surface);
		} else if (surface->mapped) {
			log_debug("[X11-ASSOC] surface already mapped, mapping 0x%x now",
					c->window);
			mapnotify(&c->map, NULL);
		}
	}
}

void
configurex11(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, configure);
	struct wlr_xwayland_surface_configure_event *event = data;
	if (c->window == XCB_NONE)
		return;
	if (!client_surface(c) || !client_surface(c)->mapped) {
		wlr_xwayland_surface_configure(c->surface.xwayland,
				event->x, event->y, event->width, event->height);
		return;
	}
	if (some_client_get_floating(c)) {
		resize(c, (struct wlr_box){.x = event->x - c->bw,
				.y = event->y - c->bw, .width = event->width,
				.height = event->height}, 0);
	} else {
		arrange(c->mon);
	}
}

void
createnotifyx11(struct wl_listener *listener, void *data)
{
	/* XWayland client creation - follows same pattern as createnotify()
	 * but adapts for XWayland-specific protocols */
	struct wlr_xwayland_surface *xsurface = data;
	Client *c;
	lua_State *L;

	/* Override-redirect windows are not window-manager clients: no tags, no
	 * layout, no rules, no Lua object. Applications create them in bulk and
	 * often never map them, so managing them here polluted client.get()
	 * with dozens of invisible entries. */
	if (xsurface->override_redirect) {
		unmanaged_create(xsurface);
		return;
	}

	L = globalconf_get_lua_State();

	/* Create Lua client object (matches AwesomeWM client_manage line 2138) */
	c = client_new(L);
	/* client_new() leaves the client on the Lua stack at index -1 */

	/* Assign unique client ID (Sway-style incrementing counter) */
	c->id = next_client_id++;

	/* Link to XWayland surface (adapts X11 window linkage to XWayland) */
	xsurface->data = c;
	c->surface.xwayland = xsurface;
	c->client_type = X11;
	/* Set the window ID for EWMH/X11 property lookups */
	c->window = xsurface->window_id;
	c->bw = get_border_width();

	/* NOTE: Do NOT call ewmh_client_check_hints() here!
	 * At this point the XWayland surface exists but may not be fully initialized.
	 * Making XCB property queries here can interfere with the XWayland protocol.
	 * EWMH hints will be read in mapnotify() when the surface is ready. */

	log_debug("[X11-CREATE] window 0x%x override_redirect=%d surface=%p",
			c->window, xsurface->override_redirect,
			(void *)xsurface->surface);

	/* Register XWayland event listeners */
	LISTEN(&xsurface->events.associate, &c->associate, associatex11);
	LISTEN(&xsurface->events.destroy, &c->destroy, destroynotify);
	LISTEN(&xsurface->events.dissociate, &c->dissociate, dissociatex11);
	LISTEN(&xsurface->events.request_activate, &c->activate, activatex11);
	LISTEN(&xsurface->events.request_configure, &c->configure, configurex11);
	LISTEN(&xsurface->events.request_fullscreen, &c->request_fullscreen, fullscreennotify);
	LISTEN(&xsurface->events.set_hints, &c->set_hints, sethints);
	LISTEN(&xsurface->events.set_title, &c->set_title, updatetitle);
	LISTEN(&xsurface->events.set_override_redirect, &c->override_redirect,
			managed_override_redirect);

	/* Add to global clients array (matches AwesomeWM client_manage line 2202) */
	lua_pushvalue(L, -1);
	client_array_push(&globalconf.clients, luaA_object_ref(L, -1));

	/* Add to stack (matches AwesomeWM client_manage) */
	stack_client_push(c);

	/* Emit client::list signal (matches AwesomeWM line 2266) */
	some_event_queue_class(&client_class, SIG_LIST);

	/* Pop the client from the Lua stack */
	lua_pop(L, 1);
}

void
dissociatex11(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, dissociate);
	log_debug("[X11-DISASSOC] window 0x%x scene=%p", c->window, (void *)c->scene);
	wl_list_remove(&c->map.link);
	wl_list_remove(&c->unmap.link);
}

void
sethints(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, set_hints);
	xcb_icccm_wm_hints_t *hints = c->surface.xwayland->hints;
	lua_State *L;

	if (!hints)
		return;

	if (c->window == XCB_NONE)
		return;

	/* Get Lua state for signal emission */
	L = globalconf_get_lua_State();
	luaA_object_push(L, c);

	/* Emit request::urgent and let Lua decide (matches AwesomeWM property.c:203-204) */
	lua_pushboolean(L, xcb_icccm_wm_hints_get_urgency(hints));
	some_event_queue_signal(L, -2, SIG_REQUEST_URGENT, 1);

	/* Handle input focus hint (XCB_ICCCM_WM_HINT_INPUT)
	 * If input hint is set and false, client should not receive focus */
	if (hints->flags & XCB_ICCCM_WM_HINT_INPUT)
		c->nofocus = !hints->input;

	/* Handle window group (XCB_ICCCM_WM_HINT_WINDOW_GROUP) */
	if (hints->flags & XCB_ICCCM_WM_HINT_WINDOW_GROUP)
		client_set_group_window(L, -1, hints->window_group);

	lua_pop(L, 1);
	printstatus();
}

void
xwaylandready(struct wl_listener *listener, void *data)
{
	struct wlr_xcursor *xcursor;
	xcb_connection_t *conn;
	const xcb_setup_t *setup;
	xcb_screen_iterator_t iter;

	/* assign the one and only seat */
	wlr_xwayland_set_seat(xwayland, seat);

	/* Set the default XWayland cursor to match the rest of somewm. */
	if ((xcursor = wlr_xcursor_manager_get_xcursor(cursor_mgr, "default", 1)))
		COMPAT_XWAYLAND_SET_CURSOR(xwayland, xcursor->images[0]);

	/* Initialize XCB connection for EWMH support (AwesomeWM pattern) */
	conn = xcb_connect(xwayland->display_name, NULL);
	if (xcb_connection_has_error(conn)) {
		fprintf(stderr, "somewm: Failed to connect to XWayland display %s\n",
		        xwayland->display_name);
		return;
	}
	globalconf.connection = conn;

	/* Set up X11 screen structure for EWMH (AwesomeWM pattern) */
	setup = xcb_get_setup(conn);
	iter = xcb_setup_roots_iterator(setup);
	if (!iter.rem) {
		fprintf(stderr, "somewm: XWayland setup has no screens\n");
		return;
	}

	/* Allocate and populate screen structure */
	globalconf.screen = calloc(1, sizeof(*globalconf.screen));
	if (!globalconf.screen) {
		fprintf(stderr, "somewm: Failed to allocate screen structure\n");
		return;
	}
	globalconf.screen->root = iter.data->root;
	globalconf.screen->black_pixel = iter.data->black_pixel;
	globalconf.screen->root_depth = iter.data->root_depth;
	globalconf.screen->root_visual = iter.data->root_visual;

	/* Initialize EWMH atoms (must be done before ewmh_init) */
	init_ewmh_atoms(conn);

	/* Initialize EWMH support on root window */
	ewmh_init(conn, 0);

	/* Connect Lua signals for automatic EWMH property updates */
	ewmh_init_lua();

	log_info("EWMH support initialized for XWayland");

	/* Notify Lua that XWayland is fully usable: DISPLAY socket bound,
	 * EWMH atoms initialized, Lua property handlers connected. Subscribers
	 * (e.g. autostart of Qt5/GTK X11 apps that race the DISPLAY socket)
	 * can act now. The flag lets luaA_hot_reload() re-emit for late
	 * subscribers after rc.lua reload. */
	globalconf.xwayland_ready_seen = true;
	luaA_emit_signal_global("xwayland::ready");
}

void
xwayland_setup(void)
{
	if ((xwayland = wlr_xwayland_create(dpy, compositor, 1))) {
		wl_signal_add(&xwayland->events.ready,
			(xwayland_ready_listener.notify = xwaylandready,
			 &xwayland_ready_listener));
		wl_signal_add(&xwayland->events.new_surface,
			(new_xwayland_surface.notify = createnotifyx11,
			 &new_xwayland_surface));

		setenv("DISPLAY", xwayland->display_name, 1);
	} else {
		fprintf(stderr, "failed to setup XWayland X server, continuing without it\n");
	}
}

void
xwayland_cleanup(void)
{
	wl_list_remove(&new_xwayland_surface.link);
	wl_list_remove(&xwayland_ready_listener.link);
	if (xwayland) {
		wlr_xwayland_destroy(xwayland);
		xwayland = NULL;
	}
}

#endif /* XWAYLAND */
