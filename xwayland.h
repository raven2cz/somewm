/*
 * xwayland.h - XWayland X11 compatibility layer
 *
 * Handles X11 client lifecycle, configuration, activation, and EWMH
 * initialization for XWayland surfaces.
 */
#ifndef XWAYLAND_H
#define XWAYLAND_H

#ifdef XWAYLAND

#include <stdbool.h>
#include "somewm_types.h"

struct wl_listener;
struct wlr_surface;

void xwayland_setup(void);
void xwayland_cleanup(void);

/* XWayland listener callbacks (used by client_reregister_listeners) */
void activatex11(struct wl_listener *listener, void *data);
void associatex11(struct wl_listener *listener, void *data);
void configurex11(struct wl_listener *listener, void *data);
void createnotifyx11(struct wl_listener *listener, void *data);
void dissociatex11(struct wl_listener *listener, void *data);
void sethints(struct wl_listener *listener, void *data);
void managed_override_redirect(struct wl_listener *listener, void *data);

/* Override-redirect (unmanaged) surfaces */
UnmanagedSurface *unmanaged_from_surface(struct wlr_surface *surface);
bool unmanaged_holds_focus(void);
bool unmanaged_surface_has_focus(UnmanagedSurface *u);
bool unmanaged_wants_focus(UnmanagedSurface *u);
void unmanaged_click(UnmanagedSurface *u);
void unmanaged_foreach(void (*cb)(UnmanagedSurface *u, void *data), void *data);

#else

static inline void xwayland_setup(void) {}
static inline void xwayland_cleanup(void) {}
static inline bool unmanaged_holds_focus(void) { return false; }

#endif /* XWAYLAND */

#endif /* XWAYLAND_H */
