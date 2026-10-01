// axi4_full_ram.v
// Простий AXI4 (Full) slave. Порти названі за офіційною конвенцією
// Vivado (interface_name + "_" + AXI signal name, тут "s_axi_..."),
// щоб Package IP міг АВТОМАТИЧНО розпізнати AXI4-інтерфейс без
// ручного втручання (підтверджено офіційною документацією UG1118).

module axi4_full_ram #(
    parameter DATA_WIDTH = 32,   // ширина слова данных
    parameter ADDR_WIDTH = 10,   // ширина байтового адреса (2^10 = 1 КБ)
    parameter MEM_DEPTH  = 256   // число слов в памяти
) (
    input  wire                        s_axi_aclk,     // тактовый сигнал
    input  wire                        s_axi_aresetn,  // сброс, активный низкий

    // --- Канал адреса записи (AW) ---
    input  wire [ADDR_WIDTH-1:0]       s_axi_awaddr,   // начальный адрес записи
    input  wire [7:0]                  s_axi_awlen,    // длина пакета минус 1 (0 = 1 слово)
    input  wire [2:0]                  s_axi_awsize,   // размер слова (не используется)
    input  wire [1:0]                  s_axi_awburst,  // тип пакета (не используется)
    input  wire                        s_axi_awvalid,  // мастер: адрес валиден
    output wire                        s_axi_awready,  // slave: готов принять адрес

    // --- Канал данных записи (W) ---
    input  wire [DATA_WIDTH-1:0]       s_axi_wdata,    // данные для записи
    input  wire [DATA_WIDTH/8-1:0]     s_axi_wstrb,    // маска байтов (не используется)
    input  wire                        s_axi_wlast,    // последнее слово пакета (не используется)
    input  wire                        s_axi_wvalid,   // мастер: данные валидны
    output wire                        s_axi_wready,   // slave: готов принять данные

    // --- Канал ответа на запись (B) ---
    output reg  [1:0]                  s_axi_bresp,    // код ответа (00 = OKAY)
    output reg                         s_axi_bvalid,   // slave: ответ валиден
    input  wire                        s_axi_bready,   // мастер: готов принять ответ

    // --- Канал адреса чтения (AR) ---
    input  wire [ADDR_WIDTH-1:0]       s_axi_araddr,   // начальный адрес чтения
    input  wire [7:0]                  s_axi_arlen,    // длина пакета минус 1
    input  wire [2:0]                  s_axi_arsize,   // размер слова (не используется)
    input  wire [1:0]                  s_axi_arburst,  // тип пакета (не используется)
    input  wire                        s_axi_arvalid,  // мастер: адрес валиден
    output wire                        s_axi_arready,  // slave: готов принять адрес

    // --- Канал данных чтения (R) ---
    output reg  [DATA_WIDTH-1:0]       s_axi_rdata,    // прочитанные данные
    output reg                         s_axi_rlast,    // последнее слово пакета
    output reg  [1:0]                  s_axi_rresp,    // код ответа (00 = OKAY)
    output reg                         s_axi_rvalid,   // slave: данные валидны
    input  wire                        s_axi_rready    // мастер: готов принять данные
);

    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];   // сама память: 256 слов x 32 бита

    // ======================== ЗАПИСЬ ========================
    localparam WRIDLE = 2'd0, WRDATA = 2'd1, WRRESP = 2'd2;  // состояния: ожидание / данные / ответ
    reg [1:0] wstate;                           // текущее состояние записи
    reg [ADDR_WIDTH-1:0] waddr_cur;             // текущий адрес внутри пакета
    reg [7:0] wburst_cnt;                       // сколько слов осталось после текущего

    assign s_axi_awready = (wstate == WRIDLE);  // адрес принимаем только в ожидании
    assign s_axi_wready  = (wstate == WRDATA);  // данные принимаем только в фазе данных

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin               // асинхронный сброс
            wstate <= WRIDLE;                   // перейти в ожидание
            s_axi_bvalid <= 1'b0;               // ответа нет
        end else case (wstate)
            WRIDLE: begin
                if (s_axi_awvalid) begin        // пришёл адрес (awready=1 -> handshake)
                    waddr_cur  <= s_axi_awaddr; // запомнить стартовый адрес
                    wburst_cnt <= s_axi_awlen;  // запомнить длину пакета
                    wstate     <= WRDATA;       // перейти к приёму данных
                end
            end
            WRDATA: begin
                if (s_axi_wvalid && s_axi_wready) begin              // handshake по данным
                    mem[waddr_cur[ADDR_WIDTH-1:2]] <= s_axi_wdata;   // запись слова (байтовый адрес -> индекс слова)
                    waddr_cur <= waddr_cur + 4;                      // следующий адрес (+4 байта, режим INCR)
                    if (wburst_cnt == 0) begin                       // это было последнее слово
                        wstate <= WRRESP;                            // перейти к отправке ответа
                    end else begin
                        wburst_cnt <= wburst_cnt - 1'b1;             // иначе уменьшить счётчик
                    end
                end
            end
            WRRESP: begin
                s_axi_bvalid <= 1'b1;           // выставить ответ
                s_axi_bresp  <= 2'b00;          // код OKAY
                if (s_axi_bvalid && s_axi_bready) begin  // мастер забрал ответ
                    s_axi_bvalid <= 1'b0;       // снять bvalid (перекрывает присваивание выше)
                    wstate <= WRIDLE;           // вернуться в ожидание
                end
            end
        endcase
    end

    // ======================== ЧТЕНИЕ ========================
    localparam RDIDLE = 2'd0, RDDATA = 2'd1;    // состояния: ожидание / выдача данных
    reg [1:0] rstate;                           // текущее состояние чтения
    reg [ADDR_WIDTH-1:0] raddr_cur;             // текущий адрес чтения
    reg [7:0] rburst_cnt;                       // сколько слов осталось после текущего

    assign s_axi_arready = (rstate == RDIDLE);  // адрес принимаем только в ожидании

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin               // асинхронный сброс
            rstate <= RDIDLE;                   // перейти в ожидание
            s_axi_rvalid <= 1'b0;               // данных нет
        end else case (rstate)
            RDIDLE: begin
                s_axi_rvalid <= 1'b0;           // в ожидании данные не выдаются
                if (s_axi_arvalid) begin        // пришёл адрес чтения (arready=1 -> handshake)
                    raddr_cur  <= s_axi_araddr; // запомнить стартовый адрес
                    rburst_cnt <= s_axi_arlen;  // запомнить длину пакета
                    rstate     <= RDDATA;       // перейти к выдаче данных
                end
            end
            RDDATA: begin
                if (!s_axi_rvalid || (s_axi_rvalid && s_axi_rready)) begin  // выход пуст или мастер забрал слово
                    s_axi_rdata  <= mem[raddr_cur[ADDR_WIDTH-1:2]];         // загрузить слово из памяти
                    s_axi_rresp  <= 2'b00;                                  // код OKAY
                    s_axi_rvalid <= 1'b1;                                   // данные валидны
                    s_axi_rlast  <= (rburst_cnt == 0);                      // пометка последнего слова
                    if (rburst_cnt != 0) begin                              // в пакете ещё есть слова
                        raddr_cur  <= raddr_cur + 4;                        // следующий адрес (+4 байта)
                        rburst_cnt <= rburst_cnt - 1'b1;                    // уменьшить счётчик
                    end else if (s_axi_rvalid && s_axi_rready) begin        // последнее слово принято
                        rstate <= RDIDLE;                                   // вернуться в ожидание
                    end
                end
            end
        endcase
    end

endmodule
