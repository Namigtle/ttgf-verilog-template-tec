`default_nettype none

module pi_fixed (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ena,

    input  wire [7:0] ref_adc,
    input  wire [7:0] feedback_adc,

    output reg  [7:0] dac_code
);

    // =====================================================
    // PARAMETERS
    // =====================================================

    // Clock = 50 MHz
    // Sampling frequency = 5 kHz
    // Ts = 200 us

    localparam [13:0] SAMPLE_MAX = 14'd9999;

    // PI coefficients:
    // Kp = 1/16
    // Ki = 78.125
    //
    // Tustin:
    // C0 =  9/128
    // C1 = -7/128
    //
    // u[k] = u[k-1] + (9e[k] - 7e[k-1])/128

    localparam signed [17:0] U_MAX = 18'sd32640;

    // =====================================================
    // SAMPLING COUNTER
    // =====================================================

    reg [13:0] sample_count;

    // =====================================================
    // PIPELINE CONTROL
    // =====================================================

    localparam [2:0]
        IDLE       = 3'd0,
        CALC_ERROR = 3'd1,
        CALC_TERMS = 3'd2,
        CALC_DELTA = 3'd3,
        CALC_U     = 3'd4,
        UPDATE_DAC = 3'd5;

    reg [2:0] state;

    // =====================================================
    // STAGE 1: ADC INPUT REGISTERS
    // =====================================================

    reg [7:0] ref_sample;
    reg [7:0] feedback_sample;

    // =====================================================
    // STAGE 2: ERROR CALCULATION
    // =====================================================

    reg signed [8:0] error_reg;
    reg signed [8:0] error_previous;

    wire signed [8:0] error_calculated;

    assign error_calculated =
        $signed({1'b0, ref_sample}) -
        $signed({1'b0, feedback_sample});

    // =====================================================
    // STAGE 3: PI TERMS
    // =====================================================

    wire signed [12:0] error_extended;
    wire signed [12:0] previous_extended;

    assign error_extended =
        {{4{error_reg[8]}}, error_reg};

    assign previous_extended =
        {{4{error_previous[8]}}, error_previous};

    wire signed [12:0] term_current_calc;
    wire signed [12:0] term_previous_calc;

    assign term_current_calc =
        (error_extended <<< 3) + error_extended;

    assign term_previous_calc =
        (previous_extended <<< 3) - previous_extended;

    reg signed [12:0] term_current_reg;
    reg signed [12:0] term_previous_reg;

    // =====================================================
    // STAGE 4: PI INCREMENT
    // =====================================================

    wire signed [12:0] delta_calculated;

    assign delta_calculated =
        term_current_reg - term_previous_reg;

    reg signed [12:0] delta_reg;

    // =====================================================
    // STAGE 5: CONTROL ACCUMULATOR
    // =====================================================

    reg [15:0] u_accumulator;

    wire signed [17:0] accumulator_extended;
    wire signed [17:0] delta_extended;

    assign accumulator_extended =
        {2'b00, u_accumulator};

    assign delta_extended =
        {{5{delta_reg[12]}}, delta_reg};

    wire signed [17:0] u_calculated;

    assign u_calculated =
        accumulator_extended + delta_extended;

    reg signed [17:0] u_candidate;

    // =====================================================
    // DAC ROUNDING
    // =====================================================

    wire [7:0] rounded_dac;

    assign rounded_dac =
        (u_candidate + 18'sd64) >>> 7;

    // =====================================================
    // SEQUENTIAL PIPELINE
    // =====================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            sample_count       <= 14'd0;
            state              <= IDLE;

            ref_sample         <= 8'd0;
            feedback_sample    <= 8'd0;

            error_reg          <= 9'sd0;
            error_previous     <= 9'sd0;

            term_current_reg   <= 13'sd0;
            term_previous_reg  <= 13'sd0;

            delta_reg          <= 13'sd0;

            u_accumulator      <= 16'd0;
            u_candidate        <= 18'sd0;

            dac_code           <= 8'd0;

        end

        else if (ena) begin

            // ---------------------------------------------
            // Sampling counter
            // ---------------------------------------------

            if (sample_count == SAMPLE_MAX)
                sample_count <= 14'd0;
            else
                sample_count <= sample_count + 1'b1;

            // ---------------------------------------------
            // Pipeline state machine
            // ---------------------------------------------

            case (state)

                // =========================================
                // IDLE: Capture ADC values
                // =========================================

                IDLE: begin

                    if (sample_count == SAMPLE_MAX) begin

                        ref_sample      <= ref_adc;
                        feedback_sample <= feedback_adc;

                        state <= CALC_ERROR;

                    end

                end

                // =========================================
                // STAGE 2: Calculate error
                // =========================================

                CALC_ERROR: begin

                    error_reg <= error_calculated;

                    state <= CALC_TERMS;

                end

                // =========================================
                // STAGE 3: Calculate PI terms
                // =========================================

                CALC_TERMS: begin

                    term_current_reg  <= term_current_calc;
                    term_previous_reg <= term_previous_calc;

                    error_previous <= error_reg;

                    state <= CALC_DELTA;

                end

                // =========================================
                // STAGE 4: Calculate delta u
                // =========================================

                CALC_DELTA: begin

                    delta_reg <= delta_calculated;

                    state <= CALC_U;

                end

                // =========================================
                // STAGE 5: Calculate candidate output
                // =========================================

                CALC_U: begin

                    u_candidate <= u_calculated;

                    state <= UPDATE_DAC;

                end

                // =========================================
                // STAGE 6: Saturation and DAC update
                // =========================================

                UPDATE_DAC: begin

                    if (u_candidate <= 18'sd0) begin

                        u_accumulator <= 16'd0;
                        dac_code      <= 8'd0;

                    end

                    else if (u_candidate >= U_MAX) begin

                        u_accumulator <= 16'd32640;
                        dac_code      <= 8'd255;

                    end

                    else begin

                        u_accumulator <= u_candidate[15:0];
                        dac_code      <= rounded_dac;

                    end

                    state <= IDLE;

                end

                default: begin

                    state <= IDLE;

                end

            endcase

        end

    end

endmodule

`default_nettype wire