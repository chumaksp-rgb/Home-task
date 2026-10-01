# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Lesson 12 home task (branch `ht_lesson_12`): a MicroBlaze system on `xc7z020clg400-1` that receives a 320×200 frame of 8-bit pixels on external ports and writes it through AXI DMA into a custom AXI4-Full RAM, starting only after a button press. The assignment text is `Task/L12_task.txt`.

It is one sub-project of the `HT1` git repository — the git root and the main `.gitignore` are one level up, and sibling directories (`../ht10_running_led/` etc.) are independent earlier tasks.

**This is a simulation-only teaching project.** No hardware bring-up is planned: there is no XDC, the clock/reset ports are IP Integrator defaults, and details that only matter on a board (button debounce, real pinout, timing closure) are deliberately left out. Do not add them unasked.

Status: the whole chain passes Behavioral Simulation (`TEST PASSED`, one frame captured after one button press).

| Path | What it is |
|---|---|
| `vivado/DMA_MB/` | Vivado 2025.2 project, block design `design_1`, top `design_1_wrapper` |
| `vivado/DMA_MB/DMA_MB.srcs/sources_1/new/frame_receiver.v` | Pixel receiver: 8-bit input → async FIFO → 32-bit AXI4-Stream master. In the BD as an RTL module reference |
| `vivado/DMA_MB/DMA_MB.srcs/sim_1/new/tb_frame_capture.v` | System testbench (simulation top) |
| `Axi4_full_ram/` | AXI4-Full slave RAM, packaged IP `xilinx.com:user:axi4_full_ram:1.0` |
| `vitis/DMA_MB/` | Vitis workspace: `platform/` (from `design_1_DMA_MB.xsa`) and `app_component/` (`src/main.c`) |
| `Axis_doubler/axis_doubler.v` | Leftover AXI4-Stream example from the lecture; not used by this design |

## Data path

```
pix_clk, pix_data[7:0], pix_valid, pix_sof          (external ports, own clock domain)
        │
  frame_receiver ── m_axis (32 bit, TLAST) ──> axi_dma_0 (S2MM only, no SG)
        ▲ start                                    │ M_AXI_S2MM
        │                                          ▼
  axi_gpio_0.GPIO2 (out)            axi_smc (SmartConnect, 2 SI / 3 MI)
  axi_gpio_0.GPIO  (in) <── btn        ├─ M00 ─> axi4_full_ram_0
        ▲                              ├─ M01 ─> axi_gpio_0
        └──────── microblaze_0 ────────┴─ M02 ─> axi_dma_0 (S_AXI_LITE)
                  (M_AXI_DP → S00)
```

Everything except the `pix_*` side runs on `clk_wiz_1/clk_out1` (100 MHz) with `rst_clk_wiz_1_100M/peripheral_aresetn`.

Address map — identical for `microblaze_0/Data` and `axi_dma_0/Data_S2MM`:

| Segment | Base | Range |
|---|---|---|
| LMB BRAM (MicroBlaze only) | `0x0000_0000` | 16K |
| `axi4_full_ram_0` | `0x0001_0000` | 64K |
| `axi_gpio_0` | `0x4000_0000` | 64K |
| `axi_dma_0` registers | `0x41E0_0000` | 64K |

Sizing: 320 × 200 = 64000 bytes = 16000 32-bit words, hence `axi4_full_ram` with `ADDR_WIDTH = 16`, `MEM_DEPTH = 16000` and a 64K segment. The DMA's *Width of Buffer Length Register* is 18; the default of 14 caps a transfer at 16 KB and would truncate the frame.

## The start protocol (spans RTL, software and testbench)

- `frame_receiver` ignores its inputs until it sees a **rising edge** on `start`. It then waits for the next `pix_sof`, takes exactly `FRAME_BYTES` pixels, asserts `TLAST` on the last word and goes back to sleep. One edge = one frame.
- `start` is a **level** from GPIO2, synchronised into the `pix_clk` domain. Software must hold it high and drop it before the next frame.
- Software must program the DMA (`S2MM_DA`, then `S2MM_LENGTH`) **before** raising `start`: the receiver's FIFO is only 16 words, so nothing may arrive while the DMA is not yet accepting. `pix_overflow` is a sticky flag for exactly this failure.
- Byte order: the first pixel goes to bits `[7:0]` of the word, so pixels sit in memory in order on little-endian MicroBlaze. The testbench's expected-word construction depends on this.
- `FRAME_BYTES` must be a multiple of 4.

`main.c` talks to GPIO and DMA through raw registers (`Xil_In32`/`Xil_Out32`) on purpose. Local memory is 16K and the `XGpio`/`XAxiDma` drivers would not fit (the sibling project overflowed 16K with less); the current ELF is about 7 KB. Completion is polled via the DMA's Idle bit — no interrupts are wired.

