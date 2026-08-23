#!/usr/bin/env python3
"""Census of the X11 windows of a nested Xwayland, next to somewm's own view.

Answers, for one moment in time: which windows exist, which are
override-redirect, where the X server thinks they are, how they are stacked,
who holds the input focus -- and which of them somewm knows about as clients.

Usage (normally through wine-sandbox.sh, which sets DISPLAY/SOMEWM_SOCKET):
    DISPLAY=:4 python3 x11-census.py [--json] [--stacking] [--watch SECONDS]

Requires python-xlib. Read-only: it queries, it never configures anything.
"""

import argparse
import json
import os
import subprocess
import sys
import time

try:
    from Xlib import X, display, error
except ImportError:
    sys.exit("ERROR: python-xlib is required (pacman -S python-xlib)")


TYPE_PREFIX = "_NET_WM_WINDOW_TYPE_"
STATE_PREFIX = "_NET_WM_STATE_"


def atom_names(dpy, values):
    """Map a list of atom ids to short names, tolerating stale atoms."""
    names = []
    for value in values or []:
        try:
            names.append(dpy.get_atom_name(value))
        except error.XError:
            names.append(f"<atom {value}>")
    return names


def short(names, prefix):
    return [n[len(prefix):].lower() if n.startswith(prefix) else n for n in names]


def prop(win, name, dpy):
    """Read a property by name; return its value or None."""
    try:
        atom = dpy.get_atom(name, only_if_exists=True)
        if atom == X.NONE:
            return None
        result = win.get_full_property(atom, X.AnyPropertyType)
    except error.XError:
        return None
    return result.value if result else None


def describe(dpy, win, depth, focus_id):
    try:
        attrs = win.get_attributes()
        geom = win.get_geometry()
    except error.XError:
        return None

    # Translate to root coordinates: a popup's own geometry is parent-relative.
    try:
        root = dpy.screen().root
        coords = win.translate_coords(root, 0, 0)
        abs_x, abs_y = -coords.x, -coords.y
    except error.XError:
        abs_x, abs_y = geom.x, geom.y

    try:
        wm_class = win.get_wm_class()
    except error.XError:
        wm_class = None
    try:
        name = win.get_wm_name()
    except error.XError:
        name = None
    try:
        transient = win.get_wm_transient_for()
    except error.XError:
        transient = None
    try:
        hints = win.get_wm_hints()
    except error.XError:
        hints = None

    types = short(atom_names(dpy, prop(win, "_NET_WM_WINDOW_TYPE", dpy)), TYPE_PREFIX)
    states = short(atom_names(dpy, prop(win, "_NET_WM_STATE", dpy)), STATE_PREFIX)
    protocols = atom_names(dpy, prop(win, "WM_PROTOCOLS", dpy))

    input_hint = None
    if hints is not None and (hints.flags & 1):  # InputHint
        input_hint = bool(hints.input)

    return {
        "id": win.id,
        "depth": depth,
        "override_redirect": bool(attrs.override_redirect),
        "mapped": attrs.map_state == X.IsViewable,
        "map_state": {X.IsUnmapped: "unmapped",
                      X.IsUnviewable: "unviewable",
                      X.IsViewable: "viewable"}.get(attrs.map_state, "?"),
        "x": abs_x, "y": abs_y,
        "width": geom.width, "height": geom.height,
        "class": wm_class[1] if wm_class else None,
        "name": name,
        "types": types,
        "states": states,
        "transient_for": transient.id if transient else None,
        "input_hint": input_hint,
        "take_focus": "WM_TAKE_FOCUS" in protocols,
        "focused": win.id == focus_id,
    }


def walk(dpy, win, depth, focus_id, out):
    """Depth-first walk of the window tree; children are bottom-to-top."""
    try:
        tree = win.query_tree()
    except error.XError:
        return
    for child in tree.children:
        entry = describe(dpy, child, depth, focus_id)
        if entry is not None:
            out.append(entry)
            walk(dpy, child, depth + 1, focus_id, out)


