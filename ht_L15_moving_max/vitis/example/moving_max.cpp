#include <climits>
#include "moving_max.h"

/* Скользящий максимум: out_data[n] = наибольшее из последних WINDOW отсчётов,
   вместе с текущим отсчётом n.
   Для первых WINDOW-1 отсчётов максимум берётся только из имеющихся:
   остальные ячейки окна содержат INT_MIN и на результат не влияют. */
void moving_max(int in_data[N_SAMPLES], int out_data[N_SAMPLES]) {
    int window[WINDOW];      /* здесь хранятся последние WINDOW отсчётов */

INIT_LOOP:
    for (int k = 0; k < WINDOW; k++) {
        window[k] = INT_MIN; /* "пустая" ячейка: меньше любого отсчёта */
    }

MAIN_LOOP:
    for (int n = 0; n < N_SAMPLES; n++) {
        /* сдвиг окна на одну позицию: самый старый отсчёт выпадает */
        
        #pragma HLS PIPELINE II=1 // pipeline is on
        
SHIFT_LOOP:
        for (int k = WINDOW - 1; k > 0; k--) {
            window[k] = window[k - 1];
        }

        /* новый отсчёт; in_data[n] читается только здесь и только один раз */
        window[0] = in_data[n];

        /* поиск наибольшего значения в окне */
        int max_val = window[0];
MAX_LOOP:
        for (int k = 1; k < WINDOW; k++) {
            if (window[k] > max_val) {
                max_val = window[k];
            }
        }

        out_data[n] = max_val;
    }
}
