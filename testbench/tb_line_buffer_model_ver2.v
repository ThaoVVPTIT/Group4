`timescale 1ns/1ps

/*
================================================================================
  Mô ph?ng 6 Ma Tr?n Input Feature Map (6x6) d?ng HEX cho C_IN = 6
  D? li?u sinh ra theo công th?c Task: pixel_in = ch * 100 + row * 10 + col
================================================================================

--- CHANNEL 0 (channel_idx = 0) ---
Row 0:  8'h00  8'h01  8'h02  8'h03  8'h04  8'h05
Row 1:  8'h0A  8'h0B  8'h0C  8'h0D  8'h0E  8'h0F
Row 2:  8'h14  8'h15  8'h16  8'h17  8'h18  8'h19
Row 3:  8'h1E  8'h1F  8'h20  8'h21  8'h22  8'h23
Row 4:  8'h28  8'h29  8'h2A  8'h2B  8'h2C  8'h2D
Row 5:  8'h32  8'h33  8'h34  8'h35  8'h36  8'h37

--- CHANNEL 1 (channel_idx = 1) ---
Row 0:  8'h64  8'h65  8'h66  8'h67  8'h68  8'h69
Row 1:  8'h6E  8'h6F  8'h70  8'h71  8'h72  8'h73
Row 2:  8'h78  8'h79  8'h7A  8'h7B  8'h7C  8'h7D
Row 3:  8'h82  8'h83  8'h84  8'h85  8'h86  8'h87
Row 4:  8'h8C  8'h8D  8'h8E  8'h8F  8'h90  8'h91
Row 5:  8'h96  8'h97  8'h98  8'h99  8'h9A  8'h9B

--- CHANNEL 2 (channel_idx = 2) ---
Row 0:  8'hC8  8'hC9  8'hCA  8'hCB  8'hCC  8'hCD
Row 1:  8'hD2  8'hD3  8'hD4  8'hD5  8'hD6  8'hD7
Row 2:  8'hDC  8'hDD  8'hDE  8'hDF  8'hE0  8'hE1
Row 3:  8'hE6  8'hE7  8'hE8  8'hE9  8'hEA  8'hEB
Row 4:  8'hF0  8'hF1  8'hF2  8'hF3  8'hF4  8'hF5
Row 5:  8'hFA  8'hFB  8'hFC  8'hFD  8'hFE  8'hFF

--- CHANNEL 3 (channel_idx = 3) [Truncate 8-bit] ---
Row 0:  8'h2C  8'h2D  8'h2E  8'h2F  8'h30  8'h31
Row 1:  8'h36  8'h37  8'h38  8'h39  8'h3A  8'h3B
Row 2:  8'h40  8'h41  8'h42  8'h43  8'h44  8'h45
Row 3:  8'h4A  8'h4B  8'h4C  8'h4D  8'h4E  8'h4F
Row 4:  8'h54  8'h55  8'h56  8'h57  8'h58  8'h59
Row 5:  8'h5E  8'h5F  8'h60  8'h61  8'h62  8'h63

--- CHANNEL 4 (channel_idx = 4) [Truncate 8-bit] ---
Row 0:  8'h90  8'h91  8'h92  8'h93  8'h94  8'h95
Row 1:  8'h9A  8'h9B  8 me  8'h9D  8'h9E  8'h9F
Row 1:  8'h9A  8'h9B  8'h9C  8'h9D  8'h9E  8'h9F
Row 2:  8'hA4  8'hA5  8'hA6  8'hA7  8'hA8  8'hA9
Row 3:  8'hAE  8'hAF  8'hB0  8'hB1  8'hB2  8'hB3
Row 4:  8'hB8  8'hB9  8'hBA  8'hBB  8'hBC  8'hBD
Row 5:  8'hC2  8'hC3  8'hC4  8'hC5  8'hC6  8'hC7

--- CHANNEL 5 (channel_idx = 5) [Truncate 8-bit] ---
Row 0:  8'hF4  8'hF5  8'hF6  8'hF7  8'hF8  8'hF9
Row 1:  8'hFE  8'hFF  8'h00  8'h01  8'h02  8'h03
Row 2:  8'h08  8'h09  8'h0A  8'h0B  8'h0C  8'h0D
Row 3:  8'h12  8'h13  8'h14  8'h15  8'h16  8'h17
Row 4:  8'h1C  8'h1D  8'h1E  8'h1F  8'h20  8'h21
Row 5:  8'h26  8'h27  8'h28  8'h29  8'h2A  8'h2B
================================================================================
*/

module tb_line_buffer_ver2;

    // =========================================================
    // PARAMETERS (CÓ TH? THAY ??I ?? TEST D? DÀNG)
    // =========================================================
    parameter DATA_WIDTH = 8;
    parameter IMG_WIDTH  = 6;   // ??i thành 28 n?u mu?n ch?y ?nh chu?n Conv2
    parameter IMG_HEIGHT = 6;   // ??i thành 28 n?u mu?n ch?y ?nh chu?n Conv2
    parameter C_IN       = 6;   // ??i C_IN = 1 (Conv1) ho?c C_IN = 6 (Conv2)

    localparam CHAN_WIDTH = (C_IN <= 1) ? 1 : $clog2(C_IN);

    // =========================================================
    // SIGNALS
    // =========================================================
    reg                      clk;
    reg                      rst_n;
    reg                      pixel_valid;
    reg  [DATA_WIDTH-1:0]    pixel_in;

    wire [DATA_WIDTH-1:0]    row0_pixel;
    wire [DATA_WIDTH-1:0]    row1_pixel;
    wire [DATA_WIDTH-1:0]    row2_pixel;
    wire                     rows_valid;
    wire                     new_row;
    wire [CHAN_WIDTH-1:0]    channel_idx;
    wire                     frame_c_done;

    // =========================================================
    // DUT INSTANTIATION
    // =========================================================
    line_buffer_model_ver2 #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .C_IN      (C_IN)
    ) u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .pixel_valid  (pixel_valid),
        .pixel_in     (pixel_in),
        .row0_pixel   (row0_pixel),
        .row1_pixel   (row1_pixel),
        .row2_pixel   (row2_pixel),
        .rows_valid   (rows_valid),
        .new_row      (new_row),
        .channel_idx  (channel_idx),
        .frame_c_done (frame_c_done)
    );

    // Clock 10ns
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // MONITOR: THEO DÕI VÀ IN TÍN HI?U RA CONSOLE
    // =========================================================
    always @(posedge clk) begin
        if (rst_n && pixel_valid) begin
            $display("[TIME %0t ns] CH=%0d | IN=%3d | ROW0=%3d | ROW1=%3d | ROW2=%3d | ROWS_VALID=%b",
                     $time, channel_idx, pixel_in, row0_pixel, row1_pixel, row2_pixel, rows_valid);
        end
        if (rst_n && new_row) begin
            $display(">>> [PULSE] NEW ROW PULSE DETECTED <<<");
        end
        if (rst_n && frame_c_done) begin
            $display("\n==================================================");
            $display(">>> [PULSE] FRAME_C_DONE DETECTED! ALL %0d CHANNELS PROCESSED <<<", C_IN);
            $display("==================================================\n");
        end
    end

    // =========================================================
    // TASKS B?M D? LI?U
    // =========================================================
    task send_pixel;
        input integer ch;
        input integer row;
        input integer col;
        begin
            @(posedge clk);
            #1;
            pixel_valid = 1'b1;
            // Công th?c t?o Pixel: Channel 0: 0..35 | Channel 1: 100..135 | Channel 2: 200..235...
            pixel_in = ch * 100 + row * 10 + col;
        end
    endtask

    task send_channel;
        input integer ch;
        integer r, c;
        begin
            $display("\n--------------------------------------------------");
            $display("START STREAMING CHANNEL %0d (C_IN = %0d)", ch, C_IN);
            $display("--------------------------------------------------");
            
            for (r = 0; r < IMG_HEIGHT; r = r + 1) begin
                for (c = 0; c < IMG_WIDTH; c = c + 1) begin
                    send_pixel(ch, r, c);
                end
                
                // K?t thúc 1 hàng: H? pixel_valid
                @(posedge clk); #1;
                pixel_valid = 1'b0;
                pixel_in    = 0;
                
                // Ngh? 2 chu k? clock ?? new_row x? s?ch an toàn
                repeat (2) @(posedge clk);
            end
        end
    endtask

    // =========================================================
    // MAIN SIMULATION PROCESS
    // =========================================================
    integer c_idx;

    initial begin
        // Reset
        rst_n       = 1'b0;
        pixel_valid = 1'b0;
        pixel_valid = 1'b0;
        pixel_in    = 0;

        #20;
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("\n##################################################");
        $display("   TESTBENCH LINE_BUFFER_MODEL_VER2 (C_IN = %0d)", C_IN);
        $display("##################################################");

        // B?m l?n l??t t?ng Channel
        for (c_idx = 0; c_idx < C_IN; c_idx = c_idx + 1) begin
            send_channel(c_idx);
        end

        repeat (5) @(posedge clk);
        $display("\n##################################################");
        $display("              SIMULATION COMPLETE");
        $display("##################################################");
        $finish;
    end

endmodule