#!/usr/bin/env python3
"""border-probe - measure whether the focused client's border renders correctly.

Written for the SceneFX 0.5 border corruption on wlroots 0.20: the first window
of a session draws a clean border, every window after it does not, and dragging
one makes it flicker. This takes the eyeballing out of it -- it screenshots the
live session, walks the 1px border ring of the focused client and counts how
many of its pixels are actually the border colour.

Run it once per configuration and compare the "clean" percentages:

    plans/scripts/border-probe.py baseline
    plans/scripts/border-probe.py noblur
    plans/scripts/border-probe.py small-blur

Results land in tests/bench/results/border/<label>/ as summary.json plus the
captured frames, so runs can be diffed after the fact.

Needs a running somewm (this is deliberately the live session -- the nested
sandbox does not reproduce the artefact), grim, and somewm-client.
"""

import json
import os
import shutil
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def die(msg):
    print(f"border-probe: {msg}", file=sys.stderr)
    sys.exit(1)


def ipc(code):
    """Run a single-line Lua snippet through somewm-client (multi-line fails).

    The wire format is a status line followed by the value, and a Lua error
    still exits 0, so both have to be unwrapped by hand.
    """
    r = subprocess.run(["somewm-client", "eval", code],
                       capture_output=True, text=True)
    out = (r.stdout or "").strip()
    if r.returncode != 0:
        die(f"somewm-client eval failed: {r.stderr.strip() or out}")
    if out.startswith("ERROR"):
        die(out)
    lines = out.splitlines()
    if lines and lines[0].strip() == "OK":
        lines = lines[1:]
    return "\n".join(lines).strip()


def read_ppm(path):
    """Parse a binary P6 PPM into (width, height, bytes). grim -t ppm only."""
    data = path.read_bytes()
    fields, pos = [], 0
    while len(fields) < 4:
        while pos < len(data) and data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b"#":
            while pos < len(data) and data[pos] != 0x0A:
                pos += 1
            continue
        start = pos
        while pos < len(data) and not data[pos:pos + 1].isspace():
            pos += 1
        fields.append(data[start:pos])
    pos += 1  # the single whitespace byte after maxval
    magic, w, h, maxval = fields[0], int(fields[1]), int(fields[2]), int(fields[3])
    if magic != b"P6" or maxval != 255:
        die(f"unexpected PPM header {magic!r} maxval {maxval}")
    return w, h, data[pos:pos + w * h * 3]


def px(buf, w, x, y):
    i = (y * w + x) * 3
    return buf[i], buf[i + 1], buf[i + 2]


def parse_hex(colour):
    c = colour.strip().lstrip("#")
    if len(c) == 8:      # #rrggbbaa
        c = c[:6]
    if len(c) == 3:
        c = "".join(ch * 2 for ch in c)
    if len(c) != 6:
        die(f"cannot parse border colour {colour!r}")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def near(a, b, tol=8):
    return all(abs(x - y) <= tol for x, y in zip(a, b))


