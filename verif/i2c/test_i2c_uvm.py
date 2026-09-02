import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from pyuvm import uvm_test, uvm_root, uvm_sequence_item, uvm_sequence, uvm_driver, uvm_sequencer, ConfigDB

class I2CTransaction(uvm_sequence_item): # i2c transaciton class to test
    def __init__(self, name="itc_txn"):
        super().__init__(name)
        self.data = 0
        self.addr = None

    def __str__(self):
        return f"addr={self.addr}, data=0x{self.data:02x}" # for logging

class I2CSeq(uvm_sequence):
    async def body(self): # create a transaction and hand it to the sequencer
        txn = I2CTransaction()
        txn.data = 0x41 # the byte the slave should send back (the sequence chooses data)
        await self.start_item(txn) # wait till sequecer can accept transaction
        await self.finish_item(txn) # wait till confirmed trnasaction

class I2CDriver(uvm_driver):
    def build_phase(self):
        self.dut = ConfigDB().get(self, "", "DUT") # set up DUT from cocotb handle

    # pulled directly from test_i2c_read.py from I2CSlaveBFM.run
    async def drive(self, txn):
        state = "IDLE"; shift = 0; bits = 0; sda_pull = 0; send_bits = 0
        prev_scl, prev_sda = 1, 1

        self.dut.start.value = 1 # pulse start, kick the read
        await RisingEdge(self.dut.clk)
        self.dut.start.value = 0
        started = False

        while True:
            await RisingEdge(self.dut.clk)
            # guard value for initial clock cycles
            scl_sig = self.dut.scl_oe.value # oe -> output enable (am I pulling this low right now)
            sda_sig = self.dut.sda_oe.value # oe=1 -> pull low, oe=0 -> release

            # open drain (the line is low if anyone pulls, otherwise it defaults to high) -> wired AND
            scl = 0 if (scl_sig.is_resolvable and int(scl_sig) == 1) else 1 
            sda = 0 if (sda_sig.is_resolvable and int(sda_sig) == 1) or sda_pull else 1 # sda_pull allows the slave to 'talk' on the shared wire

            self.dut.sda_in.value = sda

            # sda falls while scl is high, start detected
            if (prev_sda == 1 and sda == 0 and scl == 1 and prev_scl == 1): 
                state = "ADDR"
                shift = 0
                bits = 0

            # sda rises while scl is high stop detected
            if (sda == 1 and prev_sda == 0 and scl == 1 and prev_scl == 1): 
                state = "IDLE"

            # scl rises, shift the bit in MSB first
            if (prev_scl == 0 and scl == 1): # rising edge -> recieve data...
                if (state == "ADDR"):
                    shift = ((shift << 1) | sda) & 0xFF
                    bits += 1
                    if (bits == 8):
                        txn.addr = shift # put the fully shifted in addres into the address variable
                        state = "ACK"

                elif (state == "ACK"): # elif to read state for next clock when falling edge arrives
                    state = "SEND" # master has sampled the data send on the previous falling edge, go back to SEND
                    send_bits = 0 # reset number of bits to send

                elif (state == "SEND"):
                    send_bits += 1
                    if (send_bits == 8): # if whole word sent then return to idle
                        state = "IDLE"

            if (prev_scl == 1 and scl == 0): # falling edge -> we can send data
                if (state == "ACK"):
                    sda_pull = 1 # pull sda low to send data on the line as the slave
                elif (state == "SEND"):
                    bit = (txn.data >> (7 - send_bits)) & 1 # send bits MSB first, "& 1" isolates only the MSB bit by acting as 00000001 instead of dealing with the whole word
                    sda_pull = 0 if bit == 1 else 1 # pull low for 0, release high for 1
                else:
                    sda_pull = 0 #otherwise remain listening

            busy = int(self.dut.busy.value) # leave
            if busy:
                started = True
            if started and busy == 0:
                return

            prev_scl = scl
            prev_sda = sda

    async def run_phase(self):
        self.dut.start.value = 0 # init pins ONCE, before the loop
        self.dut.sda_in.value = 1

        while True:
            txn = await self.seq_item_port.get_next_item()
            await self.drive(txn) # drive the full transaction test
            self.logger.info(f"driving transaction: {txn}") 
            self.seq_item_port.item_done()

class I2CTest(uvm_test):

    def build_phase(self): # CONSTRUCT the components
        self.seqr = uvm_sequencer("seqr", self)
        self.driver = I2CDriver("driver", self)
        self.dut = ConfigDB().get(self, "", "DUT")

    def connect_phase(self): # WIRE driver's port to the sequencer's export
        self.driver.seq_item_port.connect(self.seqr.seq_item_export)

    async def run_phase(self): # RUN THE SHOW (no pins, no transactions here)
        self.raise_objection() # test is busy
        await I2CSeq("seq").start(self.seqr) # run one transaction through the sequencer
        assert int(self.dut.key.value) == 0x41, f"expected 0x41, got {int(self.dut.key.value):#x}"
        self.drop_objection() # test is done


@cocotb.test()
async def run_uvm(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start()) # setup clock
    ConfigDB().set(None, "*", "DUT", dut) # publish the dut so build_phase can fetch it
    await uvm_root().run_test("I2CTest", keep_singletons=True) # keep_singletons so the DUT set above survives
