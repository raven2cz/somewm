#!/usr/bin/env python3
"""X11 override-redirect scenarios that a plain popup helper cannot produce.

x11_override_redirect.py creates one static override-redirect window. These
scenarios exercise the parts of the lifecycle that Wine and Qt actually use
and that the compositor has to follow:

    move  <class> [x y w h nx ny]   map, then move the window afterwards
                                    (Xwayland reports this via set_geometry;
                                    submenus and screen-edge flips do it)
    flip  <class> [x y w h]         map as override-redirect, then clear the
                                    flag on the live window (role change)
    chain <class> [x y w h]         map a parent popup, then a child popup
                                    that points at it with WM_TRANSIENT_FOR,
                                    then unmap the child (menu -> submenu)
    adopt <class> [x y w h]         map as a normal managed window, then set
                                    override_redirect on the live window
                                    (the reverse of "flip")

Each scenario prints one line per step to stdout ("step: <name> <window id>")
and then waits for SIGTERM, so a test can drive it by watching the output.
Timing between steps is driven by the caller via SIGUSR1: each signal
advances one step. That keeps the test deterministic instead of racing sleeps.
"""

import os
import signal
import sys
import time

try:
    from Xlib import X, display, Xatom
except ImportError:
    sys.exit("ERROR: python-xlib is required (pacman -S python-xlib)")


advance = False


def on_usr1(signum, frame):
    global advance
    advance = True


def on_term(signum, frame):
    sys.exit(0)


def wait_for_advance(dpy):
    """Block until the driving test sends SIGUSR1."""
    global advance
    while not advance:
        dpy.flush()
        time.sleep(0.02)
    advance = False


def make_window(dpy, root, wm_class, geom, override=True, transient_for=None):
    win = root.create_window(
        geom[0], geom[1], geom[2], geom[3], 0,
        X.CopyFromParent, X.InputOutput, X.CopyFromParent,
        override_redirect=override,
        background_pixel=dpy.screen().white_pixel,
        event_mask=X.StructureNotifyMask | X.ExposureMask,
    )
    win.set_wm_class(wm_class, wm_class)
    win.set_wm_name(wm_class)
    if transient_for is not None:
        win.change_property(dpy.get_atom("WM_TRANSIENT_FOR"), Xatom.WINDOW,
                            32, [transient_for])
    return win


def report(step, win=None):
    print(f"step: {step} {win.id if win is not None else 0}", flush=True)


def scenario_move(dpy, root, wm_class, geom, new_pos):
    win = make_window(dpy, root, wm_class, geom)
    win.map()
    dpy.sync()
    report("mapped", win)

    wait_for_advance(dpy)
    # Override-redirect windows configure themselves; the compositor learns
    # about it through xwayland's set_geometry signal, not request_configure.
    win.configure(x=new_pos[0], y=new_pos[1])
    dpy.sync()
    report("moved", win)


def scenario_flip(dpy, root, wm_class, geom):
    win = make_window(dpy, root, wm_class, geom)
    win.map()
    dpy.sync()
    report("mapped", win)

    wait_for_advance(dpy)
    # Real applications (Qt, Wine) unmap before changing the role and map
    # again afterwards. That also matters here: xwm learns about the new flag
    # from ConfigureNotify/MapNotify, not from the attribute change itself.
    win.unmap()
    dpy.sync()
    win.change_attributes(override_redirect=False)
    win.configure(x=geom[0] + 1, y=geom[1] + 1)
    dpy.sync()
    win.map()
    dpy.sync()
    report("flipped", win)


def scenario_adopt(dpy, root, wm_class, geom):
    """Managed window that turns into an override-redirect one.

    The compositor has to drop the client without sending X11 teardown to a
    window that is still alive, then pick the surface up on the unmanaged
    path.
    """
    win = make_window(dpy, root, wm_class, geom, override=False)
    win.map()
    dpy.sync()
    report("mapped", win)

    wait_for_advance(dpy)
    win.unmap()
    dpy.sync()
    win.change_attributes(override_redirect=True)
    win.configure(x=geom[0] + 1, y=geom[1] + 1)
    dpy.sync()
    win.map()
    dpy.sync()
    report("adopted", win)


def scenario_chain(dpy, root, wm_class, geom):
    parent = make_window(dpy, root, wm_class + "_menu", geom)
    parent.map()
    dpy.sync()
    report("parent_mapped", parent)

    wait_for_advance(dpy)
    child = make_window(dpy, root, wm_class + "_submenu",
                        (geom[0] + geom[2], geom[1] + 20, 120, 80),
                        transient_for=parent.id)
    child.map()
    dpy.sync()
    report("child_mapped", child)

    wait_for_advance(dpy)
    child.unmap()
    dpy.sync()
    report("child_unmapped", child)


def main():
    if len(sys.argv) < 3:
        sys.exit(f"Usage: {sys.argv[0]} <move|flip|chain> <WM_CLASS> "
                 f"[x y w h [nx ny]]")

    signal.signal(signal.SIGUSR1, on_usr1)
    signal.signal(signal.SIGTERM, on_term)

    mode = sys.argv[1]
    wm_class = sys.argv[2]
    args = [int(a) for a in sys.argv[3:]]
    geom = tuple(args[0:4]) if len(args) >= 4 else (100, 100, 200, 150)

    dpy = display.Display()
    root = dpy.screen().root

    print(f"pid: {os.getpid()}", flush=True)

    if mode == "move":
        new_pos = tuple(args[4:6]) if len(args) >= 6 else (400, 300)
        scenario_move(dpy, root, wm_class, geom, new_pos)
    elif mode == "flip":
        scenario_flip(dpy, root, wm_class, geom)
    elif mode == "chain":
        scenario_chain(dpy, root, wm_class, geom)
    elif mode == "adopt":
        scenario_adopt(dpy, root, wm_class, geom)
    else:
        sys.exit(f"unknown scenario: {mode}")

    report("done")
    while True:
        dpy.flush()
        time.sleep(0.1)


if __name__ == "__main__":
    main()
