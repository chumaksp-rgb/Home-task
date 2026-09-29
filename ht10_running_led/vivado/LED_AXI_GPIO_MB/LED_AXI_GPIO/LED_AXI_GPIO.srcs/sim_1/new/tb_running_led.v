// tb_running_led.v
// Тестбенч для "бігучої доріжки" на MicroBlaze.
//
// ВАЖЛИВО: потрібен ELF, зібраний з -DTIME_SCALE=1000:
//   vivado/LED_AXI_GPIO_MB/sim_elf/app_component_sim.elf
// Прив'язати через Tools -> Associate ELF Files -> Simulation Sources.
// Бойовий ELF (реальний час) тут не годиться: один крок доріжки --
// 250 мс, тобто 25 млн тактів, симуляція нездійсненна.
//
// Зі стисненням у 1000 разів:
//   крок за замовчуванням  250 мс -> 250 мкс
//   найшвидший крок         60 мс ->  60 мкс
//   такт опитування кнопок  10 мс ->  10 мкс
//
// Кнопки: BTN0 продовжити, BTN1 стоп, BTN2 повільніше, BTN3 швидше.
// Антидребезг вимагає двох однакових відліків поспіль, тому натискання
// треба утримувати щонайменше два такти опитування (20 мкс).
//
// Рядки $display -- англійською: консоль XSim не показує кирилицю.

