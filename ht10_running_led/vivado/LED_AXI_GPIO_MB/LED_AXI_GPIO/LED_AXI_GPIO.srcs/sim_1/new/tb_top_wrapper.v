// tb_top_wrapper.v
// Тестбенч для повного проєкту design_1_wrapper:
// MicroBlaze + AXI GPIO x3 (LED / BTN / SW).
//
// Перевіряє логіку застосунку: пряме дзеркалення кнопок на світлодіоди
// (main_combined.c -- XGpio_DiscreteWrite(led, btn & 0xF)).
//
// ВАЖЛИВО: прошивку треба підключити через
//   Tools -> Associate ELF Files -> Simulation Sources ->
//   microblaze_0 -> app_component.elf
// Без неї процесор у симуляції не виконує нічого, світлодіоди
// лишаються в Z, і всі перевірки завершаться FAIL.
//
// Порти звірені з design_1_wrapper.v:
//   inout [3:0] btn_tri_io, led_tri_io   inout [1:0] sw_tri_io   input sysclk
//
// Рядки $display -- англійською: консоль XSim не показує кирилицю.

`timescale 1ns / 1ps

module tb_top_wrapper;

    // ---- Такт: sysclk 125 МГц, період 8 нс ----
    // (clk_wiz_1 усередині перетворює його на 100 МГц для MicroBlaze)
    reg sysclk = 1'b0;
    always #4 sysclk = ~sysclk;

    // ---- Двонапрямлені лінії GPIO ----
    // Кнопки й перемикачі сконфігуровані застосунком як входи,
    // тому їх веде тестбенч. Світлодіоди -- вихід, їх веде DUT.
    wire [3:0] btn_tri_io;
    wire [1:0] sw_tri_io;
    wire [3:0] led_tri_io;

    reg  [3:0] btn_drv = 4'b0000;
    reg  [1:0] sw_drv  = 2'b00;

    assign btn_tri_io = btn_drv;
    assign sw_tri_io  = sw_drv;

    // ---- DUT ----
    design_1_wrapper dut (
        .sysclk     (sysclk),
        .btn_tri_io (btn_tri_io),
        .sw_tri_io  (sw_tri_io),
        .led_tri_io (led_tri_io)
    );

    // ---- Облік помилок ----
    integer errors = 0;

    // Запас часу на реакцію. Перша перевірка включає старт MicroBlaze
    // (crt0, ініціалізація XGpio), тому запас навмисно великий.
    // Реальна затримка зазвичай значно менша -- чекаємо саме на подію,
    // а не відмірюємо фіксовану паузу, бо час старту залежить від збірки.
    localparam integer TIMEOUT_NS = 2_000_000;   // 2 мс

    // Подати кнопки й дочекатись очікуваного стану світлодіодів
    task apply_and_check(input [3:0] btn_value, input [3:0] expected);
        integer waited;
        begin
            btn_drv = btn_value;
            waited  = 0;

            while (led_tri_io !== expected && waited < TIMEOUT_NS) begin
                #100;
                waited = waited + 100;
            end

            if (led_tri_io === expected)
                $display("[%0t] PASS  btn=%b -> led=%b  (waited %0d ns)",
                         $time, btn_value, led_tri_io, waited);
            else begin
                $display("[%0t] FAIL  btn=%b -> led=%b, expected %b  (timeout)",
                         $time, btn_value, led_tri_io, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // Друкувати час у наносекундах, а не в одиницях точності (пс)
        $timeformat(-9, 0, " ns", 12);

        $display("=== Simulation started. Waiting for MicroBlaze to boot... ===");

        // Перший виклик найдовший: поки процесор не дійде до while(1),
        // світлодіоди перебувають у Z.
        apply_and_check(4'b0011, 4'b0011);
        apply_and_check(4'b1010, 4'b1010);
        apply_and_check(4'b1111, 4'b1111);
        apply_and_check(4'b0000, 4'b0000);

        // Перемикачі застосунок читає, але в логіці не використовує --
        // світлодіоди мають лишитись дзеркалом кнопок.
        sw_drv = 2'b11;
        apply_and_check(4'b0101, 4'b0101);

        $display("=== Finished. Errors: %0d ===", errors);
        if (errors == 0)
            $display("=== SUCCESS: button-to-LED mirroring works ===");
        else
            $display("=== Mismatches found -- inspect the Waveform Viewer ===");

        $finish;
    end

    // Сторожовий таймер: не дати симуляції зависнути назавжди
    initial begin
        #(TIMEOUT_NS * 8);
        $display("!!! Watchdog: simulation is running too long.");
        $display("!!! Most likely cause: no ELF associated (Tools -> Associate ELF Files).");
        $finish;
    end

endmodule
