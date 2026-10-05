# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Vitis Unified IDE workspace (AMD Vitis 2025.2, `C:/AMDDesignTools/2025.2/Vitis`) for a bare-metal **MicroBlaze** app on a PYNQ-Z1 board (`xc7z020clg400-1`). It is the MicroBlaze counterpart of `../LED_AXI_GPIO_Zynq/`, which targets the hard ARM cores of the same chip and has its own CLAUDE.md.

The hardware lives in `../../vivado/LED_AXI_GPIO_MB/LED_AXI_GPIO/` (block design `design_1`, constraints `LED_AXI_GPIO.srcs/constrs_1/new/pynq_z1.xdc`), currently exported as `design_1_wrapper_32k_memory.xsa`. **The XSA name propagates into the bitstream name**, so re-exporting under a new name breaks the `bitstreamFile` path in `launch.json` — see below.

**MicroBlaze is a soft processor: it exists only while the FPGA is configured.** Without a bitstream there is no CPU, no LMB memory and no MDM debug module, so JTAG finds no target at all. This is the key difference from the Zynq project, where the ARM cores run regardless of the PL. Every XSA export must therefore **include the bitstream** (`Export Hardware → Include bitstream`), and the launch config must program the device.

## Hardware address map

From `platform_2/export/platform_2/sw/standalone_microblaze_0/include/xparameters.h` — note these differ from the Zynq project.

| Instance | Macro | Base | Width | Use |
|---|---|---|---|---|
| axi_gpio_0 | `XPAR_AXI_GPIO_0_BASEADDR` | 0x40000000 | 4 | LEDs (output) |
| axi_gpio_1 | `XPAR_AXI_GPIO_1_BASEADDR` | 0x40010000 | 4 | buttons (input) |
| axi_gpio_2 | `XPAR_AXI_GPIO_2_BASEADDR` | 0x40020000 | 2 | switches (input) |
| axi_timer_0 | `XPAR_AXI_TIMER_0_BASEADDR` | 0x41C00000 | 2×32-bit | driver `xtmrctr` |

`XPAR_AXI_TIMER_0_CLOCK_FREQUENCY` = 100 MHz and `XPAR_MICROBLAZE_FREQ` = 100000000, so timer reload values are **twice** those of the Zynq project (50 MHz there). Always derive them from the macro, never hard-code.

No interrupts are wired: `XPAR_MICROBLAZE_USE_INTERRUPT 0` and `INTERRUPT_PRESENT 0` on every GPIO. Poll the timer's TINT flag in auto-reload mode (write-1-to-clear), as the Zynq app does.

## Local memory is the binding constraint

MicroBlaze runs entirely out of LMB block RAM — there is no DDR in this design. The BRAM was originally 16 KB, which the running-light app overflowed by 7336 bytes. It is now **32 KB**; the app occupies ~23.7 KB, leaving ~9 KB.

The size is set **only** in the Address Editor: `Range` on both `SEG_dlmb_bram_if_cntlr_Mem` and `SEG_ilmb_bram_if_cntlr_Mem`. Both must match — they are two views of the same physical memory. Everything downstream follows automatically (`C_HIGHADDR` on both controllers, and `Write_Depth_A` on `lmb_bram`, which is in `use_bram_block = BRAM_Controller` mode and must never be edited by hand).

Two things do **not** follow automatically:

- **`app_component/src/lscript.ld`** keeps the old `LENGTH` (`0x3fb0` for 16 KB, `0x7fb0` for 32 KB). It was generated when the app was created and is not refreshed by a platform rebuild. Forgetting this reproduces the original overflow error even though the hardware has the memory.
- **`launch.json`'s `bitstreamFile`**, if the XSA was re-exported under a new name.

Optimisation flags barely help: `-O0` → `-Os` saved only 632 bytes, because the bulk is BSP library code, not application code. Measured contributions: `xtmrctr.c.obj` 6079 bytes, `xgpio.c.obj` 1771, `xtmrctr_options.c.obj` 1223, while `main_combined.c.obj` is only 1216. The BSP is compiled without function sections, so `--gc-sections` cannot drop unused functions — a referenced object is pulled in whole. If memory ever runs short again, replacing `XTmrCtr`/`XGpio` with direct `Xil_In32`/`Xil_Out32` register access saves far more than any flag.

## Clocking and reset in the block design

The clock enters on a single-ended port **`sysclk`** (PYNQ-Z1: pin H16, 125 MHz, `IO_L13P_T2_MRCC_35`), feeds `clk_wiz_1`, which outputs 100 MHz to MicroBlaze and all AXI peripherals. Keep `clk_out1` at 100 MHz — changing it silently changes every timer constant.

