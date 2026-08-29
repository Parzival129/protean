#include "keyboard.h"
#include "soc.h"

// print to the screen
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

// For my own reference:
// SD = (cs << 2) | (mosi << 1) | clk
// Worked example — say cs=1, mosi=0, clk=1:
// clk            =            0b001   (1)
// mosi << 1 = 0<<1 =          0b000   (0)
// cs   << 2 = 1<<2 =          0b100   (4)
// ------------------------- OR --------
// SD =                        0b101   (5)
// To read: int miso = SD & 1 -> bitwise and to only grab first bit and ignore others

// send a byte and return reply
uint8_t sd_xfer(uint8_t out)
{
    int bit, r = 0;
    for (int i = 7; i >= 0; i--) { // capture full byte
        bit = (out >> i) & 1;
        SD = (bit << 1) | 0; // put the bit on mosi with the clock low
        SD = (bit << 1) | 1; // clock high
        r = (r << 1) | (SD & 1); // capture card bit from miso
        SD = (bit << 1) | 0; // clock low
    }
    return r; // byte sent back
}

// send 6 byte command and poll for reply
uint8_t sd_command(uint8_t idx, uint32_t arg, uint8_t crc)
{
    int r;
    sd_xfer(0x40 | idx); // send command byte with correct prefix
    sd_xfer(arg >> 24); // send 4 argument bytes, MSB first
    sd_xfer(arg >> 16);
    sd_xfer(arg >> 8);
    sd_xfer(arg);
    sd_xfer(crc);
    for (int i = 0; i < 8; i++) { // poll for a response
        r = sd_xfer(0xFF);
        if ((r & 0x80) == 0) // if bit 7 is 0 -> a valid response
            break;
    }
    return r;
}

// print "<label><2 hex digits>" to a row, e.g. print_hex(1, "R1: ", 0x01) -> "R1: 01"
void print_hex(int row, const char* label, uint8_t v)
{
    char buf[COLS + 1];
    int n = 0;
    while (label[n] && n < COLS - 2) {
        buf[n] = label[n];
        n++;
    } // copy the label
    uint8_t hi = v >> 4, lo = v & 0xF; // two nibbles
    buf[n++] = hi < 10 ? '0' + hi : 'A' + (hi - 10); // high hex digit
    buf[n++] = lo < 10 ? '0' + lo : 'A' + (lo - 10); // low hex digit
    buf[n] = '\0';
    printline(row, buf);
}

void sd_init()
{
    for (int i = 0; i < 80; i++) { // pulse clk 80 times
        SD = (1 << 2) | (1 << 1) | 0;
        SD = (1 << 2) | (1 << 1) | 1;
    }
    SD = (0 << 2) | (1 << 1) | 0; // cs, clock low
    uint8_t resp = sd_command(0, 0, 0x95); // CMD0 to test
    print_hex(1, "R1: ", resp); // expect "R1: 01"
}

// keyboard-driven persona menu
//   down/up move the highlight, enter commits the switch
void main(void)
{

    sd_init();

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
        } else if (k == KEY_UP) { // previous persona, wrapping
            if (sel == 1)
                sel = 3;
            else
                sel--;
            SEL = sel;
        } else if (k == KEY_ENTER) { // switch into the selected persona
            printline(0, "SWITCHING");
            if (sel == 1)
                FLASH = 0; // SHELL      -> slot 0 (0x200000)
            else if (sel == 2)
                FLASH = 1; // LOGIC ANALYZER -> slot 1 (0x400000)
            else if (sel == 3)
                FLASH = 2; // GAME BOY   -> slot 2 (0x600000)
        }

        for (volatile int i = 0; i < 20000; i++)
            ; // poll rate
    }
}
