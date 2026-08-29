#pragma once
#include <stdint.h>

// SoC memory map (see personas/shell/soc_top.v)
#define LED (*(volatile uint32_t*)0x10000000)
#define TEXT ((volatile uint32_t*)0x30000000)
#define BTN (*(volatile uint32_t*)0x40000000) // bit0 = NEXT, bit1 = GO
#define SEL (*(volatile uint32_t*)0x50000000)
#define FLASH (*(volatile uint32_t*)0x60000000) // write slot -> switch persona
#define I2C (*(volatile uint32_t*)0x70000000) // wr: b0=SCL b1=SDA (1=release,0=low); rd: b0=SDA
#define SD (*(volatile uint32_t*)0x80000000) // sd card

#define COLS 16 // characters per LCD text row
