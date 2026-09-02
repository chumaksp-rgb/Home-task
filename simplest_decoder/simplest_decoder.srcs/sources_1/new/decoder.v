`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: SERHII CHUMAK
// Home task 1


//////////////////////////////////////////////////////////////////////////////////

// ***************************** counter *************************************
module counter4 (
    input  logic       clk,
    input  logic       rst,
    output logic [3:0] led
);

    always_ff @(posedge clk) begin
        if (rst)
            led <= 4'd0;
        else
            led <= led + 1'b1;
    end

endmodule

// Simulation
/*
    restart
    add_force {/counter4/rst} {1 0ns}
    add_force {/counter4/clk} {0 0ns} {1 5ns} -repeat_every 10ns
    run 30 ns
    
    add_force {/counter4/rst} {0 0ns}
    run 200 ns
*/

// *********************************** decoder ***********************************
module decoder_top (
    input  logic [1:0] sel4,
    output logic [3:0] out4,

    input  logic [2:0] sel8,
    output logic [7:0] out8
);

    decoder #(.WIDTH(4)) u4 (.sel(sel4), .out(out4));
    decoder #(.WIDTH(8)) u8 (.sel(sel8), .out(out8));

endmodule


module decoder #( parameter  integer WIDTH = 4)
(
    input  logic [$clog2(WIDTH)-1:0] sel,
    output logic [WIDTH-1:0]         out
);

    always_comb begin
        out = '0;
        out[sel] = 1'b1;
        
        // Another way (for WIDTH = 4 only)    
/*        case (sel)
            2'd0: out = 4'b0001;
            2'd1: out = 4'b0010;
            2'd2: out = 4'b0100;
            2'd3: out = 4'b1000;
            default: out = 4'b0000;
           
               //the default clause is mandatory here, and this is the main rule
               //for working with case in combinational logic. without it, if the
               // value was not enumerated, out would retain its previous value,
                //and "retaining a value" in hardware means a latch-a parasitic memory 
                //element you didn't design. the synthesizer will issue a warning 
                //like "inferred latch," and it can't be ignored
            
       endcase*/     
    end


endmodule
/*
// For simulation - Run Simulation, Run this script in TCL console:
    add_force -radix dec {/decoder_top/sel4} {0 0ns}
    add_force -radix dec {/decoder_top/sel8} {0 0ns}
    run 20 ns
    
    add_force -radix dec {/decoder_top/sel4} {1 0ns}
    add_force -radix dec {/decoder_top/sel8} {1 0ns}
    run 20 ns
    
    add_force -radix dec {/decoder_top/sel4} {2 0ns}
    add_force -radix dec {/decoder_top/sel8} {2 0ns}
    run 20 ns
    
    add_force -radix dec {/decoder_top/sel4} {3 0ns}
    add_force -radix dec {/decoder_top/sel8} {3 0ns}
    run 20 ns
    
    add_force -radix dec {/decoder_top/sel8} {4 0ns}
    run 20 ns
    
    add_force -radix dec {/decoder_top/sel8} {5 0ns}
    run 20 ns
    
    add_force -radix dec {/decoder_top/sel8} {6 0ns}
    run 20 ns
    
    add_force -radix dec {/decoder_top/sel8} {7 0ns}
    run 20 ns
*/