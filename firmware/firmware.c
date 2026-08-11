#include <stdint.h>

// the ports from the SoC memory map. volatile , stop from being written away
#define LED   (*(volatile uint32_t*)0x10000000)
#define TEXT  ((volatile uint32_t*)0x30000000)
#define BTN   (*(volatile uint32_t*)0x40000000)   // bit0 = NEXT, bit1 = GO
#define SEL   (*(volatile uint32_t*)0x50000000)
#define FLASH (*(volatile uint32_t*)0x60000000)   // write slot -> switch persona

void main(void)
{
    int sel = 1;
    SEL = sel; // what persona entry are we on?
    int next_prev = 0;
    int go_prev = 0;

    while (1) {
        int next = BTN & 1;        // NEXT button
        int go   = (BTN >> 1) & 1; // GO button

        if (next && !next_prev) {  // NEXT: move the highlight, wrapping
            if (sel == 3)
                sel = 1;
            else
                sel++;
            SEL = sel;
        }

        if (go && !go_prev) {      // GO: switch into the selected persona
            if (sel == 1)
                FLASH = 0;         // PERSONA 0 -> slot 0
            else if (sel == 2)
                FLASH = 1;         // PERSONA 1 -> slot 1
            // sel == 3 (RECOVERY): not wired to a slot yet
        }

        next_prev = next;
        go_prev = go;
    }
}