def somewm_clients():
    """somewm's own view: X11 window id -> client facts, via IPC."""
    socket = os.environ.get("SOMEWM_SOCKET")
    if not socket:
        return None
    lua = (
        'local out={} for _,c in ipairs(client.get()) do '
        'out[#out+1]=string.format("%s;%s;%s;%s;%s;%s", tostring(c.window), '
        'tostring(c.class), tostring(c._scene_layer), tostring(c.floating), '
        'tostring(c.type), tostring(client.focus==c)) end return table.concat(out,"|")'
    )
    client_bin = os.environ.get("SOMEWM_CLIENT_BIN", "somewm-client")
    try:
        raw = subprocess.run([client_bin, "eval", lua], capture_output=True,
                             text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if raw.returncode != 0:
        return None

    clients = {}
    for line in raw.stdout.strip().splitlines():
        if ";" not in line:
            continue
        for record in line.split("|"):
            parts = record.split(";")
            if len(parts) != 6:
                continue
            try:
                wid = int(parts[0])
            except ValueError:
                continue
            clients[wid] = {"class": parts[1], "layer": parts[2],
                            "floating": parts[3], "type": parts[4],
                            "focused": parts[5]}
    return clients


def render(windows, clients, show_stacking):
    print(f"{'window':>10}  {'OR':<3} {'map':<9} {'geometry':<20} "
          f"{'type':<14} {'class':<22} {'somewm':<10} name")
    print("-" * 130)
    for w in windows:
        geom = f"{w['width']}x{w['height']}+{w['x']}+{w['y']}"
        known = clients.get(w["id"]) if clients else None
        somewm = known["layer"] if known else ("-" if clients is not None else "?")
        flags = []
        if w["focused"]:
            flags.append("FOCUS")
        if w["transient_for"]:
            flags.append(f"transient={w['transient_for']:#x}")
        if w["states"]:
            flags.append(",".join(w["states"]))
        if w["input_hint"] is False:
            flags.append("input=false")
        if w["take_focus"]:
            flags.append("take_focus")
        indent = "  " * w["depth"]
        print(f"{w['id']:>#10x}  {'OR' if w['override_redirect'] else '-':<3} "
              f"{w['map_state']:<9} {geom:<20} {','.join(w['types'])[:14]:<14} "
              f"{str(w['class'])[:22]:<22} {somewm:<10} "
              f"{indent}{w['name'] or ''} {' '.join(flags)}")

    if show_stacking:
        print("\nstacking (bottom to top, mapped only):")
        for w in windows:
            if w["mapped"]:
                tag = "OR" if w["override_redirect"] else "  "
                print(f"  {tag} {w['id']:#x} {str(w['class'] or w['name'])[:40]}")

    if clients:
        stray = [wid for wid in clients if not any(w["id"] == wid for w in windows)]
        if stray:
            print(f"\nsomewm clients with no live X11 window: "
                  f"{', '.join(hex(w) for w in stray)}")
        or_clients = [hex(w["id"]) for w in windows
                      if w["override_redirect"] and w["id"] in clients]
        if or_clients:
            print(f"\n!! override-redirect windows present in client.get(): "
                  f"{', '.join(or_clients)}")


def snapshot(dpy):
    try:
        focus_id = dpy.get_input_focus().focus.id
    except (error.XError, AttributeError):
        focus_id = None
    windows = []
    walk(dpy, dpy.screen().root, 0, focus_id, windows)
    return windows


def probe(windows, clients):
    """One line comparing what X11 shows with what somewm knows.

    A popup that is mapped in X11 but missing from the compositor's overlay
    layer is the failure this whole exercise is about, so it gets its own
    counter rather than being buried in the full dump.
    """
    or_mapped = [w for w in windows if w["override_redirect"] and w["mapped"]]
    managed_mapped = [w for w in windows if not w["override_redirect"] and w["mapped"]]
    overlay = []
    orphan = []
    if clients is not None:
        for w in or_mapped:
            known = clients.get(w["id"])
            if known and known["layer"] == "overlay":
                overlay.append(w)
            else:
                orphan.append(w)
    return (f"x11_or_mapped={len(or_mapped)} "
            f"x11_managed_mapped={len(managed_mapped)} "
            f"somewm_or_overlay={len(overlay)} "
            f"somewm_or_missing={len(orphan)} "
            f"clients={len(clients) if clients is not None else -1} "
            f"or_ids={','.join(hex(w['id']) for w in or_mapped) or '-'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("--probe", action="store_true",
                        help="one-line counters instead of the full dump")
    parser.add_argument("--stacking", action="store_true", help="also print stacking order")
    parser.add_argument("--watch", type=float, metavar="SECONDS",
                        help="re-run every SECONDS until interrupted")
    args = parser.parse_args()

    if not os.environ.get("DISPLAY"):
        sys.exit("ERROR: DISPLAY is not set — run me through wine-sandbox.sh")

    try:
        dpy = display.Display()
    except Exception as exc:  # noqa: BLE001 - Xlib raises plain exceptions here
        sys.exit(f"ERROR: cannot open display {os.environ['DISPLAY']}: {exc}")

    while True:
        windows = snapshot(dpy)
        clients = somewm_clients()
        if args.probe:
            print(probe(windows, clients))
        elif args.json:
            print(json.dumps({"display": os.environ["DISPLAY"],
                              "windows": windows,
                              "somewm_clients": clients}, indent=2))
        else:
            print(f"\n=== {os.environ['DISPLAY']} @ {time.strftime('%H:%M:%S')} "
                  f"({len(windows)} windows) ===")
            render(windows, clients, args.stacking)
        if not args.watch:
            break
        time.sleep(args.watch)


if __name__ == "__main__":
    main()
