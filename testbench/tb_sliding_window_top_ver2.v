`timescale 1ns/1ps

/*
================================================================================
  INTEGRATION TESTBENCH FOR TOP_SLIDING_WINDOW_VER1
  
  M?c tiêu:
  - B?m lu?ng Stream Pixel ??i di?n cho 6 Channels (Input Feature Maps).
  - Quan sát xung patch_cin_valid và ki?m tra Tensor output 3x3xC_IN (432-bit).
================================================================================
*/

module tb_top_sliding_window_ver1;

    // =========================================================
    // PARAMETERS (CÓ TH? THAY ??I THEO LAYER CONV)
    // =========================================================
    parameter DATA_WIDTH = 8;
    parameter IMG_WIDTH  = 6;   // ??i thành 28 n?u test ?nh chu?n Conv2
    parameter IMG_HEIGHT = 6;   // ??i thành 28 n?u test ?nh chu?n Conv2
    parameter C_IN       = 6;   // 1 cho Conv1, 6 cho Conv2

    localparam CHAN_WIDTH = (C_IN <= 1) ? 1 : $clog2(C_IN);

    // =========================================================
    // SIGNALS FOR TOP MODULE INTERFACE
    // =========================================================
    reg                         clk;
    reg                         rst_n;
    reg                         pixel_valid;
    reg  [DATA_WIDTH-1:0]       pixel_in;

    wire [DATA_WIDTH*9*C_IN-1:0] patch_cin_data;
    wire                        patch_cin_valid;
    wire [CHAN_WIDTH-1:0]       channel_idx;
    wire                        frame_c_done;

    // =========================================================
    // TOP MODULE INSTANTIATION (?ÚNG THEO YÊU C?U C?A B?N)
    // =========================================================
    top_sliding_window_ver1 #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .C_IN      (C_IN)
    ) u_top (
        .clk             (clk),
        .rst_n           (rst_n),
        .pixel_valid     (pixel_valid),
        .pixel_in        (pixel_in),
        .patch_cin_data  (patch_cin_data),
        .patch_cin_valid (patch_cin_valid),
        .channel_idx     (channel_idx),
        .frame_c_done    (frame_c_done)
    );

    // Clock Generator (10ns period)
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // MONITOR: DISPLAY OUTPUT TENSOR WHEN VALID = 1
    // =========================================================
    integer c_log;
    always @(posedge clk) begin
        if (rst_n && patch_cin_valid) begin
            $display("\n==================================================================================");
            $display("[TIME %0t ns] ? TOP OUTPUT VALID: FULL TENSOR 3x3x%0d READY FOR PE ARRAY!", $time, C_IN);
            $display("==================================================================================");
            for (c_log = 0; c_log < C_IN; c_log = c_log + 1) begin
                $display("--- CHANNEL %0d ---", c_log);
                $display("  | %02h  %02h  %02h |", 
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*8 +: DATA_WIDTH],
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*7 +: DATA_WIDTH],
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*6 +: DATA_WIDTH]);
                $display("  | %02h  %02h  %02h |", 
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*5 +: DATA_WIDTH],
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*4 +: DATA_WIDTH],
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*3 +: DATA_WIDTH]);
                $display("  | %02h  %02h  %02h |", 
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*2 +: DATA_WIDTH],
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*1 +: DATA_WIDTH],
                         patch_cin_data[DATA_WIDTH*9*c_log + 0           +: DATA_WIDTH]);
            end
            $display("==================================================================================\n");
        end
    end

    // =========================================================
    // TASKS FOR STREAMING PIXEL DATA
    // =========================================================
    task send_pixel;
        input integer ch;
        input integer row;
        input integer col;
        begin
            @(posedge clk);
//            #1;
            pixel_valid = 1'b1;
            pixel_in    = ch * 100 + row * 10 + col;
        end
    endtask

    task send_channel;
        input integer ch;
        integer r, c;
        begin
            $display("--------------------------------------------------");
            $display("---> START STREAMING CHANNEL %0d (C_IN = %0d) <---", ch, C_IN);
            $display("--------------------------------------------------");
            for (r = 0; r < IMG_HEIGHT; r = r + 1) begin
                for (c = 0; c < IMG_WIDTH; c = c + 1) begin
                    send_pixel(ch, r, c);
                end
                
                // End of Row: Lower pixel_valid
                @(posedge clk); //#1;
                pixel_valid = 1'b0;
                pixel_in    = 0; // delay 1 cycle
                
                // Pause 2 cycles for clean row-transition
              //  repeat (2) @(posedge clk); // delay 2 cycle
            end
        end
    endtask

    // =========================================================
    // MAIN SIMULATION FLOW
    // =========================================================
    integer c_idx;

    initial begin
        // Reset initialization
        rst_n       = 1'b0;
        pixel_valid = 1'b0;
        pixel_in    = 0;

        #20;
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("\n##################################################");
        $display("   START INTEGRATION SIMULATION: TOP MODULE");
        $display("##################################################\n");

        // Stream all C_IN channels sequentially
        for (c_idx = 0; c_idx < C_IN; c_idx = c_idx + 1) begin
            send_channel(c_idx);
        end

        repeat (10) @(posedge clk);
        $display("\n##################################################");
        $display("              SIMULATION COMPLETE");
        $display("##################################################");
        $finish;
    end

endmodule