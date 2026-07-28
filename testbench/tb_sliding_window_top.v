`timescale 1ns/1ps

module tb_sliding_window;

    // =========================================================
    // CONFIGURATION
    // =========================================================
    parameter DATA_WIDTH = 8;
    parameter IMG_WIDTH  = 6;
    parameter IMG_HEIGHT = 6;

    // =========================================================
    // SYSTEM SIGNALS
    // =========================================================
    reg clk;
    reg rst_n;

    // =========================================================
    // INPUT TO LINE BUFFER
    // =========================================================
    reg                  pixel_valid;
    reg [DATA_WIDTH-1:0] pixel_in;

    // =========================================================
    // FRAME CONTROL
    // =========================================================
    reg window_clear;

    // =========================================================
    // LINE BUFFER OUTPUT
    // =========================================================
    wire [DATA_WIDTH-1:0] row0_pixel;
    wire [DATA_WIDTH-1:0] row1_pixel;
    wire [DATA_WIDTH-1:0] row2_pixel;

    wire rows_valid;
    wire new_row;

    // =========================================================
    // WINDOW GENERATOR INPUT VALID
    // =========================================================
    wire window_pixel_valid;

    assign window_pixel_valid = pixel_valid && rows_valid;

    // =========================================================
    // WINDOW GENERATOR OUTPUT
    // =========================================================
    wire [DATA_WIDTH*9-1:0] patch_data;
    wire                    patch_valid;

    // =========================================================
    // DUT 1: LINE BUFFER
    // =========================================================
    line_buffer_model_ver1 #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    )
    u_line_buffer (
        .clk         (clk),
        .rst_n       (rst_n),

        .pixel_valid (pixel_valid),
        .pixel_in    (pixel_in),

        .row0_pixel  (row0_pixel),
        .row1_pixel  (row1_pixel),
        .row2_pixel  (row2_pixel),

        .rows_valid  (rows_valid),
        .new_row     (new_row)
    );

    // =========================================================
    // DUT 2: WINDOW GENERATOR
    // =========================================================
    window_generator #(
        .DATA_WIDTH(DATA_WIDTH)
    )
    u_window_generator (
        .clk              (clk),
        .rst_n            (rst_n),

        .row0_pixel       (row0_pixel),
        .row1_pixel       (row1_pixel),
        .row2_pixel       (row2_pixel),

        .pixel_valid      (window_pixel_valid),
        .col_window_clear (new_row),
        .window_clear     (window_clear),

        .patch_data       (patch_data),
        .patch_valid      (patch_valid)
    );

    // =========================================================
    // CLOCK GENERATION (10ns period)
    // =========================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // MONITOR: THEO DÕI VÀ IN PATCH M?I KHI PATCH_VALID = 1
    // (??c l?p tuy?t ??i v?i Task g?i pixel - Ch?ng l?ch Timing)
    // =========================================================
    always @(posedge clk) begin
        if (rst_n && patch_valid) begin
            $display("\n--------------------------------------------------");
            $display("[TIME %0t ns] >>> PATCH VALID DETECTED <<<", $time);
            $display("        +-----+-----+-----+");
            $display("        | %3d | %3d | %3d |", patch_data[71:64], patch_data[63:56], patch_data[55:48]);
            $display("        +-----+-----+-----+");
            $display("        | %3d | %3d | %3d |", patch_data[47:40], patch_data[39:32], patch_data[31:24]);
            $display("        +-----+-----+-----+");
            $display("        | %3d | %3d | %3d |", patch_data[23:16], patch_data[15:8],  patch_data[7:0]);
            $display("        +-----+-----+-----+");
        end
    end

    // =========================================================
    // SEND ONE PIXEL TASK (?ã ??ng b? hoá theo Posedge)
    // =========================================================
    task send_pixel;
        input integer row;
        input integer col;
        begin
            @(posedge clk);
            #1; // B?m d? li?u ngay sau c?nh lên clock
            pixel_valid = 1'b1;
            pixel_in    = row * 10 + col;
        end
    endtask

    // =========================================================
    // SEND ONE IMAGE ROW TASK (?ã x? lý kho?ng ngh? New Row)
    // =========================================================
    task send_row;
        input integer row;
        integer col;
        begin
            $display("\n==================================================");
            $display("                 START ROW %0d", row);
            $display("==================================================");

            for (col = 0; col < IMG_WIDTH; col = col + 1) begin
                send_pixel(row, col);
            end

            // Ng?t stream sau khi b?m ?? 1 hàng
            @(posedge clk);
            #1;
            pixel_valid = 1'b0;
            pixel_in    = 0;

            // Ch? 2 chu k? Clock ?? Line Buffer kích ho?t row_end_tick và gi?t new_row
            repeat (2) @(posedge clk);
            
            if (new_row) begin
                $display(">>> NEW ROW PULSE CAPTURED SAFELY");
            end

            // Ngh? thêm 1 chu k? ?? xung new_row h? v? 0 hoàn toàn tr??c khi sang hàng m?i
            repeat (1) @(posedge clk);

            $display("**************** END ROW %0d ****************", row);
        end
    endtask

    // =========================================================
    // MAIN SIMULATION PROCESS
    // =========================================================
    integer r;

    initial begin
        // Init
        rst_n        = 1'b0;
        pixel_valid  = 1'b0;
        pixel_in     = 0;
        window_clear = 1'b0;

        #20;
        rst_n = 1'b1;

        // Reset Frame
        @(posedge clk);
        #1;
        window_clear = 1'b1;
        @(posedge clk);
        #1;
        window_clear = 1'b0;

        $display("\n##################################################");
        $display("                 START 6x6 IMAGE");
        $display("##################################################");

        // G?i toàn b? ?nh
        for (r = 0; r < IMG_HEIGHT; r = r + 1) begin
            send_row(r);
        end

        repeat (5) @(posedge clk);
        $display("\n##################################################");
        $display("              SIMULATION COMPLETE");
        $display("##################################################");
        $finish;
    end

endmodule