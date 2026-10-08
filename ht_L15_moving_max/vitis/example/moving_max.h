#ifndef MOVING_MAX_H
#define MOVING_MAX_H

#define N_SAMPLES 64   /* сколько отсчётов обрабатывает один вызов */
#define WINDOW    8    /* размер окна: сколько последних отсчётов учитываем */

void moving_max(int in_data[N_SAMPLES], int out_data[N_SAMPLES]);

#endif
