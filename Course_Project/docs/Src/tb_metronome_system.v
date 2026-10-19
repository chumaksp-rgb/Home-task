`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Курсовий проєкт, тема 5: Метроном
//
// Тестбенч: tb_metronome_system
// Призначення: симуляція всієї системи (крок 6). MicroBlaze виконує справжню
//              програму app_metronome.elf, яка пише й читає регістри
//              axi_metronome через AXI4-Lite. Тестбенч лише подає такт і скидання
//              та спостерігає, нічого не пише в модуль сам.
//
// Що перевіряється:
//   - програма виконує транзакції в очікуваному порядку:
//       запис BPM=120, читання BPM, запис ENABLE=1, читання TICKS,
//       запис BPM=240, запис ENABLE=0, читання TICKS;
//   - прочитаний BPM дорівнює 120;
//   - кожне прочитане значення TICKS дорівнює кількості імпульсів tick,
//     які тестбенч сам нарахував від увімкнення;
//   - tick триває рівно один такт;
//   - перший tick приходить через період після запису ENABLE=1, далі імпульси
//     йдуть через 500 тактів (BPM=120), після зміни темпу через 250 (BPM=240);
//   - після ENABLE=0 імпульсів немає.
//
// Модуль спостерігається за ієрархічними іменами
// dut.Metronome_i.axi_metronome_0.inst.* -- перейменування екземпляра в
// Block Design зламає тестбенч.
//
// Повідомлення $display англійською: консоль XSim не показує кирилицю.
//////////////////////////////////////////////////////////////////////////////////

`define MET dut.Metronome_i.axi_metronome_0.inst    // экземпляр модуля внутри Block Design

