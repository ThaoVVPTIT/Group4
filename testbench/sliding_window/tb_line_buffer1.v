`timescale 1ns/1ps

module tb_line_buffer;

    parameter DATA_WIDTH = 8;
    parameter IMG_WIDTH  = 6;
    parameter IMG_HEIGHT = 6;

    reg clk;
    reg rst_n;

    reg pixel_valid;
    reg [DATA_WIDTH-1:0] pixel_in;

    wire [DATA_WIDTH-1:0] row0_pixel;
    wire [DATA_WIDTH-1:0] row1_pixel;
    wire [DATA_WIDTH-1:0] row2_pixel;

    wire rows_valid;
    wire new_row;


    // ============================================================
    // DUT
    // ============================================================

    line_buffer1 #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH(IMG_WIDTH)
    )
    u_dut (
        .clk(clk),
        .rst_n(rst_n),

        .pixel_valid(pixel_valid),
        .pixel_in(pixel_in),

        .row0_pixel(row0_pixel),
        .row1_pixel(row1_pixel),
        .row2_pixel(row2_pixel),

        .rows_valid(rows_valid),
        .new_row(new_row)
    );


    // ============================================================
    // CLOCK
    // ============================================================

    initial begin
        clk = 1'b0;

        forever #5 clk = ~clk;
    end


    // ============================================================
    // SEND ONE PIXEL
    // ============================================================

    task send_pixel;

        input integer row;
        input integer col;

        begin

            @(negedge clk);

            pixel_valid = 1'b1;

            pixel_in = row * 10 + col;


            @(posedge clk);

            #1;


            $display(
                "TIME=%0t | ROW=%0d | COL=%0d | IN=%0d | ROW0=%0d | ROW1=%0d | ROW2=%0d | ROWS_VALID=%b | NEW_ROW=%b",
                $time,
                row,
                col,
                pixel_in,
                row0_pixel,
                row1_pixel,
                row2_pixel,
                rows_valid,
                new_row
            );

        end

    endtask


    // ============================================================
    // SEND ONE ROW
    // ============================================================

    task send_row;

        input integer row;

        integer col;

        begin

            $display("");
            $display("==================================================");
            $display("START ROW %0d", row);
            $display("==================================================");


            for (col = 0; col < IMG_WIDTH; col = col + 1) begin

                send_pixel(row, col);
            end


            // Ngắt valid giữa hai hàng
            @(negedge clk);

            pixel_valid = 1'b0;

            pixel_in = 0;


            @(posedge clk);

            #1;


            $display("");
            $display("END ROW %0d", row);

            $display(
                "INTERNAL: col_cnt=%0d | row_phase=%0d | row_end_tick=%b",
                u_dut.col_cnt,
                u_dut.row_phase,
                u_dut.row_end_tick
            );

            $display(
                "CONTROL: rows_valid=%b | new_row=%b",
                rows_valid,
                new_row
            );

        end

    endtask


    // ============================================================
    // MAIN TEST
    // ============================================================

    integer r;


    initial begin

        rst_n = 1'b0;

        pixel_valid = 1'b0;

        pixel_in = 0;


        $display("");
        $display("==================================================");
        $display("RESET");
        $display("==================================================");


        #20;

        rst_n = 1'b1;


        $display("");
        $display("##################################################");
        $display("START 6x6 IMAGE");
        $display("##################################################");


        for (r = 0; r < IMG_HEIGHT; r = r + 1) begin

            send_row(r);

        end


        #20;


        $display("");
        $display("##################################################");
        $display("SIMULATION COMPLETE");
        $display("##################################################");


        $finish;

    end


    // ============================================================
    // WAVEFORM
    // ============================================================

    initial begin

        $dumpfile("tb_line_buffer.vcd");

        $dumpvars(
            0,
            tb_line_buffer
        );

    end


endmodule