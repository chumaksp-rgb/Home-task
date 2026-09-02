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
    localparam real CLK_PERIOD = 8.0;

    initial clk = 1'b0;
    always #(CLK_PERIOD/2.0) clk = ~clk;



  // ---- 4. Воздействия ----
    initial begin
        // Исходное состояние: всё выключено, сброс активен
        rst     = 1'b1;
        load    = 1'b0;
        data_in = 4'd0;
        en      = 1'b0;
        up_down = 1'b1;

        // Асинхронный сброс: снимаем не по фронту, а между фронтами
        #13 rst = 1'b0;

        // --- Счёт вверх от 0 ---
        @(negedge clk) en = 1'b1;
        repeat (20) @(negedge clk);          // 0..15, переполнение в 0, дальше 0..3

        // --- Счёт вниз ---
        @(negedge clk) up_down = 1'b0;
        repeat (8) @(negedge clk);           // проверяем и заём: 0-1 -> 15

        // --- Загрузка ---
        @(negedge clk) begin
            load    = 1'b1;
            data_in = 4'd10;
        end
        @(negedge clk) load = 1'b0;

        // --- Приоритет load над en ---
        @(negedge clk) begin
            load    = 1'b1;                  // en всё ещё 1
            data_in = 4'd7;
        end
        @(negedge clk) load = 1'b0;          // count должен стать 7, а не 6

        // --- Пауза: en=0, значение держится ---
        @(negedge clk) en = 1'b0;
        repeat (5) @(negedge clk);

        // --- Асинхронный сброс во время счёта ---
        @(negedge clk) en = 1'b1;
        repeat (3) @(negedge clk);
        #2 rst = 1'b1;                       // намеренно НЕ по фронту
        #4 rst = 1'b0;                       // count должен обнулиться сразу

        repeat (5) @(negedge clk);
        $finish;
    end
   
endmodule