def scan_edge(buf, iw, ih, want, ring, bw, radius, edge):
    """Walk one edge of the ring.

    For every position along the edge, look for the border colour anywhere in a
    +/-3px band around where it should be. Three outcomes per position:
      clean   - found at the expected offset
      shifted - found, but off by a pixel or more
      missing - not found in the band at all
    """
    x0, y0, x1, y1 = ring
    skip = radius + 2  # stay clear of the rounded corners
    band = range(-3, bw + 3)

    clean = shifted = missing = offscreen = 0
    wrong = Counter()

    if edge in ("top", "bottom"):
        base = y0 if edge == "top" else y1 - bw
        positions = range(x0 + skip, x1 - skip)
    else:
        base = x0 if edge == "left" else x1 - bw
        positions = range(y0 + skip, y1 - skip)

    for p in positions:
        # A window pushed past the edge of the output has no pixels to measure
        # there; that is not a rendering fault, so it is counted separately.
        if edge in ("top", "bottom"):
            if not (0 <= p < iw) or not (0 <= base < ih):
                offscreen += 1
                continue
        else:
            if not (0 <= p < ih) or not (0 <= base < iw):
                offscreen += 1
                continue

        hit = None
        for d in band:
            if edge in ("top", "bottom"):
                x, y = p, base + d
            else:
                x, y = base + d, p
            if not (0 <= x < iw and 0 <= y < ih):
                continue
            if near(px(buf, iw, x, y), want):
                hit = d
                break
        if hit is None:
            missing += 1
            if edge in ("top", "bottom"):
                x, y = p, base
            else:
                x, y = base, p
            if 0 <= x < iw and 0 <= y < ih:
                wrong[px(buf, iw, x, y)] += 1
        elif 0 <= hit < bw:
            clean += 1
        else:
            shifted += 1

    total_wrong = sum(wrong.values())
    top = wrong.most_common(1)[0] if wrong else None
    return {
        "positions": len(positions) - offscreen,
        "offscreen": offscreen,
        "clean": clean,
        "shifted": shifted,
        "missing": missing,
        "distinct_wrong": len(wrong),
        "top_wrong_share": round(top[1] / total_wrong, 3) if top else 0.0,
        "verdict": classify(wrong, want),
        "top_wrong_colours": [
            {"rgb": list(c), "count": n} for c, n in wrong.most_common(3)
        ],
    }


def classify(wrong, want):
    """Tell a uniform overlay apart from actual corruption.

    Something composited on top of the border -- a panel shadow, say -- tints
    every pixel of an edge by the same factor, so the wrong colours are few and
    proportional to the border colour. Corruption is a spray of unrelated
    colours. Without this the two are indistinguishable in a bare pass rate.
    """
    if not wrong:
        return "ok"
    total = sum(wrong.values())
    tinted = 0
    for c, n in wrong.items():
        # Proportional to the border colour on every channel = the border seen
        # through something, not a different colour. A gradient overlay yields
        # many such shades, so the count of distinct colours says nothing --
        # only the proportionality does.
        ratios = [c[i] / want[i] for i in range(3) if want[i] > 8]
        if ratios and max(ratios) - min(ratios) < 0.08 and max(ratios) <= 1.05:
            tinted += n
    share = tinted / total
    if share > 0.9:
        return "uniform-tint"
    if share > 0.5:
        return "mixed"
    return "corrupt"


def dominant_ring_colour(buf, iw, ih, ring, bw, radius):
    """The most common colour actually sitting on the ring.

    Used as a cross-check on the theme value: if the two disagree the theme
    key is wrong, and if they agree the measurement below is trustworthy.
    """
    x0, y0, x1, y1 = ring
    skip = radius + 2
    seen = Counter()
    for d in range(bw):
        for x in range(x0 + skip, x1 - skip):
            for y in (y0 + d, y1 - 1 - d):
                if 0 <= x < iw and 0 <= y < ih:
                    seen[px(buf, iw, x, y)] += 1
        for y in range(y0 + skip, y1 - skip):
            for x in (x0 + d, x1 - 1 - d):
                if 0 <= x < iw and 0 <= y < ih:
                    seen[px(buf, iw, x, y)] += 1
    return seen.most_common(3)


def ring_instability(a, b, iw, ih, ring, bw):
    """Ring pixels that changed between two captures.

    Exactly the bw-wide frame, nothing inside it. Anything wider would pick up
    the window's own content -- a video or a blinking cursor sitting against
    the frame would otherwise read as border flicker.
    """
    x0, y0, x1, y1 = ring
    changed = total = 0
    for y in range(max(0, y0), min(ih, y1)):
        inside_v = y0 + bw <= y < y1 - bw
        for x in range(max(0, x0), min(iw, x1)):
            if inside_v and x0 + bw <= x < x1 - bw:
                continue
            total += 1
            if px(a, iw, x, y) != px(b, iw, x, y):
                changed += 1
    return changed, total


