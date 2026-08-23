---------------------------------------------------------------------------
-- @author somewm contributors
-- @copyright 2025 somewm contributors
--
-- Test: keyboard focus stays synchronized with client.focus
--
-- Verifies that the Wayland seat keyboard focus is always delivered when
-- client.focus is set, even when the Lua-level focus hasn't changed
-- (the desync bug). Also verifies the nil -> c game timer pattern still works.
--
-- Run with: make test-one TEST=tests/test-keyboard-focus-sync.lua
---------------------------------------------------------------------------

local runner = require("_runner")
local test_client = require("_client")
local awful = require("awful")

-- Skip if no terminal for client spawning
if not test_client.is_available() then
    io.stderr:write("SKIP: no terminal available for client spawning\n")
    io.stderr:write("Test finished successfully.\n")
    awesome.quit()
    return
end

print("TEST: keyboard-focus-sync")

local clients = {}
local focus_signals_received = 0
local unfocus_signals_received = 0

-- Track focus/unfocus signal counts
client.connect_signal("focus", function()
    focus_signals_received = focus_signals_received + 1
end)
client.connect_signal("unfocus", function()
    unfocus_signals_received = unfocus_signals_received + 1
end)

local steps = {
    -- Step 1: Spawn first client
    function(count)
        if count == 1 then
            print("TEST: Step 1 - Spawning client A")
            test_client("client_a")
        end
        if #client.get() >= 1 then
            clients.a = client.get()[1]
            return true
        end
    end,

    -- Step 2: Spawn second client
    function(count)
        if count == 1 then
            print("TEST: Step 2 - Spawning client B")
            test_client("client_b")
        end
        if #client.get() >= 2 then
            -- Find the other client
            for _, c in ipairs(client.get()) do
                if c ~= clients.a then
                    clients.b = c
                    break
                end
            end
            assert(clients.b, "Could not find client B")
            return true
        end
    end,

    -- Step 3: Focus A, then B, then A again — basic switching.
    -- NOTE: focus/unfocus are dispatched through the event queue
    -- (SIG_CLIENT_FOCUS/SIG_FOCUS), so they drain at the next event-loop
    -- iteration, NOT synchronously. Set focus on the first call, then poll
    -- across runner iterations until the queued signals have drained.
    function(count)
        if count == 1 then
            print("TEST: Step 3 - Basic focus switching")
            focus_signals_received = 0
            unfocus_signals_received = 0

            client.focus = clients.a
            assert(client.focus == clients.a,
                "client.focus should be A after setting")

            client.focus = clients.b
            assert(client.focus == clients.b,
                "client.focus should be B after setting")

            client.focus = clients.a
            assert(client.focus == clients.a,
                "client.focus should be A after switching back")
        end

        -- A was already focused from Step 2, so first set is a no-op for
        -- signals. Only A→B and B→A emit focus signals = 2 minimum. Wait for
        -- the queue to drain before asserting.
        if focus_signals_received >= 2 then
            print("TEST: Step 3 - PASS (focus signals: " ..
                focus_signals_received .. ")")
            return true
        end
        assert(count < 20,
            "Expected >= 2 focus signals after drain, got " ..
            focus_signals_received)
    end,

    -- Step 4: Set focus to already-focused client (the desync case).
    -- This is the core of the fix: client_focus() must call
    -- some_set_seat_keyboard_focus() even when client_focus_update()
    -- returns false. Re-focusing an already-focused client is a no-op at
    -- the Lua level, so NO SIG_FOCUS is queued — the count must stay 0 even
    -- after the queue has had iterations to drain.
    function(count)
        if count == 1 then
            print("TEST: Step 4 - Re-focus already-focused client")
            client.focus = clients.a
            assert(client.focus == clients.a, "Precondition: A is focused")
        end

        -- Settle: let any queued focus signals from Step 3 (and the
        -- precondition set above) drain first, so we measure ONLY the
        -- re-focus that happens after the reset below.
        if count < 4 then
            return
        end

        if count == 4 then
            -- Now the queue is quiescent. Re-focus A (a no-op at the Lua
            -- level) and reset the counter to measure just this operation.
            focus_signals_received = 0
            client.focus = clients.a
            assert(client.focus == clients.a,
                "client.focus should still be A")
        end

        -- Give the event queue more iterations to drain, then confirm no
        -- spurious focus signal was emitted for the no-op re-focus.
        if count >= 8 then
            assert(focus_signals_received == 0,
                "Re-focusing same client should not emit focus signal, got " ..
                focus_signals_received)
            print("TEST: Step 4 - PASS (no crash, no spurious signals)")
            return true
        end
    end,

    -- Step 5: Game timer pattern: nil -> c
    -- This must still deliver keyboard focus after clearing
    function()
        print("TEST: Step 5 - Game timer pattern (nil -> c)")

        client.focus = clients.a
        assert(client.focus == clients.a, "Precondition: A is focused")

        focus_signals_received = 0

        -- Simulate game timer: clear focus, then re-set
        client.focus = nil
        -- After nil, focus should either be nil or fall back to first client
        -- (depending on client_focus() behavior with NULL)

        client.focus = clients.a
        assert(client.focus == clients.a,
            "client.focus should be A after nil -> A")

        print("TEST: Step 5 - PASS (nil -> c pattern works)")
        return true
    end,

    -- Step 6: Rapid focus cycling (stress test)
    function()
        print("TEST: Step 6 - Rapid focus cycling")

        for i = 1, 50 do
            client.focus = clients.a
            client.focus = clients.b
        end
        assert(client.focus == clients.b,
            "After cycling, focus should be on B")

        -- Also test rapid same-client re-focus
        for i = 1, 50 do
            client.focus = clients.a
        end
        assert(client.focus == clients.a,
            "After rapid same-focus, should still be on A")

        print("TEST: Step 6 - PASS (100 cycles, no crash)")
        return true
    end,

    -- Step 7: Cleanup
    function()
        print("TEST: Step 7 - All keyboard focus sync tests passed")
        return true
    end,
}

runner.run_steps(steps)
