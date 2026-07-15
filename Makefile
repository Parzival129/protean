# Protean — synth -> P&R -> pack -> load pipeline (FOSS Gowin toolchain).

TOP    := top
DEVICE := GW2AR-LV18QN88C8/I7
FAMILY := GW2A-18C
BOARD  := tangnano20k

SRC   := $(wildcard src/*.v)
CST   := src/tangnano20k.cst
BUILD := build
JSON  := $(BUILD)/protean.json
PNR   := $(BUILD)/protean_pnr.json
FS    := $(BUILD)/protean.fs

.PHONY: all load flash detect clean \
        blinkA blinkB flash-blinkA flash-blinkB flash-stageB reconfig \
        readid flashread flashstatus

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
# Flash JEDEC-ID reader — proves the fabric can talk to the SPI flash.
# Top is spi_controller (not top); uses src/flash_id.cst; packs the MSPI
# pins (59-62) as GPIO so the fabric can drive them. Loads to SRAM (volatile).
# Expected result: LEDs 0,1,3 lit = 0x0B (the flash's JEDEC manufacturer byte).
# ---------------------------------------------------------------------------
readid: | $(BUILD)
	yosys -p "read_verilog $(SRC); synth_gowin -top spi_controller -json $(BUILD)/readid.json"
	nextpnr-himbaechel --json $(BUILD)/readid.json --write $(BUILD)/readid_pnr.json \
	    --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=src/flash_id.cst
	gowin_pack -d $(FAMILY) --mspi_as_gpio -o $(BUILD)/readid.fs $(BUILD)/readid_pnr.json
	openFPGALoader -b $(BOARD) $(BUILD)/readid.fs

# Flash READ-DATA (0x03) reader — reads one byte from a flash address, shows it
# on the LEDs. Same pin setup as readid. Loads to SRAM (volatile).
flashread: | $(BUILD)
	yosys -p "read_verilog $(SRC); synth_gowin -top flash_read -json $(BUILD)/flashread.json"
	nextpnr-himbaechel --json $(BUILD)/flashread.json --write $(BUILD)/flashread_pnr.json \
	    --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=src/flash_id.cst
	gowin_pack -d $(FAMILY) --mspi_as_gpio -o $(BUILD)/flashread.fs $(BUILD)/flashread_pnr.json
	openFPGALoader -b $(BOARD) $(BUILD)/flashread.fs

# Flash Status Register (0x05) read — WIP-poll primitive for the write path.
flashstatus: | $(BUILD)
	yosys -p "read_verilog $(SRC); synth_gowin -top flash_status -json $(BUILD)/flashstatus.json"
	nextpnr-himbaechel --json $(BUILD)/flashstatus.json --write $(BUILD)/flashstatus_pnr.json \
	    --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=src/flash_id.cst
	gowin_pack -d $(FAMILY) --mspi_as_gpio -o $(BUILD)/flashstatus.fs $(BUILD)/flashstatus_pnr.json
	openFPGALoader -b $(BOARD) $(BUILD)/flashstatus.fs

# ---------------------------------------------------------------------------
# Phase 1 — the reconfiguration spike (TODO.md Phase 1, THE linchpin).
# Two bitstreams from one RTL (src/top.v), differing only by the BLINK_BIT tap.
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
# 0x200000  blinkB staging      — self-switch copies this -> boot, then RECONFIG_N
STAGE_OFF := 0x200000
#
# SAFETY: this JTAG cable (BL616) reflashes the boot region independently of the
# loaded bitstream, so an addr-0 write can ALWAYS be recovered — `make flash-blinkA`
# is your golden restore. You cannot permanently brick the board this way.

flash-blinkA: blinkA         ## flash slow blinkA to BOOT (addr 0) — power-cycle => slow blink from flash
	openFPGALoader -b $(BOARD) -f $(BUILD)/blinkA.fs

flash-blinkB: blinkB         ## flash fast blinkB to BOOT (addr 0) — for the manual RECONFIG_N reload proof
	openFPGALoader -b $(BOARD) -f $(BUILD)/blinkB.fs

flash-stageB: blinkB         ## pre-stage blinkB at 0x200000 (NOT boot) for the self-switch step
	@echo "NOTE: offset write — verify openFPGALoader flags on this board before trusting for self-switch."
	openFPGALoader -b $(BOARD) -f --external-flash -o $(STAGE_OFF) $(BUILD)/blinkB.fs