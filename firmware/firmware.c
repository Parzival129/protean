#include <stdint.h>

// the LED port from the SoC memory map. volatile , stop from being written away
#define LED (*(volatile uint32_t*)0x10000000)

void main(void)
{
    while (1) {
        LED = 0x3F;
        for (volatile int i = 0; i < 3000000; i++)
            ;
        LED = 0x0;
        for (volatile int i = 0; i < 3000000; i++)
            ;
    }
}
