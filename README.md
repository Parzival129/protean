# Protean

**A self-reconfiguring FPGA platform: a soft RISC-V SoC that rewrites its own bitstream to become different hardware.**

Protean runs on a Sipeed Tang Nano 20K (Gowin GW2AR-18). A picorv32-based SoC — the *shell* — presents a menu; selecting a persona makes the deck reprogram the FPGA's boot flash *from within the running fabric* and reconfigure, so the same silicon comes back up as an entirely different design: a logic analyzer, or a Game Boy. Any persona can hand control back to the shell the same way. No host PC is involved once it's flashed.

It's all hand-written RTL and bare-metal C on a fully open-source flow — no vendor EDA anywhere. I built it to go deep on CPU/SoC design, digital logic, and driving real peripherals over their native protocols.

**Stack:** Verilog RTL · bare-metal RV32I C · custom SoC bus + memory-mapped peripherals · SPI & I²C protocol engines · clock-domain crossing · self-checking `iverilog` testbenches · yosys / nextpnr-himbaechel / apicula / openFPGALoader (FOSS flow)

![Tetris running on the deck](media/tetris-title.jpg)

## What works now

A small RISC-V soft core (picorv32) boots as the **shell** — a menu on the LCD that you drive with a little I²C keyboard. Pick a persona and the shell copies that bitstream into the boot region of the onboard flash and pulses the FPGA's reconfiguration pin. A fraction of a second later the chip comes back up as an entirely different design. Hold both buttons inside any persona and it does the reverse, dropping you back at the menu.

Three personas so far:

