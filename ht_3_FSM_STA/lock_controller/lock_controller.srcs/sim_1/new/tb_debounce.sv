`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: SERHII CHUMAK
//
// Testbench for the debounce filter.
//
// CLK_HZ/STABLE_MS are shrunk so COUNT_MAX = 5 clocks instead of 1_250_000.
// Same logic, instant simulation.
//////////////////////////////////////////////////////////////////////////////////

module tb_debounce;

    localparam int WIDTH     = 4;
    localparam int CLK_HZ    = 1000;
    localparam int STABLE_MS = 5;
    localparam int STABLE    = (CLK_HZ / 1000) * STABLE_MS;   // = 5 clocks

    logic             clk;
    logic             rst;
    logic [WIDTH-1:0] noisy_in;
    logic [WIDTH-1:0] clean_out;
    logic             changed;

    int errors  = 0;
    int strobes = 0;

    debounce #(
        .WIDTH     (WIDTH),
        .CLK_HZ    (CLK_HZ),
        .STABLE_MS (STABLE_MS)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .noisy_in  (noisy_in),
        .clean_out (clean_out),
        .changed   (changed)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // count strobes so we can prove there is exactly ONE per accepted value
    always @(posedge clk)
        if (changed) strobes++;

    task automatic check(input logic [WIDTH-1:0] expected, input string step_name);
        if (clean_out === expected)
            $display("[%0t ns] PASS: %-38s clean_out=%0d", $time, step_name, clean_out);
        else begin
            errors++;
            $display("[%0t ns] FAIL: %-38s expected %0d, got %0d",
                     $time, step_name, expected, clean_out);
        end
    endtask

    task automatic check_strobes(input int expected, input string step_name);
        if (strobes == expected)
            $display("[%0t ns] PASS: %-38s strobes=%0d", $time, step_name, strobes);
        else begin
            errors++;
            $display("[%0t ns] FAIL: %-38s expected %0d strobes, got %0d",
                     $time, step_name, expected, strobes);
        end
    endtask

    initial begin
    $timeformat(-9, 0, " ns", 0);
        rst      = 1'b1;
        noisy_in = 4'd0;
        repeat (2) @(posedge clk);
        #1 rst = 1'b0;
        repeat (STABLE + 3) @(posedge clk);
        strobes = 0;                       // ignore anything during reset

        // --- 1. Short bounce, shorter than the stability window ---
        noisy_in = 4'd5; repeat (2) @(posedge clk);
        noisy_in = 4'd0; repeat (1) @(posedge clk);
        noisy_in = 4'd5; repeat (2) @(posedge clk);
        noisy_in = 4'd0; repeat (1) @(posedge clk);
        #1;
        check(4'd0, "bounce shorter than window ignored");

        // --- 2. Now hold 5 long enough: it must be accepted, exactly once ---
        noisy_in = 4'd5;
        repeat (STABLE + 4) @(posedge clk);
        #1;
        check(4'd5, "stable 5 accepted");
        check_strobes(1, "exactly one strobe for one press");

        // --- 3. Keep holding: no further strobes ---
        repeat (STABLE + 5) @(posedge clk);
        #1;
        check_strobes(1, "no extra strobes while held");

        // --- 4. Release: clean_out returns to 0 and strobes again ---
        noisy_in = 4'd0;
        repeat (STABLE + 4) @(posedge clk);
        #1;
        check(4'd0, "release accepted");
        check_strobes(2, "release also produces a strobe");

        // --- 5. Next digit ---
        strobes  = 0;
        noisy_in = 4'd3;
        repeat (STABLE + 4) @(posedge clk);
        #1;
        check(4'd3, "next digit accepted");
        check_strobes(1, "exactly one strobe for next digit");

        $display("[%0t ns] Simulation finished", $time);
        if (errors == 0) $display("=== All checks passed ===");
        else             $display("=== FAILED: %0d error(s) ===", errors);

        #5;
        $finish;
    end

endmodule
