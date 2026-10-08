#include <stdio.h>
#include <limits.h>
#include "moving_max.h"

#define N_VECTORS 6    /* количество входных векторов (по заданию не меньше пяти) */

/* Эталон: прямой перебор по правилу из задания.
   ref_data[n] = наибольшее из in_data[n-(WINDOW-1)] ... in_data[n];
   если n < WINDOW-1, то из in_data[0] ... in_data[n]. */
static void moving_max_ref(const int in_data[N_SAMPLES], int ref_data[N_SAMPLES]) {
    for (int n = 0; n < N_SAMPLES; n++) {
        int first = n - (WINDOW - 1);
        if (first < 0) {
            first = 0;
        }

        int max_val = in_data[first];
        for (int k = first + 1; k <= n; k++) {
            if (in_data[k] > max_val) {
                max_val = in_data[k];
            }
        }
        ref_data[n] = max_val;
    }
}

/* Заполнение входного вектора с номером vec */
static void fill_vector(int vec, int data[N_SAMPLES]) {
    unsigned int lfsr = 0x12345678u;   /* начальное состояние генератора псевдослучайных чисел */

    for (int n = 0; n < N_SAMPLES; n++) {
        switch (vec) {
        case 0:  /* возрастающая последовательность: максимум всегда текущий отсчёт */
            data[n] = n * 3 - 50;
            break;
        case 1:  /* убывающая последовательность: максимум всегда самый старый в окне */
            data[n] = 1000 - n * 7;
            break;
        case 2:  /* константа: все отсчёты одинаковые */
            data[n] = -5;
            break;
        case 3:  /* одиночные импульсы: видно, как максимум держится ровно WINDOW отсчётов */
            data[n] = (n == 0 || n == 20 || n == 27 || n == N_SAMPLES - 1) ? 100 + n : 0;
            break;
        case 4:  /* границы типа int: INT_MIN на входе не должен путаться с "пустой" ячейкой */
            if (n % 11 == 3) {
                data[n] = INT_MAX;
            } else if (n % 5 == 0) {
                data[n] = INT_MIN;
            } else {
                data[n] = -n;
            }
            break;
        default: /* псевдослучайные числа обоих знаков */
            lfsr = lfsr * 1664525u + 1013904223u;
            data[n] = (int)(lfsr >> 8) % 2001 - 1000;
            break;
        }
    }
}

int main()
{
    int in_data[N_SAMPLES];
    int out_data[N_SAMPLES];
    int ref_data[N_SAMPLES];
    int errors = 0;

    for (int vec = 0; vec < N_VECTORS; vec++) {
        int vec_errors = 0;

        fill_vector(vec, in_data);
        moving_max_ref(in_data, ref_data);
        moving_max(in_data, out_data);

        for (int n = 0; n < N_SAMPLES; n++) {
            if (out_data[n] != ref_data[n]) {
                printf("  vector %d, n = %2d: in = %d, out = %d, expected = %d\n",
                       vec, n, in_data[n], out_data[n], ref_data[n]);
                vec_errors++;
            }
        }

        printf("Vector %d: %s (%d mismatches)\n",
               vec, vec_errors == 0 ? "OK" : "FAIL", vec_errors);
        errors += vec_errors;
    }

    if (errors != 0) {
        printf("TEST FAILED: %d mismatches\n", errors);
        return 1;
    }

    printf("TEST PASSED: %d vectors, %d samples each\n", N_VECTORS, N_SAMPLES);
    return 0;
}
