`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Курсовий проєкт, тема 5: Метроном
//
// Тестбенч модуля axi_metronome (без процесора).
// Сам пише регістри через AXI4-Lite, стежить за виходом tick, порівнює номери
// тактів з порахованими вручну і друкує PASS або FAIL.
//
// Звідки беруться очікувані числа (CLK_HZ = 1000):
//   період у тактах = CLK_HZ * 60 / BPM = 60000 / BPM, заокруглення вниз
//   BPM = 120 -> 500,  BPM = 60 -> 1000,  BPM = 30 -> 2000,  BPM = 240 -> 250
//
// Нумерація тактів: такт 0 це перший такт після запису в ENABLE.
// Імпульси очікуються на тактах P, 2P, 3P, ... де P це період.
//
// Сценарії:
//   1. BPM = 120, перші 2000 тактів
//   2. BPM = 60, потім зміна на 120 під час роботи
//   3. ENABLE = 0 протягом 2000 тактів, потім ENABLE = 1
//   4. BPM = 0 (граничний випадок) і BPM = 1000 (вище верхньої межі)
//
// Щоб перевірити зламану копію, достатньо визначити DUT_MODULE іншим іменем.
//////////////////////////////////////////////////////////////////////////////////

`ifndef DUT_MODULE
`define DUT_MODULE axi_metronome            // имя проверяемого модуля
`endif

