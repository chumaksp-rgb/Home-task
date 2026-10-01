`timescale 1ns / 1ps
// frame_receiver.v
// Приёмник кадра: берёт 8-битные пиксели извне дизайна (на собственной
// частоте pix_clk), пакует их по 4 в 32-битные слова, переносит через
// асинхронный FIFO в домен aclk и выдаёт как AXI4-Stream master
// (подключается к AXI DMA, S_AXIS_S2MM).
//
// Приём начинается только после сигнала start (от MicroBlaze через
// AXI GPIO). До этого входные порты игнорируются. После start модуль
// ждёт начала кадра (pix_sof), принимает ровно FRAME_BYTES байтов,
// на последнем слове выставляет TLAST и снова засыпает до следующего start.
//
// Порядок байтов: первый принятый пиксель -> биты [7:0] слова, то есть
// в памяти (little-endian) пиксели лежат подряд, байт за байтом.

module frame_receiver #(
    parameter FRAME_BYTES = 320 * 200,              // пикселей (байтов) в кадре; должно быть кратно 4
    parameter FIFO_AW     = 4                       // log2 глубины FIFO (16 слов); не меньше 2
) (
    // ---- Вход кадра (домен pix_clk, извне дизайна) ----
    input  wire        pix_clk,                     // тактовый сигнал источника пикселей
    input  wire [7:0]  pix_data,                    // пиксель
    input  wire        pix_valid,                   // пиксель валиден в этом такте
    input  wire        pix_sof,                     // начало кадра: стоит вместе с первым пикселем
    output reg         pix_overflow,                // FIFO переполнился, слово потеряно (липкий флаг, для отладки)

    // ---- Системный домен (aclk) ----
    input  wire        aclk,                        // тактовый сигнал AXI
    input  wire        aresetn,                     // сброс, активный низкий
    input  wire        start,                       // уровень от GPIO: фронт 0->1 разрешает приём одного кадра

    // ---- Master side (выход потока к DMA) ----
    output wire [31:0] m_axis_tdata,                // 32-битное слово (4 пикселя)
    output wire        m_axis_tvalid,               // модуль: слово валидно
    input  wire        m_axis_tready,               // DMA: готов забрать слово
    output wire        m_axis_tlast                 // последнее слово кадра
);

    localparam DW = 33;                             // ширина слова FIFO: tlast + 32 бита данных

    reg [DW-1:0] mem [0:(1<<FIFO_AW)-1];            // память FIFO

    // ============ Сброс для домена pix_clk ============
    // Асинхронно входим в сброс, синхронно (по pix_clk) выходим.
    reg [1:0] wrst_sync;                            // синхронизатор снятия сброса
    wire      wrstn = wrst_sync[1];                 // сброс домена pix_clk, активный низкий

    always @(posedge pix_clk or negedge aresetn) begin
        if (!aresetn) wrst_sync <= 2'b00;           // сброс активен сразу
        else          wrst_sync <= {wrst_sync[0], 1'b1};  // снимается через 2 такта pix_clk
    end

    // ============ start: aclk -> pix_clk ============
    reg [2:0] start_sync;                           // 2 триггера синхронизации + 1 для детектора фронта
    wire      start_rise = start_sync[1] && !start_sync[2];  // фронт 0->1 в домене pix_clk

    always @(posedge pix_clk or negedge wrstn) begin
        if (!wrstn) start_sync <= 3'b000;           // асинхронный сброс
        else        start_sync <= {start_sync[1:0], start};  // сдвиг
    end

    // ============ Указатели FIFO ============
    reg  [FIFO_AW:0] wbin, wgray;                   // указатель записи: двоичный и в коде Грея (pix_clk)
    reg  [FIFO_AW:0] rbin, rgray;                   // указатель чтения: двоичный и в коде Грея (aclk)
    reg  [FIFO_AW:0] rgray_w1, rgray_w2;            // указатель чтения, синхронизированный в pix_clk
    reg  [FIFO_AW:0] wgray_r1, wgray_r2;            // указатель записи, синхронизированный в aclk

    wire [FIFO_AW:0] wbin_next = wbin + 1'b1;       // следующий указатель записи
    wire [FIFO_AW:0] rbin_next = rbin + 1'b1;       // следующий указатель чтения

    wire wfull  = (wgray == {~rgray_w2[FIFO_AW:FIFO_AW-1], rgray_w2[FIFO_AW-2:0]});  // полон: два старших бита Грея инвертированы
    wire rempty = (rgray == wgray_r2);              // пуст: указатели совпали

    // ============ Приём и упаковка (домен pix_clk) ============
    localparam ST_IDLE = 2'd0, ST_WAIT_SOF = 2'd1, ST_CAPTURE = 2'd2;  // состояния: сон / ждём начало кадра / приём
    reg [1:0]  state;                               // текущее состояние приёма
    reg [31:0] byte_cnt;                            // номер текущего байта в кадре
    reg [23:0] pack;                                // три младших байта собираемого слова

    wire take      = pix_valid && ((state == ST_CAPTURE) ||
                                   (state == ST_WAIT_SOF && pix_sof));  // этот пиксель принимаем
    wire last_byte = (byte_cnt == FRAME_BYTES - 1);                     // это последний байт кадра
    wire wr_en     = take && (byte_cnt[1:0] == 2'd3);                   // четвёртый байт -> слово готово
    wire [DW-1:0] wr_data = {last_byte, pix_data, pack};                // {tlast, байт3, байт2, байт1, байт0}

    always @(posedge pix_clk or negedge wrstn) begin
        if (!wrstn) begin                           // асинхронный сброс
            state        <= ST_IDLE;                // спим, вход игнорируется
            byte_cnt     <= 0;                      // счётчик байтов в ноль
            pack         <= 0;                      // обнулить собираемое слово
            pix_overflow <= 1'b0;                   // переполнения не было
        end else begin
            if (state == ST_IDLE && start_rise)     // пришёл "старт"
                state <= ST_WAIT_SOF;               // ждём начало ближайшего кадра

            if (take) begin                         // принят очередной пиксель
                pack[8*byte_cnt[1:0] +: 8] <= pix_data;  // положить байт на своё место (для 4-го байта не используется)
                if (last_byte) begin                // кадр принят целиком
                    byte_cnt <= 0;                  // счётчик в ноль
                    state    <= ST_IDLE;            // заснуть до следующего "старта"
                end else begin
                    byte_cnt <= byte_cnt + 1'b1;    // следующий байт
                    state    <= ST_CAPTURE;         // продолжаем приём (в т.ч. переход из WAIT_SOF)
                end
            end

            if (wr_en && wfull)                     // слово готово, а места в FIFO нет
                pix_overflow <= 1'b1;               // запомнить потерю
        end
    end

    // ============ Запись в FIFO (домен pix_clk) ============
    always @(posedge pix_clk) begin
        if (wr_en && !wfull)                        // есть слово и есть место
            mem[wbin[FIFO_AW-1:0]] <= wr_data;      // записать в память
    end

    always @(posedge pix_clk or negedge wrstn) begin
        if (!wrstn) begin                           // асинхронный сброс
            wbin     <= 0;                          // указатель записи в ноль
            wgray    <= 0;
            rgray_w1 <= 0;                          // синхронизатор указателя чтения в ноль
            rgray_w2 <= 0;
        end else begin
            {rgray_w2, rgray_w1} <= {rgray_w1, rgray};  // 2 триггера: rgray -> pix_clk
            if (wr_en && !wfull) begin              // слово записано
                wbin  <= wbin_next;                 // сдвинуть указатель
                wgray <= wbin_next ^ (wbin_next >> 1);  // он же в коде Грея
            end
        end
    end

    // ============ Чтение из FIFO = AXI4-Stream master (домен aclk) ============
    assign m_axis_tvalid = !rempty;                 // слово есть -> валидно
    assign {m_axis_tlast, m_axis_tdata} = mem[rbin[FIFO_AW-1:0]];  // слово на выходе сразу (first-word fall-through)

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin                         // асинхронный сброс
            rbin     <= 0;                          // указатель чтения в ноль
            rgray    <= 0;
            wgray_r1 <= 0;                          // синхронизатор указателя записи в ноль
            wgray_r2 <= 0;
        end else begin
            {wgray_r2, wgray_r1} <= {wgray_r1, wgray};  // 2 триггера: wgray -> aclk
            if (m_axis_tvalid && m_axis_tready) begin   // handshake: DMA забрал слово
                rbin  <= rbin_next;                 // сдвинуть указатель
                rgray <= rbin_next ^ (rbin_next >> 1);  // он же в коде Грея
            end
        end
    end

endmodule
