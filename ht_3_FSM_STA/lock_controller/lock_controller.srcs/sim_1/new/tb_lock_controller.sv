`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer: SERHII CHUMAK
//
// Create Date: 11.09.2026 10:30:49
// Module Name: tb_lock_controller
//
// Change: every digit is now applied together with a one-cycle digit_valid
// strobe. Added a check that the FSM does NOT move while digit_valid is low.
//////////////////////////////////////////////////////////////////////////////////


import lock_pkg::*;

module tb_lock_controller;

    logic       clk;
    logic       rst;
    logic [3:0] digit_in;
    logic       digit_valid;
    logic       unlocked_led;

    lock_controller dut (
        .clk         (clk),
        .rst         (rst),
        .digit_in    (digit_in),
        .digit_valid (digit_valid),
        .unlocked_led(unlocked_led)
    );

    int errors = 0;   // errors counter

    // expected values -- deliberately independent of the DUT constants
    localparam logic [3:0] EXP0 = 4'd5;   // 1 digit
    localparam logic [3:0] EXP1 = 4'd3;   // 2 digit
    localparam logic [3:0] EXP2 = 4'd7;   // 3 digit
    localparam logic [3:0] WRONG = 4'd9;  // matches no code digit

    // ---- Clock generator ----
    initial clk = 0;
    always #5 clk = ~clk;

    // ---- Apply one digit with a valid strobe, then check the state ----
    task automatic check_transition(
        input logic [3:0] digit_val,
        input state_t     expected_state,
        input string      step_name
    );
        digit_in    = digit_val;
        digit_valid = 1'b1;
        @(posedge clk);
        #1;
        digit_valid = 1'b0;
        if (dut.state === expected_state)
            $display("[%0t ns] PASS: %-32s -> state=%s", $time, step_name, dut.state.name());
        else begin
            errors++;
            $display("[%0t ns] FAIL: %-32s -> expected %s, got %s",
                     $time, step_name, expected_state.name(), dut.state.name());
        end
    endtask

    // ---- Hold the digit but keep the strobe low: nothing must move ----
    task automatic check_hold(
        input logic [3:0] digit_val,
        input state_t     expected_state,
        input string      step_name
    );
        digit_in    = digit_val;
        digit_valid = 1'b0;
        repeat (5) @(posedge clk);
        #1;
        if (dut.state === expected_state)
            $display("[%0t ns] PASS: %-32s -> state=%s", $time, step_name, dut.state.name());
        else begin
            errors++;
            $display("[%0t ns] FAIL: %-32s -> expected %s, got %s",
                     $time, step_name, expected_state.name(), dut.state.name());
        end
    endtask

    task automatic do_reset;
        rst         = 1'b1;
        digit_in    = 4'd0;
        digit_valid = 1'b0;
        @(posedge clk);
        #1;
        rst = 1'b0;
    endtask

    initial begin
        // ---- Reset ----
        do_reset();
        $display("[%0t ns] after reset: state=%s (expect LOCKED)", $time, dut.state.name());

        // ---- Scenario 1: correct sequence -> UNLOCKED ----
        check_transition(EXP0, WAIT_D2,  "digit1 correct");

        // key still held, no new strobe: the FSM must stay put
        check_hold      (EXP0, WAIT_D2,  "digit1 held, no strobe");

        check_transition(EXP1, WAIT_D3,  "digit2 correct");
        check_transition(EXP2, UNLOCKED, "digit3 correct");

        if (unlocked_led === 1'b1)
            $display("[%0t ns] PASS: unlocked_led=1 after correct sequence", $time);
        else begin
            errors++;
            $display("[%0t ns] FAIL: unlocked_led expected 1, got %0b", $time, unlocked_led);
        end

        check_transition(4'd0, UNLOCKED, "wrong digit while UNLOCKED");
        check_transition(EXP0, UNLOCKED, "code digit while UNLOCKED");

        // ---- Scenario 2: error on the first digit ----
        do_reset();
        check_transition(WRONG, LOCKED, "digit1 WRONG -> stays LOCKED");

        // ---- Scenario 3: error on the second digit ----
        check_transition(EXP0,  WAIT_D2, "digit1 correct");
        check_transition(WRONG, LOCKED,  "digit2 WRONG -> back to LOCKED");

        // ---- Scenario 4: error on the third digit ----
        check_transition(EXP0,  WAIT_D2, "digit1 correct");
        check_transition(EXP1,  WAIT_D3, "digit2 correct");
        check_transition(WRONG, LOCKED,  "digit3 WRONG -> back to LOCKED");

        $display("[%0t ns] Simulation finished", $time);
        if (errors == 0) $display("=== All checks passed ===");
        else             $display("=== FAILED: %0d error(s) ===", errors);

        #5;   // so the last state is visible on the waveform
        $finish;
    end

endmodule