## Simulation

The testbench runs the real MicroBlaze executing the real ELF. The ELF is referenced by the Vivado project directly from `vitis/DMA_MB/app_component/build/app_component.elf` and associated with `microblaze_0` for simulation (*Tools → Associate ELF Files*). So after changing `main.c`: rebuild in Vitis, then relaunch the simulation — no copying.

Run from the GUI: *Run Simulation → Run Behavioral Simulation*, then `run all` in the Tcl console (the project's default run time is still 1000 ns; the testbench ends itself with `$finish`). A full run is about 5.1 ms of simulated time and takes a few minutes. Results also land in `vivado/DMA_MB/DMA_MB.sim/sim_1/behav/xsim/simulate.log`.

What `tb_frame_capture` does: 25 MHz `pix_clk`, back-to-back frames with a 16-cycle gap, pixel = column + row + 17 × frame number; presses the button at 300 µs; waits for `start` to rise and fall; then compares all 16000 words of the RAM against the frame whose SOF started the capture. It also fails if any stream data appears before the button press or if `pix_overflow` is set.

The testbench reaches into the design by hierarchical name — `dut.design_1_i.frame_receiver.inst.*` and `dut.design_1_i.axi4_full_ram_0.inst.mem`. Renaming those BD instances, or signals `start` / `state` / `mem`, breaks it. `$display` strings are English because the XSim console garbles Cyrillic.

To check a single module quickly without the whole system, compile it standalone with `xvlog` / `xelab` / `xsim` from `C:/AMDDesignTools/2025.2/Vivado/bin/` in a scratch directory, overriding `FRAME_BYTES` to something small.

## How edits reach the block design

Two different mechanisms, and mixing them up wastes a synthesis run:

- **`frame_receiver.v`** is an RTL module reference. After editing, click *Refresh Changed Modules* on the diagram banner.
- **`axi4_full_ram.v`** is a packaged IP (`DMA_MB.xpr` registers `Axi4_full_ram/` as an IP repository); the BD uses a generated copy. After editing: right-click the block → *Edit in IP Packager* → *Re-Package IP*, then *Report IP Status → Upgrade Selected*, then re-check the block parameters and the Address Editor range, which an upgrade can reset. Do not hand-edit `component.xml` or `xgui/`.

After any hardware change that affects software (addresses, new peripherals): re-export the XSA and rebuild the Vitis platform before the app.

Port names follow the Vivado `<interface>_<signal>` convention (`s_axi_awaddr`, `m_axis_tdata`, `aclk`, `aresetn`) on purpose: that is what lets Vivado infer the bus interfaces and their clock association automatically.

## Traps already hit

- **Memory arrays must not live in an `always` block with asynchronous reset.** With the write and read of `mem` inside the reset FSM blocks, `axi4_full_ram` synthesised only while it was 256 words; at 16000 it failed with `[Synth 8-3391] Unable to infer a block/distributed RAM`. The memory write and the registered read are now separate reset-less `always @(posedge clk)` blocks (16 RAMB36).
- **`m_axi_s2mm_aclk` on the DMA is not connected by Connection Automation** in this flow and must be wired to `clk_out1` by hand, as must `M_AXI_S2MM` → `axi_smc/S01_AXI` and the RAM's assignment in the `Data_S2MM` address space.
- **clangd shows a false error on `#include "xil_io.h"`** while the build succeeds. Fixed by `-D__MICROBLAZE__` in `vitis/DMA_MB/app_component/src/.clangd`; Vitis may regenerate that file and drop the flag.
- `axi4_full_ram` simplifications: `wstrb`, `awsize`/`arsize`, `awburst`/`arburst`, `wlast` are ignored (always full-word INCR), no ID signals, and AW must be accepted before W. SmartConnect and the DMA live with this; a byte-wide write from software would not.

## Conventions

- RTL is plain Verilog-2001 with active-low **asynchronous** reset (`negedge aresetn`), except memory arrays (see above).
- Nearly every RTL line carries a comment: file and section headers in Ukrainian, per-line comments in Russian. C sources are commented in Ukrainian. Keep both the density and the language.
- The user works in the Vivado/Vitis GUIs and edits the block design themself; the saved `design_1.bd` is JSON and is the reliable way to verify connectivity, parameters and addresses.

## Repository hygiene

`../.gitignore` ignores Vivado's `*.runs/`, `*.gen/`, `*.cache/`, `*.sim/`, `*.hw/`, `*.ip_user_files/` and the generated BD wrapper. Tracked Vivado state is the `.xpr`, `design_1.bd`/`.bda`, per-IP `.xci` files and hand-written sources under `*.srcs/`. Opening or building the project rewrites `DMA_MB.xpr`, and Vitis rewrites files under `vitis/DMA_MB/_ide/`, so expect both to show as modified.
