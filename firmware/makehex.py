# firmware.bin -> 32-bit little-endian words, one 8-hex-digit line each (for $readmemh)
import sys

data = open(sys.argv[1], "rb").read()
while len(data) % 4:
    data += b"\x00"
for i in range(0, len(data), 4):
    w = data[i] | (data[i+1] << 8) | (data[i+2] << 16) | (data[i+3] << 24)
    print(f"{w:08x}")
