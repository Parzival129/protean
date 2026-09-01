# cocotb Python runner 
import os
from pathlib import Path
from cocotb_tools.runner import get_runner

ROOT = Path(__file__).resolve().parents[2]
DUT = ROOT / "personas" / "logic_analyzer" / "i2c_master.v"


def main():
    sim = os.getenv("SIM", "icarus")
    test_module = os.getenv("MODULE", "test_hello")
    runner = get_runner(sim)
    runner.build(
        sources=[str(DUT)],
        hdl_toplevel="i2c_master",
        parameters={"DIV": 4},
        timescale=("1ns", "1ps"),
        always=True,
    )
    runner.test(hdl_toplevel="i2c_master", test_module=test_module) # wire whatever test to the i2c_master module


if __name__ == "__main__":
    main()