Two traps that cost a full debug cycle each:

**Port frequency overrides the wizard.** IP Integrator propagates `CONFIG.FREQ_HZ` from the external port into the connected IP, not the other way round. An auto-created clock port defaults to 100 MHz and will silently reset the Clocking Wizard's input frequency back to 100. After creating or reconnecting the clock port, assert both:

```tcl
set_property CONFIG.FREQ_HZ 125000000 [get_bd_ports sysclk]
```

then reopen the wizard and confirm Input Frequency reads 125.000.

**The port name must match the XDC.** `pynq_z1.xdc` constrains `sysclk`; a port left named `clk_in1_0` or `clk_100MHz` makes `get_ports` return nothing and synthesis dies with `[Common 17-55] 'set_property' expects at least one object`.

**Reset is tied off, not external.** All four buttons and both switches are taken by the GPIO blocks, so `rst_clk_wiz_1_100M/ext_reset_in` is driven by an `xlconstant` (width 1, value 1). The value is 1 because that port's `POLARITY` is `ACTIVE_LOW` — 1 means "not in reset". Power-on reset still works through `clk_wiz_1/locked` → `dcm_locked`. There is no external reset port; do not re-add one without a free pin, or bitstream DRC will fail.

## Build

Same CMake + Ninja flow as the Zynq project, but with the MicroBlaze toolchain at `C:/AMDDesignTools/2025.2/Vitis/gnu/microblaze/nt/bin/` (`mb-gcc`, `mb-size`, …). Build from the IDE: platform first, then `app_component`. Sources and flags live in `app_component/src/UserConfig.cmake` (`USER_COMPILE_SOURCES`); new `.c` files must be added there.

Outside the IDE, the platform's BSP and the app can be rebuilt with the commands Vitis logs in `_ide/logs/vitis.log`:

```
empyro.bat reconfig_bsp -d <bsp_dir>
empyro.bat build_bsp   -d <bsp_dir>
empyro.bat build_app   --src_dir <app_dir> --build_dir <app_dir>/build
```

`build_app` needs `platform_2/export/` to exist, so generate the platform in the IDE at least once.

## clangd shows a false error on `xil_io.h`

The editor reports `'xpseudo_asm.h' file not found` on the `#include "xil_io.h"` line while the build succeeds. `xil_io.h` branches on `__MICROBLAZE__`, a builtin macro of `mb-gcc` that is never passed as a flag. clangd is clang, clang has no MicroBlaze target, so it falls back to host defaults, takes the `#else` branch and looks for the ARM header — which is not exported into the MicroBlaze BSP include dir (only `mb_interface.h` is).

Fixed by `-D__MICROBLAZE__` in `app_component/src/.clangd`. The same flag also silences a second, related error (`machine/ieeefp.h: #error Endianess not declared!!`). Note `.clangd` is generated — if the error returns, check whether Vitis overwrote the flag. A second `.clangd` under `platform_2/microblaze_0/standalone_microblaze_0/bsp/libsrc/` affects BSP sources and does not carry the flag.

## Run / debug on hardware

`app_component/_ide/launch.json` is created from a **Zynq template** and is wrong for MicroBlaze out of the box. Three settings had to be corrected, and Vitis may reset them when it regenerates the file:

| Setting | Template default | Correct here |
|---|---|---|
| `runPs7Init`, `runPs7PostInit` | `true`, with an empty `ps7InitTclFile` | `false` |
| `initWithFSBL` | `true`, pointing at a non-existent `fsbl.elf` | `false` |
| `bitstreamFile` | `""` | `platform_2/export/platform_2/hw/sdt/design_1_wrapper_32k_memory.bit` |

`ps7_init` and the FSBL are Zynq PS bring-up mechanisms and have no MicroBlaze equivalent — the bitstream does that job. Leaving `runPs7Init` on with an empty path makes Vitis run `source ""`, which fails with:

```
wrong # args: should be "source ?-encoding name? fileName"
```

`debugType: baremetal-zynq` and `context: zynq` are also template leftovers; they were left alone because the ELF already targets `core: microblaze_0` and the flow works. Change them only with evidence.

There are no automated tests; verification is on the board.

## Vivado: stale output products

Synthesis once failed with `[Synth 8-439] module 'bd_afc3_m03e_0' not found` inside `axi_smc`. The SmartConnect wrapper `bd_afc3.v` and its sub-IPs had been generated in different passes (timestamps ten minutes apart), leaving a reference to a module that no longer existed while a stale `m04e` survived.

