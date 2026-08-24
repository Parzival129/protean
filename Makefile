# Protean — synth -> P&R -> pack -> load pipeline (FOSS Gowin toolchain).

TOP    := top
DEVICE := GW2AR-LV18QN88C8/I7
FAMILY := GW2A-18C
BOARD  := tangnano20k

# blinky persona (generic all/load/flash + blinkA/blinkB build from this)
SRC   := personas/blinky/top.v
CST   := personas/blinky/blinky.cst
# reusable RTL shared across personas
COMMON := common/picorv32.v common/spi.v common/flash_ctrl.v common/lcd_render.v
BUILD := build
JSON  := $(BUILD)/protean.json
PNR   := $(BUILD)/protean_pnr.json
FS    := $(BUILD)/protean.fs

.PHONY: all load flash detect clean \
        blinkA blinkB flash-blinkA flash-blinkB stage-golden stage-slot0 stage-slot1 reconfig \
        firmware soc la stage-shell stage-la

all: $(FS)

$(BUILD):
	mkdir -p $(BUILD)

# Synthesis: Verilog -> generic netlist (yosys)
$(JSON): $(SRC) | $(BUILD)
	yosys -p "read_verilog $(SRC); synth_gowin -top $(TOP) -json $@"

# Place & route: map to physical LUT/DSP/BRAM + route (nextpnr)
$(PNR): $(JSON) $(CST)
	nextpnr-himbaechel --json $(JSON) --write $@ \
	    --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=$(CST)

# Pack: placed netlist -> bitstream (gowin_pack)
$(FS): $(PNR)
	gowin_pack -d $(FAMILY) -o $@ $(PNR)

# Hardware (needs the board)
detect:
	openFPGALoader --detect

load: $(FS)          ## SRAM, volatile — gone on power-cycle; use while iterating
	openFPGALoader -b $(BOARD) $(FS)

flash: $(FS)         ## onboard flash, persistent — survives reboot
	openFPGALoader -b $(BOARD) -f $(FS)

clean:
	rm -rf $(BUILD)

# ---------------------------------------------------------------------------
# Phase 1 — the reconfiguration spike (TODO.md Phase 1, THE linchpin).
# Two bitstreams from one RTL (personas/blinky/top.v), differing only by the BLINK_BIT tap.
#   make blinkA  -> build/blinkA.fs  (slow, tap 24 — the golden/known-good)
#   make blinkB  -> build/blinkB.fs  (fast, tap 22 — the reload target)
# ---------------------------------------------------------------------------
blinkA: BLINK_BIT := 24
blinkB: BLINK_BIT := 22
blinkA blinkB: | $(BUILD)
	yosys -p "read_verilog $(SRC); chparam -set BLINK_BIT $(BLINK_BIT) $(TOP); synth_gowin -top $(TOP) -json $(BUILD)/$@.json"
	nextpnr-himbaechel --json $(BUILD)/$@.json --write $(BUILD)/$@_pnr.json \
	    --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=$(CST)
	gowin_pack -d $(FAMILY) -o $(BUILD)/$@.fs $(BUILD)/$@_pnr.json

# --- Flash slot map (8 MB onboard flash; 1 MB slots) --------------------------
# 0x000000  BOOT / active slot  — what the FPGA loads on power-up & on RECONFIG_N
# 0x100000  GOLDEN recovery     — immutable known-good (blinkA)  [reserved]
# 0x200000  persona SLOT 0       — blinkB (fast); self-switch copies a slot -> boot
# 0x400000  persona SLOT 1       — blinkA (slow)
GOLDEN_OFF := 0x100000
STAGE_OFF  := 0x200000
SLOT1_OFF  := 0x400000
#
# SAFETY: this JTAG cable (BL616) reflashes the boot region independently of the
# loaded bitstream, so an addr-0 write can ALWAYS be recovered — `make flash-blinkA`
# is your golden restore. You cannot permanently brick the board this way.

flash-blinkA: blinkA         ## flash slow blinkA to BOOT (addr 0) — power-cycle => slow blink from flash
	openFPGALoader -b $(BOARD) -f $(BUILD)/blinkA.fs

flash-blinkB: blinkB         ## flash fast blinkB to BOOT (addr 0) — for the manual RECONFIG_N reload proof
	openFPGALoader -b $(BOARD) -f $(BUILD)/blinkB.fs

# ---------------------------------------------------------------------------
# Shell soft-core: picorv32 SoC (personas/shell/ + common/). Builds the C firmware, bakes it
# into on-chip RAM via $readmemh, synths the SoC. Loads to SRAM to iterate.
# ---------------------------------------------------------------------------
RVGCC   := riscv64-elf-gcc
RVCOPY  := riscv64-elf-objcopy
RVFLAGS := -march=rv32i -mabi=ilp32 -Os -ffreestanding -nostdlib -nostartfiles

