
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

    // External clock: 50 MHz
    // PID/PI sampling frequency: 5 kHz
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

    // =====================================================
    // SAMPLING COUNTER
    // =====================================================

    reg [13:0] sample_count;

    // =====================================================
    // ERROR CALCULATION
    // =====================================================

    wire signed [8:0] error_now;

    assign error_now =
        $signed({1'b0, ref_adc}) -
        $signed({1'b0, feedback_adc});

    reg signed [8:0] error_previous;

    // Sign extension to 13 bits
    wire signed [12:0] error_extended;
    wire signed [12:0] error_previous_extended;

    assign error_extended =
        {{4{error_now[8]}}, error_now};

    assign error_previous_extended =
        {{4{error_previous[8]}}, error_previous};

    // =====================================================
    // PI INCREMENT
    // =====================================================

    // 9*e[k] = 8*e[k] + e[k]
    wire signed [12:0] term_current;

    assign term_current =
        (error_extended <<< 3) + error_extended;

    // 7*e[k-1] = 8*e[k-1] - e[k-1]
    wire signed [12:0] term_previous;

    assign term_previous =
        (error_previous_extended <<< 3)
        - error_previous_extended;

    // Delta u = 9*e[k] - 7*e[k-1]
    wire signed [12:0] delta_u;

    assign delta_u =
        term_current - term_previous;

    // =====================================================
    // INTEGRAL / CONTROL ACCUMULATOR
    // =====================================================

    // Q7 representation:
    // One DAC unit = 128 accumulator units.
    //
    // Maximum output = 255*128 = 32640.

    reg [15:0] u_accumulator;

    wire signed [17:0] accumulator_extended;
    wire signed [17:0] delta_extended;

    assign accumulator_extended =
        {2'b00, u_accumulator};

    assign delta_extended =
        {{5{delta_u[12]}}, delta_u};

    wire signed [17:0] u_candidate;

    assign u_candidate =
        accumulator_extended + delta_extended;

    // Maximum allowed accumulator value
    localparam signed [17:0] U_MAX = 18'sd32640;

    // Rounded DAC conversion:
    // DAC = round(u_accumulator / 128)

    wire signed [17:0] rounded_candidate;

    assign rounded_candidate =
        (u_candidate + 18'sd64) >>> 7;

    // =====================================================
    // SEQUENTIAL PI CONTROLLER
    // =====================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            sample_count    <= 14'd0;
            error_previous  <= 9'sd0;
            u_accumulator   <= 16'd0;
            dac_code        <= 8'd0;

        end

        else if (ena) begin

            if (sample_count == SAMPLE_MAX) begin

                sample_count <= 14'd0;

                // Update previous error
                error_previous <= error_now;

                // Lower saturation limit
                if (u_candidate <= 18'sd0) begin

                    u_accumulator <= 16'd0;
                    dac_code      <= 8'd0;

                end

                // Upper saturation limit
                else if (u_candidate >= U_MAX) begin

                    u_accumulator <= 16'd32640;
                    dac_code      <= 8'd255;

                end

                // Normal PI operation
                else begin

                    u_accumulator <= u_candidate[15:0];
                    dac_code      <= rounded_candidate[7:0];

                end

            end

            else begin

                sample_count <= sample_count + 1'b1;

            end

        end

    end

endmodule

`default_nettype wire
