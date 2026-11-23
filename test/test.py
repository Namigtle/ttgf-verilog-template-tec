
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import (
    ClockCycles,
    RisingEdge,
    FallingEdge,
    Timer
)


async def reset_pid(dut):

    # Apply asynchronous reset
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    await ClockCycles(dut.clk, 3)

    # Release reset away from the rising clock edge
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1

    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    assert int(dut.uo_out.value) == 0, \
        "DAC output must be zero after reset"


@cocotb.test()
async def test_pid_controller(dut):

    # PID sampling frequency = 5 kHz
    # Sampling period = 200 us

    clock = Clock(dut.clk, 200, unit="us")
    cocotb.start_soon(clock.start())

    await reset_pid(dut)

    # =============================================
    # TEST 1: Positive tracking error
    # =============================================

    await FallingEdge(dut.clk)

    dut.ui_in.value = 26
    dut.uio_in.value = 0

    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    positive_output = int(dut.uo_out.value)

    assert positive_output > 0, \
        "Positive error must generate positive DAC output"

    cocotb.log.info(
        f"Positive error: DAC = {positive_output}"
    )

    # =============================================
    # TEST 2: Negative tracking error
    # =============================================

    await reset_pid(dut)

    await FallingEdge(dut.clk)

    dut.ui_in.value = 0
    dut.uio_in.value = 26

    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    negative_output = int(dut.uo_out.value)

    assert negative_output == 0, \
        "Negative control output must be clamped to zero"

    cocotb.log.info(
        f"Negative error: DAC = {negative_output}"
    )

    # =============================================
    # TEST 3: Enable functionality
    # =============================================

    await reset_pid(dut)

    await FallingEdge(dut.clk)

    dut.ui_in.value = 26
    dut.uio_in.value = 0

    await ClockCycles(dut.clk, 3)
    await Timer(1, unit="ns")

    held_output = int(dut.uo_out.value)

    assert held_output > 0, \
        "PID output must be positive before disabling"

    await FallingEdge(dut.clk)

    dut.ena.value = 0
    dut.ui_in.value = 0

    await ClockCycles(dut.clk, 3)
    await Timer(1, unit="ns")

    disabled_output = int(dut.uo_out.value)

    assert disabled_output == held_output, \
        "PID output must hold its value when ena is low"

    cocotb.log.info(
        f"Enable test: output held at {disabled_output}"
    )

    # =============================================
    # TEST 4: Asynchronous reset functionality
    # =============================================

    await FallingEdge(dut.clk)

    dut.rst_n.value = 0

    await Timer(1, unit="ns")

    reset_output = int(dut.uo_out.value)

    assert reset_output == 0, \
        "Asynchronous reset must clear the DAC output"

    cocotb.log.info(
        "Asynchronous reset test passed"
    )

    cocotb.log.info(
        "All PID tests completed successfully"
    )