firmware: | $(BUILD)         ## compile C firmware -> personas/shell/firmware.hex
	$(RVGCC) $(RVFLAGS) -Ifirmware -T firmware/sections.lds firmware/start.S firmware/firmware.c firmware/keyboard.c -o $(BUILD)/firmware.elf
	$(RVCOPY) -O binary $(BUILD)/firmware.elf $(BUILD)/firmware.bin
	python3 firmware/makehex.py $(BUILD)/firmware.bin > personas/shell/firmware.hex

soc: firmware               ## build firmware + picorv32 SoC, load to SRAM
	yosys -p "read_verilog $(COMMON) personas/shell/soc_top.v; synth_gowin -top soc_top -json $(BUILD)/soc.json"
	nextpnr-himbaechel --json $(BUILD)/soc.json --write $(BUILD)/soc_pnr.json \
	    --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=personas/shell/soc.cst
	gowin_pack -d $(FAMILY) --mspi_as_gpio -o $(BUILD)/soc.fs $(BUILD)/soc_pnr.json
	openFPGALoader -b $(BOARD) $(BUILD)/soc.fs

# ---------------------------------------------------------------------------
# Simulation (iverilog + vvp). Self-checking testbenches under sim/.
#   make sim-sampler   -> compiles sim/sampler_tb.v + personas/logic_analyzer/sampler.v, runs it
# One rule for every LA module: sim-<name> pairs sim/<name>_tb.v with the DUT of the same name.
# ---------------------------------------------------------------------------
LA := personas/logic_analyzer

sim-%: | $(BUILD)             ## simulate: make sim-sampler / sim-capture / sim-trigger / sim-la_engine
	iverilog -g2012 -o $(BUILD)/$*_tb.vvp sim/$*_tb.v $(wildcard $(LA)/*.v) common/spi.v common/flash_ctrl.v
	vvp $(BUILD)/$*_tb.vvp

la: | $(BUILD)                ## build Logic Analyzer persona (la_top) + load to SRAM
	yosys -p "read_verilog common/spi.v common/flash_ctrl.v $(wildcard $(LA)/*.v); synth_gowin -top la_top -json $(BUILD)/la.json"
	nextpnr-himbaechel --json $(BUILD)/la.json --write $(BUILD)/la_pnr.json \
	    --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=$(LA)/la.cst
	gowin_pack -d $(FAMILY) --mspi_as_gpio -o $(BUILD)/la.fs $(BUILD)/la_pnr.json
	openFPGALoader -b $(BOARD) $(BUILD)/la.fs

stage-golden: blinkA         ## stage blinkA (slow) into the IMMUTABLE GOLDEN slot (0x100000) — the self-heal fallback
	openFPGALoader -b $(BOARD) -f --external-flash -o $(GOLDEN_OFF) $(BUILD)/blinkA.fs

stage-slot0: blinkB          ## stage blinkB (fast) into persona SLOT 0 (0x200000)
	@echo "NOTE: offset write — verify openFPGALoader flags on this board before trusting for self-switch."
	openFPGALoader -b $(BOARD) -f --external-flash -o $(STAGE_OFF) $(BUILD)/blinkB.fs

stage-slot1: blinkA          ## stage blinkA (slow) into persona SLOT 1 (0x400000)
	openFPGALoader -b $(BOARD) -f --external-flash -o $(SLOT1_OFF) $(BUILD)/blinkA.fs

stage-shell: soc             ## stage the shell into persona SLOT 0 (0x200000) — LA escape copies it to boot
	openFPGALoader -b $(BOARD) -f --external-flash -o $(STAGE_OFF) $(BUILD)/soc.fs

stage-la: | $(BUILD)         ## build LA + stage into persona SLOT 1 (0x400000) — shell menu "LOGIC ANALYZER" -> LA
	yosys -p "read_verilog common/spi.v common/flash_ctrl.v $(wildcard $(LA)/*.v); synth_gowin -top la_top -json $(BUILD)/la.json"
	nextpnr-himbaechel --json $(BUILD)/la.json --write $(BUILD)/la_pnr.json \
	    --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=$(LA)/la.cst
	gowin_pack -d $(FAMILY) --mspi_as_gpio -o $(BUILD)/la.fs $(BUILD)/la_pnr.json
	openFPGALoader -b $(BOARD) -f --external-flash -o $(SLOT1_OFF) $(BUILD)/la.fs