module tb_axi_metronome;

    // ---------------- Параметры теста ----------------
    localparam CLK_HZ      = 1000;          // "частота" для модуля: 60000 тактов в минуте
    localparam CLK_PERIOD  = 10;            // период тактового сигнала в симуляции, нс (на счёт тактов не влияет)
    localparam MAX_OBS     = 64;            // сколько импульсов запоминаем за один сценарий

    localparam [3:0] ADDR_BPM    = 4'h0;    // смещение регистра BPM
    localparam [3:0] ADDR_ENABLE = 4'h4;    // смещение регистра ENABLE
    localparam [3:0] ADDR_TICKS  = 4'h8;    // смещение регистра TICKS

    // ---------------- Сигналы к модулю ----------------
    reg         aclk    = 1'b0;             // тактовый сигнал
    reg         aresetn = 1'b0;             // сброс, активный ноль

    reg  [3:0]  s_axi_awaddr  = 4'd0;       // адрес записи
    reg         s_axi_awvalid = 1'b0;       // адрес записи выставлен
    wire        s_axi_awready;              // адрес записи принят
    reg  [31:0] s_axi_wdata   = 32'd0;      // данные записи
    reg         s_axi_wvalid  = 1'b0;       // данные записи выставлены
    wire        s_axi_wready;               // данные записи приняты
    wire [1:0]  s_axi_bresp;                // ответ на запись
    wire        s_axi_bvalid;               // ответ на запись готов
    reg  [3:0]  s_axi_araddr  = 4'd0;       // адрес чтения
    reg         s_axi_arvalid = 1'b0;       // адрес чтения выставлен
    wire        s_axi_arready;              // адрес чтения принят
    wire [31:0] s_axi_rdata;                // прочитанные данные
    wire [1:0]  s_axi_rresp;                // ответ на чтение
    wire        s_axi_rvalid;               // прочитанные данные готовы
    wire        tick;                       // выход метронома

    // ---------------- Проверяемый модуль ----------------
    `DUT_MODULE #(
        .CLK_HZ (CLK_HZ)
    ) dut (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (4'hF),              // пишем слово целиком
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (1'b1),              // ответ на запись принимаем сразу
        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (1'b1),              // данные чтения принимаем сразу
        .tick          (tick)
    );

    // ---------------- Тактовый сигнал ----------------
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // ============================================================================
    // Наблюдатель: счёт тактов и запись моментов импульсов
    // ============================================================================

    integer cyc = 0;                        // номер такта от последней записи в ENABLE
    integer obs [0:MAX_OBS-1];              // номера тактов, на которых был tick
    integer n_obs = 0;                      // сколько импульсов замечено в текущем окне
    reg     watch = 1'b0;                   // окно наблюдения открыто

    // Запись в ENABLE принята модулем в этом такте
    wire en_write = s_axi_awvalid & s_axi_awready & s_axi_wvalid & s_axi_wready
                  & (s_axi_awaddr == ADDR_ENABLE);

    always @(posedge aclk) begin
        if (tick && watch) begin            // tick был высоким в течение такта cyc
            $display("      tick at cycle %0d", cyc);
            if (n_obs < MAX_OBS) obs[n_obs] = cyc;  // запоминаем номер такта
            n_obs = n_obs + 1;
        end
        if (en_write) cyc = 0;              // следующий такт будет тактом 0
        else          cyc = cyc + 1;
    end

    // ============================================================================
    // Учёт ошибок
    // ============================================================================

    integer errors      = 0;                // ошибок всего
    integer scen_errors = 0;                // ошибок в текущем сценарии

    task fail;                              // общая часть для любой ошибки
        begin
            errors      = errors + 1;
            scen_errors = scen_errors + 1;
        end
    endtask

    task scenario_begin(input [8*64-1:0] name);
        begin
            $display("");
            $display("Scenario %0s", name);
            scen_errors = 0;
        end
    endtask

    task scenario_end;
        begin
            if (scen_errors == 0) $display("  -> scenario PASS");
            else                  $display("  -> scenario FAIL (%0d errors)", scen_errors);
        end
    endtask

    // ============================================================================
    // Транзакции AXI4-Lite
    // ============================================================================

    // Запись одного регистра
    task axi_write(input [3:0] addr, input [31:0] data);
        begin
            @(negedge aclk);                // сигналы меняем по спаду, модуль читает их по фронту
            s_axi_awaddr  = addr;
            s_axi_wdata   = data;
            s_axi_awvalid = 1'b1;
            s_axi_wvalid  = 1'b1;
            @(posedge aclk);
            while (!(s_axi_awready && s_axi_wready)) @(posedge aclk); // ждём приёма адреса и данных
            @(negedge aclk);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid  = 1'b0;
            while (!s_axi_bvalid) @(negedge aclk);  // ждём ответ на запись
            if (s_axi_bresp !== 2'b00) begin
                $display("  ERROR: write to 0x%0h, bresp = %b", addr, s_axi_bresp);
                fail;
            end
        end
    endtask

    // Чтение одного регистра
    task axi_read(input [3:0] addr, output [31:0] data);
        begin
            @(negedge aclk);
            s_axi_araddr  = addr;
            s_axi_arvalid = 1'b1;
            @(posedge aclk);
            while (!s_axi_arready) @(posedge aclk); // ждём приёма адреса
            @(negedge aclk);
            s_axi_arvalid = 1'b0;
            while (!s_axi_rvalid) @(negedge aclk);  // ждём данные
            data = s_axi_rdata;
            if (s_axi_rresp !== 2'b00) begin
                $display("  ERROR: read from 0x%0h, rresp = %b", addr, s_axi_rresp);
                fail;
            end
        end
    endtask

    // Чтение регистра и сравнение с ожидаемым значением
    task check_reg(input [3:0] addr, input [31:0] expected, input [8*8-1:0] name);
        reg [31:0] value;
        begin
            axi_read(addr, value);
            if (value === expected) begin
                $display("  ok:    %0s = %0d", name, value);
            end else begin
                $display("  ERROR: %0s = %0d, expected %0d", name, value, expected);
                fail;
            end
        end
    endtask

    // ============================================================================
    // Управление окном наблюдения и проверка импульсов
    // ============================================================================

    // Открыть окно наблюдения и записать ENABLE; отсчёт тактов начинается с нуля
    task set_enable(input value);
        begin
            n_obs = 0;                      // список импульсов начинаем заново
            watch = 1'b1;
            axi_write(ADDR_ENABLE, {31'd0, value});
        end
    endtask

    // Ждать, пока номер такта не станет равен n
    task wait_cycle(input integer n);
        begin
            @(negedge aclk);
            while (cyc < n) @(negedge aclk);
        end
    endtask

    // Закрыть окно после n тактов: в списке остаются импульсы тактов 0 .. n-1
    task close_window(input integer n);
        begin
            wait_cycle(n);
            watch = 1'b0;
        end
    endtask

    // Проверка количества импульсов в окне
    task check_count(input integer expected);
        begin
            if (n_obs === expected) begin
                $display("  ok:    %0d ticks in the window", n_obs);
            end else begin
                $display("  ERROR: %0d ticks in the window, expected %0d", n_obs, expected);
                fail;
            end
        end
    endtask

    // Проверка номера такта для импульса с порядковым номером idx (с нуля)
    task check_tick(input integer idx, input integer expected);
        begin
            if (idx >= n_obs) begin
                $display("  ERROR: tick #%0d is missing, expected at cycle %0d", idx + 1, expected);
                fail;
            end else if (obs[idx] !== expected) begin
                $display("  ERROR: tick #%0d at cycle %0d, expected %0d", idx + 1, obs[idx], expected);
                fail;
            end
        end
    endtask

    // ============================================================================
    // Сценарии
    // ============================================================================

    initial begin
        // ---- Сброс ----
        repeat (5) @(negedge aclk);
        aresetn = 1'b1;
        repeat (2) @(negedge aclk);

        // ------------------------------------------------------------------------
        // Сценарий 1. BPM = 120, первые 2000 тактов.
        // Период 60000 / 120 = 500. В тактах 0..1999 импульсы на 500, 1000, 1500
        // (четвёртый приходится на такт 2000 и в окно уже не попадает).
        // ------------------------------------------------------------------------
        scenario_begin("1: BPM=120, first 2000 cycles");
        axi_write(ADDR_BPM, 32'd120);
        check_reg(ADDR_BPM, 32'd120, "BPM");
        set_enable(1'b1);
        wait_cycle(1700);
        check_reg(ADDR_TICKS, 32'd3, "TICKS");  // к такту 1700 выдано 3 импульса
        close_window(2000);
        check_count(3);
        check_tick(0, 500);
        check_tick(1, 1000);
        check_tick(2, 1500);
        axi_write(ADDR_ENABLE, 32'd0);
        scenario_end;
//$stop;
        // ------------------------------------------------------------------------
        // Сценарий 2. BPM = 60, затем смена на 120 во время работы.
        // Период 1000: импульс на такте 1000. На такте 1300 записываем BPM = 120.
        // Промежуток 1000..2000 уже начат и дорабатывает по старому темпу: импульс
        // на 2000. Дальше период 500: 2500, 3000, 3500. Окно 0..3999.
        // ------------------------------------------------------------------------
        scenario_begin("2: BPM=60, changed to 120 while running");
        axi_write(ADDR_BPM, 32'd60);
        set_enable(1'b1);
        wait_cycle(1300);
        axi_write(ADDR_BPM, 32'd120);
        check_reg(ADDR_BPM, 32'd120, "BPM");
        wait_cycle(3700);
        check_reg(ADDR_TICKS, 32'd5, "TICKS");  // к такту 3700 выдано 5 импульсов
        close_window(4000);
        check_count(5);
        check_tick(0, 1000);
        check_tick(1, 2000);
        check_tick(2, 2500);
        check_tick(3, 3000);
        check_tick(4, 3500);
        axi_write(ADDR_ENABLE, 32'd0);
        scenario_end;

        // ------------------------------------------------------------------------
        // Сценарий 3. ENABLE = 0 в течение 2000 тактов, затем ENABLE = 1.
        // Сначала метроном 300 тактов работает на BPM = 120 и останавливается, не
        // дойдя до первого импульса. За 2000 тактов простоя импульсов быть не
        // должно. После включения отсчёт идёт с нуля: импульсы на 500, 1000, 1500,
        // а не на 200, 700, ... как было бы, если бы счётчик не обнулился.
        // ------------------------------------------------------------------------
        scenario_begin("3: ENABLE=0 for 2000 cycles, then ENABLE=1");
        axi_write(ADDR_BPM, 32'd120);
        set_enable(1'b1);
        wait_cycle(300);
        set_enable(1'b0);                       // останавливаем, окно наблюдения открыто
        check_reg(ADDR_ENABLE, 32'd0, "ENABLE");
        close_window(2000);
        check_count(0);                         // за время простоя ни одного импульса
        set_enable(1'b1);
        wait_cycle(1700);
        check_reg(ADDR_TICKS, 32'd3, "TICKS");  // счёт импульсов тоже начат заново
        close_window(2000);
        check_count(3);
        check_tick(0, 500);
        check_tick(1, 1000);
        check_tick(2, 1500);
        axi_write(ADDR_ENABLE, 32'd0);
        scenario_end;

        // ------------------------------------------------------------------------
        // Сценарий 4 (граничный). BPM = 0 и BPM = 1000.
        // 0 ограничивается до 30: период 60000 / 30 = 2000, в окне 0..4999
        // импульсы на 2000 и 4000.
        // 1000 ограничивается до 240: период 60000 / 240 = 250, в окне 0..599
        // импульсы на 250 и 500.
        // ------------------------------------------------------------------------
        scenario_begin("4: BPM=0 and BPM=1000 (out of range)");
        axi_write(ADDR_BPM, 32'd0);
        check_reg(ADDR_BPM, 32'd30, "BPM");     // читается уже ограниченное значение
        set_enable(1'b1);
        wait_cycle(4700);
        check_reg(ADDR_TICKS, 32'd2, "TICKS");
        close_window(5000);
        check_count(2);
        check_tick(0, 2000);
        check_tick(1, 4000);
        axi_write(ADDR_ENABLE, 32'd0);

        axi_write(ADDR_BPM, 32'd1000);
        check_reg(ADDR_BPM, 32'd240, "BPM");
        set_enable(1'b1);
        close_window(600);
        check_count(2);
        check_tick(0, 250);
        check_tick(1, 500);
        axi_write(ADDR_ENABLE, 32'd0);
        scenario_end;

        // ---- Итог ----
        $display("");
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

    // ---- Защита от зависания: модуль не отвечает по шине ----
    initial begin
        #(CLK_PERIOD * 100000);
        $display("");
        $display("RESULT: FAIL (timeout)");
        $finish;
    end

endmodule
