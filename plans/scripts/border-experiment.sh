#!/bin/bash
# border-experiment - run the SceneFX 0.5 border corruption experiments.
#
# Background: on wlroots 0.20 + SceneFX 0.5 the first window of a session draws
# a clean border and every window after it does not. The leading explanation is
# SceneFX's blur padding band, which 0.5 widened from S to 2*S pixels and which
# now fires whenever damage comes within S of a blur node. With this fork's blur
# settings S is 80px, wide enough to reach across a tiled gap onto a
# neighbouring window's border. See plans/kolo10-upstream-sync.md.
#
# This script measures rather than eyeballs. Run it on the live session -- the
# nested sandbox does not reproduce the artefact.
#
# Usage:
#   plans/scripts/border-experiment.sh            # runs A and B back to back
#   plans/scripts/border-experiment.sh --report   # re-print results collected so far
#   plans/scripts/border-experiment.sh --dump     # scene tree of the focused client:
#                                                 # node boxes, clipped_region, radii,
#                                                 # and the region each node may paint
#
# The full protocol is three runs:
#   A  baseline   blur on, default settings           <- this script
#   B  noblur     blur switched off on every client   <- this script
#   C  smallblur  blur on, S shrunk from 80px to 12px <- needs a restart, see below
#
set -euo pipefail

SRCDIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROBE="$SRCDIR/plans/scripts/border-probe.py"
RESULTS="$SRCDIR/tests/bench/results/border"

