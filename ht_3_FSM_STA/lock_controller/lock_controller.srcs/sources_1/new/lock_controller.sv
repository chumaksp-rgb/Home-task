`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: SERHII CHUMAK
// 
// Create Date: 11.09.2026 10:20:47
//////////////////////////////////////////////////////////////////////////////////

import lock_pkg::*;


module lock_controller (
    input  logic       clk,
    input  logic       rst,        // asynchronous reset, active high
    input  logic [3:0] digit_in,
    output logic       unlocked_led
);

    // The 3-digit code. Change these three values to set a different code.
    localparam logic [3:0] CODE0 = 4'd5;
    localparam logic [3:0] CODE1 = 4'd3;
    localparam logic [3:0] CODE2 = 4'd7;

    state_t state, next_state;

    // ---- Block 1: state register (memory only) ----
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            state <= LOCKED;
        else
            state <= next_state;
    end

    // ---- Block 2: next-state logic (transitions) ----
    always_comb begin
        next_state = state;  // default -> avoids an unintended latch
        case (state)
            LOCKED:
                if (digit_in == CODE0) next_state = WAIT_D2;
                else                   next_state = LOCKED;
            WAIT_D2:
                if (digit_in == CODE1) next_state = WAIT_D3;
                else                   next_state = LOCKED;
            WAIT_D3:
                if (digit_in == CODE2) next_state = UNLOCKED;
                else                   next_state = LOCKED;
            UNLOCKED:
                next_state = UNLOCKED;
            default:
                next_state = LOCKED;
        endcase
    end

    // ---- Block 3: output logic (Moore -- depends only on state) ----
    always_comb begin
        unlocked_led = (state == UNLOCKED);
    end

endmodule
