# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Vitis Unified IDE workspace (AMD Vitis 2025.2, `C:/AMDDesignTools/2025.2/Vitis`) for a bare-metal **MicroBlaze** app on a PYNQ-Z1 board (`xc7z020clg400-1`). It is the MicroBlaze counterpart of `../LED_AXI_GPIO_Zynq/`, which targets the hard ARM cores of the same chip and has its own CLAUDE.md.

The hardware lives in `../../vivado/LED_AXI_GPIO_MB/LED_AXI_GPIO/` (block design `design_1`, constraints `LED_AXI_GPIO.srcs/constrs_1/new/pynq_z1.xdc`), exported as `design_1_wrapper_real_HW.xsa`.

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
| `bitstreamFile` | `""` | `platform_2/export/platform_2/hw/sdt/design_1_wrapper_real_HW.bit` |

`ps7_init` and the FSBL are Zynq PS bring-up mechanisms and have no MicroBlaze equivalent — the bitstream does that job. Leaving `runPs7Init` on with an empty path makes Vitis run `source ""`, which fails with:

```
wrong # args: should be "source ?-encoding name? fileName"
```

`debugType: baremetal-zynq` and `context: zynq` are also template leftovers; they were left alone because the ELF already targets `core: microblaze_0` and the flow works. Change them only with evidence.

There are no automated tests; verification is on the board.

## Vivado: stale output products

Synthesis once failed with `[Synth 8-439] module 'bd_afc3_m03e_0' not found` inside `axi_smc`. The SmartConnect wrapper `bd_afc3.v` and its sub-IPs had been generated in different passes (timestamps ten minutes apart), leaving a reference to a module that no longer existed while a stale `m04e` survived.

After any block-design change — especially to the SmartConnect's master count — use **Reset Output Products** before **Generate Output Products**, rather than regenerating on top. If it persists, delete `LED_AXI_GPIO.gen/sources_1/bd/design_1/` and reset the affected run.

## Conventions

Comments in `app_component/src/main_combined.c` are written in Ukrainian; keep that style. The app is currently the simple version that mirrors buttons onto LEDs — the timer-driven running-light logic lives in the Zynq project and has not been ported here.

## Repository hygiene

Build output is committed in this workspace (~138 tracked files under `build/`, `gen_bsp/`, plus `.obj` and `.a`), unlike the Zynq workspace, where it was removed from the index. Its `.gitignore` also carries the same broken patterns (`.o`, `.d`, `.log` without `*`, matching nothing). Porting the Zynq workspace's `.gitignore` rules here would prevent generated state from masking a broken setting, which is exactly how a BSP misconfiguration stayed hidden in the Zynq project.
