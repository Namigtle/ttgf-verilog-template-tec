import cocotb
from cocotb.clock import Clock
from cocotb.triggers import (
    ClockCycles,
    RisingEdge,
    FallingEdge,
    Timer
)


# =============================================================
# TIMING PARAMETERS
# =============================================================

CLOCK_PERIOD_NS = 20
SAMPLE_CYCLES = 10008

# =============================================================
# RESET FUNCTION
# =============================================================

async def reset_pi(dut):

    dut.rst_n.value = 0
    dut.ena.value = 1

    dut.ui_in.value = 0
    dut.uio_in.value = 0

    # Apply reset for three clock cycles
    await ClockCycles(dut.clk, 3)

    # Release reset away from rising edge
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1

    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    assert int(dut.uo_out.value) == 0, \
        "DAC output must be zero after reset"


# =============================================================
# WAIT FOR ONE PI UPDATE
# =============================================================

async def wait_for_pi_update(dut):

    await ClockCycles(dut.clk, SAMPLE_CYCLES)
    await Timer(1, unit="ns")


# =============================================================
# MAIN TEST
# =============================================================

@cocotb.test()
async def test_pi_controller(dut):

    # ---------------------------------------------------------
    # START CLOCK
    # ---------------------------------------------------------

    clock = Clock(
        dut.clk,
        CLOCK_PERIOD_NS,
        unit="ns"
    )

    cocotb.start_soon(clock.start())

    await reset_pi(dut)

    # =========================================================
    # TEST 1: POSITIVE ERROR
    # =========================================================

    cocotb.log.info("TEST 1: Positive tracking error")

    await FallingEdge(dut.clk)

    dut.ui_in.value = 26
    dut.uio_in.value = 0

    await wait_for_pi_update(dut)

    positive_output = int(dut.uo_out.value)

    cocotb.log.info(
        f"Positive error: DAC = {positive_output}"
    )

    assert positive_output > 0, \
        "Positive error must generate positive control output"

    # =========================================================
    # TEST 2: INTEGRAL ACTION
    # =========================================================

    cocotb.log.info("TEST 2: Integral accumulation")

    first_output = positive_output

    await wait_for_pi_update(dut)

    second_output = int(dut.uo_out.value)

    await wait_for_pi_update(dut)

    third_output = int(dut.uo_out.value)

    cocotb.log.info(
        f"PI outputs: {first_output}, "
        f"{second_output}, {third_output}"
    )

    assert second_output >= first_output, \
        "PI output should not decrease for constant positive error"

    assert third_output > first_output, \
        "Integral action must increase the output for constant positive error"

    # =========================================================
    # TEST 3: NEGATIVE ERROR
    # =========================================================

    cocotb.log.info("TEST 3: Negative tracking error")

    await reset_pi(dut)

    await FallingEdge(dut.clk)

    dut.ui_in.value = 0
    dut.uio_in.value = 26

    await wait_for_pi_update(dut)

    negative_output = int(dut.uo_out.value)

    cocotb.log.info(
        f"Negative error: DAC = {negative_output}"
    )

    assert negative_output == 0, \
        "Negative control output must be clamped to zero"

    # =========================================================
    # TEST 4: ENABLE FUNCTIONALITY
    # =========================================================

    cocotb.log.info("TEST 4: Enable functionality")

    await reset_pi(dut)

    await FallingEdge(dut.clk)

    dut.ui_in.value = 26
    dut.uio_in.value = 0

    await wait_for_pi_update(dut)

    held_output = int(dut.uo_out.value)

    assert held_output > 0, \
        "PI output must be positive before disabling"

    # Disable controller
    await FallingEdge(dut.clk)

    dut.ena.value = 0

    dut.ui_in.value = 0
    dut.uio_in.value = 0

    await ClockCycles(dut.clk, 20)
    await Timer(1, unit="ns")

    disabled_output = int(dut.uo_out.value)

    assert disabled_output == held_output, \
        "Output must hold its value when ena is low"

    cocotb.log.info(
        f"Enable test passed: DAC = {disabled_output}"
    )

    # =========================================================
    # TEST 5: ASYNCHRONOUS RESET
    # =========================================================

    cocotb.log.info("TEST 5: Asynchronous reset")

    await FallingEdge(dut.clk)

    dut.rst_n.value = 0

    # Check before next rising edge
    await Timer(1, unit="ns")

    reset_output = int(dut.uo_out.value)

    assert reset_output == 0, \
        "Asynchronous reset must clear DAC output"

    cocotb.log.info(
        "Asynchronous reset test passed"
    )

    # =========================================================
    # FINAL REPORT
    # =========================================================

    cocotb.log.info("-----------------------------------")
    cocotb.log.info("ALL PI TESTS PASSED")
    cocotb.log.info("-----------------------------------")
