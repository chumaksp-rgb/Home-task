`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: SERHII CHUMAK
//
// Testbench for the debounce filter.
//
// CLK_HZ/STABLE_MS are shrunk so COUNT_MAX = 5 clocks instead of 1_250_000.
// Same logic, instant simulation.
//
// Change: added bounce WHILE HELD and bounce ON RELEASE -- the realistic cases.
//         Time is now printed in ns via $timeformat.
//////////////////////////////////////////////////////////////////////////////////



//Общие условия
//Тактовый сигнал с периодом 10 нс, передние фронты на 5, 15, 25… нс. Параметры фильтра уменьшены для симуляции: CLK_HZ = 1000, STABLE_MS = 5, отсюда окно устойчивости COUNT_MAX = 5 тактов. На плате при 125 МГц и 10 мс это было бы 1 250 000 тактов, логика та же.
//Задержка фильтра - 8 тактов от изменения входа до появления значения на выходе. Складывается так: 2 такта синхронизатор (sync0 → sync1), 1 такт на захват кандидата со сбросом счётчика, 4 такта счёт до COUNT_MAX - 1, 1 такт на принятие и строб. Отсюда в тестбенче ожидания STABLE + 4 = 9 тактов - с запасом в один такт.
//Все проверки делаются через 1 нс после фронта (#1), чтобы читать уже обновлённые регистры. Счётчик strobes подсчитывает импульсы changed в отдельном блоке always и обнуляется после сброса, чтобы не учитывать переходные процессы.
//Сценарий 1 - дребезг при нажатии
//Проверка 1 · 156 нс · bounce shorter than window ignored
//На вход подаётся последовательность, имитирующая замыкание скачущего контакта: 5 на 2 такта, 0 на 1 такт, 5 на 2 такта, 0 на 1 такт. Ни один отрезок не дотягивает до окна в 5 тактов, при каждой смене значения счётчик устойчивости сбрасывается. Ожидается clean_out = 0 - выход не сдвинулся.
//Ловит главную возможную ошибку фильтра: отсутствие или слишком короткое окно устойчивости. Если фильтр пропускает всё, что продержалось хотя бы такт, эта проверка покажет 5 вместо 0.
//Сценарий 2 - устойчивое нажатие
//Проверка 2 · 246 нс · stable 5 accepted
//Вход держится на 5 девять тактов подряд. Через 8 тактов значение проходит фильтр. Ожидается clean_out = 5.
//Ловит обратную ошибку - фильтр, который не пропускает ничего: например, счётчик не доходит до порога из-за неверной разрядности или условие сравнения никогда не выполняется. Вместе с проверкой 1 задаёт обе границы: короткое отсекается, длинное проходит.
//Проверка 3 · 246 нс · exactly one strobe for one press
//Там же проверяется счётчик импульсов: ожидается strobes = 1.
//Самая важная проверка для связки с автоматом. Одно нажатие должно давать ровно один импульс changed длиной в один такт. Если бы changed держался уровнем, пока значение совпадает, автомат получил бы миллион переходов вместо одного. Проверка значения clean_out этого бы не заметила - только подсчёт импульсов.
//Сценарий 3 - удержание кнопки
//Проверка 4 · 346 нс · no extra strobes while held
//Вход продолжает держаться на 5 ещё десять тактов. Ожидается, что strobes остался равен 1.
//Ловит фильтр, который генерирует строб периодически - каждый раз, когда счётчик устойчивости доходит до порога. Защита от этого в коде - условие clean_out != candidate перед выдачей строба: если значение уже на выходе, повторно оно не принимается. Эта проверка подтверждает, что условие работает.
//Сценарий 3a - сбой контакта при удержании
//Проверка 5 · 456 нс · glitch while held ignored
//Пятёрка уже на выходе, кнопка удерживается. Вход на 2 такта проваливается в 0 и возвращается к 5 на девять тактов. Кандидат внутри фильтра успевает смениться на 0, но за 2 такта до порога не доходит; затем возвращается к 5, отсчёт начинается заново. Ожидается clean_out = 5.
//Имитирует дрогнувший палец или окисленный контакт. Ловит фильтр, который на кратковременный провал выдаёт на выход 0.
//Проверка 6 · 456 нс · no strobe from glitch while held
//Ожидается, что strobes по-прежнему равен 1.
//Даже если выход не изменился, важно, что не было и лишнего строба. Сценарий потенциально опасный: провал 5→0→5 мог бы дать два импульса - на уход в 0 и на возврат к 5. Для замка это превратило бы одно нажатие в три шага автомата.
//Сценарий 4 - отпускание с дребезгом
//Проверка 7 · 596 нс · bouncy release accepted
//При размыкании контакт скачет так же, как при замыкании. Подаётся 0 на 1 такт, 5 на 2 такта, 0 на 1 такт, 5 на 1 такт, затем 0 устойчиво на девять тактов. Ожидается clean_out = 0.
//Проверяет, что после всех скачков фильтр всё же признаёт отпускание. Возвраты к 5 в середине не дают строба: 5 уже на выходе, а условие clean_out != candidate не выполнится.
//Проверка 8 · 596 нс · bouncy release -> exactly one strobe
//Ожидается strobes = 2: один импульс был за нажатие в сценарии 2, ещё один - за отпускание. Ровно один за весь дребезжащий процесс размыкания.
//Значение 2 - задокументированное и ожидаемое поведение, а не ошибка. Фильтр сообщает о любом изменении, включая возврат к 0000. Отличать нажатие от отпускания - задача верхнего уровня: в lock_top строб пропускается к автомату только при digit_clean != 0.
//Сценарий 5 - следующая цифра
//Проверка 9 · 686 нс · next digit accepted
//Счётчик стробов обнуляется, на вход подаётся 3 на девять тактов. Ожидается clean_out = 3.
//Проверяет, что после полного цикла «нажатие - удержание - отпускание» фильтр не остался в каком-либо промежуточном состоянии и принимает новое значение так же, как первое.
//Проверка 10 · 686 нс · exactly one strobe for next digit
//Ожидается strobes = 1.
//Подтверждает, что поведение повторяемо: каждое новое нажатие даёт ровно один строб, независимо от предыстории.
//Проверка самого тестбенча
//Набор проверок был прогнан на намеренно испорченном фильтре - с убранным окном устойчивости, то есть принимающим любое значение, продержавшееся один такт. Результат: 5 проверок из 10 упали, включая оба сценария с дребезгом при удержании и при отпускании. Это подтверждает, что тестбенч действительно различает правильную и неправильную реализации, а не проходит при любой.


module tb_debounce;

    localparam int WIDTH     = 4;
    localparam int CLK_HZ    = 1000;
    localparam int STABLE_MS = 5;
    localparam int STABLE    = (CLK_HZ / 1000) * STABLE_MS;   // = 5 clocks

    logic             clk;
    logic             rst;
    logic [WIDTH-1:0] noisy_in;
    logic [WIDTH-1:0] clean_out;
    logic             changed;

    int errors  = 0;
    int strobes = 0;

    debounce #(
        .WIDTH     (WIDTH),
        .CLK_HZ    (CLK_HZ),
        .STABLE_MS (STABLE_MS)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .noisy_in  (noisy_in),
        .clean_out (clean_out),
        .changed   (changed)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // count strobes so we can prove there is exactly ONE per accepted value
    always @(posedge clk)
        if (changed) strobes++;

    task automatic check(input logic [WIDTH-1:0] expected, input string step_name);
        if (clean_out === expected)
            $display("[%t] PASS: %s  clean_out=%0d", $time, step_name, clean_out);
        else begin
            errors++;
            $display("[%t] FAIL: %s  expected %0d, got %0d",
                     $time, step_name, expected, clean_out);
        end
    endtask

    task automatic check_strobes(input int expected, input string step_name);
        if (strobes == expected)
            $display("[%t] PASS: %s  strobes=%0d", $time, step_name, strobes);
        else begin
            errors++;
            $display("[%t] FAIL: %s  expected %0d strobes, got %0d",
                     $time, step_name, expected, strobes);
        end
    endtask

    initial begin
        // units 1e-9 s, 0 decimals, suffix, min width
        $timeformat(-9, 0, " ns", 6);

        rst      = 1'b1;
        noisy_in = 4'd0;
        repeat (2) @(posedge clk);
        #1 rst = 1'b0;
        repeat (STABLE + 3) @(posedge clk);
        strobes = 0;                       // ignore anything during reset

        // --- 1. Short bounce, shorter than the stability window ---
        noisy_in = 4'd5; repeat (2) @(posedge clk);
        noisy_in = 4'd0; repeat (1) @(posedge clk);
        noisy_in = 4'd5; repeat (2) @(posedge clk);
        noisy_in = 4'd0; repeat (1) @(posedge clk);
        #1;
        check(4'd0, "bounce shorter than window ignored");

        // --- 2. Now hold 5 long enough: it must be accepted, exactly once ---
        noisy_in = 4'd5;
        repeat (STABLE + 4) @(posedge clk);
        #1;
        check(4'd5, "stable 5 accepted");
        check_strobes(1, "exactly one strobe for one press");

        // --- 3. Keep holding: no further strobes ---
        repeat (STABLE + 5) @(posedge clk);
        #1;
        check_strobes(1, "no extra strobes while held");

        // --- 3a. Glitch WHILE HELD: short drop to 0 and back to 5 ---
        // The finger slips for a moment. Output must stay 5, no strobe.
        noisy_in = 4'd0; repeat (2) @(posedge clk);
        noisy_in = 4'd5; repeat (STABLE + 4) @(posedge clk);
        #1;
        check(4'd5, "glitch while held ignored");
        check_strobes(1, "no strobe from glitch while held");

        // --- 4. Release WITH bounce: 5 -> 0 -> 5 -> 0 -> 5 -> 0 (stable) ---
        // Contacts bounce on opening too. Expect exactly ONE release strobe.
        noisy_in = 4'd0; repeat (1) @(posedge clk);
        noisy_in = 4'd5; repeat (2) @(posedge clk);
        noisy_in = 4'd0; repeat (1) @(posedge clk);
        noisy_in = 4'd5; repeat (1) @(posedge clk);
        noisy_in = 4'd0; repeat (STABLE + 4) @(posedge clk);
        #1;
        check(4'd0, "bouncy release accepted");
        check_strobes(2, "bouncy release -> exactly one strobe");

        // --- 5. Next digit ---
        strobes  = 0;
        noisy_in = 4'd3;
        repeat (STABLE + 4) @(posedge clk);
        #1;
        check(4'd3, "next digit accepted");
        check_strobes(1, "exactly one strobe for next digit");

        $display("[%t] Simulation finished", $time);
        if (errors == 0) $display("=== All checks passed ===");
        else             $display("=== FAILED: %0d error(s) ===", errors);

        #5;
        $finish;
    end

endmodule