`timescale 1ns / 1ps

module tb_running_led;

    // ---- Такт sysclk 125 МГц ----
    reg sysclk = 1'b0;
    always #4 sysclk = ~sysclk;

    // ---- GPIO ----
    wire [3:0] btn_tri_io;
    wire [1:0] sw_tri_io;
    wire [3:0] led_tri_io;

    reg  [3:0] btn_drv = 4'b0000;
    reg  [1:0] sw_drv  = 2'b00;

    assign btn_tri_io = btn_drv;
    assign sw_tri_io  = sw_drv;

    design_1_wrapper dut (
        .sysclk     (sysclk),
        .btn_tri_io (btn_tri_io),
        .sw_tri_io  (sw_tri_io),
        .led_tri_io (led_tri_io)
    );

    // ---- Параметри ----
    localparam integer RES_NS       = 10;        // крок опитування в тестбенчі
    // Утримання кнопки. Антидребезг вимагає двох однакових відліків
    // і на натискання, і на відпускання, тобто мінімум 20 мкс на кожну
    // фазу. При 30 мкс одне натискання з чотирьох інколи губилося
    // через збіг фаз, тому запас збільшено до 50 мкс.
    localparam integer HOLD_NS      = 50_000;
    localparam integer BOOT_TIMEOUT = 500_000;   // запас на старт MicroBlaze
    localparam integer STEP_TIMEOUT = 2_000_000; // запас на один крок доріжки

    integer errors  = 0;
    integer elapsed = 0;
    reg [3:0] led_last = 4'bxxxx;

    // ---- Допоміжні функції ----
    // Коректний стан доріжки -- рівно один запалений світлодіод.
    // Перевіряти треба саме це, а не "не Z": одразу після t=0 буфер
    // IOBUF видає X, бо сигнал керування третім станом ще не визначений.
    // Саме на цьому попередня версія тестбенча хибно рапортувала
    // "boot done" у нульовий момент часу.
    function is_onehot(input [3:0] v);
        is_onehot = (v === 4'b0001) || (v === 4'b0010) ||
                    (v === 4'b0100) || (v === 4'b1000);
    endfunction

    function [3:0] rot_fwd(input [3:0] v);   // LED0 -> LED1 -> LED2 -> LED3
        rot_fwd = {v[2:0], v[3]};
    endfunction

    function [3:0] rot_bwd(input [3:0] v);
        rot_bwd = {v[0], v[3:1]};
    endfunction

    // ---- Чекати зміни стану світлодіодів ----
    task wait_change(input integer timeout_ns);
        integer waited;
        begin
            waited = 0;
            while (led_tri_io === led_last && waited < timeout_ns) begin
                #RES_NS;
                waited = waited + RES_NS;
            end
            elapsed  = waited;
            led_last = led_tri_io;
        end
    endtask

    // ---- Натиснути й відпустити кнопку ----
    // Увага: BTN2/BTN3 змінюють швидкість, а це викликає
    // step_timer_restart -- лічильник кроку перезапускається з нуля.
    // Тому під час серії натискань доріжка стоїть на місці.
    task press(input [3:0] mask, input [127:0] name);
        begin
            $display("[%0t] press %0s", $time, name);
            btn_drv = mask;
            #HOLD_NS;
            btn_drv = 4'b0000;
            #HOLD_NS;
            led_last = led_tri_io;   // синхронізуємось після паузи
        end
    endtask

    // ---- Перевірити один крок у заданому напрямку ----
    task check_step(input integer forward);
        reg [3:0] expect_val;
        begin
            expect_val = forward ? rot_fwd(led_last) : rot_bwd(led_last);
            wait_change(STEP_TIMEOUT);
            if (led_tri_io === expect_val)
                $display("[%0t] PASS  led=%b  (step took %0d ns)",
                         $time, led_tri_io, elapsed);
            else begin
                $display("[%0t] FAIL  led=%b, expected %b",
                         $time, led_tri_io, expect_val);
                errors = errors + 1;
            end
        end
    endtask

    integer waited;
    integer period_default;
    integer period_fast;
    reg [3:0] frozen;

    initial begin
        $timeformat(-9, 0, " ns", 12);
        $display("=== Running-light testbench. Waiting for MicroBlaze boot... ===");

        // ---- 1. Старт: чекаємо коректного стану доріжки ----
        waited = 0;
        while (!is_onehot(led_tri_io) && waited < BOOT_TIMEOUT) begin
            #RES_NS;
            waited = waited + RES_NS;
        end
        if (!is_onehot(led_tri_io)) begin
            $display("!!! FAIL: no valid LED pattern after %0d ns (led=%b).",
                     waited, led_tri_io);
            $display("!!! Most likely no ELF associated, or the wrong one.");
            errors = errors + 1;
            $finish;
        end
        $display("[%0t] boot done in %0d ns, led=%b", $time, waited, led_tri_io);
        led_last = led_tri_io;

        // ---- 2. Рух уперед на швидкості за замовчуванням (~250 мкс) ----
        // Перший крок може бути неповним (лічильник стартував до того,
        // як застосунок записав початковий стан), тому за еталон беремо другий.
        $display("--- forward at default speed (expect ~250000 ns per step) ---");
        check_step(1);
        check_step(1);
        period_default = elapsed;

        if (period_default > 200_000 && period_default < 300_000)
            $display("[%0t] PASS  default step = %0d ns (expected ~250000)",
                     $time, period_default);
        else begin
            $display("[%0t] FAIL  default step = %0d ns, expected ~250000",
                     $time, period_default);
            errors = errors + 1;
        end

        // ---- 3. BTN3 чотири рази: 250 -> 175 -> 125 -> 90 -> 60 мкс ----
        $display("--- BTN3 x4: speed up to the fastest step (~60000 ns) ---");
        press(4'b1000, "BTN3 faster");
        press(4'b1000, "BTN3 faster");
        press(4'b1000, "BTN3 faster");
        press(4'b1000, "BTN3 faster");

        // press() синхронізує led_last у довільній точці всередині кроку,
        // тому перший вимір після натискань -- неповний. Відкидаємо його
        // й міряємо період між двома послідовними змінами.
        check_step(1);
        check_step(1);
        period_fast = elapsed;
        if (period_fast > 40_000 && period_fast < 80_000)
            $display("[%0t] PASS  fast step = %0d ns (expected ~60000)",
                     $time, period_fast);
        else begin
            $display("[%0t] FAIL  fast step = %0d ns, expected ~60000",
                     $time, period_fast);
            errors = errors + 1;
        end

        if (period_fast < period_default)
            $display("[%0t] PASS  step shrank: %0d ns -> %0d ns",
                     $time, period_default, period_fast);
        else begin
            $display("[%0t] FAIL  step did not shrink: %0d ns -> %0d ns",
                     $time, period_default, period_fast);
            errors = errors + 1;
        end

        // ---- 4. SW0 = 1: рух назад ----
        $display("--- SW0 = 1: direction must reverse ---");
        sw_drv = 2'b01;
        #HOLD_NS;
        led_last = led_tri_io;
        check_step(0);
        check_step(0);

        // ---- 5. BTN1: стоп ----
        $display("--- BTN1: movement must stop ---");
        press(4'b0010, "BTN1 stop");
        frozen = led_tri_io;
        #(300_000);                      // близько 5 найшвидших кроків
        if (led_tri_io === frozen)
            $display("[%0t] PASS  led frozen at %b", $time, led_tri_io);
        else begin
            $display("[%0t] FAIL  led moved while stopped: %b -> %b",
                     $time, frozen, led_tri_io);
            errors = errors + 1;
        end

        // ---- 6. BTN0: продовжити ----
        $display("--- BTN0: movement must resume ---");
        press(4'b0001, "BTN0 resume");
        check_step(0);

        // ---- Підсумок ----
        $display("=== Finished. Errors: %0d ===", errors);
        if (errors == 0)
            $display("=== SUCCESS: running light, speed, direction, stop/resume all OK ===");
        else
            $display("=== Mismatches found -- inspect the Waveform Viewer ===");
        $finish;
    end

    // ---- Сторожовий таймер ----
    initial begin
        #10_000_000;                     // 10 мс модельного часу
        $display("!!! Watchdog: simulation is running too long.");
        $display("!!! Check that app_component_sim.elf (TIME_SCALE=1000) is associated.");
        $finish;
    end

endmodule
