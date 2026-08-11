// bit-bang I2C driver for the M5Stack CardKB keyboard.
// wired on the free GPIO 71/72 (see personas/shell/soc.cst); needs real pull-ups to 3V3.
#include "soc.h"
#include "keyboard.h"

#define CARDKB 0x5F

static void i2c_delay(void)
{
    for (volatile int i = 0; i < 400; i++) // slow clock, easy on the pull-ups
        ;
}

static void i2c_pins(int scl, int sda) { I2C = (scl ? 1 : 0) | (sda ? 2 : 0); }

static void i2c_start(void)
{
    i2c_pins(1, 1); i2c_delay(); // both released
    i2c_pins(1, 0); i2c_delay(); // SDA low while SCL high
    i2c_pins(0, 0); i2c_delay(); // SCL low
}

static void i2c_stop(void)
{
    i2c_pins(0, 0); i2c_delay();
    i2c_pins(1, 0); i2c_delay(); // SCL high, SDA low
    i2c_pins(1, 1); i2c_delay(); // SDA high while SCL high
}

static void i2c_wbit(int b)
{
    i2c_pins(0, b); i2c_delay(); // set SDA while SCL low
    i2c_pins(1, b); i2c_delay(); // SCL high (slave samples)
    i2c_pins(0, b); i2c_delay(); // SCL low
}

static int i2c_rbit(void)
{
    int b;
    i2c_pins(0, 1); i2c_delay(); // release SDA, SCL low
    i2c_pins(1, 1); i2c_delay(); // SCL high
    b = I2C & 1;                 // sample the wire
    i2c_pins(0, 1); i2c_delay(); // SCL low
    return b;
}

static int i2c_wbyte(int v) // returns ACK (0 = acked)
{
    for (int i = 0; i < 8; i++) {
        i2c_wbit((v & 0x80) ? 1 : 0);
        v <<= 1;
    }
    return i2c_rbit();
}

static int i2c_rbyte(int ack) // ack=1 -> ACK, 0 -> NACK
{
    int v = 0;
    for (int i = 0; i < 8; i++)
        v = (v << 1) | i2c_rbit();
    i2c_wbit(ack ? 0 : 1);
    return v;
}

int kb_read(void)
{
    i2c_start();
    i2c_wbyte((CARDKB << 1) | 1); // address + read
    int key = i2c_rbyte(0);       // one byte, then NACK
    i2c_stop();
    return key;
}