red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[1;33m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

ipc() {
    local out
    out="$(somewm-client eval "$1")" || { red "somewm-client eval failed"; exit 1; }
    printf '%s\n' "$out" | tail -n +2
}

report() {
    bold "=== collected so far ==="
    printf '%-14s %-8s %-13s %-9s %-6s %s\n' run clean verdict flicker blur client
    for d in "$RESULTS"/*/; do
        [[ -f "$d/summary.json" ]] || continue
        python3 - "$d/summary.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
c = s["client"]
print("%-14s %-8s %-13s %-9s %-6s %s" % (
    s["label"], f'{s["clean_pct"]}%', s.get("worst_verdict", "?"),
    f'{s["ring_changed_px"]}/{s["ring_band_px"]}',
    str(c["blur"]), f'{c["class"]} {c["w"]}x{c["h"]}+{c["x"]}+{c["y"]}'))
PY
    done
}

dump_scene() {
    bold "=== scene tree of the focused client ==="
    ipc 'local c=client.focus; if not c then return "no focused client" end; local g=c:geometry(); local t=root.scene_tree_dump(c); local o={string.format("%s  geo=%dx%d+%d+%d  bw=%d  corner_radius=%d", c.class or "?", g.width, g.height, g.x, g.y, c.border_width or 0, c.corner_radius or 0)}; o[#o+1]="painted bottom to top:"; for _,n in ipairs(t) do local extra=""; if n.type=="rect" then extra=string.format("  clip=%dx%d+%d+%d  r=%d/%d  alpha=%.2f", n.clip_w, n.clip_h, n.clip_x, n.clip_y, n.radius, n.clip_radius, n.alpha) end; o[#o+1]=string.format("%s%-6s abs=%d,%d size=%dx%d en=%-5s visible=%dx%d+%d+%d in %d rect(s)%s", string.rep("  ", n.depth), n.type, n.abs_x or -1, n.abs_y or -1, n.width, n.height, tostring(n.enabled), n.vis_w, n.vis_h, n.vis_x, n.vis_y, n.vis_rects, extra) end; return table.concat(o,"\n")'
}

if [[ "${1:-}" == "--report" ]]; then
    report
    exit 0
fi

if [[ "${1:-}" == "--dump" ]]; then
    dump_scene
    exit 0
fi

command -v grim >/dev/null || { red "grim is not installed"; exit 1; }
command -v somewm-client >/dev/null || { red "somewm-client is not on PATH"; exit 1; }

# --- preflight -------------------------------------------------------------

# Match the compositor this script is talking to, not just the first somewm:
# a sandbox instance may be running alongside the live session.
compositor_pid() {
    local pids pid
    pids=$(pgrep -x somewm) || return 1
    if [[ -n "${SOMEWM_SOCKET:-}" ]]; then
        for pid in $pids; do
            if tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
                    | grep -qx "SOMEWM_SOCKET=$SOMEWM_SOCKET"; then
                printf '%s\n' "$pid"; return 0
            fi
        done
    fi
    printf '%s\n' "${pids%%$'\n'*}"
}

SOMEWM_PID="$(compositor_pid)" || { red "no somewm process found"; exit 1; }
STACK="$(ldd "$(readlink -f "/proc/$SOMEWM_PID/exe")" 2>/dev/null \
    | grep -oE 'libscenefx-[0-9.]+|libwlroots-[0-9.]+' | tr '\n' ' ')"
bold "graphics stack: $STACK"
if [[ "$STACK" != *"scenefx-0.5"* ]]; then
    yellow "This session is not on SceneFX 0.5, so there is nothing to reproduce."
    yellow "Reinstall with:  SOMEWM_WLROOTS=0.20 $SRCDIR/plans/scripts/install-scenefx.sh"
    yellow "then restart from TTY and run this again."
    exit 1
fi

NCLIENTS="$(ipc 'return #client.get()')"
if (( NCLIENTS < 2 )); then
    red "Only $NCLIENTS client open. The artefact needs at least two windows."
    red "Open a second terminal, focus it, and run this again."
    exit 1
fi

FOCUS="$(ipc 'local c=client.focus; return c and (c.class.." "..c:geometry().width.."x"..c:geometry().height) or "none"')"
if [[ "$FOCUS" == "none" ]]; then
    red "No focused client. Click the window whose border looks wrong."
    exit 1
fi
bold "focused: $FOCUS   ($NCLIENTS clients open)"
yellow "Make sure this is a window that LOOKS BROKEN -- not the first one you"
yellow "opened, and fully on screen. Ctrl-C now if it is not."
echo
sleep 4

# --- A: baseline -----------------------------------------------------------

bold ">>> A  baseline (blur as configured)"
python3 "$PROBE" A-baseline
echo
dump_scene
echo

# --- B: blur off -----------------------------------------------------------

bold ">>> B  blur off on every client"
# Remember which clients actually had blur -- it is applied per class, so
# blanket-restoring it afterwards would turn it on for windows that never had
# it. The list lives in the compositor's Lua state between eval calls.
restore_blur() {
    somewm-client eval 'for c in pairs(_G.__border_probe_blurred or {}) do if c.valid then c.backdrop_blur=true end end; _G.__border_probe_blurred=nil; return "ok"' >/dev/null 2>&1 || true
}
trap restore_blur EXIT

BLURRED="$(ipc '_G.__border_probe_blurred={}; local n=0; for _,c in ipairs(client.get()) do if c.backdrop_blur then n=n+1; _G.__border_probe_blurred[c]=true; c.backdrop_blur=false end end; return n')"
echo "    switched blur off on $BLURRED client(s)"
if [[ "$BLURRED" == "0" ]]; then
    yellow "    no client had blur on -- run B is not a useful contrast"
fi
sleep 2
python3 "$PROBE" B-noblur
echo
echo "    restoring blur"
restore_blur
trap - EXIT
sleep 1

# --- C: instructions -------------------------------------------------------

echo
bold ">>> C  needs a restart, because the blur radius is set once at startup"
cat <<EOF

  Exit somewm, then relaunch from the TTY with the blur sampling radius
  shrunk from 80px to 12px:

      SOMEWM_BLUR_PASSES=1 SOMEWM_BLUR_RADIUS=3 $SRCDIR/plans/scripts/start.sh

  Open two terminals again, focus the one that looks broken, and run:

      $SRCDIR/plans/scripts/border-probe.py C-smallblur

  Then send me the output of:

      $SRCDIR/plans/scripts/border-experiment.sh --report

EOF

report
