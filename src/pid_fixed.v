/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */


`timescale 1ns/1ps

module pid_fixed (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ena,

    input  wire [7:0] ref_adc,
    input  wire [7:0] feedback_adc,

    output wire [7:0] dac_code
);

    // =========================================================
    // PID COEFFICIENTS: Q4.16
    // C(s) = Kp + Ki/s + Kd*Nf*s/(s+Nf)
    // Discretization: Tustin, Ts = 200 us
    // =========================================================

    localparam signed [19:0] A1 =  20'sd47663;
    localparam signed [19:0] A2 =  20'sd17873;

    localparam signed [19:0] B0 =  20'sd262208;
    localparam signed [19:0] B1 = -20'sd517136;
    localparam signed [19:0] B2 =  20'sd256908;

    // =========================================================
    // INTERNAL REGISTERS
    // =========================================================

    // Error history: Q16.16
    reg signed [31:0] e_z1;
    reg signed [31:0] e_z2;

    // PID output history: Q8.16
    reg signed [23:0] u_z1;
    reg signed [23:0] u_z2;

    // Current error
    wire signed [8:0] error_code;

    assign error_code =
        $signed({1'b0, ref_adc}) -
        $signed({1'b0, feedback_adc});

    // Convert ADC difference to Q16.16
    // 5/256 * 65536 = 1280

    wire signed [31:0] error_q16;

    assign error_q16 = error_code * 32'sd1280;

    // =========================================================
    // SIGN EXTENSION
    // =========================================================

    wire signed [63:0] e0_ext;
    wire signed [63:0] e1_ext;
    wire signed [63:0] e2_ext;

    wire signed [63:0] u1_ext;
    wire signed [63:0] u2_ext;

    wire signed [63:0] a1_ext;
    wire signed [63:0] a2_ext;
    wire signed [63:0] b0_ext;
    wire signed [63:0] b1_ext;
    wire signed [63:0] b2_ext;

    assign e0_ext = {{32{error_q16[31]}}, error_q16};
    assign e1_ext = {{32{e_z1[31]}}, e_z1};
    assign e2_ext = {{32{e_z2[31]}}, e_z2};

    assign u1_ext = {{40{u_z1[23]}}, u_z1};
    assign u2_ext = {{40{u_z2[23]}}, u_z2};

    assign a1_ext = {{44{A1[19]}}, A1};
    assign a2_ext = {{44{A2[19]}}, A2};
    assign b0_ext = {{44{B0[19]}}, B0};
    assign b1_ext = {{44{B1[19]}}, B1};
    assign b2_ext = {{44{B2[19]}}, B2};

    // =========================================================
    // MULTIPLICATIONS
    // Products are Q32.32
    // =========================================================

    wire signed [63:0] P_A1;
    wire signed [63:0] P_A2;

    wire signed [63:0] P_B0;
    wire signed [63:0] P_B1;
    wire signed [63:0] P_B2;

    assign P_A1 = a1_ext * u1_ext;
    assign P_A2 = a2_ext * u2_ext;

    assign P_B0 = b0_ext * e0_ext;
    assign P_B1 = b1_ext * e1_ext;
    assign P_B2 = b2_ext * e2_ext;

    // =========================================================
    // ACCUMULATOR
    // =========================================================

    wire signed [63:0] accumulator;

    assign accumulator =
          P_A1
        + P_A2
        + P_B0
        + P_B1
        + P_B2;

    // =========================================================
    // ROUNDING: Q32.32 -> Q8.16
    // =========================================================

    function signed [63:0] round_q16;
        input signed [63:0] value;
        begin
            if (value >= 0)
                round_q16 = (value + 64'sd32768) >>> 16;
            else
                round_q16 = (value - 64'sd32768) >>> 16;
        end
    endfunction

    wire signed [63:0] u_next_wide;

    assign u_next_wide = round_q16(accumulator);

    // =========================================================
    // SATURATION TO SIGNED 24-BIT Q8.16
    // =========================================================

    function signed [23:0] saturate_internal;
        input signed [63:0] value;
        begin
            if (value > 64'sd8388607)
                saturate_internal = 24'sh7FFFFF;
            else if (value < -64'sd8388608)
                saturate_internal = 24'sh800000;
            else
                saturate_internal = value[23:0];
        end
    endfunction

    wire signed [23:0] u_next;

    assign u_next = saturate_internal(u_next_wide);

    // =========================================================
    // SEQUENTIAL PID
    // =========================================================

    reg signed [23:0] u_internal;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            e_z1       <= 32'sd0;
            e_z2       <= 32'sd0;

            u_z1       <= 24'sd0;
            u_z2       <= 24'sd0;

            u_internal <= 24'sd0;

        end

        else if (ena) begin

            // Update output history
            u_z2 <= u_z1;
            u_z1 <= u_next;

            // Update error history
            e_z2 <= e_z1;
            e_z1 <= error_q16;

            // Store current PID output
            u_internal <= u_next;

        end
    end

    // =========================================================
    // DAC CONVERSION
    //
    // DAC range: 0 to 2.5 V
    // Q16.16 conversion:
    // DAC_code = round(u_internal / 640)
    // =========================================================

    function [7:0] convert_dac;
        input signed [23:0] value;

        reg signed [63:0] temp;
        reg signed [63:0] code;

        begin

            if (value <= 0)
                convert_dac = 8'd0;

            else if (value >= 24'sd163840)
                convert_dac = 8'd255;

            else begin

                temp = {{40{value[23]}}, value};

                // Round division by 640
                code = (temp + 64'sd320) / 64'sd640;

                if (code > 255)
                    convert_dac = 8'd255;
                else
                    convert_dac = code[7:0];

            end
        end
    endfunction

    assign dac_code = convert_dac(u_internal);

endmodule
