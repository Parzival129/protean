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
        blinkA blinkB flash-blinkA flash-blinkB stage-slot0 stage-slot1 reconfig \
        flashswitch

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

# COPY_LEN — bytes the self-switch copies; override to the real bitstream size.
COPY_LEN ?= 4096

# Flash SELF-SWITCH — THE Phase-1 exit gate. Idles with a heartbeat; on a button
# press copies the staged bitstream (source 0x200000) into BOOT 0x000000, verifies,
# then pulses RECONFIG_N (pin 9) so the FPGA reloads into the new persona.
# Packed WITHOUT --reconfign_as_gpio (keeps pin 9 as the trigger) and WITH
# --mspi_as_gpio (drives the flash). Loads to SRAM (volatile) for iterating.
# MUST override COPY_LEN to the real bitstream size, e.g.:
#   make stage-slot0                         # put blinkB at 0x200000
#   make flashswitch COPY_LEN=600000         # load the switcher; press button to switch
# RECOVERY if boot ends up bad: `make flash-blinkA` reflashes boot over JTAG.
flashswitch: | $(BUILD)
	yosys -p "read_verilog $(SRC); chparam -set COPY_LEN $(COPY_LEN) flash_switch; synth_gowin -top flash_switch -json $(BUILD)/flashswitch.json"
	nextpnr-himbaechel --json $(BUILD)/flashswitch.json --write $(BUILD)/flashswitch_pnr.json \
	    --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=src/flash_switch.cst
	gowin_pack -d $(FAMILY) --mspi_as_gpio -o $(BUILD)/flashswitch.fs $(BUILD)/flashswitch_pnr.json
	openFPGALoader -b $(BOARD) $(BUILD)/flashswitch.fs

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
# 0x200000  persona SLOT 0       — blinkB (fast); self-switch copies a slot -> boot
# 0x400000  persona SLOT 1       — blinkA (slow)
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

stage-slot0: blinkB          ## stage blinkB (fast) into persona SLOT 0 (0x200000)
	@echo "NOTE: offset write — verify openFPGALoader flags on this board before trusting for self-switch."
	openFPGALoader -b $(BOARD) -f --external-flash -o $(STAGE_OFF) $(BUILD)/blinkB.fs

stage-slot1: blinkA          ## stage blinkA (slow) into persona SLOT 1 (0x400000)
	openFPGALoader -b $(BOARD) -f --external-flash -o $(SLOT1_OFF) $(BUILD)/blinkA.fs