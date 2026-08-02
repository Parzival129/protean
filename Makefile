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
        readid flashread flashstatus flasherase flashwrite flashcopy flashbufread flashcopypage flashfullcopy flashfull flashswitch

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

# Flash SECTOR ERASE (0x20) — the first write. WREN -> erase 4KB sector at
# 0x200000 (scratch, NOT boot) -> poll status WIP until clear -> read the byte
# back (0x03). Expected result: all 6 LEDs lit = 0xFF (a freshly erased byte).
flasherase: | $(BUILD)
	yosys -p "read_verilog $(SRC); synth_gowin -top flash_erase -json $(BUILD)/flasherase.json"
	nextpnr-himbaechel --json $(BUILD)/flasherase.json --write $(BUILD)/flasherase_pnr.json \
	    --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=src/flash_id.cst
	gowin_pack -d $(FAMILY) --mspi_as_gpio -o $(BUILD)/flasherase.fs $(BUILD)/flasherase_pnr.json
	openFPGALoader -b $(BOARD) $(BUILD)/flasherase.fs

# Flash PAGE PROGRAM (0x02) — writes a data byte (0xA5) to 0x200000, the other
# half of the writer. WREN -> program 0x02+addr+data -> poll WIP -> read back
# (0x03). Run `make flasherase` first (program only flips 1->0; target must be
# erased). Expected result: LEDs 0,2,5 lit = 0xA5 read back.
flashwrite: | $(BUILD)
	yosys -p "read_verilog $(SRC); synth_gowin -top flash_write -json $(BUILD)/flashwrite.json"
	nextpnr-himbaechel --json $(BUILD)/flashwrite.json --write $(BUILD)/flashwrite_pnr.json \
	    --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=src/flash_id.cst
	gowin_pack -d $(FAMILY) --mspi_as_gpio -o $(BUILD)/flashwrite.fs $(BUILD)/flashwrite_pnr.json
	openFPGALoader -b $(BOARD) $(BUILD)/flashwrite.fs

# Flash MULTI-BYTE program — writes a 4-byte pattern (A5 3C 18 24) to 0x200000
# in ONE Page Program command, then verifies the 4th byte at 0x200003 reads 0x24.
# Proves the multi-byte write engine for the bitstream copier. Run `make flasherase`
# first. Expected result: LEDs 2,5 lit = 0x24 read back.
flashcopy: | $(BUILD)
	yosys -p "read_verilog $(SRC); synth_gowin -top flash_copy -json $(BUILD)/flashcopy.json"
	nextpnr-himbaechel --json $(BUILD)/flashcopy.json --write $(BUILD)/flashcopy_pnr.json \
	    --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=src/flash_id.cst
	gowin_pack -d $(FAMILY) --mspi_as_gpio -o $(BUILD)/flashcopy.fs $(BUILD)/flashcopy_pnr.json
	openFPGALoader -b $(BOARD) $(BUILD)/flashcopy.fs

# Flash BUFFERED STREAMING read — one Read-Data (0x03) command, then keep
# clocking dummy bytes in the SAME CS-low frame; the flash auto-increments the
# address, so 4 dummies stream {A5,3C,18,24} from 0x200000 into buf[0..3].
# Displays buf[3]. Run `make flasherase && make flashcopy` first to lay the
# pattern (do NOT erase again before this). Expected result: LEDs 2,5 = 0x24.
flashbufread: | $(BUILD)
	yosys -p "read_verilog $(SRC); synth_gowin -top flash_bufread -json $(BUILD)/flashbufread.json"
	nextpnr-himbaechel --json $(BUILD)/flashbufread.json --write $(BUILD)/flashbufread_pnr.json \
	    --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=src/flash_id.cst
	gowin_pack -d $(FAMILY) --mspi_as_gpio -o $(BUILD)/flashbufread.fs $(BUILD)/flashbufread_pnr.json
	openFPGALoader -b $(BOARD) $(BUILD)/flashbufread.fs

