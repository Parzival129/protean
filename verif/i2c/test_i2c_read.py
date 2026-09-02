import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

# as a class to hold state
# Slave to connect to i2c master-> bus functional model (BFM)
class I2CSlaveBFM:
    def __init__(self, data=0x41): # with data to send defaults to 0x41 -> A
        self.addr = None
        self.state = "IDLE"
        self.shift = 0
        self.bits = 0
        self.sda_pull = 0
        self.data = data
        self.send_bits = 0

    async def run(self, dut):
        prev_scl, prev_sda = 1, 1
        while True:
            await RisingEdge(dut.clk)
            # guard value for initial clock cycles
            scl_sig = dut.scl_oe.value # oe -> output enable (am I pulling this low right now)
            sda_sig = dut.sda_oe.value # oe=1 -> pull low, oe=0 -> release

            # open drain (the line is low if anyone pulls, otherwise it defaults to high) -> wired AND
            scl = 0 if (scl_sig.is_resolvable and int(scl_sig) == 1) else 1 
            sda = 0 if (sda_sig.is_resolvable and int(sda_sig) == 1) or self.sda_pull else 1 # sda_pull allows the slave to 'talk' on the shared wire

            dut.sda_in.value = sda

            # sda falls while scl is high, start detected
            if (prev_sda == 1 and sda == 0 and scl == 1 and prev_scl == 1): 
                self.state = "ADDR"
                self.shift = 0
                self.bits = 0

            # sda rises while scl is high stop detected
            if (sda == 1 and prev_sda == 0 and scl == 1 and prev_scl == 1): 
                self.state = "IDLE"

            # scl rises, shift the bit in MSB first
            if (prev_scl == 0 and scl == 1): # rising edge -> recieve data...
                if (self.state == "ADDR"):
                    self.shift = ((self.shift << 1) | sda) & 0xFF
                    self.bits += 1
                    if (self.bits == 8):
                        self.addr = self.shift # put the fully shifted in addres into the address variable
                        self.state = "ACK"

                elif (self.state == "ACK"): # elif to read state for next clock when falling edge arrives
                    self.state = "SEND" # master has sampled the data send on the previous falling edge, go back to SEND
                    self.send_bits = 0 # reset number of bits to send

                elif (self.state == "SEND"):
                    self.send_bits += 1
                    if (self.send_bits == 8): # if whole word sent then return to idle
                        self.state = "IDLE"

            if (prev_scl == 1 and scl == 0): # falling edge -> we can send data
                if (self.state == "ACK"):
                    self.sda_pull = 1 # pull sda low to send data on the line as the slave
                elif (self.state == "SEND"):
                    bit = (self.data >> (7 - self.send_bits)) & 1 # send bits MSB first, "& 1" isolates only the MSB bit by acting as 00000001 instead of dealing with the whole word
                    self.sda_pull = 0 if bit == 1 else 1 # pull low for 0, release high for 1
                else:
                    self.sda_pull = 0 #otherwise remain listening

            prev_scl = scl
            prev_sda = sda
    

async def drive_bus(dut):
    while (True):
        await RisingEdge(dut.clk)
        sda_oe = dut.sda_oe.value # is_resolvable tells it if its a stable 1 or 0
        master_is_pulling = sda_oe.is_resolvable and int(sda_oe) == 1 # guard since sda_oe isn't driven till ~4 cycles in
        dut.sda_in.value = 0 if master_is_pulling else 1

# test a floating i2c bus
@cocotb.test()
async def read_no_slave(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start()) # clock
    cocotb.start_soon(drive_bus(dut)) # run concurrentely

    dut.start.value = 0
    dut.sda_in.value = 1  # idle bus: released high (open-drain pull-up)

    for i in range(5):
        await RisingEdge(dut.clk)
    assert dut.busy.value == 0, "DUT should be idle before start"

    # one-cycle start pulse -> should kick a transaction
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    key = -1
    for i in range(2000):
        await RisingEdge(dut.clk)
        if (dut.valid.value == 1):
            key = int(dut.key.value)
            break

    assert key == 0xFF, f"expected 0xFF from a floating bus but got: {key:#x}" # actual test


@cocotb.test()
async def read_addr(dut):
    bfm = I2CSlaveBFM()
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start()) # clock
    cocotb.start_soon(bfm.run(dut)) # run concurrentely

    dut.start.value = 0
    dut.sda_in.value = 1  # idle bus: released high (open-drain pull-up)

    for i in range(2000):          # let any leftover transaction from a prior test drain
        if int(dut.busy.value) == 0:
            break
        await RisingEdge(dut.clk)
    assert int(dut.busy.value) == 0, "DUT should be idle before start"

    # one-cycle start pulse -> should kick a transaction
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    key = -1
    for i in range(2000): # wait for valid transaction
        await RisingEdge(dut.clk)
        if (dut.valid.value == 1):
            key = int(dut.key.value)
            break

    assert bfm.addr == 0xBF, f"expected 0xBF got: {key:#x}" # address sent from master to slave

@cocotb.test()
async def ack_addr(dut):
    bfm = I2CSlaveBFM()
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start()) # clock
    cocotb.start_soon(bfm.run(dut)) # run concurrentely

    dut.start.value = 0
    dut.sda_in.value = 1  # idle bus: released high (open-drain pull-up)

    for i in range(2000):          # let any leftover transaction from a prior test drain
        if int(dut.busy.value) == 0:
            break
        await RisingEdge(dut.clk)
    assert int(dut.busy.value) == 0, "DUT should be idle before start"

    # one-cycle start pulse -> should kick a transaction
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    key = -1
    for i in range(2000): # wait for valid transaction
        await RisingEdge(dut.clk)
        if (dut.valid.value == 1):
            key = int(dut.key.value)
            break

    assert int(dut.acked.value) == 1, f"slave should have acknowledged the address" # ack sent from slave to master

@cocotb.test()
async def read_byte(dut):
    bfm = I2CSlaveBFM()
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start()) # clock
    cocotb.start_soon(bfm.run(dut)) # run concurrentely

    dut.start.value = 0
    dut.sda_in.value = 1  # idle bus: released high (open-drain pull-up)

    for i in range(2000):          # let any leftover transaction from a prior test drain
        if int(dut.busy.value) == 0:
            break
        await RisingEdge(dut.clk)
    assert int(dut.busy.value) == 0, "DUT should be idle before start"

    # one-cycle start pulse -> should kick a transaction
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    key = -1
    for i in range(2000): # wait for valid transaction
        await RisingEdge(dut.clk)
        if (dut.valid.value == 1):
            key = int(dut.key.value)
            break

    assert key == 0x41, f"expected 0x41 got {key:x}" # confirm key sent to master
