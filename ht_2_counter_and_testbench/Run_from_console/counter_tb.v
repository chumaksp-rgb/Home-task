`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: SERHII CHUMAK
// 
// Create Date: 02.09.2026 15:18:20

//////////////////////////////////////////////////////////////////////////////////


module counter_tb;

    // ---- 1. Sigbals ----
    reg        clk;
    reg        rst;
    reg        load;
    reg  [3:0] data_in;
    reg        en;
    reg        up_down;
    wire [3:0] count;

    // ---- 2. Instance DUT ----
    counter dut (
        .clk     (clk),
        .rst     (rst),
        .load    (load),
        .data_in (data_in),
        .en      (en),
        .up_down (up_down),
        .count   (count)
    );

    // ---- 3. Clock: 125 MHz -> period 8 нс ----
    //localparam real CLK_PERIOD = 8.0;

    initial clk = 1'b0;
    //always #(CLK_PERIOD/2.0) clk = ~clk;
    always #5 clk =~ clk; // 5ns


    // ---- 4. Checks ----
    integer errors = 0; // total number of errors

    initial begin
        // Initial stste
        rst     = 1'b0;
        load    = 1'b0;
        data_in = 4'd0;
        en      = 1'b0;
        up_down = 1'b1;

        // === Test 1:  (LOAD) ===

        // 1.Reset for 1 clock tick
        rst = 1'b1;
        @(posedge clk); // waiting for a positive clock edge
        #1;
         rst = 1'b0;

        // 2. Loading  10
        load    = 1'b1; // load on
        data_in = 4'd10;
        @(posedge clk);
        #1;

        // 3.  load off
        load = 1'b0; 
         //#1;
         
        // 4. Check
        if (count === 4'd10)
            $display("PASS: LOAD  count=%0d (expected 10)", count);
        else begin
            $display("FAIL: LOAD  count=%0d (expected 10)", count);
            errors = errors + 1;
        end



        
        
        // === Test 2:  (Counting UP) ===
        
        en = 1'b1; // counter enable
        up_down = 1'b1; // count UP
        
        //  3 clock ticks       
            repeat (3) @(posedge clk);
            #1;

        // Check
        if (count === 4'd13)
            $display("PASS: COUNT UP  count=%0d (expected 13)", count);
        else begin
            $display("FAIL: COUNT UP  count=%0d (expected 13)", count);
            errors = errors + 1;
        end  
        
        //  3 clock ticks       
            repeat (3) @(posedge clk);
            #1;
         
        // Check
        if (count === 4'd0)
            $display("PASS: COUNT UP OVERFILL  count=%0d (expected 0)", count);
        else begin
            $display("FAIL: COUNT UP OVERFILL  count=%0d (expected 0)", count);
            errors = errors + 1;
        end        
   
   
        // === Test 3:  (HOLD) ===
         en = 1'b0; // counter disable
         up_down = 1'b1; // count UP, does not matter

        //  2 clock ticks
        repeat (2) @(posedge clk);           
        #1;
                 

        if (count === 4'd0)
            $display("PASS: COUNT  HOLD  count=%0d (expected 0)", count);
        else begin
            $display("FAIL: COUNT  HOLD  count=%0d (expected 0)", count);
            errors = errors + 1;
        end     
  
  
         // === Test 4:  (COUNT DOWN) ===
          en = 1'b1; // counter enable         
          up_down = 1'b0; // count DOWN
          @(posedge clk);
          #1;
          
        if (count === 4'd15)
            $display("PASS: COUNT DOWN  count=%0d (expected 15)", count);
        else begin
            $display("FAIL: COUNT DOWN  count=%0d (expected 15)", count);
            errors = errors + 1;
        end 
  
  
  
         // === Test 5:  (CHECK PRIORITY LOAD vs EN) === 
        load = 1'b1;
        data_in = 4'd5;
        en = 1'b1;
        up_down = 1'b1;   
             
        //  2 clock ticks
        @(posedge clk);
        #1;
           
          if (count === 4'd5)
            $display("PASS: CHECK PRIORITY  count=%0d (expected 5)", count);
        else begin
            $display("FAIL: CHECK PRIORITY  count=%0d (expected 5)", count);
            errors = errors + 1;
        end
                     
         // Resume
        if (errors == 0) $display("=== Passed ===");
        else             $display("=== Errors: %0d ===", errors);  

//      End of test
        load = 0;
        rst = 1; 
                   
        #15; 
        $finish;
    end 
   
endmodule