- **Shell** — the picorv32 SoC and menu launcher, built up from the gates.
- **Logic Analyzer** — samples 8 channels with a pre-trigger ring buffer, pans/zooms the captured waveform from the keyboard, and decodes the live I²C traffic from its *own* keyboard bus on screen.
- **Game Boy** — an original DMG running real cartridges, drawn to the LCD at 2×, played on the keyboard. The CPU/PPU core is the open-source [VerilogBoy](https://github.com/zephray/VerilogBoy); I wrote everything around it to make it a persona — clock, cartridge ROM, the framebuffer/video path, and the keyboard-to-joypad mapping.

### In action

**Switching personas from the menu**

![Shell menu switching personas](media/demo-shell.gif)

**The Logic Analyzer decoding its own keyboard bus** — `A:BF` is the CardKB's I²C address, with the live waveform below

![Logic analyzer decoding its keyboard bus](media/demo-logic-analyzer.gif)

**The Game Boy running Tetris, played on the keyboard**

![Game Boy running Tetris](media/demo-gameboy.gif)

## How the switching works

The FPGA can only load its bitstream from the onboard SPI flash, so switching a persona means rewriting the flash boot region and reconfiguring:

```
power on → shell (menu) → pick a persona
                              │
        shell copies that slot's bitstream → flash boot region → RECONFIG_N
                              │
                         persona runs
                              │
              hold both buttons → copies the shell back → RECONFIG_N
                              │
                          back to menu
```

Each persona bundles a tiny fabric SPI-flash writer for the "escape back to shell" path, so no PC is involved once it's flashed.

## Under the hood

The interesting parts are the subsystems — all hand-written RTL and bare-metal C:

- **Custom RISC-V SoC (the shell).** A picorv32 core on a memory-mapped bus I wired up myself: on-chip RAM with the firmware baked in via `$readmemh`, the LCD text buffer, buttons, the flash switcher, and the I²C/SD peripherals, each decoded at its own address. No OS — the firmware is bare-metal RV32I.

- **SPI flash byte engine (`flash_ctrl.v`).** A fabric-resident SPI master FSM that reprograms the onboard flash *from within the running design*: write-enable, 64 KB block erase, 256-byte page program, and a read-back checksum verify, streaming the full ~900 KB bitstream a page at a time — then it pulses `RECONFIG_N` to reboot the FPGA into the new image. Falls back to a golden slot on a bad copy. This is the engine that lets the deck reconfigure itself with no host.

- **Hand-written I²C master (`i2c_master.v`).** A quarter-bit tick divider drives a four-phase bit clock through a START → address → ACK → data → NACK → STOP state machine — open-drain (drive-low / release-to-pull-up), with two-flop input synchronization. Reads the CardKB keyboard.

- **Passive I²C decoder (`i2c_decode.v`).** The mirror image: a bus monitor that reconstructs the protocol from the SCL/SDA lines alone — edge-detected START/STOP, a byte shifted in on each SCL rising edge, ACK on the 9th bit, address-vs-data tracking. The Logic Analyzer uses it to decode the deck's *own* keyboard traffic on screen.

- **Bare-metal C firmware.** RV32I with no runtime beyond what it needs — a menu state machine, a keyboard driver over the I²C peripheral, and small memory-mapped drivers that write the LCD text buffer and kick the flash switcher.

- **LCD beam-racer + a clock-domain crossing.** A video timing generator (H/V counters, porches, a ~9 MHz pixel clock from a phase divider) drives the 480×272 RGB panel, with glyphs from a font ROM. In the Game Boy persona it feeds a **dual-clock framebuffer** (inferred block RAM) that carries pixels from the emulated core's ~4.5 MHz domain into the 27 MHz display domain.

- **Logic-analyzer front end.** Two-flop-synchronized sampling, a configurable edge trigger, and a **pre-trigger ring buffer** so you see what happened *before* the trigger fired.

- **Verification.** Self-checking `iverilog` testbenches for the sampler, trigger, ring-buffer capture, the I²C master (driven against a fake CardKB slave on a wired-AND bus), the decoder, and the Game Boy bring-up.

## Hardware

- Sipeed Tang Nano 20K (Gowin GW2AR-18C)
- 4.3" 480×272 RGB LCD on the onboard 40-pin connector
- M5Stack CardKB — a card-sized QWERTY keyboard over I²C
- 3.7" e-ink HUD (driver written, not yet wired into the personas)

## Toolchain

Fully open source: `yosys` → `nextpnr-himbaechel` → `apicula` (`gowin_pack`) → `openFPGALoader`.

## Building

```bash
make soc         # build the shell + firmware, load to SRAM
make la          # build + load the Logic Analyzer persona
make gb          # build + load the Game Boy persona

make stage-shell # flash the shell into its persona slot
make stage-la    # flash the Logic Analyzer into its slot
make stage-gb    # flash the Game Boy into its slot
make detect      # openFPGALoader --detect
```

`make soc` / `la` / `gb` load to volatile SRAM for iterating; the `stage-*` targets write to flash so the shell menu can launch them. The Game Boy needs a ROM (see `personas/gameboy/roms/README.md`).

## Layout

```
protean/
├── personas/
│   ├── shell/          picorv32 SoC + menu launcher
│   ├── logic_analyzer/ sampler, trigger, capture, I²C decoder, LCD render
│   ├── gameboy/        VerilogBoy core (vendored) + the integration RTL
│   └── blinky/         the original reconfiguration spike
├── common/             shared RTL: picorv32, flash writer, SPI, LCD text, font
├── firmware/           C for the shell's soft core
├── sim/                iverilog testbenches
├── tools/              helper scripts (e.g. gb2hex.py)
└── Makefile            synth → P&R → pack → load pipeline
```

## Status / what's next

- The three-persona deck works end to end. Next up is an **SD-card persona library** so new personas can be dropped onto a card and launched without reflashing fixed slots.
- Adding a SBC like a Raspberry pi for 'on-the-fly' RTL generation through an LLM to adapt to different computationally intensive scenarios.

## Credits

- [VerilogBoy](https://github.com/zephray/VerilogBoy) — the Game Boy core
- [picorv32](https://github.com/YosysHQ/picorv32) — the shell's RISC-V core
- [yosys](https://github.com/YosysHQ/yosys), [nextpnr](https://github.com/YosysHQ/nextpnr), [apicula](https://github.com/YosysHQ/apicula) — the open Gowin toolchain
- M5Stack CardKB — the keyboard
