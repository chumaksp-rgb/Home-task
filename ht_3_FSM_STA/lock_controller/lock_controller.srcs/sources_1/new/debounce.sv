`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: SERHII CHUMAK
//
// Debounce filter for a bus of mechanical contacts.
//
// A new value is accepted only after it has stayed unchanged for STABLE_MS
// milliseconds. Any bounce restarts the timer. One-cycle 'changed' strobe is
// asserted when clean_out actually takes a new value.
//
// Timing parameters are generics on purpose: the testbench instantiates this
// with tiny values so the simulation finishes instantly.
//////////////////////////////////////////////////////////////////////////////////

module debounce #(
    parameter int WIDTH     = 4,
    parameter int CLK_HZ    = 125_000_000,
    parameter int STABLE_MS = 10
) (
    input  logic             clk,
    input  logic             rst,        // asynchronous reset, active high
    input  logic [WIDTH-1:0] noisy_in,   // straight from the pins
    output logic [WIDTH-1:0] clean_out,  // debounced value
    output logic             changed     // 1 clock pulse when clean_out changes
);

    localparam int COUNT_MAX = (CLK_HZ / 1000) * STABLE_MS;
    localparam int CNT_W     = $clog2(COUNT_MAX);

    // ------------------------------------------------------------------
    // Two-stage synchronizer.
    // The buttons are asynchronous to clk, so setup/hold cannot be met.
    // The first flop may go metastable; it settles within one clock and
    // the second flop captures a clean level.
    // ------------------------------------------------------------------
    logic [WIDTH-1:0] sync0, sync1;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sync0 <= '0;
            sync1 <= '0;
        end else begin
            sync0 <= noisy_in;
            sync1 <= sync0;
        end
    end

    // ------------------------------------------------------------------
    // Stability filter.
    // ------------------------------------------------------------------
    logic [WIDTH-1:0] candidate;
    logic [CNT_W-1:0] cnt;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            candidate <= '0;
            clean_out <= '0;
            cnt       <= '0;
            changed   <= 1'b0;
        end else begin
            changed <= 1'b0;                        // default: no strobe

            if (sync1 != candidate) begin
                candidate <= sync1;                 // input moved -> restart
                cnt       <= '0;
            end
            else if (cnt != CNT_W'(COUNT_MAX - 1)) begin
                cnt <= cnt + 1'b1;                  // accumulating stability
            end
            else if (clean_out != candidate) begin
                clean_out <= candidate;             // held long enough: accept
                changed   <= 1'b1;
            end
        end
    end

endmodule
