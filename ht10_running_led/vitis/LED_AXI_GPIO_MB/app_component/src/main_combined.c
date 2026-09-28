// main.c -- проста версія: кнопки напряму на світлодіоди.
// Перемикачі фізично підключені й ініціалізовані, але в логіці
// не використовуються -- залишені на майбутнє, якщо захочете
// розширити.

#include "xparameters.h"
#include "xil_io.h"
#include "xgpio.h"

// ---- ПЕРЕВІРИТИ реальні назви у вашому xparameters.h ----
#define LED_BASEADDR   XPAR_AXI_GPIO_0_BASEADDR
#define BTN_BASEADDR   XPAR_AXI_GPIO_1_BASEADDR
#define SW_BASEADDR    XPAR_AXI_GPIO_2_BASEADDR

XGpio led_gpio, btn_gpio, sw_gpio;

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
    XGpio_SetDataDirection(&sw_gpio,  1, 0x3); // вхід (не використовується в логіці)

    while (1) {
        u32 btn_value = XGpio_DiscreteRead(&btn_gpio, 1);

        // Пряме дзеркалення: яка кнопка натиснута -- той LED світиться
        XGpio_DiscreteWrite(&led_gpio, 1, btn_value & 0xF);
    }

    return 0;
}