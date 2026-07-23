`timescale 1ns/1ps

module tb_sliding_window_top;

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
    // INPUT STREAM
    // =========================================================

    reg                   pixel_valid;
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
    // WINDOW GENERATOR CONTROL
    // =========================================================

    wire window_pixel_valid;


    assign window_pixel_valid =
           pixel_valid && rows_valid;


    // =========================================================
    // WINDOW GENERATOR OUTPUT
    // =========================================================

    wire [DATA_WIDTH*9-1:0] patch_data;
    wire                    patch_valid;


    // =========================================================
    // DUT 1: LINE BUFFER
    // =========================================================

    line_buffer_model #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH (IMG_WIDTH)
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

        .pixel_valid      (window_pixel_valid),

        .col_window_clear (new_row),

        .window_clear     (window_clear),

        .row0_pixel       (row0_pixel),
        .row1_pixel       (row1_pixel),
        .row2_pixel       (row2_pixel),

        .patch_data       (patch_data),
        .patch_valid      (patch_valid)
    );


    // =========================================================
    // CLOCK
    // =========================================================

    initial begin

        clk = 1'b0;

        forever #5 clk = ~clk;

    end


    // =========================================================
    // DISPLAY PATCH
    // =========================================================

    task display_patch;

    begin

        $display("");

        $display("        CURRENT 3x3 PATCH");

        $display("        +-----+-----+-----+");

        $display(
            "        | %3d | %3d | %3d |",
            patch_data[71:64],
            patch_data[63:56],
            patch_data[55:48]
        );

        $display("        +-----+-----+-----+");

        $display(
            "        | %3d | %3d | %3d |",
            patch_data[47:40],
            patch_data[39:32],
            patch_data[31:24]
        );

        $display("        +-----+-----+-----+");

        $display(
            "        | %3d | %3d | %3d |",
            patch_data[23:16],
            patch_data[15:8],
            patch_data[7:0]
        );

        $display("        +-----+-----+-----+");

    end

    endtask


    // =========================================================
    // SEND ONE PIXEL
    // =========================================================

    task send_pixel;

        input integer row;
        input integer col;

        begin

            @(negedge clk);

            pixel_valid = 1'b1;

            pixel_in =
                row * 10 + col;


            @(posedge clk);

            #1;


            if (patch_valid) begin

                $display("");

                $display(
                    "[PATCH VALID] Row = %0d | Col = %0d",
                    row,
                    col
                );

                display_patch();

            end

        end

    endtask


    // =========================================================
    // SEND ONE IMAGE ROW
    // =========================================================

    task send_row;

        input integer row;

        integer col;

        begin

            $display("");
            $display("");
            $display("==================================================");
            $display("                 START ROW %0d", row);
            $display("==================================================");


            for (
                col = 0;
                col < IMG_WIDTH;
                col = col + 1
            )
            begin

                send_pixel(row, col);

            end


            // -------------------------------------------------
            // END OF ROW
            // -------------------------------------------------

            @(negedge clk);

            pixel_valid = 1'b0;
            pixel_in    = 0;


            @(posedge clk);

            #1;


            $display("");

            $display(
                "**************** END ROW %0d ****************",
                row
            );


            if (new_row) begin

                $display(
                    ">>> NEW ROW PULSE DETECTED"
                );

                $display(
                    ">>> WINDOW COLUMN STATE RESET"
                );

            end

        end

    endtask


    // =========================================================
    // MAIN TEST
    // =========================================================

    integer r;


    initial begin


        // -----------------------------------------------------
        // INITIALIZATION
        // -----------------------------------------------------

        rst_n        = 1'b0;

        pixel_valid  = 1'b0;

        pixel_in     = 0;

        window_clear = 1'b0;


        // -----------------------------------------------------
        // RESET
        // -----------------------------------------------------

        #20;

        rst_n = 1'b1;


        // -----------------------------------------------------
        // CLEAR NEW FRAME
        // -----------------------------------------------------

        @(negedge clk);

        window_clear = 1'b1;


        @(negedge clk);

        window_clear = 1'b0;


        // -----------------------------------------------------
        // START IMAGE
        // -----------------------------------------------------

        $display("");

        $display("##################################################");
        $display("                 START 6x6 IMAGE");
        $display("##################################################");


        // -----------------------------------------------------
        // SEND IMAGE ROW BY ROW
        // -----------------------------------------------------

        for (
            r = 0;
            r < IMG_HEIGHT;
            r = r + 1
        )
        begin

            send_row(r);

        end


        // -----------------------------------------------------
        // FINISH
        // -----------------------------------------------------

        #20;


        $display("");

        $display("##################################################");
        $display("              SIMULATION COMPLETE");
        $display("##################################################");


        $finish;

    end

endmodule