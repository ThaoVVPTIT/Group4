//==========================
//Control
//==========================
//clk
//rst_n
//pixel_valid
//window_clear
//col_window_clear
//
//==========================
//Input Stream
//==========================
//row0_pixel
//row1_pixel
//row2_pixel
//
//==========================
//Internal Window
//==========================
//win_00 win_01 win_02
//win_10 win_11 win_12
//win_20 win_21 win_22
//col_fill_cnt
//
//==========================
//Output
//==========================
//patch_valid
//patch_data

`timescale 1ns/1ps

module tb_window_generator;

parameter DATA_WIDTH = 8;

//////////////////////////////////////////////////////////////
// Clock & Reset
//////////////////////////////////////////////////////////////

reg clk;
reg rst_n;

//////////////////////////////////////////////////////////////
// Inputs
//////////////////////////////////////////////////////////////

reg pixel_valid;
reg col_window_clear;
reg window_clear;

reg [DATA_WIDTH-1:0] row0_pixel;
reg [DATA_WIDTH-1:0] row1_pixel;
reg [DATA_WIDTH-1:0] row2_pixel;

//////////////////////////////////////////////////////////////
// Outputs
//////////////////////////////////////////////////////////////

wire [DATA_WIDTH*9-1:0] patch_data;
wire                    patch_valid;

//////////////////////////////////////////////////////////////
// DUT
//////////////////////////////////////////////////////////////

window_generator #(
    .DATA_WIDTH(DATA_WIDTH)
)
dut
(
    .clk(clk),
    .rst_n(rst_n),

    .pixel_valid(pixel_valid),
    .col_window_clear(col_window_clear),
    .window_clear(window_clear),

    .row0_pixel(row0_pixel),
    .row1_pixel(row1_pixel),
    .row2_pixel(row2_pixel),

    .patch_data(patch_data),
    .patch_valid(patch_valid)
);

//////////////////////////////////////////////////////////////
// CLOCK
//////////////////////////////////////////////////////////////

always #5 clk = ~clk;

//////////////////////////////////////////////////////////////
// SEND ONE COLUMN
//////////////////////////////////////////////////////////////

task send_column;

input [7:0] r0;
input [7:0] r1;
input [7:0] r2;

begin

    @(negedge clk);

    row0_pixel  = r0;
    row1_pixel  = r1;
    row2_pixel  = r2;

    pixel_valid = 1'b1;

    @(posedge clk);

    #1;

    pixel_valid = 1'b0;

end

endtask

//////////////////////////////////////////////////////////////
// DISPLAY PATCH
//////////////////////////////////////////////////////////////

always @(posedge clk)
begin

    if(patch_valid)
    begin

        $display("");

        $display("-------------------------------------------");
        $display("PATCH VALID @ %0t",$time);

        $display("%3d %3d %3d",
            patch_data[71:64],
            patch_data[63:56],
            patch_data[55:48]);

        $display("%3d %3d %3d",
            patch_data[47:40],
            patch_data[39:32],
            patch_data[31:24]);

        $display("%3d %3d %3d",
            patch_data[23:16],
            patch_data[15:8],
            patch_data[7:0]);

    end

end

//////////////////////////////////////////////////////////////
// MAIN
//////////////////////////////////////////////////////////////

initial
begin

    clk = 0;

    rst_n = 0;

    pixel_valid = 0;

    window_clear = 0;

    col_window_clear = 0;

    row0_pixel = 0;
    row1_pixel = 0;
    row2_pixel = 0;

    /////////////////////////////////////////////
    // RESET
    /////////////////////////////////////////////

    #20;

    rst_n = 1;

    /////////////////////////////////////////////
    // CLEAR WINDOW
    /////////////////////////////////////////////

    @(negedge clk);

    window_clear = 1;

    @(negedge clk);

    window_clear = 0;

    /////////////////////////////////////////////
    // ROW
    /////////////////////////////////////////////

    send_column(0,10,20);
    send_column(1,11,21);
    send_column(2,12,22);

    send_column(3,13,23);
    send_column(4,14,24);
    send_column(5,15,25);

    /////////////////////////////////////////////
    // END ROW
    /////////////////////////////////////////////

    @(negedge clk);

    col_window_clear = 1;

    @(negedge clk);

    col_window_clear = 0;

    #50;

    $finish;

end

//////////////////////////////////////////////////////////////
// Waveform
//////////////////////////////////////////////////////////////

initial
begin

    $dumpfile("window_generator.vcd");

    $dumpvars(0,tb_window_generator);

end

endmodule