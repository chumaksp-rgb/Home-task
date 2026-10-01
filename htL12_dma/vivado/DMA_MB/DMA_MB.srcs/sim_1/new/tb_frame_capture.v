`timescale 1ns / 1ps
// tb_frame_capture.v
// Testbench всей системы: MicroBlaze (выполняет настоящий ELF) + AXI GPIO +
// frame_receiver + AXI DMA + axi4_full_ram.
//
// Источник кадров: pix_clk = 25 МГц, кадры 320x200 идут непрерывно один
// за другим с короткой паузой между ними. Значение пикселя зависит от
// номера кадра, строки и столбца -- поэтому по содержимому памяти видно, что
// принят целый кадр, именно с его начала, и какой именно.
//
// Сценарий: сброс -> кадры идут, кнопка не нажата (ничего не должно
// приниматься) -> нажатие кнопки -> программа запускает DMA и даёт start ->
// принимается ближайший полный кадр -> сравнение памяти с ожидаемым.
//
// Сообщения $display -- на английском: консоль XSim не показывает кириллицу.

module tb_frame_capture;

    localparam FRAME_WIDTH  = 320;
    localparam FRAME_HEIGHT = 200;
    localparam FRAME_BYTES  = FRAME_WIDTH * FRAME_HEIGHT;   // 64000
    localparam FRAME_WORDS  = FRAME_BYTES / 4;              // 16000
    localparam FRAME_GAP    = 16;                           // пауза между кадрами, тактов pix_clk

    localparam BTN_PRESS_NS = 300_000;                      // когда нажать кнопку (программа к этому моменту уже загрузилась)
    localparam WATCHDOG_NS  = 20_000_000;                   // предел времени симуляции

    // ---- Сигналы к DUT ----
    reg        clk_p = 1'b0;                                // системный такт 100 МГц (дифференциальный)
    wire       clk_n = ~clk_p;
    reg        reset_rtl = 1'b0;                            // сброс, активный низкий
    reg        btn = 1'b0;                                  // кнопка, нажата = 1
    reg        pix_clk = 1'b0;                              // такт источника пикселей 25 МГц
    reg  [7:0] pix_data = 8'd0;
    reg        pix_valid = 1'b0;
    reg        pix_sof = 1'b0;
    wire       pix_overflow;

    design_1_wrapper dut (
        .btn_tri_i            (btn),
        .diff_clock_rtl_clk_n (clk_n),
        .diff_clock_rtl_clk_p (clk_p),
        .pix_clk              (pix_clk),
        .pix_data             (pix_data),
        .pix_overflow         (pix_overflow),
        .pix_sof              (pix_sof),
        .pix_valid            (pix_valid),
        .reset_rtl            (reset_rtl)
    );

    always #5  clk_p   = ~clk_p;                            // 100 МГц
    always #20 pix_clk = ~pix_clk;                          // 25 МГц

    // ---- Ожидаемое значение пикселя ----
    function [7:0] pixel;
        input integer frame;                                // номер кадра
        input integer idx;                                  // номер пикселя в кадре, 0..63999
        begin
            pixel = (idx % FRAME_WIDTH) + (idx / FRAME_WIDTH) + 17 * frame;  // столбец + строка + 17*кадр
        end
    endfunction

    // ---- Источник кадров: работает всё время, независимо от кнопки ----
    integer src_frame = 0;                                  // номер кадра, который сейчас передаётся
    integer i;

    initial begin
        wait (reset_rtl === 1'b1);
        forever begin
            for (i = 0; i < FRAME_BYTES; i = i + 1) begin
                @(negedge pix_clk);                         // меняем данные по спаду, DUT берёт по фронту
                pix_valid = 1'b1;
                pix_sof   = (i == 0);
                pix_data  = pixel(src_frame, i);
            end
            @(negedge pix_clk);
            pix_valid = 1'b0;                               // пауза между кадрами
            pix_sof   = 1'b0;
            repeat (FRAME_GAP) @(negedge pix_clk);
            src_frame = src_frame + 1;
        end
    end

    // ---- Наблюдение внутри дизайна ----
    wire        start    = dut.design_1_i.frame_receiver.inst.start;          // "старт" от GPIO
    wire [1:0]  rx_state = dut.design_1_i.frame_receiver.inst.state;          // состояние приёмника
    wire        s_tvalid = dut.design_1_i.frame_receiver.inst.m_axis_tvalid;  // поток в DMA

    integer errors = 0;
    integer cap_frame = -1;                                 // какой кадр был захвачен

    // До нажатия кнопки приёмник должен молчать
    always @(posedge clk_p) begin
        if (reset_rtl && !btn && cap_frame < 0 && s_tvalid === 1'b1) begin
            $display("%0t ERROR: stream data before the button was pressed", $time);
            errors = errors + 1;
        end
    end

    // Запомнить, с какого кадра начался приём (переход в состояние ST_CAPTURE = 2)
    always @(rx_state) begin
        if (rx_state === 2'd2 && cap_frame < 0) begin
            cap_frame = src_frame;
            $display("%0t capture started, source frame %0d", $time, cap_frame);
        end
    end

    // ---- Основной сценарий ----
    integer w, b;
    reg [31:0] got, exp;

    initial begin
        $timeformat(-9, 0, " ns", 12);

        #200 reset_rtl = 1'b1;                              // снять сброс
        $display("%0t reset released", $time);

        #(BTN_PRESS_NS);
        if (start !== 1'b0) begin                           // программа должна была выставить start = 0
            $display("%0t ERROR: start is %b before the button press (program not running? ELF associated?)", $time, start);
            errors = errors + 1;
        end
        btn = 1'b1;                                         // нажать кнопку
        $display("%0t button pressed", $time);

        @(posedge start);                                   // программа настроила DMA и дала старт
        $display("%0t start asserted by software", $time);

        @(negedge start);                                   // программа увидела Idle у DMA и сняла старт
        $display("%0t start released: DMA transfer finished", $time);
        btn = 1'b0;

        // Сравнение содержимого памяти с кадром
        for (w = 0; w < FRAME_WORDS; w = w + 1) begin
            got = dut.design_1_i.axi4_full_ram_0.inst.mem[w];
            for (b = 0; b < 4; b = b + 1)
                exp[8*b +: 8] = pixel(cap_frame, 4*w + b);  // первый пиксель -- в младшем байте слова
            if (got !== exp) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("ERROR: word %0d: got %h, expected %h", w, got, exp);
            end
        end

        if (pix_overflow !== 1'b0) begin
            $display("ERROR: pix_overflow = %b (FIFO lost data)", pix_overflow);
            errors = errors + 1;
        end

        $display("Frame %0d checked: %0d words, first %h, last %h",
                 cap_frame, FRAME_WORDS,
                 dut.design_1_i.axi4_full_ram_0.inst.mem[0],
                 dut.design_1_i.axi4_full_ram_0.inst.mem[FRAME_WORDS-1]);
        $display("Errors: %0d", errors);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED");
        $finish;
    end

    // ---- Сторож ----
    initial begin
        #(WATCHDOG_NS);
        $display("%0t ERROR: watchdog timeout (start=%b, rx_state=%0d, cap_frame=%0d)", $time, start, rx_state, cap_frame);
        $display("TEST FAILED");
        $finish;
    end

endmodule
