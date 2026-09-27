# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Vitis Unified IDE workspace (AMD Vitis 2025.2, installed at `C:/AMDDesignTools/2025.2/Vitis`) for a bare-metal Zynq-7000 (`xc7z020clg400-1`) app that drives LEDs from push-buttons/switches through AXI GPIO. It is one homework (ht10) inside the git repo rooted at `C:/PROJECTS_FPGA/Home_tasks/HT1` (sibling folders are other homework projects).

The hardware side lives in the Vivado project at `../../vivado/LED_AXI_GPIO_Zynq/LED_AXI_GPIO/` (`LED_AXI_GPIO.xpr`, block design `design_1`, pin constraints in `LED_AXI_GPIO.srcs/constrs_1/new/design_1.xdc`). Vivado exports `design_1_wrapper_vitis.xsa`, which `platform_2` consumes.

## Components

- `platform_2/` — Vitis platform generated from the XSA. Contains the `standalone_ps7_cortexa9_0` BSP domain and an auto-generated `zynq_fsbl`. Treat it as generated: don't hand-edit BSP/FSBL sources; regenerate the platform in Vitis after the XSA changes.
- `app_component_2/` — the user application (`src/main_combined.c`), standalone on `ps7_cortexa9_0`.
- `_ide/`, `.rigel_lopper/`, `*/build/`, `*/export/`, `.cache/`, `compile_commands.json` — IDE/tool generated state. Changes to `.ninja_log`, `CMakeCache.txt`, `workspace_journal*.py` etc. are build noise, not meaningful edits.

## Hardware address map (from `platform_2/export/platform_2/sw/standalone_ps7_cortexa9_0/include/xparameters.h`)

| Instance | Macro | Base | Width | Use |
|---|---|---|---|---|
| axi_gpio_0 | `XPAR_AXI_GPIO_0_BASEADDR` | 0x41200000 | 4 | LEDs (output) |
| axi_gpio_1 | `XPAR_AXI_GPIO_1_BASEADDR` | 0x41210000 | 4 | buttons (input) |
| axi_gpio_2 | `XPAR_AXI_GPIO_2_BASEADDR` | 0x41220000 | 2 | switches (input) |
| axi_timer_0 | `XPAR_AXI_TIMER_0_BASEADDR` | 0x42800000 | 2×32-bit | step timer for the running LED (driver `xtmrctr`, clock `XPAR_AXI_TIMER_0_CLOCK_FREQUENCY` = 50 MHz) |

The GPIOs are single-channel (use channel 1). No PL interrupts are wired to the PS (`IRQ_F2P` disabled), so the timer is used by polling its TINT flag in auto-reload mode; the flag is write-1-to-clear. With the SDT-based flow, `XGpio_LookupConfig()` / `XTmrCtr_Initialize()` take the **base address**, not a device ID. If the block design changes, re-check these macros in the regenerated `xparameters.h`.

## Build

Builds are CMake + Ninja driven by Vitis. Normally build from the Vitis IDE (platform first, then `app_component_2`). From a shell, an already-configured app build dir can be rebuilt with:

```
PATH="/c/AMDDesignTools/2025.2/Vitis/gnu/aarch32/nt/gcc-arm-none-eabi/bin:$PATH" \
  C:/AMDDesignTools/2025.2/Vitis/bin/ninja.exe -C app_component_2/build
```

The ARM toolchain must be on `PATH`: the post-link step calls `arm-none-eabi-size` by bare name and fails otherwise (the ELF itself is still linked).

Output: `app_component_2/build/app_component_2.elf`.

Source files and compiler flags are set in `app_component_2/src/UserConfig.cmake` (`USER_COMPILE_SOURCES`, `-O0 -g3`, linker script `src/lscript.ld`). New `.c` files in `src/` must be added to `USER_COMPILE_SOURCES`.

## Run / debug on hardware

Launch config `app_component_2/_ide/launch.json` (JTAG, TCF): resets the system, programs the PL with `app_component_2/_ide/bitstream/design_1_wrapper_vitis.bit`, initializes PS via the platform FSBL (`platform_2/export/platform_2/sw/boot/fsbl.elf`), then downloads and runs the ELF. There are no automated tests; verification is on the board.

After re-exporting the XSA and rebuilding the platform, the launch bitstream is **not** refreshed automatically: copy the new `.bit` from `platform_2/export/platform_2/hw/sdt/` over `app_component_2/_ide/bitstream/design_1_wrapper_vitis.bit` (and check `_ide/psinit/ps7_init.tcl` against the platform's). A stale bitstream missing a peripheral makes AXI accesses to it hang.

## Conventions

Code comments in the app are written in Ukrainian; keep that style when editing existing files.
