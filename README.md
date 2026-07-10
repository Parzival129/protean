# Protean — Adaptive-Silicon Cyberdeck

A pocket cyberdeck whose **FPGA reconfigures itself into different hardware.** Most decks are a
Raspberry Pi in a case running different _software_. Protean loads a different **bitstream** and
_becomes_ a different instrument — a logic analyzer, then a software-defined radio, then a bus
sniffer, then a synthesizer, then a cycle-accurate retro computer you type on. A resident **shell**
(a CPU/SoC designed from the gates up) is the launcher; pick a **persona** and the silicon
rearranges itself for the task.

Built on a **Sipeed Tang Nano 20K** (Gowin GW2AR-18) with an RGB LCD, a 3.7" e-ink HUD, an M5Stack
mini keyboard, and a LiPo — using an entirely **FOSS toolchain** (yosys / nextpnr / apicula /
openFPGALoader), no Gowin proprietary EDA.

> **Why it's an FPGA project, not a Pi-in-a-case:** the differentiator is reconfigurable _hardware_,
> which a CPU fundamentally can't do. Each persona is a real custom datapath.

## Status

**Phase 1 proven (2026-07-09):** the core mechanic works on hardware — a running design pulses
`RECONFIG_N` and the FPGA reconfigures itself from flash, standalone, no PC. Next: the Phase-1 exit
gate (reload a _different_ bitstream via a fabric SPI-flash writer), then the shell.

## Quickstart

```bash
make            # src/*.v → yosys → nextpnr → gowin_pack → build/protean.fs
make load       # upload to SRAM (volatile) — needs the board
make detect     # openFPGALoader --detect
```

## Layout

```
protean/
├── Makefile   ← synth → P&R → pack → load pipeline
├── src/       ← Verilog RTL + tangnano20k.cst pin constraints
├── sim/       ← verilator testbenches
└── build/     ← generated .json/.fs (gitignored)
```
