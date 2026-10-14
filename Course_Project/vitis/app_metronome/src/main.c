// main.c -- керування IP-модулем метронома axi_metronome з MicroBlaze
//
// Послідовність (за завданням, тема 5):
//   1. записуємо BPM = 120 і читаємо його назад;
//   2. записуємо ENABLE = 1 -- метроном починає видавати імпульси tick;
//   3. чекаємо простим циклом затримки;
//   4. читаємо TICKS -- скільки імпульсів видано;
//   5. змінюємо BPM на 240 і знову чекаємо, щоб на діаграмі було видно новий темп;
//   6. записуємо ENABLE = 0 -- імпульси припиняються;
//   7. читаємо TICKS ще раз: після вимкнення значення зберігається.
//
// Регістри метронома (зміщення від базової адреси):
//   0x00  BPM     запис/читання  темп, 30..240 (поза діапазоном обмежується модулем)
//   0x04  ENABLE  запис/читання  розряд [0]: 1 працює, 0 стоїть
//   0x08  TICKS   читання        кількість імпульсів від моменту ввімкнення
//
// Драйвер для власного IP не потрібен: звертаємося до регістрів напряму
// через Xil_Out32 / Xil_In32. Кожен виклик -- одна транзакція AXI4-Lite.
//
// Затримки розраховані на симуляцію з CLK_HZ = 1000 у налаштуваннях IP:
// при BPM = 120 період -- 500 тактів aclk (5 мкс при 100 МГц).

#include "xparameters.h"
#include "xil_io.h"
#include "xil_types.h"

// Базова адреса з Address Editor (0x0001_0000), Vitis бере її з XSA
#define METRONOME_BASEADDR  XPAR_AXI_METRONOME_0_BASEADDR

// ---- Зміщення регістрів ----
#define REG_BPM             0x00
#define REG_ENABLE          0x04
#define REG_TICKS           0x08

// ---- Параметри сценарію ----
#define BPM_START           120u                        // початковий темп
#define BPM_CHANGED         240u                        // темп після зміни
#define DELAY_LOOPS         200u                        // ітерацій циклу затримки, приблизно 4-5 періодів при BPM = 120

// Результати -- глобальні змінні, щоб їх було видно в налагоджувачі
volatile u32 bpm_read      = 0;                         // BPM, прочитаний після запису
volatile u32 ticks_running = 0;                         // TICKS під час роботи
volatile u32 ticks_stopped = 0;                         // TICKS після вимкнення
volatile u32 done          = 0;                         // 1 -- програма дійшла до кінця

// Простий цикл затримки; volatile не дає компілятору його викинути
static void delay(u32 loops) {
    volatile u32 i;
    for (i = 0; i < loops; i++)
        ;
}

static void metronome_write(u32 offset, u32 value) {
    Xil_Out32(METRONOME_BASEADDR + offset, value);
}

static u32 metronome_read(u32 offset) {
    return Xil_In32(METRONOME_BASEADDR + offset);
}

int main(void) {
    // 1. Темп 120 і перевірка читанням
    metronome_write(REG_BPM, BPM_START);
    bpm_read = metronome_read(REG_BPM);

    // 2. Увімкнення: лічильник TICKS обнуляється, відлік періоду починається спочатку
    metronome_write(REG_ENABLE, 1u);

    // 3. Чекаємо кілька імпульсів
    delay(DELAY_LOOPS);

    // 4. Скільки імпульсів видано
    ticks_running = metronome_read(REG_TICKS);

    // 5. Зміна темпу: діє з наступного проміжку (після найближчого tick)
    metronome_write(REG_BPM, BPM_CHANGED);
    delay(DELAY_LOOPS);

    // 6. Вимкнення: імпульси припиняються, внутрішній лічильник тримається в нулі
    metronome_write(REG_ENABLE, 0u);

    // 7. TICKS після вимкнення зберігає значення
    ticks_stopped = metronome_read(REG_TICKS);

    done = 1;
    while (1)
        ;

    return 0;
}
