# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

FPGA course project (branch `Courese_Project` — the typo is the real branch name): a custom Verilog IP with an AXI4-Lite register interface, driven by a C program on MicroBlaze. The chosen topic is **Тема 5, Метроном**. The full assignment, including the grading table, is `Doc/Task.md` (Ukrainian) — read section 5 (required steps and evidence) and the "Тема 5" part of section 6 before designing anything.

It is one sub-project of the `HT1` git repository: the git root and the only `.gitignore` are one level up, and the sibling directories (`../htL12_dma/`, `../ht_l14_debug/`, ...) are independent earlier home tasks. `../htL12_dma/` is the closest precedent (MicroBlaze + packaged custom IP + Vitis app + system simulation) and has its own `CLAUDE.md` worth consulting for flow details.

**Graded in simulation, also run on a PYNQ-Z1.** Everything graded is done in simulation, but the user has the board and wants the design to work on it too (beyond the assignment). Planned board I/O, wired with spare capacity: 4 buttons, 4 LEDs, 2 switches. LED3/LED2 flash alternately on each beat with duty below 0.5, LED0 is their OR (main output, possibly driving a sounder), BTN3/BTN2 raise/lower the tempo, SW1 stops, zeroes and restarts the count. The user wants to proceed in small steps — do one stage at a time and do not build ahead.

## Current state

Only the skeleton exists:

| Path | State |
|---|---|
| `Doc/Task.md` | Assignment text |
| `vivado/Metronome/Metronome.xpr` | Vivado 2025.2 project, part `xc7z020clg400-1`, no board part |
| `vivado/Metronome/Metronome.srcs/sources_1/bd/Metronome/Metronome.bd` | Block design `Metronome`, still empty (`design_tree: {}`) |
| `vitis/` | Empty; the Vitis workspace goes here |

| `ip_repo/axi_metronome/axi_metronome.v` | The graded module, written and smoke-tested standalone in XSim; not yet packaged as IP |

| `tb/tb_axi_metronome.v` | Self-checking module testbench, 4 scenarios, prints `RESULT: PASS` / `RESULT: FAIL`; passes on the module. Kept outside `ip_repo/` so Package IP does not pick it up |

| `vivado/Metronome_testbench/` | The user's separate Vivado project for simulating the module with its testbench; references the two files above in place, plus a saved `.wcfg` |
| `README.md` | The graded README, in Russian (as in the sibling projects). Has a status table and placeholder sections for steps 3–7 — keep it in sync as each step is finished |
| `.gitignore` | Project-local additions to `../.gitignore` (XSim CLI output, editor lock files, Vitis build output) |

No broken copy, packaged IP or C program has been written yet. Update this section as they appear.

The testbench is black-box (no hierarchical references). It numbers cycles from the accepted write to `ENABLE` and instantiates `` `DUT_MODULE `` (default `axi_metronome`), so a broken copy can be checked either by defining `DUT_MODULE` or by compiling a same-named file instead. Run it standalone from a scratch directory:

```
xvlog <repo>/ip_repo/axi_metronome/axi_metronome.v <repo>/tb/tb_axi_metronome.v
xelab tb_axi_metronome -s sim
xsim sim -runall
```

**The graded module follows `Doc/Task.md` literally — the user insisted on this.** Board extras stay outside it: buttons and switches go through AXI GPIO and the C program (which writes `BPM`/`ENABLE`), and LED stretching/alternation goes in a separate indicator module fed by `tick`.

Design decisions made in `axi_metronome.v` (they must be repeated in the README and matched by the testbench):

- Period is computed by a sequential restoring divider (`36'd60 * CLK_HZ / BPM`, one bit per cycle, 36 cycles) restarted at the start of every interval; a plain cycle counter then counts to `period - 1`. Requires the period to exceed the division time, i.e. `CLK_HZ` ≳ 160.
- `BPM` is clamped to 30..240 at write time, so it reads back the effective tempo; reset value is 120.
- A new `BPM` is sampled at the start of an interval, so a tempo change takes effect from the next `tick`.
- Cycle 0 is the first clock cycle with `ENABLE` = 1; `tick` is high in cycles P, 2P, ... (BPM=120, `CLK_HZ`=1000: 500, 1000, 1500, 2000).
- `TICKS` is cleared on the 0→1 transition of `ENABLE` and keeps its value after `ENABLE` goes to 0.
- `wstrb` is ignored (full-word writes only); AW and W are accepted together.
- The module is named `axi_metronome`, not `metronome`, to avoid a case-insensitive clash with the block design `Metronome`.

The task text says Vivado/Vitis 2026.1, but the installed and used version is **2025.2** (`C:/AMDDesignTools/2025.2/`, with `Vivado/bin` on `PATH`); the user confirmed 2025.2 is accepted.

## What has to be delivered

Seven graded steps (`Doc/Task.md` §5), each counted only with its evidence file or screenshot:

