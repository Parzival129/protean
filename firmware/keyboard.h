#pragma once

// M5Stack CardKB Mini (I2C 0x5F). returns the ASCII of the pressed key, 0 = none.
int kb_read(void);

// CardKB special keycodes
#define KEY_UP    0xB5
#define KEY_DOWN  0xB6
#define KEY_ENTER 0x0D
