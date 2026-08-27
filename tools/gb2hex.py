# Convert a Game Boy ROM (.gb / .bin) into a $readmemh image:
# one byte per line as two hex digits. Optionally pad/truncate to a size.
#
#   python3 tools/gb2hex.py game.gb > personas/gameboy/roms/game.hex
import sys, argparse

p = argparse.ArgumentParser()
p.add_argument("rom")
p.add_argument("--size", type=int, default=0, help="pad/truncate to this many bytes (0 = as-is)")
a = p.parse_args()

data = open(a.rom, "rb").read()
if a.size:
    data = data[:a.size].ljust(a.size, b"\x00")
sys.stdout.write("\n".join(f"{b:02x}" for b in data) + "\n")
