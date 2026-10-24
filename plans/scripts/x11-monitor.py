#!/usr/bin/env python3
"""Live log of X11 structural events in a nested Xwayland.

Selects SubstructureNotify on the root window and reports create / map /
unmap / destroy / configure / reparent as they happen, annotated with the
override-redirect flag, geometry and window name. This is the ground truth for
"the popup never appeared": it shows whether the client ever created and mapped
a window, and what the X server did with it afterwards.

Usage (through wine-sandbox.sh, which sets DISPLAY):
    DISPLAY=:4 python3 x11-monitor.py [--filter CLASS] [--duration SECONDS]

Read-only: it only selects for events, it never configures anything.
"""

import argparse
import os
import sys
import time

try:
    from Xlib import X, display, error
except ImportError:
    sys.exit("ERROR: python-xlib is required (pacman -S python-xlib)")


class Monitor:
    def __init__(self, dpy, name_filter=None):
        self.dpy = dpy
        self.root = dpy.screen().root
        self.filter = name_filter.lower() if name_filter else None
        self.start = time.monotonic()
        # Remember facts about windows so destroy events can still be labelled
        # after the window is gone.
        self.known = {}

    def stamp(self):
        return f"{time.monotonic() - self.start:7.3f}"

    def facts(self, win_id):
        """Best-effort description; falls back to the last known values."""
        try:
            win = self.dpy.create_resource_object("window", win_id)
            attrs = win.get_attributes()
            geom = win.get_geometry()
            try:
                wm_class = win.get_wm_class()
            except error.XError:
                wm_class = None
            try:
                name = win.get_wm_name()
            except error.XError:
                name = None
            info = {
                "or": bool(attrs.override_redirect),
                "geom": f"{geom.width}x{geom.height}+{geom.x}+{geom.y}",
                "class": wm_class[1] if wm_class else None,
                "name": name,
            }
            self.known[win_id] = info
            return info
        except error.XError:
            return self.known.get(win_id, {"or": None, "geom": "?", "class": None, "name": None})

    def interesting(self, info):
        if not self.filter:
            return True
        haystack = f"{info.get('class') or ''} {info.get('name') or ''}".lower()
        return self.filter in haystack

    def report(self, kind, win_id, extra=""):
        info = self.facts(win_id)
        if not self.interesting(info):
            return
        flag = "OR" if info["or"] else "--"
        label = info["name"] or info["class"] or ""
        print(f"{self.stamp()}  {kind:<11} {win_id:#10x} {flag} "
              f"{info['geom']:<20} {label[:44]:<44} {extra}", flush=True)

    def run(self, duration=None):
        self.root.change_attributes(
            event_mask=X.SubstructureNotifyMask | X.FocusChangeMask)
        self.dpy.sync()
        print(f"# monitoring {os.environ['DISPLAY']} "
              f"(filter={self.filter or 'none'}) — Ctrl-C to stop", flush=True)
        print(f"{'time':>7}  {'event':<11} {'window':>10} OR "
              f"{'geometry':<20} {'name/class':<44}", flush=True)

        deadline = self.start + duration if duration else None
        while deadline is None or time.monotonic() < deadline:
            # pending_events() lets us honour the deadline even when idle.
            if self.dpy.pending_events() == 0:
                time.sleep(0.01)
                continue
            event = self.dpy.next_event()
            etype = event.type

            if etype == X.CreateNotify:
                self.report("create", event.window.id,
                            f"parent={event.parent.id:#x}")
            elif etype == X.MapNotify:
                self.report("MAP", event.window.id,
                            "override" if event.override_redirect else "")
            elif etype == X.UnmapNotify:
                self.report("unmap", event.window.id)
            elif etype == X.DestroyNotify:
                self.report("destroy", event.window.id)
                self.known.pop(event.window.id, None)
            elif etype == X.ConfigureNotify:
                # The sibling field is named differently across xlib versions
                # and is absent when the stacking order did not change.
                above = getattr(event, "above_sibling", None) or getattr(event, "above", None)
                above_id = getattr(above, "id", above)
                self.report("configure", event.window.id,
                            f"-> {event.width}x{event.height}+{event.x}+{event.y}"
                            + (f" above={above_id:#x}" if isinstance(above_id, int) and above_id else ""))
            elif etype == X.ReparentNotify:
                self.report("reparent", event.window.id,
                            f"parent={event.parent.id:#x}")
            elif etype == X.MapRequest:
                self.report("map_request", event.window.id)
            elif etype in (X.FocusIn, X.FocusOut):
                kind = "FocusIn" if etype == X.FocusIn else "FocusOut"
                self.report(kind, event.window.id, f"mode={event.mode}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--filter", help="only report windows whose class/name matches")
    parser.add_argument("--duration", type=float, help="stop after N seconds")
    args = parser.parse_args()

    if not os.environ.get("DISPLAY"):
        sys.exit("ERROR: DISPLAY is not set — run me through wine-sandbox.sh")
    try:
        dpy = display.Display()
    except Exception as exc:  # noqa: BLE001
        sys.exit(f"ERROR: cannot open display {os.environ['DISPLAY']}: {exc}")

    try:
        Monitor(dpy, args.filter).run(args.duration)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
