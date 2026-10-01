// axis_doubler.v
// Найпростіший можливий AXI4-Stream акселератор: множить кожне
// вхідне 16-бітне значення на 2. Правильно обробляє backpressure
// (TREADY) з обох боків -- жодних припущень "приймач завжди готовий".

module axis_doubler #(
    parameter DATA_WIDTH = 16                       // ширина слова потока
) (
    input  wire                        aclk,        // тактовый сигнал
    input  wire                        aresetn,     // сброс, активный низкий

    // ---- Slave side (вхід потоку) ----
    input  wire [DATA_WIDTH-1:0]       s_axis_tdata,   // входные данные
    input  wire                        s_axis_tvalid,  // источник: данные валидны
    output wire                        s_axis_tready,  // модуль: готов принять слово
    input  wire                        s_axis_tlast,   // последнее слово пакета

    // ---- Master side (вихід потоку) ----
    output reg  [DATA_WIDTH-1:0]       m_axis_tdata,   // выходные данные (вход x 2)
    output reg                         m_axis_tvalid,  // модуль: выходные данные валидны
    input  wire                        m_axis_tready,  // приёмник: готов забрать слово
    output reg                         m_axis_tlast    // последнее слово пакета (транслируется со входа)
);

    // Простий, однотактовий конвеєр: приймаємо слово, наступного
    // такту видаємо подвоєне значення. slave готовий приймати новий
    // вхід, лише коли master-вихід або порожній, або саме
    // "звільняється" цього такту (m_axis_tready==1).
    assign s_axis_tready = !m_axis_tvalid || m_axis_tready;  // готов, если выходной регистр пуст или приёмник забирает слово

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin                         // асинхронный сброс
            m_axis_tvalid <= 1'b0;                  // на выходе нет данных
            m_axis_tdata  <= 0;                     // обнулить данные
            m_axis_tlast  <= 1'b0;                  // обнулить признак конца пакета
        end else begin
            if (s_axis_tready && s_axis_tvalid) begin       // handshake на входе: слово принято
                m_axis_tdata  <= s_axis_tdata * 2;          // удвоить (старший бит теряется при переполнении)
                m_axis_tvalid <= 1'b1;                      // выставить результат на выход
                m_axis_tlast  <= s_axis_tlast;              // передать признак конца пакета дальше
            end else if (m_axis_tready) begin               // нового слова нет, а приёмник забрал текущее
                m_axis_tvalid <= 1'b0;                      // выход пуст
            end
        end
    end

endmodule
