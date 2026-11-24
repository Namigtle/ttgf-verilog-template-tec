# Fixed-Point Digital PI Controller for a Sallen–Key Filter

## How it works

This project implements a fixed-point digital Proportional-Integral (PI) controller designed to regulate a second-order analog system based on an active Sallen–Key low-pass filter.

The controller uses a discrete-time control algorithm obtained through Tustin (bilinear) discretization.

The controller receives:
- An 8-bit digital reference signal through `ui_in[7:0]`.
- An 8-bit digital feedback signal through `uio_in[7:0]`.

The tracking error is calculated as:

$
e[k] = r[k] - y[k]
$

The PI controller uses the following incremental difference equation:

$
u[k] = u[k-1] + \frac{9e[k]-7e[k-1]}{128}
$

The controller gains are:

- Proportional gain: $K_p = 0.0625$
- Integral gain: $K_i = 78.125$
- Sampling period: $T_s = 200\,\mu s$
- Sampling frequency: $f_s = 5\,kHz$

### Clock and sampling frequency

The design uses an external clock of **50 MHz**. An internal counter generates the sampling interval required by the PI controller.

The controller updates its internal states once every 10,000 clock cycles, resulting in a sampling frequency of 5 kHz.

### Fixed-point implementation

The PI algorithm is implemented using fixed-point arithmetic (Q7 representation). Constant multiplications are implemented using bit shifts, additions, and subtractions to reduce hardware resource usage.

The internal accumulator is limited to the range from 0 to 32,640. The resulting control signal is rounded and saturated to an 8-bit output:

$
0 \leq u_{\mathrm{out}}[k] \leq 255
$

The digital control output is available through `uo_out[7:0]`.

The design also includes:
- An enable input (`ena`) that pauses the controller when disabled.
- An active-low asynchronous reset (`rst_n`).
- Internal storage for the previous tracking error and accumulated control output.

## How to test

The project includes a Cocotb testbench in the `test` directory.

The testbench verifies the following controller functions:

- Reset functionality and initialization of the output.
- Positive tracking error and corresponding control output.
- Integral action under a constant positive error.
- Negative error and lower output clamping.
- Enable functionality: the controller state and output remain unchanged when `ena` is disabled.
- Asynchronous reset during operation.

### Simulation configuration

Use the following configuration:

| Parameter | Value |
|---|---:|
| External clock frequency | 50 MHz |
| Clock period | 20 ns |
| Internal sampling frequency | 5 kHz |
| Sampling period | 200 µs |
| Clock cycles per sample | 10,000 |
| Reference input | 8 bits |
| Feedback input | 8 bits |
| Control output | 8 bits |

Apply the reference value to `ui_in[7:0]` and the feedback value to `uio_in[7:0]`.

The controller updates its output every 10,000 rising edges of the external clock, provided that `ena` is asserted.

The digital output is available on `uo_out[7:0]`.

## External hardware

The digital controller is intended to operate with an external analog plant and signal-conditioning interfaces.

The required external hardware includes:

- **Sallen–Key filter:** second-order active low-pass filter used as the controlled plant.
- **ADC:** converts the measured analog output of the filter into an 8-bit digital feedback signal.
- **DAC:** converts the 8-bit digital control output into an analog control signal.
- **External clock source:** provides the 50 MHz clock required by the digital design.
- **Signal conditioning:** appropriate interface circuits for the ADC, DAC, and analog plant.

### Sallen–Key filter parameters

The nominal component values used for the second-order filter are:

| Component | Value |
|---|---:|
| \(R_1\) | 10 kΩ |
| \(R_2\) | 10 kΩ |
| \(C_1\) | 100 nF |
| \(C_2\) | 100 nF |
| \(R_g\) | 10 kΩ |
| \(R_f\) | 8.06 kΩ |

The nominal plant transfer function is:

$
G(s)=\frac{1.806\times10^6}
{s^2+1194s+10^6}
$

The ADC, DAC, signal-conditioning circuits, and Sallen–Key filter are external to the digital chip.

## Chip implementation and Tiny Tapeout

The design is implemented in Verilog and integrated into the Tiny Tapeout project template.

The physical design is configured with:

- **Target PDK:** GF180MCU (`gf180mcuD`)
- **Project size:** 1x1 tile
- **Top module:** `tt_um_pid_controller`
- **Hardware description language:** Verilog
- **External clock:** 50 MHz

The GitHub Actions workflow automates the following stages:

1. RTL synthesis and GDS generation.
2. Tiny Tapeout physical-design precheck.
3. Gate-level simulation testing.
4. GDS and OASIS artifact preparation.
5. Viewer generation and deployment through GitHub Pages.

The resulting physical layout can be inspected using the Tiny Tapeout 3D GDS Viewer.