After any block-design change — especially to the SmartConnect's master count — use **Reset Output Products** before **Generate Output Products**, rather than regenerating on top. If it persists, delete `LED_AXI_GPIO.gen/sources_1/bd/design_1/` and reset the affected run.

## Simulation (Vivado XSim)

Behavioural simulation of this design runs the **real MicroBlaze executing the real ELF**, so it verifies the software, not just the RTL. Two facts shape everything:

**1. The ELF is an input to the simulator.** Without `Tools → Associate ELF Files → Simulation Sources → microblaze_0`, the CPU executes nothing and the LEDs stay high-Z. The dialog only lists ELFs already added to the project, so the file must first go in via `Add Sources → Add or create simulation sources` (set the filter to All Files — the default hides `.elf`).

**2. Real timing cannot be simulated.** One 250 ms step at 100 MHz is 25 million cycles. The app therefore carries a `TIME_SCALE` macro (default 1); building with `-DTIME_SCALE=1000` turns 250 ms into 250 µs and the 10 ms button tick into 10 µs, while the logic stays identical. Do not go much past 1000: the polling loop itself costs a few µs per iteration, and the debounce tick would stop being reliable.

This means **two ELFs**, and mixing them up is the most likely failure:

| File | Built with | Use |
|---|---|---|
| `app_component/build/app_component.elf` | default (`TIME_SCALE` = 1) | the board |
| `../../vivado/LED_AXI_GPIO_MB/sim_elf/app_component_sim.elf` | `-DTIME_SCALE=1000` | simulation |

Both are produced by **`build_elfs.ps1`** in this workspace root — use it rather than toggling the define by hand:

```powershell
.\build_elfs.ps1              # TIME_SCALE=1000
.\build_elfs.ps1 -Scale 500   # other scale
```

It builds the sim variant first, copies it to `sim_elf/`, then rebuilds the board variant. That order is the safety invariant: `app_component/build/` is left holding the real-time ELF even if the script is interrupted, so the board can never be flashed with a 1000× version. `UserConfig.cmake` is restored in a `finally` block, and the script aborts if the `USER_COMPILE_DEFINITIONS` block no longer matches the expected shape rather than corrupting it silently.

Mixing the two ELFs up fails quietly rather than loudly: associating the board ELF with the simulation just hangs until the testbench watchdog fires, and flashing the sim ELF gives a running light 1000× too fast.

Two Windows PowerShell 5.1 quirks are baked into that script; both bit during its development, so preserve them when editing:

- It must stay **UTF-8 with BOM**. Without a BOM, PS 5.1 reads the file as ANSI, the Cyrillic comments turn to mojibake and parsing fails outright.
- It does **not** use `2>&1` on `empyro.bat`. In PS 5.1 redirecting a native program's stderr wraps every line in an `ErrorRecord`, which under `$ErrorActionPreference = 'Stop'` aborts the script even on a successful build. Success is judged by `$LASTEXITCODE` instead.

Testbenches live in `../../vivado/LED_AXI_GPIO_MB/LED_AXI_GPIO/LED_AXI_GPIO.srcs/sim_1/new/`:

- `tb_top_wrapper.v` — the earlier button-to-LED mirror app
- `tb_running_led.v` — the running light: step period, BTN3 speed-up, SW0 direction, BTN1 stop, BTN0 resume

Three traps these testbenches encode, each of which cost a debugging round:

- **At `t=0` the GPIO lines are `X`, not `Z`.** The `IOBUF` tri-state control is undefined until reset propagates. A boot wait written as `while (led === 4'bzzzz)` therefore exits immediately and reports success at 0 ns. Wait for a valid one-hot pattern instead (`is_onehot()`), and compare with `===` throughout so `X` and `Z` are distinguished from `0`/`1`.
- **A resync point makes the next measured interval a partial period.** Any `led_last = led_tri_io` after a button press lands mid-step, so the following measurement is shorter than the real period. Discard it and measure between two consecutive LED changes.
- **Button presses must be held generously.** The debounce needs two matching samples for the press *and* two for the release. At a 10 µs tick, a 30 µs hold lost roughly one press in four on phase-alignment; 50 µs is reliable.

Expected healthy output: boot at ~44 µs, default step ~251 µs (nominal 250), fast step ~61 µs (nominal 60), `Errors: 0`. Those tolerances are the hardware timer's real accuracy — worth keeping as the pass criteria.

`$display` strings are in English on purpose: the XSim console renders Cyrillic as mojibake. `$timeformat(-9, 0, " ns", 12)` is set so `%0t` prints nanoseconds rather than the raw picosecond precision units.

## On-chip debug (ILA)

