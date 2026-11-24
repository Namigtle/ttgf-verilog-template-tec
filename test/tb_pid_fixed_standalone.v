
`timescale 1us/1ns

module tb_pid_fixed;

    // =====================================================
    // 1. SIGNAL DECLARATIONS
    // =====================================================

    reg clk;
    reg rst_n;
    reg ena;

    reg [7:0] ref_adc;
    reg [7:0] feedback_adc;

    wire [7:0] dac_code;

    integer k;
    integer csv_file;
    integer errors;


    pid_fixed dut (
        .clk(clk),
        .rst_n(rst_n),
        .ena(ena),
        .ref_adc(ref_adc),
        .feedback_adc(feedback_adc),
        .dac_code(dac_code)
    );



    initial begin
        clk = 1'b0;
        forever #100 clk = ~clk;
    end


    task wait_cycles;
        input integer number_cycles;
        integer i;
        begin
            for (i = 0; i < number_cycles; i = i + 1) begin
                @(posedge clk);
                #1;
            end
        end
    endtask



    task log_sample;
        begin

            $display(
                "%0t,%0d,%0d,%0d,%0d",
                $time,
                ref_adc,
                feedback_adc,
                dac_code,
                $signed(dut.u_internal)
            );

            $fdisplay(
                csv_file,
                "%0t,%0d,%0d,%0d,%0d",
                $time,
                ref_adc,
                feedback_adc,
                dac_code,
                $signed(dut.u_internal)
            );

            // Check DAC range
            if (dac_code > 8'd255) begin
                $display("ERROR: DAC out of range");
                errors = errors + 1;
            end

        end
    endtask



    initial begin

        // Initialize signals
        rst_n = 1'b0;
        ena = 1'b0;

        ref_adc = 8'd0;
        feedback_adc = 8'd0;

        errors = 0;

        // Open CSV file
        csv_file = $fopen("pid_results.csv", "w");

        if (csv_file == 0) begin
            $display("ERROR: Cannot open CSV file");
            $finish;
        end

        $fdisplay(
            csv_file,
            "time_ns,reference_adc,feedback_adc,dac_code,pid_internal"
        );

        // Header
        $display("");
        $display("====================================================");
        $display("           PID FIXED POINT TESTBENCH");
        $display("====================================================");
        $display("Time(ns),Ref,Feedback,DAC,PID_Internal");
        $display("----------------------------------------------------");


        wait_cycles(3);

        @(negedge clk);
        rst_n = 1'b1;
        ena = 1'b1;



        @(negedge clk);

        ref_adc = 8'd26;
        feedback_adc = 8'd0;

        $display("");
        $display("TEST 1: Reference = 0.5 V, feedback = 0 V");

        for (k = 0; k < 50; k = k + 1) begin
            @(posedge clk);
            #1;
            log_sample;
        end



        @(negedge clk);

        feedback_adc = 8'd10;

        $display("");
        $display("TEST 2: Feedback ADC = 10");

        for (k = 0; k < 50; k = k + 1) begin
            @(posedge clk);
            #1;
            log_sample;
        end



        @(negedge clk);

        feedback_adc = 8'd20;

        $display("");
        $display("TEST 3: Feedback ADC = 20");

        for (k = 0; k < 50; k = k + 1) begin
            @(posedge clk);
            #1;
            log_sample;
        end



        @(negedge clk);

        feedback_adc = 8'd26;

        $display("");
        $display("TEST 4: Feedback ADC = 26");

        for (k = 0; k < 50; k = k + 1) begin
            @(posedge clk);
            #1;
            log_sample;
        end


        @(negedge clk);
        ena = 1'b0;

        $display("");
        $display("TEST 5: Enable disabled");

        wait_cycles(5);

        log_sample;



        @(negedge clk);
        ena = 1'b1;

        $display("");
        $display("TEST 6: Enable reactivated");

        wait_cycles(10);

        log_sample;

        // -------------------------------------------------
        // FINISH
        // -------------------------------------------------

        $fclose(csv_file);

        $display("");
        $display("====================================================");

        if (errors == 0)
            $display("TESTBENCH PASSED: No basic range errors.");
        else
            $display("TESTBENCH FAILED: %0d errors.", errors);

        $display("CSV file: pid_results.csv");
        $display("====================================================");

        $finish;

    end

    // =====================================================
    // 7. WATCHDOG
    // =====================================================

    initial begin
        #200000;
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule
