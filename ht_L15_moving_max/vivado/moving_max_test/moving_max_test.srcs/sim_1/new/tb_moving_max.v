`timescale 1ns / 1ps

// Тестбенч для IP скользящего максимума (moving_max_0, сгенерирован в Vitis HLS).
//
// Массивы функции moving_max(int in_data[64], int out_data[64]) в железе стали
// портами памяти (ap_memory), поэтому тестбенч моделирует две памяти:
//   in_mem  - блок сам выставляет адрес и читает данные (задержка чтения 1 такт);
//   out_mem - блок сам выставляет адрес, данные и строб записи.
// Запуск и завершение - по протоколу ap_ctrl_hs (ap_start / ap_done / ap_idle / ap_ready).
//
// Проверка: те же шесть входных векторов, что и в C-тестбенче, результат
// сравнивается с эталоном (прямой перебор по правилу из задания).
// Сообщения $display на английском: консоль XSim портит кириллицу.

module tb_moving_max;

    localparam N_SAMPLES  = 64;     // сколько отсчётов обрабатывает один запуск
    localparam WINDOW     = 8;      // размер окна
    localparam N_VECTORS  = 6;      // количество входных векторов
    localparam CLK_PERIOD = 10;     // период тактового сигнала, нс (100 МГц)
    localparam TIMEOUT    = 1000;   // предел ожидания ap_done, тактов

    // ---------------- сигналы блока ----------------
    reg         ap_clk   = 1'b0;
    reg         ap_rst   = 1'b1;    // сброс синхронный, активный уровень высокий
    reg         ap_start = 1'b0;
    wire        ap_done;
    wire        ap_idle;
    wire        ap_ready;

    wire [5:0]  in_data_address0;
    wire        in_data_ce0;
    reg  [31:0] in_data_q0 = 32'd0;

    wire [5:0]  out_data_address0;
    wire        out_data_ce0;
    wire        out_data_we0;
    wire [31:0] out_data_d0;

    // ---------------- памяти и эталон ----------------
    integer in_mem  [0:N_SAMPLES-1];    // входной массив
    integer out_mem [0:N_SAMPLES-1];    // выходной массив (пишет блок)
    integer ref_mem [0:N_SAMPLES-1];    // эталонный результат

    integer wr_count;                   // сколько записей сделал блок за запуск

    integer vec;
    integer n;
    integer cycles;
    integer vec_errors;
    integer errors;

    // ---------------- проверяемый блок ----------------
    moving_max_0 dut (
        .ap_clk            (ap_clk),
        .ap_rst            (ap_rst),
        .ap_start          (ap_start),
        .ap_done           (ap_done),
        .ap_idle           (ap_idle),
        .ap_ready          (ap_ready),
        .in_data_address0  (in_data_address0),
        .in_data_ce0       (in_data_ce0),
        .in_data_q0        (in_data_q0),
        .out_data_address0 (out_data_address0),
        .out_data_ce0      (out_data_ce0),
        .out_data_we0      (out_data_we0),
        .out_data_d0       (out_data_d0)
    );

    // ---------------- тактовый сигнал ----------------
    always #(CLK_PERIOD / 2) ap_clk = ~ap_clk;

    // ---------------- входная память ----------------
    // Синхронное чтение: адрес берётся по фронту, данные появляются на следующем такте
    always @(posedge ap_clk) begin
        if (in_data_ce0) begin
            in_data_q0 <= in_mem[in_data_address0];
        end
    end

    // ---------------- выходная память ----------------
    always @(posedge ap_clk) begin
        if (out_data_ce0 && out_data_we0) begin
            out_mem[out_data_address0] = out_data_d0;
            wr_count = wr_count + 1;
        end
    end

    // ---------------- заполнение входного вектора с номером v ----------------
    task fill_vector;
        input integer v;
        integer    i;
        reg [31:0] lfsr;                // генератор псевдослучайных чисел, как в C-тестбенче
        begin
            lfsr = 32'h12345678;
            for (i = 0; i < N_SAMPLES; i = i + 1) begin
                case (v)
                    0:  // возрастающая последовательность: максимум всегда текущий отсчёт
                        in_mem[i] = i * 3 - 50;
                    1:  // убывающая последовательность: максимум всегда самый старый в окне
                        in_mem[i] = 1000 - i * 7;
                    2:  // константа: все отсчёты одинаковые
                        in_mem[i] = -5;
                    3:  // одиночные импульсы: максимум держится ровно WINDOW отсчётов
                        in_mem[i] = (i == 0 || i == 20 || i == 27 || i == N_SAMPLES - 1) ? 100 + i : 0;
                    4:  // границы типа int: INT_MAX и INT_MIN на входе
                        if (i % 11 == 3)
                            in_mem[i] = 32'h7FFFFFFF;
                        else if (i % 5 == 0)
                            in_mem[i] = 32'h80000000;
                        else
                            in_mem[i] = -i;
                    default: begin  // псевдослучайные числа обоих знаков
                        lfsr = lfsr * 32'd1664525 + 32'd1013904223;
                        in_mem[i] = (lfsr >> 8) % 2001;
                        in_mem[i] = in_mem[i] - 1000;
                    end
                endcase
            end
        end
    endtask

    // ---------------- эталон: прямой перебор ----------------
    // ref_mem[i] = наибольшее из in_mem[i-(WINDOW-1)] ... in_mem[i];
    // если i < WINDOW-1, то из in_mem[0] ... in_mem[i]
    task calc_reference;
        integer i;
        integer k;
        integer first;
        integer max_val;
        begin
            for (i = 0; i < N_SAMPLES; i = i + 1) begin
                first = i - (WINDOW - 1);
                if (first < 0)
                    first = 0;

                max_val = in_mem[first];
                for (k = first + 1; k <= i; k = k + 1) begin
                    if (in_mem[k] > max_val)
                        max_val = in_mem[k];
                end
                ref_mem[i] = max_val;
            end
        end
    endtask

    // ---------------- один запуск блока ----------------
    // ap_start держится до ap_ready; cycles - латентность от приёма ap_start до ap_done
    task run_block;
        begin
            cycles = 0;
            @(posedge ap_clk);
            ap_start <= 1'b1;
            @(posedge ap_clk);              // на этом фронте блок видит ap_start = 1

            while (!ap_done && cycles < TIMEOUT) begin
                cycles = cycles + 1;
                @(posedge ap_clk);
            end
            ap_start <= 1'b0;               // ap_ready приходит вместе с ap_done

            @(posedge ap_clk);              // пауза между запусками
        end
    endtask

    // ---------------- основной сценарий ----------------
    initial begin
        errors = 0;

        // сброс на несколько тактов
        repeat (5) @(posedge ap_clk);
        ap_rst <= 1'b0;
        repeat (2) @(posedge ap_clk);

        if (!ap_idle) begin
            $display("ERROR: ap_idle is not set after reset");
            errors = errors + 1;
        end

        for (vec = 0; vec < N_VECTORS; vec = vec + 1) begin
            vec_errors = 0;
            wr_count   = 0;
            for (n = 0; n < N_SAMPLES; n = n + 1)
                out_mem[n] = 32'hXXXXXXXX;      // чтобы пропущенная запись была видна

            fill_vector(vec);
            calc_reference;
            run_block;

            if (cycles >= TIMEOUT) begin
                $display("  vector %0d: timeout, ap_done did not arrive", vec);
                vec_errors = vec_errors + 1;
            end

            // сравнение с эталоном
            for (n = 0; n < N_SAMPLES; n = n + 1) begin
                if (out_mem[n] !== ref_mem[n]) begin
                    $display("  vector %0d, n = %0d: in = %0d, out = %0d, expected = %0d",
                             vec, n, in_mem[n], out_mem[n], ref_mem[n]);
                    vec_errors = vec_errors + 1;
                end
            end

            if (wr_count != N_SAMPLES) begin
                $display("  vector %0d: %0d writes to out_data, expected %0d", vec, wr_count, N_SAMPLES);
                vec_errors = vec_errors + 1;
            end

            $display("Vector %0d: %0s (%0d mismatches), latency = %0d cycles",
                     vec, (vec_errors == 0) ? "OK" : "FAIL", vec_errors, cycles);
            errors = errors + vec_errors;
        end

        if (errors != 0)
            $display("TEST FAILED: %0d mismatches", errors);
        else
            $display("TEST PASSED: %0d vectors, %0d samples each", N_VECTORS, N_SAMPLES);

        $finish;
    end

endmodule
