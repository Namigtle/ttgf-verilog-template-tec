## How it works

This project implements a fixed-point digital PID controller using a discrete-time control algorithm obtained through Tustin discretization.

The controller receives an 8-bit digital reference signal (`ui_in`) and an 8-bit digital feedback signal (`uio_in`). It calculates the tracking error and processes it using a second-order difference equation with fixed-point arithmetic.

The PID coefficients are designed for a sampling period of 200 microseconds (5 kHz). The controller updates its internal states at every rising edge of the external clock.

The controller generates an 8-bit digital output (`uo_out`) representing the control signal. The output is limited to the range from 0 to 255 to prevent values outside the supported output range.

The design also includes an enable input and an active-low asynchronous reset.

## How to test

Apply an 8-bit reference value to `ui_in` and an 8-bit feedback value to `uio_in`.

Configure the external clock to 5 kHz to match the PID sampling period of 200 microseconds.

The controller behavior can be verified using the Cocotb testbench included in the `test` directory. The tests check:

- Reset functionality.
- Positive tracking error and corresponding control output.
- Negative control output clamping.
- Output saturation.
- Enable functionality.

The digital output is available on `uo_out[7:0]`.

## External hardware

The design requires external hardware to interface with a physical control system:

- An ADC to acquire the measured system output and provide its 8-bit digital feedback value.
- A digital-to-analog converter (DAC), or an appropriate digital output interface, to convert the 8-bit control signal into a physical actuator command.
- A controlled plant, such as a first-order or second-order system.
- An external clock source configured to provide a 5 kHz clock signal.

The ADC, DAC, actuator and controlled plant are external to this digital design.