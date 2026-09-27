// main.c -- "бігуча доріжка": один запалений LED рухається по колу
// LED0 -> LED1 -> LED2 -> LED3 -> LED0 -> ...
//
// Керування:
//   BTN3 -- швидше          BTN1 -- стоп
//   BTN2 -- повільніше      BTN0 -- продовжити рух
//   SW0  -- напрямок (0: вперед LED0->LED3, 1: назад LED3->LED0)
//
// Уся часова логіка -- на апаратному AXI Timer (режим auto-reload):
//   Timer 0 -- крок доріжки (період змінюється кнопками),
//   Timer 1 -- такт 10 мс для опитування кнопок (антидребезг).
// Переривання таймера в block design не підключене, тому програма
// опитує прапорці спрацювання (TINT) таймерів. Програмних затримок немає.

#include "xparameters.h"
#include "xgpio.h"
#include "xtmrctr.h"

#define LED_BASEADDR    XPAR_AXI_GPIO_0_BASEADDR
#define BTN_BASEADDR    XPAR_AXI_GPIO_1_BASEADDR
#define SW_BASEADDR     XPAR_AXI_GPIO_2_BASEADDR
#define TIMER_BASEADDR  XPAR_AXI_TIMER_0_BASEADDR
#define TIMER_CLK_HZ    XPAR_AXI_TIMER_0_CLOCK_FREQUENCY   // 50 МГц

#define LED_COUNT       4

#define STEP_TIMER      0                                  // крок доріжки
#define BTN_TIMER       1                                  // опитування кнопок
#define BTN_POLL_MS     10

#define BTN_RESUME      (1u << 0)
#define BTN_STOP        (1u << 1)
#define BTN_SLOWER      (1u << 2)
#define BTN_FASTER      (1u << 3)
#define SW_DIRECTION    (1u << 0)

// У режимі auto-reload період = (TLR + 2) тактів
#define MS_TO_RELOAD(ms)  ((TIMER_CLK_HZ / 1000) * (ms) - 2)

// Доступні періоди кроку, від найповільнішого до найшвидшого
static const u32 step_ms_table[] = { 1000, 700, 500, 350, 250, 175, 125, 90, 60 };
#define SPEED_LEVELS    (sizeof(step_ms_table) / sizeof(step_ms_table[0]))
#define SPEED_DEFAULT   4                                  // 250 мс

XGpio   led_gpio, btn_gpio, sw_gpio;
XTmrCtr timer;

// Скидання прапорця TINT: біт скидається записом 1
static void timer_clear_flag(u8 tmr) {
    u32 csr = XTmrCtr_ReadReg(TIMER_BASEADDR, tmr, XTC_TCSR_OFFSET);
    XTmrCtr_WriteReg(TIMER_BASEADDR, tmr, XTC_TCSR_OFFSET,
                     csr | XTC_CSR_INT_OCCURED_MASK);
}

// Перевірка й скидання прапорця за один виклик
static int timer_expired(u8 tmr) {
    if (!XTmrCtr_IsExpired(&timer, tmr))
        return 0;
    timer_clear_flag(tmr);
    return 1;
}

// Лічба вниз від reload до 0, потім автоматичне перезавантаження
static void timer_setup(u8 tmr, u32 reload) {
    XTmrCtr_SetOptions(&timer, tmr,
                       XTC_DOWN_COUNT_OPTION | XTC_AUTO_RELOAD_OPTION);
    XTmrCtr_SetResetValue(&timer, tmr, reload);
}

// Новий період кроку діє одразу: Start перезавантажує лічильник з TLR
static void step_timer_restart(u32 speed) {
    XTmrCtr_Stop(&timer, STEP_TIMER);
    XTmrCtr_SetResetValue(&timer, STEP_TIMER, MS_TO_RELOAD(step_ms_table[speed]));
    timer_clear_flag(STEP_TIMER);
    XTmrCtr_Start(&timer, STEP_TIMER);
}

int main() {
    XGpio_Config *cfg_ptr;

    cfg_ptr = XGpio_LookupConfig(LED_BASEADDR);
    XGpio_CfgInitialize(&led_gpio, cfg_ptr, cfg_ptr->BaseAddress);

    cfg_ptr = XGpio_LookupConfig(BTN_BASEADDR);
    XGpio_CfgInitialize(&btn_gpio, cfg_ptr, cfg_ptr->BaseAddress);

    cfg_ptr = XGpio_LookupConfig(SW_BASEADDR);
    XGpio_CfgInitialize(&sw_gpio, cfg_ptr, cfg_ptr->BaseAddress);

    XGpio_SetDataDirection(&led_gpio, 1, 0x0); // вихід
    XGpio_SetDataDirection(&btn_gpio, 1, 0xF); // вхід
    XGpio_SetDataDirection(&sw_gpio,  1, 0x3); // вхід

    XTmrCtr_Initialize(&timer, TIMER_BASEADDR);

    u32 speed   = SPEED_DEFAULT;
    int running = 1;

    timer_setup(STEP_TIMER, MS_TO_RELOAD(step_ms_table[speed]));
    timer_setup(BTN_TIMER,  MS_TO_RELOAD(BTN_POLL_MS));
    XTmrCtr_Start(&timer, STEP_TIMER);
    XTmrCtr_Start(&timer, BTN_TIMER);

    u32 pos = 0;
    XGpio_DiscreteWrite(&led_gpio, 1, 1u << pos);

    // Антидребезг: стан кнопки приймається, коли два послідовні
    // відліки (з інтервалом 10 мс) однакові
    u32 btn_prev_sample = 0, btn_stable = 0;

    while (1) {
        if (timer_expired(BTN_TIMER)) {
            u32 sample = XGpio_DiscreteRead(&btn_gpio, 1) & 0xF;
            u32 same = ~(sample ^ btn_prev_sample);   // біти, що не змінились
            u32 new_stable = (btn_stable & ~same) | (sample & same);
            u32 pressed = new_stable & ~btn_stable;   // фронт натискання
            btn_prev_sample = sample;
            btn_stable = new_stable;

            if ((pressed & BTN_FASTER) && speed < SPEED_LEVELS - 1) {
                speed++;
                if (running)
                    step_timer_restart(speed);
            }
            if ((pressed & BTN_SLOWER) && speed > 0) {
                speed--;
                if (running)
                    step_timer_restart(speed);
            }
            if ((pressed & BTN_STOP) && running) {
                XTmrCtr_Stop(&timer, STEP_TIMER);
                running = 0;
            }
            if ((pressed & BTN_RESUME) && !running) {
                step_timer_restart(speed);
                running = 1;
            }
        }

        if (running && timer_expired(STEP_TIMER)) {
            if (XGpio_DiscreteRead(&sw_gpio, 1) & SW_DIRECTION)
                pos = (pos + LED_COUNT - 1) % LED_COUNT;  // назад
            else
                pos = (pos + 1) % LED_COUNT;              // вперед
            XGpio_DiscreteWrite(&led_gpio, 1, 1u << pos);
        }
    }

    return 0;
}