module tb_metronome_system;

    // ---------------- Параметры ----------------
    localparam CLK_HZ       = 1000;                 // должен совпадать с CLK_HZ в настройках IP
    localparam BPM_MIN      = 30;                   // границы темпа, как в модуле
    localparam BPM_MAX      = 240;
    localparam BPM_RST      = 120;                  // темп после сброса
    localparam ADDR_BPM     = 4'h0;                 // смещения регистров
    localparam ADDR_ENABLE  = 4'h4;
    localparam ADDR_TICKS   = 4'h8;
    localparam N_TRANS      = 7;                    // сколько транзакций делает программа
    localparam TAIL_CYCLES  = 2000;                 // сколько тактов наблюдать после последней транзакции
    localparam WATCHDOG_NS  = 5_000_000;            // предел времени симуляции, 5 мс

    // ---------------- Такт и сброс ----------------
    reg  sys_clk = 1'b0;                            // 125 МГц, как генератор на PYNQ-Z1
    reg  reset_n = 1'b0;                            // внешний сброс, активный ноль
    wire tick;                                      // выход метронома

    always #4 sys_clk = ~sys_clk;                   // период 8 нс

    Metronome_wrapper dut (
        .sys_clk (sys_clk),
        .reset_n (reset_n),
        .tick    (tick)
    );

    initial begin
        $timeformat(-9, 0, " ns", 0);              // %t печатает время в наносекундах
        reset_n = 1'b0;
        #200;
        reset_n = 1'b1;                             // дальше сбросом управляет Processor System Reset
    end

    // ---------------- Сигналы модуля (только чтение) ----------------
    wire        aclk    = `MET.aclk;                // 100 МГц с Clocking Wizard
    wire        aresetn = `MET.aresetn;
    wire [3:0]  awaddr  = `MET.s_axi_awaddr;
    wire [31:0] wdata   = `MET.s_axi_wdata;
    wire [3:0]  araddr  = `MET.s_axi_araddr;
    wire [31:0] rdata   = `MET.s_axi_rdata;
    wire [1:0]  bresp   = `MET.s_axi_bresp;
    wire [1:0]  rresp   = `MET.s_axi_rresp;

    // Рукопожатия AXI4-Lite в текущем такте
    wire wr_hs = `MET.s_axi_awvalid & `MET.s_axi_awready
               & `MET.s_axi_wvalid  & `MET.s_axi_wready;           // запись принята
    wire b_hs  = `MET.s_axi_bvalid  & `MET.s_axi_bready;            // ответ на запись забран
    wire ar_hs = `MET.s_axi_arvalid & `MET.s_axi_arready;           // адрес чтения принят
    wire r_hs  = `MET.s_axi_rvalid  & `MET.s_axi_rready;            // данные чтения забраны

    // ---------------- Ожидаемая последовательность транзакций ----------------
    reg        exp_wr   [0:N_TRANS-1];              // 1 запись, 0 чтение
    reg [3:0]  exp_addr [0:N_TRANS-1];              // смещение регистра
    reg [31:0] exp_data [0:N_TRANS-1];              // данные записи (для чтения не используется)

    initial begin
        exp_wr[0] = 1; exp_addr[0] = ADDR_BPM;    exp_data[0] = 120;  // BPM = 120
        exp_wr[1] = 0; exp_addr[1] = ADDR_BPM;    exp_data[1] = 0;    // чтение BPM
        exp_wr[2] = 1; exp_addr[2] = ADDR_ENABLE; exp_data[2] = 1;    // ENABLE = 1
        exp_wr[3] = 0; exp_addr[3] = ADDR_TICKS;  exp_data[3] = 0;    // чтение TICKS
        exp_wr[4] = 1; exp_addr[4] = ADDR_BPM;    exp_data[4] = 240;  // BPM = 240
        exp_wr[5] = 1; exp_addr[5] = ADDR_ENABLE; exp_data[5] = 0;    // ENABLE = 0
        exp_wr[6] = 0; exp_addr[6] = ADDR_TICKS;  exp_data[6] = 0;    // чтение TICKS
    end

    // ---------------- Модель модуля в тестбенче ----------------
    integer errors     = 0;                         // количество ошибок
    integer n_trans    = 0;                         // сколько транзакций уже было
    integer cyc        = 0;                         // номер такта от последней записи ENABLE=1
    integer last_tick  = 0;                         // такт предыдущего импульса
    integer period     = 0;                         // ожидаемая длина текущего промежутка
    integer bpm_m      = BPM_RST;                   // BPM с учётом записей до предыдущего такта
    integer bpm_m1     = BPM_RST;                   // то же, на такт раньше
    integer tb_ticks   = 0;                         // импульсы, насчитанные тестбенчем с момента включения
    integer n_250      = 0;                         // сколько промежутков по 250 тактов увидено
    reg     enabled    = 1'b0;                      // метроном включён (по записям программы)
    reg     tick_d     = 1'b0;                      // tick в предыдущем такте
    integer dis_cyc    = -1;                        // такт записи ENABLE=0
    reg [3:0]  rd_addr;                             // адрес текущего чтения
    reg [31:0] rd_exp;                              // ожидаемые данные текущего чтения
    integer    rd_idx;                              // номер текущего чтения в последовательности
    integer    ticks_running = -1;                  // TICKS, прочитанный во время работы
    integer    ticks_stopped = -1;                  // TICKS, прочитанный после выключения
    integer    t_done = -1;                         // такт последней транзакции

    // Ограничение темпа, как в модуле
    function integer clamp(input [31:0] v);
        begin
            if (v < BPM_MIN)      clamp = BPM_MIN;
            else if (v > BPM_MAX) clamp = BPM_MAX;
            else                  clamp = v;
        end
    endfunction

    always @(posedge aclk) begin
        if (aresetn) begin
            // ---- Импульсы tick ----
            if (tick) begin
                if (tick_d) begin
                    $display("ERROR: tick is high for more than one cycle at %0t", $time);
                    errors = errors + 1;
                end
                if (!enabled && !(dis_cyc >= 0 && cyc == dis_cyc + 1)) begin
                    // после ENABLE=0 допустим только импульс, уже начатый в такте записи
                    $display("ERROR: tick at %0t while the metronome is disabled", $time);
                    errors = errors + 1;
                end else begin
                    tb_ticks = tb_ticks + 1;
                    if (cyc - last_tick != period) begin
                        $display("ERROR: tick #%0d at cycle %0d: interval %0d, expected %0d",
                                 tb_ticks, cyc, cyc - last_tick, period);
                        errors = errors + 1;
                    end else begin
                        $display("      tick #%0d at cycle %0d (interval %0d)", tb_ticks, cyc, cyc - last_tick);
                    end
                    if (cyc - last_tick == 250) n_250 = n_250 + 1;
                    last_tick = cyc;
                    period    = (60 * CLK_HZ) / bpm_m1;  // следующий промежуток: темп на начало промежутка
                end
            end
            tick_d = tick;

            // ---- Запись ----
            if (wr_hs) begin
                $display("AXI WRITE  addr 0x%h  data %0d  at %0t", awaddr, wdata, $time);
                if (n_trans >= N_TRANS || !exp_wr[n_trans] || exp_addr[n_trans] != awaddr
                        || exp_data[n_trans] != wdata) begin
                    $display("ERROR: unexpected write, transaction #%0d", n_trans + 1);
                    errors = errors + 1;
                end
                n_trans = n_trans + 1;
                if (awaddr[3:2] == 2'd1) begin                     // ENABLE
                    if (wdata[0] && !enabled) begin
                        tb_ticks  = 0;                              // модуль обнуляет TICKS при включении
                        last_tick = 0;
                        period    = (60 * CLK_HZ) / bpm_m;          // первый промежуток
                        cyc       = -1;                             // следующий такт будет тактом 0
                        $display("      expected period %0d cycles", period);
                    end
                    if (!wdata[0] && enabled) dis_cyc = cyc;
                    enabled = wdata[0];
                end
                if (n_trans == N_TRANS) t_done = cyc;
            end
            bpm_m1 = bpm_m;                                         // до обновления этим тактом
            if (wr_hs && awaddr[3:2] == 2'd0) bpm_m = clamp(wdata); // BPM, как его запишет модуль

            if (b_hs && bresp != 2'b00) begin
                $display("ERROR: write response is not OKAY");
                errors = errors + 1;
            end

            // ---- Чтение: ожидаемое значение фиксируется в такте приёма адреса ----
            if (ar_hs) begin
                rd_addr = araddr;
                rd_idx  = n_trans;
                case (araddr[3:2])
                    2'd0:    rd_exp = bpm_m1;                       // значение регистра до этого такта
                    2'd1:    rd_exp = enabled;
                    2'd2:    rd_exp = tb_ticks;                     // уже с учётом tick в этом такте
                    default: rd_exp = 0;
                endcase
                if (n_trans >= N_TRANS || exp_wr[n_trans] || exp_addr[n_trans] != araddr) begin
                    $display("ERROR: unexpected read of 0x%h, transaction #%0d", araddr, n_trans + 1);
                    errors = errors + 1;
                end
                n_trans = n_trans + 1;
                if (n_trans == N_TRANS) t_done = cyc;
            end
            if (r_hs) begin
                $display("AXI READ   addr 0x%h  data %0d  at %0t", rd_addr, rdata, $time);
                if (rdata !== rd_exp || rresp != 2'b00) begin
                    $display("ERROR: read 0x%h returned %0d, expected %0d", rd_addr, rdata, rd_exp);
                    errors = errors + 1;
                end
                if (rd_addr == ADDR_TICKS && rd_idx == 3) ticks_running = rdata;
                if (rd_addr == ADDR_TICKS && rd_idx == 6) ticks_stopped = rdata;
            end

            cyc = cyc + 1;
        end
    end

    // ---------------- Завершение ----------------
    initial begin
        wait (t_done >= 0);                                         // программа сделала все транзакции
        wait (cyc >= t_done + TAIL_CYCLES);                         // убеждаемся, что импульсов больше нет
        $display("");
        $display("TICKS while running: %0d, after disable: %0d, ticks counted by testbench: %0d",
                 ticks_running, ticks_stopped, tb_ticks);
        if (ticks_running < 1) begin
            $display("ERROR: no tick before the first TICKS read, the delay in main.c is too short");
            errors = errors + 1;
        end
        if (n_250 < 1) begin
            $display("ERROR: no 250-cycle interval after BPM=240, the delay in main.c is too short");
            errors = errors + 1;
        end
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #(WATCHDOG_NS);
        $display("ERROR: timeout, the program made %0d of %0d transactions", n_trans, N_TRANS);
        $display("RESULT: FAIL (timeout)");
        $finish;
    end

endmodule
