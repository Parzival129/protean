#include "soc.h"
#include "keyboard.h"

void printline(int row, const char* s)
{
    volatile uint32_t* cell = TEXT + row * COLS; // start of this row
    int i = 0;
    while (s[i] && i < COLS) { // copy chars until '\0' or the row is full
        cell[i] = s[i];
        i++;
    }
    while (i < COLS) { // pad the rest of the row with spaces
        cell[i] = ' ';
        i++;
    }
}

// keyboard-driven persona menu
//   down/up move the highlight, enter commits the switch
void main(void)
{
    int sel = 1;
    SEL = sel;

    while (1) {
        int k = kb_read();

        if (k == KEY_DOWN) { // next persona, wrapping
            if (sel == 3)
                sel = 1;
            else
                sel++;
            SEL = sel;
        }
        else if (k == KEY_UP) { // previous persona, wrapping
            if (sel == 1)
                sel = 3;
            else
                sel--;
            SEL = sel;
        }
        else if (k == KEY_ENTER) { // switch into the selected persona
            printline(0, "SWITCHING");
            if (sel == 1)
                FLASH = 0; // PERSONA 0 -> slot 0
            else if (sel == 2)
                FLASH = 1; // PERSONA 1 -> slot 1
            // sel == 3 (RECOVERY): not wired to a slot yet
        }

        for (volatile int i = 0; i < 20000; i++); // poll rate
    }
}