# Flash SINGLE-PAGE COPY — read a block from a source addr into a fabric buffer,
# then page-program that buffer to a DIFFERENT dest addr, then verify. First time
# real data moves A->B through rbuf[] instead of being hard-coded. Source 0x200000,
# dest 0x200800 (same erased sector, different page), verify dest+3 = 0x200803.
# Run `make flasherase && make flashcopy` first. Expected result: LEDs 2,5 = 0x24.
flashcopypage: | $(BUILD)
	yosys -p "read_verilog $(SRC); synth_gowin -top flash_copy_page -json $(BUILD)/flashcopypage.json"
	nextpnr-himbaechel --json $(BUILD)/flashcopypage.json --write $(BUILD)/flashcopypage_pnr.json \
	    --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=src/flash_id.cst
	gowin_pack -d $(FAMILY) --mspi_as_gpio -o $(BUILD)/flashcopypage.fs $(BUILD)/flashcopypage_pnr.json
	openFPGALoader -b $(BOARD) $(BUILD)/flashcopypage.fs

# Flash FULL-SCALE block copier (scratch->scratch, NO brick risk) — erase dest
# region (64KB block erase 0xD8), copy source->dest 256 bytes/page in a loop, then
# streaming-read the whole dest back and compare a running checksum. src 0x200000,
# dest 0x300000. Length is a parameter (bytes); override for the real bitstream:
#   make flashfullcopy COPY_LEN=550000
# Run `make flasherase && make flashcopy` first to put data at the source.
# Expected result: LEDs 0,2,4 lit = checksum OK (LEDs 1,3,5 = mismatch/FAIL).
COPY_LEN ?= 4096
flashfullcopy: | $(BUILD)
	yosys -p "read_verilog $(SRC); chparam -set COPY_LEN $(COPY_LEN) flash_full_copy; synth_gowin -top flash_full_copy -json $(BUILD)/flashfullcopy.json"
	nextpnr-himbaechel --json $(BUILD)/flashfullcopy.json --write $(BUILD)/flashfullcopy_pnr.json \
	    --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=src/flash_id.cst
	gowin_pack -d $(FAMILY) --mspi_as_gpio -o $(BUILD)/flashfullcopy.fs $(BUILD)/flashfullcopy_pnr.json
	openFPGALoader -b $(BOARD) $(BUILD)/flashfullcopy.fs

# Flash FULL copier + button trigger + idle heartbeat (Step 1 of the self-switch:
# still scratch->scratch, NO boot write, NO reconfig). Idles with a slow blink,
# and on a button press (pin 88) runs the full erase/copy/verify to 0x300000.
# Uses src/flash_full.cst (adds the btn pin). Run `make flasherase && make flashcopy`
# (or stage a real bitstream) first. Expected: LEDs 0,2,4 = checksum OK after press.
flashfull: | $(BUILD)
	yosys -p "read_verilog $(SRC); chparam -set COPY_LEN $(COPY_LEN) flash_full; synth_gowin -top flash_full -json $(BUILD)/flashfull.json"
	nextpnr-himbaechel --json $(BUILD)/flashfull.json --write $(BUILD)/flashfull_pnr.json \
	    --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=src/flash_full.cst
	gowin_pack -d $(FAMILY) --mspi_as_gpio -o $(BUILD)/flashfull.fs $(BUILD)/flashfull_pnr.json
	openFPGALoader -b $(BOARD) $(BUILD)/flashfull.fs

# Flash SELF-SWITCH — THE Phase-1 exit gate. Idles with a heartbeat; on a button
# press copies the staged bitstream (source 0x200000) into BOOT 0x000000, verifies,
# then pulses RECONFIG_N (pin 9) so the FPGA reloads into the new persona.
# Packed WITHOUT --reconfign_as_gpio (keeps pin 9 as the trigger) and WITH
# --mspi_as_gpio (drives the flash). Loads to SRAM (volatile) for iterating.
# MUST override COPY_LEN to the real bitstream size, e.g.:
#   make flash-stageB                        # put blinkB at 0x200000
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