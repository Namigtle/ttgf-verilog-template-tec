
/*
 * Copyright (c) 2026
 * SPDX-License-Identifier: Apache-2.0
 *
 * Sequential fixed-point PID controller.
 *
 * External clock: 50 MHz
 * PID sampling frequency: 5 kHz
 * Sampling period: 200 us
 *
 * One shared multiplier and one shared accumulator.
 */

module pid_fixed (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ena,

    input  wire [7:0] ref_adc,
    input  wire [7:0] feedback_adc,

    output reg  [7:0] dac_code
);

    // =========================================================
    // TIMING
    // =========================================================

    localparam [13:0] SAMPLE_COUNT_MAX = 14'd9999;

    reg [13:0] sample_count;

    // =========================================================
    // PID COEFFICIENTS - Q4.16
    // Tustin discretization, Ts = 200 us
    // =========================================================

    localparam signed [19:0] A1 =  20'sd47663;
    localparam signed [19:0] A2 =  20'sd17873;

    localparam signed [19:0] B0 =  20'sd262208;
    localparam signed [19:0] B1 = -20'sd517136;
    localparam signed [19:0] B2 =  20'sd256908;

    // =========================================================
    // PID HISTORY
    // =========================================================

    reg signed [31:0] e_z1;
    reg signed [31:0] e_z2;

    reg signed [23:0] u_z1;
    reg signed [23:0] u_z2;

    reg signed [31:0] e_current;

    reg signed [23:0] u_internal;

    // =========================================================
    // CURRENT ERROR
    // =========================================================

    wire signed [8:0] error_code;

    assign error_code =
        $signed({1'b0, ref_adc}) -
        $signed({1'b0, feedback_adc});

    wire signed [31:0] error_q16;

    assign error_q16 = error_code * 32'sd1280;

    // =========================================================
    // FSM STATES
    // =========================================================

    localparam [3:0]
        IDLE   = 4'd0,
        MAC_A1 = 4'd1,
        MAC_A2 = 4'd2,
        MAC_B0 = 4'd3,
        MAC_B1 = 4'd4,
        MAC_B2 = 4'd5,
        ROUND  = 4'd6,
        DIVIDE = 4'd7;

    reg [3:0] state;

    // =========================================================
    // SHARED MULTIPLIER
    // =========================================================

    reg signed [19:0] mult_coef;
    reg signed [31:0] mult_data;

    wire signed [51:0] product;

    assign product =
    $signed(mult_coef) * $signed(mult_data);

    always @(*) begin

        mult_coef = 20'sd0;
        mult_data = 32'sd0;

        case (state)

            MAC_A1: begin
                mult_coef = A1;
                mult_data = {{8{u_z1[23]}}, u_z1};
            end

            MAC_A2: begin
                mult_coef = A2;
                mult_data = {{8{u_z2[23]}}, u_z2};
            end

            MAC_B0: begin
                mult_coef = B0;
                mult_data = e_current;
            end

            MAC_B1: begin
                mult_coef = B1;
                mult_data = e_z1;
            end

            MAC_B2: begin
                mult_coef = B2;
                mult_data = e_z2;
            end

            default: begin
                mult_coef = 20'sd0;
                mult_data = 32'sd0;
            end

        endcase

    end

    // =========================================================
    // SHARED ACCUMULATOR
    // =========================================================

    reg signed [55:0] accumulator;

    wire signed [55:0] product_extended;

    assign product_extended =
        {{4{product[51]}}, product};

    // =========================================================
    // ROUNDING: Q32.32 -> Q8.16
    //
    // Preserve the rounding convention of the original design.
    // =========================================================

    wire signed [55:0] rounded_value;

    assign rounded_value =
        (accumulator >= 0)
        ? ((accumulator + 56'sd32768) >>> 16)
        : ((accumulator - 56'sd32768) >>> 16);

    // =========================================================
    // INTERNAL SATURATION
    // =========================================================

    function signed [23:0] saturate_internal;

        input signed [55:0] value;

        begin

            if (value > 56'sd8388607)
                saturate_internal = 24'sh7FFFFF;

            else if (value < -56'sd8388608)
                saturate_internal = 24'sh800000;

            else
                saturate_internal = value[23:0];

        end

    endfunction

    wire signed [23:0] u_next;

    assign u_next = saturate_internal(rounded_value);

    // =========================================================
    // SEQUENTIAL DAC DIVIDER
    //
    // DAC_code = round(u_internal / 640)
    //
    // Restoring division, 18 iterations.
    // =========================================================

    reg [17:0] div_numerator;
    reg [10:0] div_remainder;
    reg [17:0] div_quotient;
    reg [4:0]  div_count;

    wire [10:0] remainder_trial;

    assign remainder_trial =
        {div_remainder[9:0], div_numerator[17]};

    wire div_bit;

    assign div_bit = (remainder_trial >= 11'd640);

    wire [17:0] quotient_next;

    assign quotient_next =
        {div_quotient[16:0], div_bit};

    // =========================================================
    // MAIN SEQUENTIAL PROCESS
    // =========================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            sample_count <= 14'd0;

            state <= IDLE;

            e_z1 <= 32'sd0;
            e_z2 <= 32'sd0;

            u_z1 <= 24'sd0;
            u_z2 <= 24'sd0;

            e_current <= 32'sd0;

            u_internal <= 24'sd0;

            accumulator <= 56'sd0;

            div_numerator <= 18'd0;
            div_remainder <= 11'd0;
            div_quotient <= 18'd0;
            div_count <= 5'd0;

            dac_code <= 8'd0;

        end

        else if (ena) begin

            // -------------------------------------------------
            // SAMPLE COUNTER
            // One PID sample every 10,000 clock cycles.
            // -------------------------------------------------

            if (sample_count == SAMPLE_COUNT_MAX)
                sample_count <= 14'd0;
            else
                sample_count <= sample_count + 1'b1;

            // -------------------------------------------------
            // FSM
            // -------------------------------------------------

            case (state)

                // =============================================
                // IDLE
                // =============================================

                IDLE: begin

                    if (sample_count == SAMPLE_COUNT_MAX) begin

                        e_current <= error_q16;

                        accumulator <= 56'sd0;

                        state <= MAC_A1;

                    end

                end

                // =============================================
                // MAC A1
                // =============================================

                MAC_A1: begin

                    accumulator <=
                        accumulator + product_extended;

                    state <= MAC_A2;

                end

                // =============================================
                // MAC A2
                // =============================================

                MAC_A2: begin

                    accumulator <=
                        accumulator + product_extended;

                    state <= MAC_B0;

                end

                // =============================================
                // MAC B0
                // =============================================

                MAC_B0: begin

                    accumulator <=
                        accumulator + product_extended;

                    state <= MAC_B1;

                end

                // =============================================
                // MAC B1
                // =============================================

                MAC_B1: begin

                    accumulator <=
                        accumulator + product_extended;

                    state <= MAC_B2;

                end

                // =============================================
                // MAC B2
                // =============================================

                MAC_B2: begin

                    accumulator <=
                        accumulator + product_extended;

                    state <= ROUND;

                end

                // =============================================
                // ROUND AND UPDATE PID HISTORY
                // =============================================

                ROUND: begin

                    // Update error history
                    e_z2 <= e_z1;
                    e_z1 <= e_current;

                    // Update output history
                    u_z2 <= u_z1;
                    u_z1 <= u_next;

                    u_internal <= u_next;

                    // DAC lower saturation
                    if (u_next <= 24'sd0) begin

                        dac_code <= 8'd0;

                        state <= IDLE;

                    end

                    // DAC upper saturation
                    else if (u_next >= 24'sd163840) begin

                        dac_code <= 8'd255;

                        state <= IDLE;

                    end

                    // Start sequential division
                    else begin

                        div_numerator <= u_next[17:0] + 18'd320;

                        div_remainder <= 11'd0;
                        div_quotient <= 18'd0;
                        div_count <= 5'd0;

                        state <= DIVIDE;

                    end

                end

                // =============================================
                // SEQUENTIAL DIVISION BY 640
                // =============================================

                DIVIDE: begin

                    if (div_bit) begin

                        div_remainder <=
                            remainder_trial - 11'd640;

                    end

                    else begin

                        div_remainder <= remainder_trial;

                    end

                    div_quotient <= quotient_next;

                    div_numerator <=
                        {div_numerator[16:0], 1'b0};

                    if (div_count == 5'd17) begin

                        if (|quotient_next[17:8])
                            dac_code <= 8'd255;
                        else
                            dac_code <= quotient_next[7:0];

                        state <= IDLE;

                    end

                    else begin

                        div_count <= div_count + 1'b1;

                    end

                end

                // =============================================
                // DEFAULT
                // =============================================

                default: begin

                    state <= IDLE;

                end

            endcase

        end

    end

endmodule