def compositor_pid():
    """The somewm process this probe is actually talking to.

    With SOMEWM_SOCKET set there may be a sandbox instance alongside the live
    session, so match on the socket rather than taking the first hit.
    """
    pids = subprocess.run(["pgrep", "-x", "somewm"], capture_output=True,
                          text=True).stdout.split()
    if not pids:
        return None
    sock = os.environ.get("SOMEWM_SOCKET")
    if sock:
        for pid in pids:
            try:
                raw = Path(f"/proc/{pid}/environ").read_bytes().decode(errors="replace")
            except OSError:
                continue
            if f"SOMEWM_SOCKET={sock}" in raw:
                return pid
    return pids[0]


def compositor_env():
    """Blur-related env of the running compositor, straight from /proc."""
    pid = compositor_pid()
    try:
        raw = Path(f"/proc/{pid}/environ").read_bytes().decode(errors="replace")
    except Exception:
        return {"pid": pid}
    env = dict(e.split("=", 1) for e in raw.split("\0") if "=" in e)
    out = {"pid": pid}
    for k in ("SOMEWM_BLUR_PASSES", "SOMEWM_BLUR_RADIUS",
              "SOMEWM_BLUR_BOTTOM_ONLY"):
        out[k] = env.get(k, "(unset)")
    libs = subprocess.run(["ldd", f"/proc/{pid}/exe"], capture_output=True,
                          text=True).stdout
    out["libs"] = [l.split("=>")[0].strip() for l in libs.splitlines()
                   if "scenefx" in l or "wlroots" in l]
    return out


