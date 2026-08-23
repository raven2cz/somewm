/*
 * scenefx_compat.h - Conditional include for wlroots scene graph
 *
 * When scenefx is available, use its extended scene API (rounded corners,
 * shadows, blur, opacity). Otherwise, fall back to vanilla wlroots scene API.
 * Both APIs are source-compatible — scenefx extends without replacing.
 *
 * SceneFX releases track wlroots: 0.4 goes with wlroots 0.19, 0.5 with 0.20.
 * The two express rounded corners differently, so this header hides that
 * behind one shape:
 *
 *   0.4  wlr_scene_*_set_corner_radius(node, radius, enum corner_location)
 *        one radius, applied to a bitmask of corners
 *   0.5  wlr_scene_*_set_corner_radii(node, struct fx_corner_radii)
 *        a separate radius per corner, and set_corner_radius() means "all"
 *
 * Callers use somewm_corners_t plus the somewm_* setters below and do not
 * care which is linked.
 */

#ifndef SCENEFX_COMPAT_H
#define SCENEFX_COMPAT_H

#ifdef HAVE_SCENEFX
#include <scenefx/types/wlr_scene.h>
#include <scenefx/render/fx_renderer/fx_renderer.h>

/** Which corners a radius applies to. Bit values match SceneFX 0.4's
 * enum corner_location so the 0.4 path is a plain cast. */
typedef enum {
	SOMEWM_CORNER_NONE         = 0,
	SOMEWM_CORNER_TOP_LEFT     = 1 << 0,
	SOMEWM_CORNER_TOP_RIGHT    = 1 << 1,
	SOMEWM_CORNER_BOTTOM_RIGHT = 1 << 2,
	SOMEWM_CORNER_BOTTOM_LEFT  = 1 << 3,
	SOMEWM_CORNER_TOP    = SOMEWM_CORNER_TOP_LEFT | SOMEWM_CORNER_TOP_RIGHT,
	SOMEWM_CORNER_BOTTOM = SOMEWM_CORNER_BOTTOM_LEFT | SOMEWM_CORNER_BOTTOM_RIGHT,
	SOMEWM_CORNER_ALL    = SOMEWM_CORNER_TOP | SOMEWM_CORNER_BOTTOM,
} somewm_corners_t;

#ifdef HAVE_SCENEFX_CORNER_RADII  /* SceneFX 0.5+ */

static inline struct fx_corner_radii
somewm_corner_radii(int radius, somewm_corners_t corners)
{
	struct fx_corner_radii radii = {0};
	if (corners & SOMEWM_CORNER_TOP_LEFT)     radii.top_left = radius;
	if (corners & SOMEWM_CORNER_TOP_RIGHT)    radii.top_right = radius;
	if (corners & SOMEWM_CORNER_BOTTOM_RIGHT) radii.bottom_right = radius;
	if (corners & SOMEWM_CORNER_BOTTOM_LEFT)  radii.bottom_left = radius;
	return radii;
}

static inline void
somewm_scene_buffer_set_corners(struct wlr_scene_buffer *buffer, int radius,
		somewm_corners_t corners)
{
	wlr_scene_buffer_set_corner_radii(buffer, somewm_corner_radii(radius, corners));
}

static inline void
somewm_scene_rect_set_corners(struct wlr_scene_rect *rect, int radius,
		somewm_corners_t corners)
{
	wlr_scene_rect_set_corner_radii(rect, somewm_corner_radii(radius, corners));
}

static inline void
somewm_scene_blur_set_corners(struct wlr_scene_blur *blur, int radius,
		somewm_corners_t corners)
{
	wlr_scene_blur_set_corner_radii(blur, somewm_corner_radii(radius, corners));
}

/** Fill in a clipped_region's corner fields. 0.4 carries a radius plus a
 * bitmask, 0.5 a per-corner struct, so the assignment differs. */
#define SOMEWM_CLIPPED_REGION_SET_CORNERS(region, radius, corner_mask) \
	do { (region).corners = somewm_corner_radii((radius), (corner_mask)); } while (0)

#else  /* SceneFX 0.4 */

static inline void
somewm_scene_buffer_set_corners(struct wlr_scene_buffer *buffer, int radius,
		somewm_corners_t corners)
{
	wlr_scene_buffer_set_corner_radius(buffer, radius,
			(enum corner_location)corners);
}

static inline void
somewm_scene_rect_set_corners(struct wlr_scene_rect *rect, int radius,
		somewm_corners_t corners)
{
	wlr_scene_rect_set_corner_radius(rect, radius,
			(enum corner_location)corners);
}

#define SOMEWM_CLIPPED_REGION_SET_CORNERS(region, radius, corner_mask) \
	do { \
		(region).corner_radius = (radius); \
		(region).corners = (enum corner_location)(corner_mask); \
	} while (0)

#endif /* HAVE_SCENEFX_CORNER_RADII */

#else /* !HAVE_SCENEFX */
#include <wlr/types/wlr_scene.h>
#endif

#endif /* SCENEFX_COMPAT_H */
