`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: SERHII CHUMAK
// 
// Create Date: 11.09.2026 10:30:49
// Design Name: 
// Module Name: tb_lock_controller

// 
//////////////////////////////////////////////////////////////////////////////////


import lock_pkg::*;

module tb_lock_controller;

    logic       clk;
    logic       rst;
    logic [3:0] digit_in;
    logic       unlocked_led;

    lock_controller dut (
        .clk(clk), .rst(rst),
        .digit_in(digit_in), .unlocked_led(unlocked_led)
    );

    //expected values
    localparam logic [3:0] EXP0 = 4'd5; //1 digit
    localparam logic [3:0] EXP1 = 4'd3; //2 digit
    localparam logic [3:0] EXP2 = 4'd7; //3 digit
    
    // ---- Clock generator ----
    initial clk = 0;
    always #5 clk = ~clk;

    // ---- Self-checking task: apply one digit, check the resulting state ----
    task automatic check_transition(
        input logic [3:0] digit_val,
        input state_t      expected_state,
        input string        step_name
    );
        digit_in = digit_val;
        @(posedge clk); #1;
        if (dut.state === expected_state)
            $display("[%0t ns] PASS: %-28s -> state=%s", $time, step_name, dut.state.name());
        else
            $display("[%0t ns] FAIL: %-28s -> expected %s, got %s",
                      $time, step_name, expected_state.name(), dut.state.name());
    endtask

    initial begin
        // ---- Reset ----
        rst = 1; 
        digit_in = 4'd0;
        @(posedge clk); 
        #1;
        rst = 0;
        $display("[%0t ns] after reset: state=%s (expect LOCKED)", $time, dut.state.name());


        // ---- Scenario 1: correct sequence -> UNLOCKED ----
        check_transition(EXP0, WAIT_D2,  "digit1 correct");
        check_transition(EXP1, WAIT_D3,  "digit2 correct");
        check_transition(EXP2, UNLOCKED, "digit3 correct");
        if (unlocked_led === 1'b1)
            $display("[%0t ns] PASS: unlocked_led=1 after correct sequence", $time);
        else
            $display("[%0t ns] FAIL: unlocked_led expected 1, got %0b", $time, unlocked_led);

        check_transition(4'd0, UNLOCKED, "wrong digit while UNLOCKED");
        check_transition(EXP0, UNLOCKED, "code digit while UNLOCKED");
        
        // ---- Reset before the error scenario ----
        rst = 1; digit_in = 4'd0;
        @(posedge clk); #1;
        rst = 0;

        // ---- Scenario 2: error on the second digit -> back to LOCKED ----
        check_transition(EXP0,     WAIT_D2, "digit1 correct");
        check_transition(EXP0 + 1, LOCKED,  "digit2 WRONG -> back to LOCKED");

        $display("[%0t ns] Simulation finished", $time);
        #5; // delay in order to see last state LOCKED after wrong digit input
        $finish;
    end

endmodule

