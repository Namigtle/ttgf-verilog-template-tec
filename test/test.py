
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadOnly, Timer


async def reset_pid(dut):
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    await ClockCycles(dut.clk, 3)
    await Timer(1, unit="ns")

    assert int(dut.uo_out.value) == 0, \
        "DAC output must be zero after reset"

    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)


@cocotb.test()
async def test_pid_controller(dut):

    # PID sampling period: 200 us (5 kHz)
    clock = Clock(dut.clk, 200, unit="us")
    cocotb.start_soon(clock.start())

    await reset_pid(dut)

    # -------------------------------------------------
    # TEST 1: Positive error
    # -------------------------------------------------
    dut.ui_in.value = 26
    dut.uio_in.value = 0

    await ClockCycles(dut.clk, 1)
    await ReadOnly()

    positive_output = int(dut.uo_out.value)

    assert positive_output > 0, \
        "Positive error must generate positive DAC output"

    assert positive_output <= 255

    dut._log.info(
        f"Positive error: DAC = {positive_output}"
    )

    # -------------------------------------------------
    # TEST 2: Negative error
    # -------------------------------------------------
    await reset_pid(dut)

    dut.ui_in.value = 0
    dut.uio_in.value = 26

    await ClockCycles(dut.clk, 1)
    await ReadOnly()

    negative_output = int(dut.uo_out.value)

    assert negative_output == 0, \
        "Negative control must be clamped to zero"

    dut._log.info(
        f"Negative error: DAC = {negative_output}"
    )

    # -------------------------------------------------
    # TEST 3: Output saturation
    # -------------------------------------------------
    await reset_pid(dut)

    dut.ui_in.value = 255
    dut.uio_in.value = 0

    await ClockCycles(dut.clk, 3)
    await ReadOnly()

    saturated_output = int(dut.uo_out.value)

    assert saturated_output == 255, \
        "DAC output must saturate at 255 for a sufficiently large positive error"

    dut._log.info(
        f"Saturation test: DAC = {saturated_output}"
    )

    # -------------------------------------------------
    # TEST 4: Enable functionality
    # -------------------------------------------------
    dut.ui_in.value = 26
    dut.uio_in.value = 0

    await ClockCycles(dut.clk, 2)
    await ReadOnly()

    held_output = int(dut.uo_out.value)

    dut.ena.value = 0
    dut.ui_in.value = 0

    await ClockCycles(dut.clk, 3)
    await ReadOnly()

    disabled_output = int(dut.uo_out.value)

    assert disabled_output == held_output, \
        "PID output must hold its value when ena is low"

    dut._log.info(
        f"Enable test: held DAC = {disabled_output}"
    )

    # -------------------------------------------------
    # TEST 5: Reset functionality
    # -------------------------------------------------
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2)
    await Timer(1, unit="ns")

    assert int(dut.uo_out.value) == 0, \
        "DAC output must return to zero after reset"

    dut._log.info("All PID tests completed successfully")
