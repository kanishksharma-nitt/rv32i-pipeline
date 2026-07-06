# FPGA synthesis notes (RV32I 5-stage core)

How to synthesize the core, reproduce timing and utilization, and the one RTL
change needed to map cleanly to on-chip block RAM.

## Memory: simulation vs. FPGA

`riscv_soc.sv` uses combinational-read instruction and data memories, which
keeps the classic 5-stage model exact and simulates fast. Real FPGA block RAM
has a registered read (1-cycle latency). Two options for hardware:

1. Registered-fetch buffer: add a small IF stage register so the instruction
   returned by BRAM is captured before ID. The PC-redirect and flush logic
   already tolerates a fetch bubble.
2. Distributed RAM (LUTRAM) for a small instruction window: combinational read
   maps directly but costs LUTs, which is fine for tiny test images.

For synthesis, instantiate the core with separate instruction/data BRAM wrappers
generated from the vendor memory compiler.

## Vivado flow (Artix-7 example)

```tcl
read_verilog -sv [glob rtl/*.sv]
synth_design -top riscv_core -part xc7a35tcpg236-1
create_clock -name clk -period 11.0 [get_ports clk]   ;# ~90 MHz target
opt_design && place_design && route_design
report_timing_summary -file timing.rpt
report_utilization     -file util.rpt
```

`docs/constraints.xdc` has a starting clock constraint.

## Representative results

Numbers below are typical for this style of single-issue RV32I core on a
mid-range Artix-7 (`xc7a35t-1`); reproduce with the flow above and paste your
own `report_timing_summary` / `report_utilization` figures here.

| Metric            | Value (typical)              |
|-------------------|------------------------------|
| Fmax              | ~80–100 MHz                  |
| Critical path     | EX: forward mux → ALU → branch compare → PC redirect |
| Slice LUTs        | ~1,500–2,000                 |
| Slice registers   | ~1,000–1,300                 |
| Block RAM         | per instruction/data memory size |
| DSP               | 0 (no mul/div in RV32I base) |

## Reducing the critical path

- Resolve branches in ID (adds a comparator earlier) to cut the taken-branch
  penalty from 2 to 1 cycle, at the cost of an extra forwarding path into ID.
- Register the ALU-result forwarding network if the mux→ALU path dominates.
- Pipeline the comparator separately from the adder.
