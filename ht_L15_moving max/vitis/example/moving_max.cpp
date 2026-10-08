#include <climits>
#include "moving_max.h"

/* Ковзний максимум: out_data[n] = найбільше з останніх WINDOW відліків,
   разом із поточним відліком n.
   Допишіть місця, позначені TODO. */
void moving_max(int in_data[N_SAMPLES], int out_data[N_SAMPLES]) {
    int window[WINDOW];      /* тут зберігаються останні WINDOW відліків */

INIT_LOOP:
    for (int k = 0; k < WINDOW; k++) {
        /* TODO 1: запишіть у window[k] найменше можливе значення типу int
                   (воно називається INT_MIN) */
    }

MAIN_LOOP:
    for (int n = 0; n < N_SAMPLES; n++) {
        /* TODO 2: зсуньте вміст window на одну позицію:
                   window[k] отримує значення window[k-1],
                   для k від WINDOW-1 до 1 (по спаданню) */

        /* TODO 3: покладіть новий відлік in_data[n] у window[0].
                   in_data[n] читається ТІЛЬКИ тут і ТІЛЬКИ один раз */

        /* TODO 4: знайдіть найбільше значення серед усіх window[0..WINDOW-1]
                   і запишіть його в out_data[n] */
        out_data[n] = 0;     
    }
}
