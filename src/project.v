
/*
 * Copyright (c) 2026
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_pid_controller (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,

    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,

    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // -------------------------------------------------
    // INPUT MAPPING
    // -------------------------------------------------

    wire [7:0] ref_adc;
    wire [7:0] feedback_adc;

    assign ref_adc      = ui_in;
    assign feedback_adc = uio_in;

    // -------------------------------------------------
    // PID OUTPUT
    // -------------------------------------------------

    wire [7:0] dac_code;

    // -------------------------------------------------
    // PID FIXED-POINT CONTROLLER
    // -------------------------------------------------

    pid_fixed pid_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .ena           (ena),

        .ref_adc       (ref_adc),
        .feedback_adc  (feedback_adc),

        .dac_code      (dac_code)
    );

    // -------------------------------------------------
    // TINY TAPEOUT OUTPUT MAPPING
    // -------------------------------------------------

    assign uo_out  = dac_code;

    // Bidirectional pins are not used.
    assign uio_out = 8'b00000000;
    assign uio_oe  = 8'b00000000;

endmodule

`default_nettype wire