1. IP with the AXI4-Lite registers + module logic; register table in the README.
2. Self-checking module testbench printing PASS/FAIL, at least three scenarios, one of them a boundary/error case. Expected values are computed by hand *before* the run and written in the README.
3. A deliberately broken copy of the module on which the same testbench prints FAIL.
4. Package IP, add the repository to the IP Catalog.
5. Block Design: MicroBlaze + the IP, Validate Design passes, the IP has an address in the Address Editor.
6. System simulation: the real C program on MicroBlaze writes and reads the IP's registers; AXI4-Lite transactions and `tick` are visible on the waveform.
7. Implementation: LUT / FF / DSP used by the IP and the WNS, with a one-line verdict on timing.

Section 7 of the task also requires a `README.md` (topic, register table, hand-computed expected results, step 7 numbers, 2–5 problems hit and how they were solved) and a `docs/` folder with the screenshots. The existing folder is `Doc/`, not `docs/` — ask before renaming or adding a second one.

## Metronome specification (Тема 5)

Registers, all 32-bit, unused bits read as zero:

| Offset | Name | Access | Meaning |
|---|---|---|---|
| `0x00` | `BPM` | R/W | Tempo, beats per minute |
| `0x04` | `ENABLE` | R/W | Bit 0: 1 = running, 0 = stopped |
| `0x08` | `TICKS` | R | Number of pulses since it was enabled |

Behaviour that the RTL, the testbench and the README all have to agree on:

- `tick` is an external output, high for exactly one `clk` cycle per beat.
- `CLK_HZ` is a module parameter (and an IP customization parameter in the BD). Use `CLK_HZ = 1000` in simulation — MicroBlaze simulation is slow and a realistic clock frequency makes the run impractically long.
- Interval in clock cycles is `CLK_HZ * 60 / BPM`, rounded down when not integer; the rounding must be stated in the README.
- `BPM` outside 30–240 (including 0) is clamped to the nearest limit, never an error.
- `ENABLE = 0` stops pulses and holds the internal counter at zero; re-enabling starts the interval from the beginning.
- A tempo change while running takes effect no later than the end of the current interval; the exact moment chosen must be documented in the README.

Required testbench scenarios, each with the expected tick cycle numbers written down in advance: BPM=120 over the first 2000 cycles; BPM=60 then changed to 120 while running; `ENABLE`=0 for 2000 cycles then 1; BPM=0.

The C program writes `BPM=120`, `ENABLE=1`, waits in a plain delay loop, reads `TICKS`, then changes `BPM` and disables the metronome. In the BD, `tick` is made external.

## Commands

The user works in the Vivado and Vitis GUIs and edits the block design themself; there are no build scripts. The saved `.bd` is JSON and is the reliable way to check connectivity, parameters and addresses.

To check a module and its testbench standalone, without the project (run in a scratch directory, not in the repo):

```
xvlog <module>.v <tb>.v
xelab <tb_top_module> -s sim
xsim sim -runall
```

Swap the module file for the broken copy to reproduce the step 3 FAIL with the same testbench.

Project simulation from the GUI: *Run Simulation → Run Behavioral Simulation*, then `run all` in the Tcl console; the log lands in `vivado/Metronome/Metronome.sim/sim_1/behav/xsim/simulate.log`.

## Conventions carried over from the sibling projects

These come from `../htL12_dma/CLAUDE.md` and apply here unless the user says otherwise:

- RTL is plain Verilog-2001 with active-low asynchronous reset (`negedge aresetn`).
- Port names follow the Vivado `<interface>_<signal>` convention (`s_axi_awaddr`, `aclk`, `aresetn`) so that Package IP infers the bus interface and its clock association automatically.
- Nearly every RTL line carries a comment: file and section headers in Ukrainian, per-line comments in Russian. C sources are commented in Ukrainian.
- `$display` strings are English — the XSim console garbles Cyrillic.
- The C program accesses registers with raw `Xil_In32` / `Xil_Out32`; MicroBlaze local memory is small (16K there) and full drivers did not fit.
- For system simulation the ELF is associated with `microblaze_0` (*Tools → Associate ELF Files*) straight from the Vitis build directory, so after changing `main.c`: rebuild in Vitis, relaunch the simulation.
- After editing a packaged IP's source: *Edit in IP Packager → Re-Package IP*, then *Report IP Status → Upgrade Selected*, then re-check block parameters and the Address Editor. Do not hand-edit `component.xml` or `xgui/`.
- After a hardware change that affects software (addresses, ports): re-export the XSA and rebuild the Vitis platform before the app.

## Repository hygiene

`../.gitignore` ignores `*.runs/`, `*.gen/`, `*.cache/`, `*.sim/`, `*.hw/`, `*.ip_user_files/`, the generated BD `hdl/` wrapper, and Vitis build output. Tracked Vivado state is the `.xpr`, the `.bd`, per-IP `.xci` files and hand-written sources under `*.srcs/`. Opening the project rewrites `Metronome.xpr`, so expect it to show as modified.

The project is submitted as a link to a specific commit and must be readable in the browser without cloning. The user makes their own commits — stage if asked, do not commit or push.
