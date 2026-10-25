#!/usr/bin/env bash
#
# A hot-reload while a client's configure retry is pending must not leave the
# timer behind. The client commits whole 16 px cells, so a size that is not a
# multiple of the cell arms the retry (window.c configure_retry_arm). The
# reload copies the client to a snapshot and lua_close() frees the old
# userdata; a timer still pointing at it fired a second later on freed memory
# and took the compositor down.

. "$(dirname "$0")/lib.sh"

sw_require_helper test-transient-client
CLIENT=$SW_HELPER
REPORT=$(mktemp)

sw_start hr-retry --config "$ROOT_DIR/tests/rc.lua" || finish

sw_spawn hr-retry "$CLIENT retry_client $REPORT 0 ff204060 0 0 0 16" || finish
check_client_appeared hr-retry retry_client || finish

sw_eval hr-retry 'local c = client.get()[1]; c.floating = true; c.border_width = 0; c:geometry{x = 50, y = 50, width = 1001, height = 649}; return "ok"'
check_wait_true hr-retry "the client draws a size other than the configured one" \
    'return tostring(client.get()[1]._committed_size ~= nil)'

sw_reload hr-retry || finish

# The retry interval is 1 s: give a stale timer time to fire.
sleep 2.5

check_match "the compositor survives the pending retry" "$(sw_alive hr-retry && echo alive)" '^alive$'
check_eval hr-retry "exactly one client after the reload" \
    'return tostring(#client.get())' 1
check_eval hr-retry "the restored client is a live object" \
    'return tostring(client.get()[1].valid)' true

sw_check_log_clean hr-retry "post-reload log"
rm -f "$REPORT"

finish