An ILA is currently inserted on the LED output nets. The debug constraints live in `../../vivado/LED_AXI_GPIO_MB/LED_AXI_GPIO/LED_AXI_GPIO.srcs/constrs_1/new/pynq_z1.xdc` as an auto-generated `create_debug_core` / `connect_debug_port` block appended after the pin constraints; deleting that block removes the ILA without touching the pin assignments.

**Probe the internal nets, not the pad.** Mark `led_tri_o[3:0]` — the data the AXI GPIO drives. `led_tri_io` is a top-level `inout` pad and cannot be probed. `led_tri_i` just mirrors what is driven, and `led_tri_t` only changes once at startup.

**Expect one probe per bit.** `design_1_wrapper.v` splits buses into scalar nets (`led_tri_o_0` … `led_tri_o_3`) because each feeds its own `IOBUF`, so Set Up Debug creates four 1-bit probes rather than one 4-bit probe. In the waveform window select all four and use **New Virtual Bus** to read them as `0001`/`0010`/`0100`/`1000`.

**Capture control is mandatory here, not optional.** At 100 MHz a 1024-sample buffer spans 10.24 µs, while one running-light step is 60–1000 ms. Without storage qualification you capture a frozen picture. Tick **Capture control** (and **Advanced trigger**, which is cheap and saves a re-synthesis if basic mode turns out too limited) on the ILA Core Options page.

**The global condition defaults to AND — this is the trap.** In both Trigger Setup and Capture Setup the rows are combined by a global operator whose state is *not visible in the table*; it is behind the gate-icon toolbar button. Six rows of "signal changed" ANDed together mean "all six changed on the same clock edge", which never happens: a running-light step changes exactly two of four bits. Symptom: `Window sample 0 of 1024`, 0%, forever. Switch both to **OR**. When in doubt, start with a *single* row — with one condition the operator is irrelevant.

**Trigger position** defaults to mid-buffer, which makes the core collect ~512 qualified samples before it even starts evaluating the trigger — at four LED transitions per second that is two minutes of apparent hang (status `Pre-Trigger`, 0%). Set it to 0 while debugging. `Trigger Immediately` forces a capture regardless of the trigger condition and is the fastest way to tell a broken trigger from a broken capture condition.

**With storage qualification the X axis is sample index, not time.** The order of states and the response to buttons are accurate; the intervals on screen are meaningless. Measuring the real step period needs a free-running counter on an extra probe — simulation is the better tool for timing.

### Running it

`programDevice: false` in `launch.json` does **not** work with this project's `debugType: baremetal-zynq`: Vitis reaches a reset step that has no MicroBlaze equivalent and aborts with `Invalid reset type` / `Failed to initialize the hardware` (the log shows it selecting an `APU*` target first). Setting `resetSystem: false` does not help — the programming step is what satisfies the reset. So keep both `true` and point `bitstreamFile` at the ILA bitstream instead:

```
..\..\vivado\LED_AXI_GPIO_MB\LED_AXI_GPIO\LED_AXI_GPIO.runs\impl_1\design_1_wrapper.bit
```

That path is **build output** — it is outside git, and a rebuild without the ILA silently leaves a non-ILA bitstream there. It is a debug-session setting; restore the platform bitstream when finished. Keep `design_1_wrapper.ltx` next to the `.bit`, or Hardware Manager shows probes as `probe0`…`probe3` with no signal names.

Because Vitis reconfigures the FPGA on every launch, the ILA resets with it, so arm the trigger **after** the program is running. For a repeating pattern that costs nothing — the next cycle is a few hundred ms away. The proper fix, if this ever becomes tedious, is to recreate the run configuration from the Vitis GUI so it gets a MicroBlaze-appropriate `debugType` instead of the Zynq template's.

## Conventions

Comments in `app_component/src/main_combined.c` are written in Ukrainian; keep that style. The app is the timer-driven running light, ported from the Zynq project — the C source is **identical** apart from the header comment and the `TIME_SCALE` macro, since all addresses and clock rates come from `xparameters.h`. Keeping it that way is the point of the exercise; prefer fixing the hardware or the build over letting the two versions diverge.

## Repository hygiene

Build output is committed in this workspace (~138 tracked files under `build/`, `gen_bsp/`, plus `.obj` and `.a`), unlike the Zynq workspace, where it was removed from the index. Its `.gitignore` also carries the same broken patterns (`.o`, `.d`, `.log` without `*`, matching nothing). Porting the Zynq workspace's `.gitignore` rules here would prevent generated state from masking a broken setting, which is exactly how a BSP misconfiguration stayed hidden in the Zynq project.