def main():
    label = sys.argv[1] if len(sys.argv) > 1 else "run"
    for tool in ("grim", "somewm-client"):
        if not shutil.which(tool):
            die(f"{tool} not found")

    focused = ipc('return client.focus and "yes" or "no"')
    if focused != "yes":
        die("no focused client -- click a window first")

    geo = json.loads(ipc(
        'local b=require("beautiful"); '
        'local c=client.focus; local g=c:geometry(); local s=c.screen; '
        'local sg=s.geometry; local o=s.outputs; local n=nil; '
        'for k,v in pairs(o) do n = (type(v)=="table" and v.name) or '
        '(type(v)=="string" and v) or (type(k)=="string" and k) or n end; '
        'return string.format('
        '\'{"x":%d,"y":%d,"w":%d,"h":%d,"bw":%d,"radius":%d,"name":"%s",'
        '"class":"%s","output":"%s","sx":%d,"sy":%d,"sw":%d,"sh":%d,'
        '"blur":%s,"colour":"%s"}\', '
        'g.x, g.y, g.width, g.height, c.border_width or 0, c.corner_radius or 0, '
        '(c.name or ""):gsub(\'"\',""), c.class or "", tostring(n), '
        'sg.x, sg.y, sg.width, sg.height, '
        'tostring(c.backdrop_blur and true or false), '
        'tostring(b.border_color_active or b.border_focus or b.border_color '
        'or "#000000"))'))

    nclients = int(ipc("return #client.get()"))
    if nclients < 2:
        print("border-probe: warning -- only one client. The artefact needs at "
              "least two windows; open another terminal and focus it.",
              file=sys.stderr)

    if geo["bw"] <= 0:
        die(f"focused client has border_width {geo['bw']} -- nothing to measure")

    outdir = REPO / "tests" / "bench" / "results" / "border" / label
    outdir.mkdir(parents=True, exist_ok=True)

    shots = []
    for i in range(2):
        p = outdir / f"frame{i}.ppm"
        cmd = ["grim", "-t", "ppm"]
        if geo["output"] not in ("nil", "None", ""):
            cmd += ["-o", geo["output"]]
        cmd.append(str(p))
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            die(f"grim failed: {r.stderr.strip()}")
        shots.append(read_ppm(p))
        if i == 0:
            time.sleep(0.4)

    iw, ih, buf = shots[0]
    if (iw, ih) != (geo["sw"], geo["sh"]):
        print(f"border-probe: warning -- captured {iw}x{ih} but the screen is "
              f"{geo['sw']}x{geo['sh']}; output scale or transform is in play "
              f"and the coordinate mapping below may be off.", file=sys.stderr)

    bw = geo["bw"]
    x0 = geo["x"] - geo["sx"]
    y0 = geo["y"] - geo["sy"]
    ring = (x0, y0, x0 + geo["w"] + 2 * bw, y0 + geo["h"] + 2 * bw)
    want = parse_hex(geo["colour"])

    edges = {e: scan_edge(buf, iw, ih, want, ring, bw, geo["radius"], e)
             for e in ("top", "bottom", "left", "right")}
    tot = sum(e["positions"] for e in edges.values())
    ok = sum(e["clean"] for e in edges.values())

    changed, band_total = ring_instability(buf, shots[1][2], iw, ih, ring, bw)
    dominant = dominant_ring_colour(buf, iw, ih, ring, bw, geo["radius"])

    summary = {
        "label": label,
        "client": {k: geo[k] for k in
                   ("name", "class", "x", "y", "w", "h", "bw", "radius", "blur")},
        "border_colour": geo["colour"],
        "clients_open": nclients,
        "compositor": compositor_env(),
        "edges": edges,
        "clean_pct": round(100.0 * ok / tot, 1) if tot else 0.0,
        "worst_verdict": ("corrupt" if any(e["verdict"] == "corrupt"
                                           for e in edges.values())
                          else "mixed" if any(e["verdict"] == "mixed"
                                              for e in edges.values())
                          else "uniform-tint" if any(e["verdict"] == "uniform-tint"
                                                     for e in edges.values())
                          else "ok"),
        "ring_changed_px": changed,
        "ring_band_px": band_total,
        "dominant_ring_colours": [
            {"rgb": list(c), "count": n} for c, n in dominant
        ],
    }
    (outdir / "summary.json").write_text(json.dumps(summary, indent=2))

    print(f"=== border-probe: {label} ===")
    print(f"client     : {geo['class']} \"{geo['name'][:40]}\" "
          f"{geo['w']}x{geo['h']}+{geo['x']}+{geo['y']}")
    print(f"border     : width {bw}, radius {geo['radius']}, theme colour "
          f"{geo['colour']} -> rgb{want}, blur {geo['blur']}")
    print(f"on screen  : " + ", ".join(f"rgb{c} x{n}" for c, n in dominant))
    if dominant and not near(dominant[0][0], want):
        print("             ^ theme colour is not what is actually drawn; "
              "the numbers below measure the theme colour")
    print(f"clients    : {nclients} open")
    c = summary["compositor"]
    print(f"compositor : pid {c.get('pid')}  {' '.join(c.get('libs', []))}")
    print(f"blur env   : passes={c.get('SOMEWM_BLUR_PASSES')} "
          f"radius={c.get('SOMEWM_BLUR_RADIUS')} "
          f"bottom_only={c.get('SOMEWM_BLUR_BOTTOM_ONLY')}")
    print()
    print(f"{'edge':<8} {'clean':>8} {'shifted':>8} {'missing':>8} "
          f"{'offscr':>7} {'colours':>8} {'verdict':<13} worst wrong colour")
    for name, e in edges.items():
        w0 = e["top_wrong_colours"]
        wtxt = (f"rgb{tuple(w0[0]['rgb'])} {int(e['top_wrong_share'] * 100)}%"
                if w0 else "-")
        print(f"{name:<8} {e['clean']:>8} {e['shifted']:>8} {e['missing']:>8} "
              f"{e['offscreen']:>7} {e['distinct_wrong']:>8} "
              f"{e['verdict']:<13} {wtxt}")
    print()
    print("verdict: ok = every pixel is the border colour; uniform-tint = the "
          "whole edge is\n         shaded by one constant factor, i.e. "
          "something is composited over it;\n         corrupt = a spray of "
          "unrelated colours")
    if any(e["offscreen"] for e in edges.values()):
        print("             ^ the window hangs off the output; only the visible "
              "part was measured")
    print()
    print(f"clean      : {summary['clean_pct']}%  (a correct border is 100%)")
    print(f"flicker    : {changed} of {band_total} ring pixels changed between "
          f"two captures 0.4s apart")
    print(f"written    : {outdir}/summary.json")


if __name__ == "__main__":
    main()
