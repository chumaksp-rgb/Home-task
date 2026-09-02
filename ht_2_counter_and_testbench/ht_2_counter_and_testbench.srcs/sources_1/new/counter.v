`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: SERHII CHUMAK
// 
// Create Date: 02.09.2026 13:32:27

// 
//////////////////////////////////////////////////////////////////////////////////


module counter(
    input wire clk,
    input wire rst,
    input wire load,
    input wire [3:0] data_in,
    input wire en,
    input wire up_down,
    output reg [3:0] count

    );
    
    always @(posedge clk or posedge rst) begin
        if(rst == 1) 
            count <= 4'd0;
        else if(load == 1)
             count <= data_in;
         else if(en == 1)begin
             if (up_down == 1)
                count <= count + 1'b1;
             else count <= count - 1'b1; 
          end     
             
     end
endmodule


