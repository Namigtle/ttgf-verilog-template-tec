```python
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import (
    ClockCycles,
    RisingEdge,
    FallingEdge,
    Timer
)


# =============================================================
# PID TIMING PARAMETERS
# =============================================================

CLOCK_PERIOD_NS = 20          # 50 MHz
PID_SAMPLE_CYCLES = 10000     # 5 kHz
PID_UPDATE_WAIT = 10030       # Sampling + FSM + DAC conversion


# =============================================================
# RESET FUNCTION
# =============================================================

async def reset_pid(dut):

    dut.rst_n.value = 0
    dut.ena.value = 1

    dut.ui_in.value = 0
    dut.uio_in.value = 0

    # Keep reset active for three clock cycles
    await ClockCycles(dut.clk, 3)

    # Release reset away from the rising edge
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1

    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    assert int(dut.uo_out.value) == 0, \
        "DAC output must be zero after reset"


# =============================================================
# WAIT FOR A COMPLETE PID UPDATE
# =============================================================

async def wait_for_pid_update(dut):

    # Wait for one complete sampling interval
    # plus the sequential PID processing time.

    await ClockCycles(dut.clk, PID_UPDATE_WAIT)

    # Allow signal updates to settle
    await Timer(1, unit="ns")


# =============================================================
# TEST SUITE
# =============================================================

@cocotb.test()
async def test_pid_controller(dut):

    # ---------------------------------------------------------
    # START CLOCK
    # ---------------------------------------------------------

    clock = Clock(
        dut.clk,
        CLOCK_PERIOD_NS,
        unit="ns"
    )

    cocotb.start_soon(clock.start())

    await reset_pid(dut)

    # =========================================================
    # TEST 1: POSITIVE TRACKING ERROR
    # =========================================================

    cocotb.log.info("TEST 1: Positive tracking error")

    await FallingEdge(dut.clk)

    dut.ui_in.value = 26
    dut.uio_in.value = 0

    await wait_for_pid_update(dut)

    positive_output = int(dut.uo_out.value)

    cocotb.log.info(
        f"Positive error: DAC = {positive_output}"
    )

    assert positive_output > 0, \
        "Positive error must generate positive DAC output"

    # =========================================================
    # TEST 2: NEGATIVE TRACKING ERROR
    # =========================================================

    cocotb.log.info("TEST 2: Negative tracking error")

    await reset_pid(dut)

    await FallingEdge(dut.clk)

    dut.ui_in.value = 0
    dut.uio_in.value = 26

    await wait_for_pid_update(dut)

    negative_output = int(dut.uo_out.value)

    cocotb.log.info(
        f"Negative error: DAC = {negative_output}"
    )

    assert negative_output == 0, \
        "Negative control output must be clamped to zero"

    # =========================================================
    # TEST 3: ENABLE FUNCTIONALITY
    # =========================================================

    cocotb.log.info("TEST 3: Enable functionality")

    await reset_pid(dut)

    await FallingEdge(dut.clk)

    dut.ui_in.value = 26
    dut.uio_in.value = 0

    # Wait for the first valid PID output
    await wait_for_pid_update(dut)

    held_output = int(dut.uo_out.value)

    assert held_output > 0, \
        "PID output must be positive before disabling"

    cocotb.log.info(
        f"Output before disabling: {held_output}"
    )

    # Disable the controller
    await FallingEdge(dut.clk)

    dut.ena.value = 0

    dut.ui_in.value = 0
    dut.uio_in.value = 0

    # Verify that the output remains unchanged
    await ClockCycles(dut.clk, 20)
    await Timer(1, unit="ns")

    disabled_output = int(dut.uo_out.value)

    assert disabled_output == held_output, \
        "PID output must hold its value when ena is low"

    cocotb.log.info(
        f"Enable test passed: output held at {disabled_output}"
    )

    # =========================================================
    # TEST 4: ASYNCHRONOUS RESET FUNCTIONALITY
    # =========================================================

    cocotb.log.info("TEST 4: Asynchronous reset")

    # Assert reset while the clock is running
    await FallingEdge(dut.clk)

    dut.rst_n.value = 0

    # Check asynchronous reset before the next rising edge
    await Timer(1, unit="ns")

    reset_output = int(dut.uo_out.value)

    assert reset_output == 0, \
        "Asynchronous reset must clear the DAC output"

    cocotb.log.info(
        "Asynchronous reset test passed"
    )

    # =========================================================
    # ALL TESTS COMPLETED
    # =========================================================

    cocotb.log.info("-----------------------------------")
    cocotb.log.info("ALL PID TESTS PASSED")
    cocotb.log.info("-----------------------------------")
```