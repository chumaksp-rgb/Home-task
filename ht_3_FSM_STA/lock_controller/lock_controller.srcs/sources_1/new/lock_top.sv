`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: SERHII CHUMAK
//
// Top level for the board: raw buttons -> debounce -> FSM -> LED.
//////////////////////////////////////////////////////////////////////////////////

module lock_top #(
    parameter int CLK_HZ    = 125_000_000,   // PYNQ-Z1 oscillator
    parameter int STABLE_MS = 10
) (
    input  logic       clk,
    input  logic       rst_btn,     // raw reset button
    input  logic [3:0] btn,         // raw digit buttons
    output logic       unlocked_led
);

    // ------------------------------------------------------------------
    // Reset synchronizer: assert asynchronously, release synchronously.
    // A raw button release can violate the recovery time of every flop in
    // the design and put them into metastability at different moments,
    // which would leave the FSM in an undefined state.
    // ------------------------------------------------------------------
    logic rst_meta, rst;

    always_ff @(posedge clk or posedge rst_btn) begin
        if (rst_btn) begin
            rst_meta <= 1'b1;
            rst      <= 1'b1;
        end else begin
            rst_meta <= 1'b0;
            rst      <= rst_meta;
        end
    end

    // ------------------------------------------------------------------
    // Debounce
    // ------------------------------------------------------------------
    logic [3:0] digit_clean;
    logic       digit_changed;
    logic       digit_valid;

    debounce #(
        .WIDTH     (4),
        .CLK_HZ    (CLK_HZ),
        .STABLE_MS (STABLE_MS)
    ) u_db (
        .clk       (clk),
        .rst       (rst),
        .noisy_in  (btn),
        .clean_out (digit_clean),
        .changed   (digit_changed)
    );

    // 'changed' also fires on release (value goes back to 0000). Treat 0000 as
    // "nothing pressed" so releasing a button does not look like a wrong digit.
    // Side effect: the digit 0 cannot be entered.
    assign digit_valid = digit_changed && (digit_clean != 4'd0);

    // ------------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------------
    lock_controller u_fsm (
        .clk          (clk),
        .rst          (rst),
        .digit_in     (digit_clean),
        .digit_valid  (digit_valid),
        .unlocked_led (unlocked_led)
    );

endmodule
