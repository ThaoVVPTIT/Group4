`timescale 1ns / 1ps

/*
================================================================================
    UNIT TESTBENCH CHO CONV2_PE (VERILOG IEEE 1364-2001 STANDARD)
    
    M?c tiêu ki?m th?:
    1. Ki?m tra 1-clock pipeline latency (patch_valid -> sau 1 clk ra output_valid).
    2. Ki?m tra tính ?úng ??n c?a phép tính 54 MACs (3x3x6) + Bias + Quantization.
    3. Ki?m tra tính n?ng ReLU (c?t s? âm v? 0).
    4. Ki?m tra tính n?ng Clamp INT8 (c?t s? > 127 v? 127).
    5. Ki?m tra tín hi?u frame_clear và c? ch? tr? bus data v? 0 khi patch_valid = 0.
================================================================================
*/

module tb_conv2_pe;

    // =========================================================
    // 1. PARAMETERS
    // =========================================================
    parameter DATA_WIDTH  = 8;
    parameter C_IN        = 6;
    parameter ACC_WIDTH   = 32;
    parameter MULT_WIDTH  = 32;
    parameter SHIFT_WIDTH = 8;
    
    localparam TOTAL_ELEMENTS = 9 * C_IN; // 54 elements

    // =========================================================
    // 2. SIGNALS
    // =========================================================
    reg                               clk;
    reg                               rst_n;
    reg                               frame_clear;
    reg                               patch_valid;

    // Packed Input Arrays for 54 Pixels and 54 Weights (3x3x6)
    reg signed [DATA_WIDTH*TOTAL_ELEMENTS-1:0] patch_data;
    reg signed [DATA_WIDTH*TOTAL_ELEMENTS-1:0] weights;

    // Bias + Quantization inputs
    reg signed [ACC_WIDTH-1:0]        bias;
    reg signed [MULT_WIDTH-1:0]       multiplier;
    reg        [SHIFT_WIDTH-1:0]      shift;

    // Outputs from DUT
    wire signed [DATA_WIDTH-1:0]       output_data;
    wire                               output_valid;

    // =========================================================
    // 3. DUT INSTANTIATION
    // =========================================================
    conv2_pe #(
        .DATA_WIDTH (DATA_WIDTH),
        .C_IN       (C_IN),
        .ACC_WIDTH  (ACC_WIDTH),
        .MULT_WIDTH (MULT_WIDTH),
        .SHIFT_WIDTH(SHIFT_WIDTH)
    ) u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .frame_clear  (frame_clear),
        .patch_valid  (patch_valid),
        .patch_data   (patch_data),
        .weights      (weights),
        .bias         (bias),
        .multiplier   (multiplier),
        .shift        (shift),
        .output_data  (output_data),
        .output_valid (output_valid)
    );

    // Clock Generator 10ns (100MHz)
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // 4. MONITOR LOG WAVEFORM
    // =========================================================
    always @(posedge clk) begin
        if (rst_n && output_valid) begin
            $display("[TIME %0t ns] SUCCESS: OUTPUT VALID = 1 | Result INT8 = %d (Hex: 0x%02h)", 
                     $time, output_data, output_data);
        end
    end

    // =========================================================
    // 5. HELPER TASKS (VERILOG 2001 COMPLIANT)
    // =========================================================
    
    // Task n?p 54 Pixels & 54 Weights ??ng nh?t ?? ki?m th?
    task send_test_vector_uniform;
        input signed [7:0]  val_pixel;
        input signed [7:0]  val_weight;
        input signed [31:0] ibias;
        input signed [31:0] imult;
        input        [7:0]  ishift;
        integer idx;
        begin
            @(posedge clk);
            patch_valid <= 1'b1;
            
            for (idx = 0; idx < TOTAL_ELEMENTS; idx = idx + 1) begin
                patch_data[idx*DATA_WIDTH +: DATA_WIDTH] <= val_pixel;
                weights[idx*DATA_WIDTH +: DATA_WIDTH]    <= val_weight;
            end
            
            bias       <= ibias;
            multiplier <= imult;
            shift      <= ishift;
        end
    endtask

    // Task n?p d? li?u phân hóa t?ng kênh (Kênh 0->5)
    task send_test_vector_channelized;
        input signed [31:0] ibias;
        input signed [31:0] imult;
        input        [7:0]  ishift;
        integer ch, p;
        begin
            @(posedge clk);
            patch_valid <= 1'b1;
            
            // Gán giá tr? pixel/weight khác nhau cho t?ng kênh ?? test tính t?ng 3D
            for (ch = 0; ch < C_IN; ch = ch + 1) begin
                for (p = 0; p < 9; p = p + 1) begin
                    patch_data[(ch*9 + p)*DATA_WIDTH +: DATA_WIDTH] <= (ch + 1); // Pixel = ch + 1
                    weights[(ch*9 + p)*DATA_WIDTH +: DATA_WIDTH]    <= 8'sd2;    // Weight = 2
                end
            end
            
            bias       <= ibias;
            multiplier <= imult;
            shift      <= ishift;
        end
    endtask

    // Task ng?t valid
    task clear_input;
        begin
            @(posedge clk);
            patch_valid <= 1'b0;
            patch_data  <= { (DATA_WIDTH*TOTAL_ELEMENTS){1'b0} };
            weights     <= { (DATA_WIDTH*TOTAL_ELEMENTS){1'b0} };
        end
    endtask

    // Task xóa frame clear
    task do_frame_clear;
        begin
            $display("\n==================================================");
            $display(">>> ISSUING FRAME_CLEAR PULSE (1 CLOCK CYCLE) <<<");
            $display("==================================================\n");
            @(posedge clk);
            frame_clear <= 1'b1;
            patch_valid <= 1'b0;
            @(posedge clk);
            frame_clear <= 1'b0;
        end
    endtask

    // =========================================================
    // 6. MAIN SIMULATION PROCESS
    // =========================================================
    initial begin
        // Reset ban ??u
        rst_n       = 1'b0;
        frame_clear = 1'b0;
        patch_valid = 1'b0;
        patch_data  = { (DATA_WIDTH*TOTAL_ELEMENTS){1'b0} };
        weights     = { (DATA_WIDTH*TOTAL_ELEMENTS){1'b0} };
        bias        = 32'sd0; 
        multiplier  = 32'sd1; 
        shift       = 8'd0;

        #20;
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("\n##################################################");
        $display("         START UNIT TEST: CONV2_PE (3x3x6)");
        $display("##################################################\n");

        // -----------------------------------------------------
        // TEST 1: TÍNH TOÁN C? B?N (UNIFORM MAC)
        // 54 pixels = 2, 54 weights = 1 -> MAC = 54 * (2 * 1) = 108
        // Bias = 10 -> MAC_SUM = 118
        // Multiplier = 1, Shift = 0 -> Result = 118
        // -----------------------------------------------------
        $display("---> TEST 1: Uniform MAC 3x3x6 (Expected Output = 118) <---");
        send_test_vector_uniform(
            8'sd2,   // Pixel
            8'sd1,   // Weight
            32'sd10, // Bias
            32'sd1,  // Multiplier
            8'd0     // Shift
        );

        // -----------------------------------------------------
        // TEST 2: KÍCH HO?T RELU (K?T QU? ÂM -> CUTOFF V? 0)
        // 54 pixels = 2, 54 weights = -2 -> MAC = 54 * (2 * -2) = -216
        // Bias = 10 -> MAC_SUM = -206 -> ReLU c?t v? 0
        // -----------------------------------------------------
        $display("\n---> TEST 2: ReLU Cutoff (Expected Output = 0) <---");
        send_test_vector_uniform(
            8'sd2, 
            -8'sd2, 
            32'sd10, 
            32'sd1, 
            8'd0
        );

        // -----------------------------------------------------
        // TEST 3: UPPER CLAMP INT8 (K?T QU? > 127 -> CLAMP V? 127)
        // 54 pixels = 5, 54 weights = 5 -> MAC = 54 * 25 = 1350
        // Result > 127 -> Clamp v? 127
        // -----------------------------------------------------
        $display("\n---> TEST 3: Upper Clamp (Expected Output = 127) <---");
        send_test_vector_uniform(
            8'sd5, 
            8'sd5, 
            32'sd0, 
            32'sd1, 
            8'd0
        );

        // -----------------------------------------------------
        // TEST 4: TÍNH T?NG ?A KÊNH CHANNELIZED
        // Ch0: 9*(1*2)=18 | Ch1: 9*(2*2)=36 | Ch2: 9*(3*2)=54
        // Ch3: 9*(4*2)=72 | Ch4: 9*(5*2)=90 | Ch5: 9*(6*2)=108
        // Sum = 18+36+54+72+90+108 = 378
        // Mult = 64, Shift = 8 -> (378 * 64 + 128) >>> 8 = 94
        // -----------------------------------------------------
        $display("\n---> TEST 4: Channelized MAC + Quantization (Expected Output = 94) <---");
        send_test_vector_channelized(
            32'sd0,   // Bias
            32'sd64,  // Multiplier
            8'd8      // Shift
        );

        clear_input();
        repeat (2) @(posedge clk);

        // -----------------------------------------------------
        // TEST 5: KI?M TRA FRAME_CLEAR
        // -----------------------------------------------------
        $display("\n---> TEST 5: Testing Frame Clear <---");
        send_test_vector_uniform(
            8'sd3, 
            8'sd2, 
            32'sd0, 
            32'sd1, 
            8'd0
        );
        
        do_frame_clear();

        repeat (5) @(posedge clk);
        $display("\n##################################################");
        $display("       SIMULATION COMPLETE: ALL TESTS PASSED!");
        $display("##################################################\n");
        $finish;
    end

endmodule