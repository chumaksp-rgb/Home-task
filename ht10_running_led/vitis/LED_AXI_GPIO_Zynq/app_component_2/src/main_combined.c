// main.c -- "бігуча доріжка": один запалений LED рухається по колу
// LED0 -> LED1 -> LED2 -> LED3 -> LED0 -> ...
// Темп задає апаратний AXI Timer в режимі auto-reload: програма лише
// чекає прапорець спрацювання таймера (TINT), програмної затримки немає.
// Переривання таймера в block design не підключене, тому прапорець
// опитується (polling).

#include "xparameters.h"
#include "xgpio.h"
#include "xtmrctr.h"

#define LED_BASEADDR    XPAR_AXI_GPIO_0_BASEADDR
#define TIMER_BASEADDR  XPAR_AXI_TIMER_0_BASEADDR
#define TIMER_CLK_HZ    XPAR_AXI_TIMER_0_CLOCK_FREQUENCY   // 50 МГц

#define LED_COUNT       4
#define STEP_MS         250                                // крок доріжки

#define TIMER_NUM       0                                  // використовуємо Timer 0
// У режимі auto-reload період = (TLR + 2) тактів
#define TIMER_RELOAD    ((TIMER_CLK_HZ / 1000) * STEP_MS - 2)

XGpio   led_gpio;
XTmrCtr timer;

// Скидання прапорця TINT: біт скидається записом 1
static void timer_clear_flag(void) {
    u32 csr = XTmrCtr_ReadReg(TIMER_BASEADDR, TIMER_NUM, XTC_TCSR_OFFSET);
    XTmrCtr_WriteReg(TIMER_BASEADDR, TIMER_NUM, XTC_TCSR_OFFSET,
                     csr | XTC_CSR_INT_OCCURED_MASK);
}

int main() {
    XGpio_Config *cfg_ptr = XGpio_LookupConfig(LED_BASEADDR);
    XGpio_CfgInitialize(&led_gpio, cfg_ptr, cfg_ptr->BaseAddress);
    XGpio_SetDataDirection(&led_gpio, 1, 0x0); // вихід

    XTmrCtr_Initialize(&timer, TIMER_BASEADDR);
    // Лічба вниз від TIMER_RELOAD до 0, потім автоматичне перезавантаження
    XTmrCtr_SetOptions(&timer, TIMER_NUM,
                       XTC_DOWN_COUNT_OPTION | XTC_AUTO_RELOAD_OPTION);
    XTmrCtr_SetResetValue(&timer, TIMER_NUM, TIMER_RELOAD);
    XTmrCtr_Start(&timer, TIMER_NUM);

    u32 pos = 0;
    XGpio_DiscreteWrite(&led_gpio, 1, 1u << pos);

    while (1) {
        if (XTmrCtr_IsExpired(&timer, TIMER_NUM)) {
            timer_clear_flag();
            pos = (pos + 1) % LED_COUNT;
            XGpio_DiscreteWrite(&led_gpio, 1, 1u << pos);
        }
    }

    return 0;
}
