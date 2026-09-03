import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb_coverage.coverage import CoverPoint, coverage_db
from pyuvm import uvm_test, uvm_root, uvm_sequence_item, uvm_sequence, uvm_driver, uvm_sequencer, ConfigDB,  uvm_monitor, uvm_analysis_port, uvm_scoreboard, uvm_tlm_analysis_fifo, uvm_subscriber
import random

class I2CTransaction(uvm_sequence_item): # i2c transaciton class to test
    def __init__(self, name="itc_txn"):
        super().__init__(name)
        self.data = 0
        self.addr = None

    def __str__(self):
        return f"addr={self.addr}, data=0x{self.data:02x}" # for logging

class I2CSeq(uvm_sequence):
    async def body(self): # create a transaction and hand it to the sequencer
        for i in range(1000):
            txn = I2CTransaction()
            txn.data = random.randint(0, 255) # the byte the slave should send back -> fully randomized
            await self.start_item(txn) # wait till sequecer can accept transaction
            await self.finish_item(txn) # wait till confirmed trnasaction

class I2CDriver(uvm_driver):
    def build_phase(self):
        self.dut = ConfigDB().get(self, "", "DUT") # set up DUT from cocotb handle
        self.ap = uvm_analysis_port("ap", self)

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
            self.ap.write(txn) # broadcast
            self.logger.info(f"driving transaction: {txn}") 
            self.seq_item_port.item_done()

# watch valid / key to confirm transactions
class I2CMonitor(uvm_monitor):

    def build_phase(self):
        self.dut = ConfigDB().get(self, "", "DUT") # set up DUT from cocotb handle
        self.ap = uvm_analysis_port("ap", self) # broadcast port, send data to anyone asking

    async def run_phase(self):
        valid_prev = 0
        while True:

            await RisingEdge(self.dut.clk)
            valid_sig = self.dut.valid.value
            valid = 1 if (valid_sig.is_resolvable and int(valid_sig) == 1) else 0  # watc the bus for a completed read

            if (valid_prev == 0 and valid == 1): # rising edge pulse
                key = int(self.dut.key.value) # replicates a transaction based on what its read from the bus
                txn = I2CTransaction()
                txn.data = key
                self.ap.write(txn)

            valid_prev = valid

    
class I2CScoreboard(uvm_scoreboard):
    def build_phase(self):
        self.exp_fifo = uvm_tlm_analysis_fifo("exp_fifo", self) # from driver (expected)
        self.obs_fifo = uvm_tlm_analysis_fifo("obv_fifo", self) # from monitor (observed)
        self.matches = 0
        self.errors = 0

    async def run_phase(self):
        while True:
            expected = await self.exp_fifo.get()   # blocks until driver broadcasts
            observed = await self.obs_fifo.get()   # blocks until monitor broadcast s
            if (expected.data == observed.data): # compare transaction objects
                self.matches += 1
            else: self.errors += 1

@CoverPoint("top.i2c.data", xf=lambda txn: txn.data, bins=list(range(256))) # marks what bytes have been hit (0-255)
def sample_data(txn):
    pass # decorator samples when called, leave empty

class I2CCoverage(uvm_subscriber):
    def build_phase(self):
        pass

    def write(self, txn):
        sample_data(txn) # sample for every txn broadcast

    def check_phase(self):
        coverage_db.report_coverage(self.logger.info, bins=True) # report coverage
        self.logger.info(f"Total byte coverage: {coverage_db["top.i2c.data"].cover_percentage}%")

class I2CTest(uvm_test):

    def build_phase(self): # CONSTRUCT the components
        self.seqr = uvm_sequencer("seqr", self)
        self.driver = I2CDriver("driver", self)
        self.dut = ConfigDB().get(self, "", "DUT")
        self.monitor = I2CMonitor("monitor", self)
        self.scoreboard = I2CScoreboard("scoreboard", self)
        self.coverage = I2CCoverage("coverage", self)

    def connect_phase(self): # WIRE driver's port to the sequencer's export and the driver monitor fifos
        self.driver.seq_item_port.connect(self.seqr.seq_item_export)
        self.driver.ap.connect(self.scoreboard.exp_fifo.analysis_export)
        self.monitor.ap.connect(self.scoreboard.obs_fifo.analysis_export)
        self.monitor.ap.connect(self.coverage.analysis_export)

    async def run_phase(self): # RUN THE SHOW (no pins, no transactions here)
        self.raise_objection() # test is busy
        await I2CSeq("seq").start(self.seqr) # run one transaction through the sequencer
        for i in range(20): await RisingEdge(self.dut.clk) # wait a few clock cycles to allow monitor + scoreboard time to work
        assert (int(self.scoreboard.errors) == 0 and int(self.scoreboard.matches) > 0), f"expected 0 errors got {int(self.scoreboard.errors)} errors"
        self.logger.info(f"{self.scoreboard.matches} matches, {self.scoreboard.errors} errors") 
        self.drop_objection() # test is done

    
    
@cocotb.test()
async def run_uvm(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start()) # setup clock
    ConfigDB().set(None, "*", "DUT", dut) # publish the dut so build_phase can fetch it
    await uvm_root().run_test("I2CTest", keep_singletons=True) # keep_singletons so the DUT set above survives
