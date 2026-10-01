// main.c -- прийом кадру 320x200 через AXI DMA за натисканням кнопки (MicroBlaze)
//
// Послідовність:
//   1. чекаємо натискання кнопки (AXI GPIO, канал 1, біт 0);
//   2. готуємо DMA: адреса буфера = axi4_full_ram, довжина = 64000 байтів;
//   3. виставляємо start = 1 (AXI GPIO, канал 2, біт 0) -- frame_receiver
//      дочекається початку найближчого кадру й почне видавати слова в DMA;
//   4. чекаємо, поки DMA завершить запис (біт Idle), знімаємо start;
//   5. чекаємо відпускання кнопки -- і все спочатку.
//
// Драйвери XGpio / XAxiDma свідомо НЕ використовуються: локальної пам'яті
// MicroBlaze лише 16 КБ, а потрібно всього кілька регістрів. Переривання
// в block design не підключені, тому стан DMA опитується.

#include "xparameters.h"
#include "xil_io.h"
#include "xil_types.h"

#define GPIO_BASEADDR   XPAR_AXI_GPIO_0_BASEADDR
#define DMA_BASEADDR    XPAR_AXI_DMA_0_BASEADDR

// Власний IP не має драйвера, тож макроса в xparameters.h може не бути --
// тоді беремо адресу з Address Editor.
#ifdef XPAR_AXI4_FULL_RAM_0_BASEADDR
#define RAM_BASEADDR    XPAR_AXI4_FULL_RAM_0_BASEADDR
#else
#define RAM_BASEADDR    0x00010000u
#endif

#define FRAME_WIDTH     320
#define FRAME_HEIGHT    200
#define FRAME_BYTES     (FRAME_WIDTH * FRAME_HEIGHT)       // 64000 байтів = 16000 слів

// ---- Регістри AXI GPIO ----
#define GPIO_DATA       0x00                               // канал 1: кнопка (вхід)
#define GPIO_DATA2      0x08                               // канал 2: start (вихід)

#define BTN_MASK        (1u << 0)
#define START_MASK      (1u << 0)

// ---- Регістри AXI DMA, канал S2MM (потік -> пам'ять) ----
#define S2MM_DMACR      0x30                               // керування
#define S2MM_DMASR      0x34                               // стан
#define S2MM_DA         0x48                               // адреса буфера призначення
#define S2MM_LENGTH     0x58                               // довжина в байтах; запис сюди запускає прийом

#define DMACR_RS        (1u << 0)                          // Run/Stop
#define DMACR_RESET     (1u << 2)                          // програмне скидання, біт знімається сам
#define DMASR_HALTED    (1u << 0)
#define DMASR_IDLE      (1u << 1)                          // передачу завершено
#define DMASR_ERR_MASK  ((1u << 4) | (1u << 5) | (1u << 6))  // внутрішня помилка / SLVERR / DECERR

// Для спостереження у симуляції та в налагоджувачі
volatile u32 frames_done   = 0;                            // скільки кадрів прийнято
volatile u32 last_rx_bytes = 0;                            // скільки байтів DMA реально записав
volatile u32 dma_error     = 0;                            // DMASR на момент помилки (0 -- помилок не було)

static int button_pressed(void) {
    return (Xil_In32(GPIO_BASEADDR + GPIO_DATA) & BTN_MASK) != 0;
}

static void set_start(u32 on) {
    Xil_Out32(GPIO_BASEADDR + GPIO_DATA2, on ? START_MASK : 0);
}

// Скидання DMA і перехід у стан "працює"
static void dma_init(void) {
    Xil_Out32(DMA_BASEADDR + S2MM_DMACR, DMACR_RESET);
    while (Xil_In32(DMA_BASEADDR + S2MM_DMACR) & DMACR_RESET)
        ;
    Xil_Out32(DMA_BASEADDR + S2MM_DMACR, DMACR_RS);
    while (Xil_In32(DMA_BASEADDR + S2MM_DMASR) & DMASR_HALTED)
        ;
}

// Прийом одного кадру. Повертає 0 -- успіх, -1 -- помилка DMA.
static int receive_frame(void) {
    // Спершу озброюємо DMA, і лише потім даємо start: інакше перші слова
    // кадру чекали б у FIFO приймача, а він лише на 16 слів.
    Xil_Out32(DMA_BASEADDR + S2MM_DA, RAM_BASEADDR);
    Xil_Out32(DMA_BASEADDR + S2MM_LENGTH, FRAME_BYTES);
    set_start(1);

    u32 sr;
    do {
        sr = Xil_In32(DMA_BASEADDR + S2MM_DMASR);
    } while (!(sr & (DMASR_IDLE | DMASR_ERR_MASK)));

    set_start(0);                                          // наступний кадр -- лише після нового фронту

    if (sr & DMASR_ERR_MASK) {
        dma_error = sr;
        return -1;
    }

    last_rx_bytes = Xil_In32(DMA_BASEADDR + S2MM_LENGTH);  // після завершення тут фактична довжина
    frames_done++;
    return 0;
}

int main() {
    set_start(0);
    dma_init();

    while (1) {
        while (!button_pressed())                          // до натискання вхід кадру ігнорується
            ;

        if (receive_frame() != 0)
            dma_init();                                    // після помилки DMA зупиняється -- перезапуск

        while (button_pressed())                           // одне натискання -- один кадр
            ;
    }

    return 0;
}
