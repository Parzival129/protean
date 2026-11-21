# Game Boy ROMs

Neither the DMG boot ROM nor any game is distributed with this repo. Supply your own legally obtained copies.

| File (not tracked)                      | What it is                              | How to make it                                           |
|-----------------------------------------|-----------------------------------------|----------------------------------------------------------|
| `personas/gameboy/roms/bootrom.mif`     | 256-byte DMG boot ROM, one hex byte/line | `python3 tools/gb2hex.py dmg_boot.bin > personas/gameboy/roms/bootrom.mif` |
| `personas/gameboy/roms/game.hex`        | Cartridge ROM image                     | `python3 tools/gb2hex.py game.gb > personas/gameboy/roms/game.hex`         |

`make gb` / `make stage-gb` copy `bootrom.mif` into the synthesis directory and read `game.hex` into the cartridge ROM.
