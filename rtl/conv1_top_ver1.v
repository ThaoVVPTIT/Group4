`timescale 1ns / 1ps

// ============================================================================
// MODULE: conv1_top_ver1
// Ch?c n?ng: Top-level Tích ch?p Conv1 (S?a d?t ?i?m l?i Pipeline Stall Patch 11-15)
// ============================================================================

module conv1_top_ver1 #(
    parameter DATA_WIDTH  = 8,
    parameter IMG_WIDTH   = 28,
    parameter IMG_HEIGHT  = 28,
    parameter KERNEL_SIZE = 3,
    parameter C_IN        = 1,
    parameter C_OUT       = 6
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // Giao di?n ?i?u khi?n FSM
    input  wire                         start,        // B?t 1 clock ?? b?t ??u Frame m?i
    output wire                         ready,        // Báo h? th?ng r?nh (ready = 1)
    output wire                         done,         // Báo hoàn thành toàn b? Frame

    // Giao di?n Stream Pixel ??u vào
    input  wire                         pixel_valid,  // C? báo pixel_in h?p l?
    input  wire signed [DATA_WIDTH-1:0] pixel_in,     // D? li?u Pixel INT8

    // Giao di?n ??c BRAM Feature Map ??u ra
    input  wire [((C_OUT * (IMG_WIDTH - KERNEL_SIZE + 1) * (IMG_HEIGHT - KERNEL_SIZE + 1)) <= 1 ? 0 : $clog2(C_OUT * (IMG_WIDTH - KERNEL_SIZE + 1) * (IMG_HEIGHT - KERNEL_SIZE + 1)) - 1) : 0] out_rd_addr,
    output wire signed [DATA_WIDTH-1:0] out_rd_data
);

    // ========================================================================
    // LOCAL PARAMETERS & ADDR WIDTH CALCULATION
    // ========================================================================
    localparam OUTPUT_WIDTH     = IMG_WIDTH - KERNEL_SIZE + 1;
    localparam OUTPUT_HEIGHT    = IMG_HEIGHT - KERNEL_SIZE + 1;
    localparam PATCH_COUNT      = OUTPUT_WIDTH * OUTPUT_HEIGHT;
    localparam OUTPUT_SIZE      = C_OUT * PATCH_COUNT;
    localparam TOTAL_PIXELS     = IMG_WIDTH * IMG_HEIGHT;

    localparam PATCH_ADDR_WIDTH  = (PATCH_COUNT <= 1)  ? 1 : $clog2(PATCH_COUNT);
    localparam OUTPUT_ADDR_WIDTH = (OUTPUT_SIZE <= 1)   ? 1 : $clog2(OUTPUT_SIZE);

    reg busy;
    reg done_reg;
    reg frame_clear;

    assign ready = !busy;
    assign done  = done_reg;

    // Gate nh?n pixel: Cho phép nh?n khi h? th?ng ?ang BUSY
    wire pixel_valid_gate;
    assign pixel_valid_gate = pixel_valid && busy;

    // Dây n?i Stage 1 (Line Buffer) -> Stage 2 (Window Gen)
    wire [DATA_WIDTH-1:0] row0_pixel, row1_pixel, row2_pixel;
    wire                  rows_valid, new_row;

    // Dây n?i Stage 2 (Window Gen) -> PE Array
    wire [DATA_WIDTH*9-1:0] patch_3x3_data;
    wire                    patch_3x3_valid;

    // ========================================================================
    // 1. STAGE 1: LINE BUFFER MODEL (VER3)
    // ========================================================================
    line_buffer_model_ver3 #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .C_IN      (C_IN)
    ) u_line_buffer (
        .clk          (clk),
        .rst_n        (rst_n),
        .frame_clear  (frame_clear),
        .pixel_valid  (pixel_valid_gate),
        .pixel_in     (pixel_in),

        .row0_pixel   (row0_pixel),
        .row1_pixel   (row1_pixel),
        .row2_pixel   (row2_pixel),
        .rows_valid   (rows_valid),
        .new_row      (new_row),

        .channel_idx  (),
        .frame_c_done ()
    );

    // ========================================================================
    // 2. STAGE 2: 3x3 WINDOW GENERATOR (VER3)
    // ========================================================================
    window_generator_ver3 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_window_generator (
        .clk              (clk),
        .rst_n            (rst_n),
        .frame_clear      (frame_clear),
        .pixel_valid      (rows_valid),
        .col_window_clear (new_row),
        
        .row0_pixel       (row0_pixel),
        .row1_pixel       (row1_pixel),
        .row2_pixel       (row2_pixel),

        .patch_3x3_data   (patch_3x3_data),
        .patch_3x3_valid  (patch_3x3_valid)
    );

    // ========================================================================
    // 3. ROMS WEIGHTS / BIAS / QUANTIZATION PARAMETERS
    // ========================================================================
    reg signed [DATA_WIDTH-1:0] c1_kernel [0:C_OUT*9-1]; 
    reg signed [31:0]           c1_bias   [0:C_OUT-1];   
    reg signed [31:0]           c1_mult   [0:C_OUT-1];   
    reg [7:0]                   c1_shift  [0:C_OUT-1];   

    initial begin
        $readmemh("weights_hex/conv1_kernel.hex",     c1_kernel);
        $readmemh("weights_hex/conv1_bias.hex",       c1_bias);
        $readmemh("weights_hex/conv1_multiplier.hex", c1_mult);
        $readmemh("weights_hex/conv1_shift.hex",      c1_shift);
    end

    wire signed [DATA_WIDTH-1:0] p0, p1, p2, p3, p4, p5, p6, p7, p8;
    assign p0 = patch_3x3_data[71:64]; assign p1 = patch_3x3_data[63:56]; assign p2 = patch_3x3_data[55:48];
    assign p3 = patch_3x3_data[47:40]; assign p4 = patch_3x3_data[39:32]; assign p5 = patch_3x3_data[31:24];
    assign p6 = patch_3x3_data[23:16]; assign p7 = patch_3x3_data[15:8];  assign p8 = patch_3x3_data[7:0];

    wire signed [DATA_WIDTH-1:0] pe_output [0:C_OUT-1];
    wire                         pe_valid  [0:C_OUT-1];

    // ========================================================================
    // 4. INSTANTIATE 6 KH?I PE
    // ========================================================================
    conv1_pe u_pe_0 (
        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear), .patch_valid(patch_3x3_valid),
        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
        .w0(c1_kernel[0]), .w1(c1_kernel[1]), .w2(c1_kernel[2]),
        .w3(c1_kernel[3]), .w4(c1_kernel[4]), .w5(c1_kernel[5]),
        .w6(c1_kernel[6]), .w7(c1_kernel[7]), .w8(c1_kernel[8]),
        .bias(c1_bias[0]), .multiplier(c1_mult[0]), .shift(c1_shift[0]),
        .output_data(pe_output[0]), .output_valid(pe_valid[0])
    );

    conv1_pe u_pe_1 (
        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear), .patch_valid(patch_3x3_valid),
        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
        .w0(c1_kernel[9]),  .w1(c1_kernel[10]), .w2(c1_kernel[11]),
        .w3(c1_kernel[12]), .w4(c1_kernel[13]), .w5(c1_kernel[14]),
        .w6(c1_kernel[15]), .w7(c1_kernel[16]), .w8(c1_kernel[17]),
        .bias(c1_bias[1]), .multiplier(c1_mult[1]), .shift(c1_shift[1]),
        .output_data(pe_output[1]), .output_valid(pe_valid[1])
    );

    conv1_pe u_pe_2 (
        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear), .patch_valid(patch_3x3_valid),
        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
        .w0(c1_kernel[18]), .w1(c1_kernel[19]), .w2(c1_kernel[20]),
        .w3(c1_kernel[21]), .w4(c1_kernel[22]), .w5(c1_kernel[23]),
        .w6(c1_kernel[24]), .w7(c1_kernel[25]), .w8(c1_kernel[26]),
        .bias(c1_bias[2]), .multiplier(c1_mult[2]), .shift(c1_shift[2]),
        .output_data(pe_output[2]), .output_valid(pe_valid[2])
    );

    conv1_pe u_pe_3 (
        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear), .patch_valid(patch_3x3_valid),
        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
        .w0(c1_kernel[27]), .w1(c1_kernel[28]), .w2(c1_kernel[29]),
        .w3(c1_kernel[30]), .w4(c1_kernel[31]), .w5(c1_kernel[32]),
        .w6(c1_kernel[33]), .w7(c1_kernel[34]), .w8(c1_kernel[35]),
        .bias(c1_bias[3]), .multiplier(c1_mult[3]), .shift(c1_shift[3]),
        .output_data(pe_output[3]), .output_valid(pe_valid[3])
    );

    conv1_pe u_pe_4 (
        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear), .patch_valid(patch_3x3_valid),
        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
        .w0(c1_kernel[36]), .w1(c1_kernel[37]), .w2(c1_kernel[38]),
        .w3(c1_kernel[39]), .w4(c1_kernel[40]), .w5(c1_kernel[41]),
        .w6(c1_kernel[42]), .w7(c1_kernel[43]), .w8(c1_kernel[44]),
        .bias(c1_bias[4]), .multiplier(c1_mult[4]), .shift(c1_shift[4]),
        .output_data(pe_output[4]), .output_valid(pe_valid[4])
    );

    conv1_pe u_pe_5 (
        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear), .patch_valid(patch_3x3_valid),
        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
        .w0(c1_kernel[45]), .w1(c1_kernel[46]), .w2(c1_kernel[47]),
        .w3(c1_kernel[48]), .w4(c1_kernel[49]), .w5(c1_kernel[50]),
        .w6(c1_kernel[51]), .w7(c1_kernel[52]), .w8(c1_kernel[53]),
        .bias(c1_bias[5]), .multiplier(c1_mult[5]), .shift(c1_shift[5]),
        .output_data(pe_output[5]), .output_valid(pe_valid[5])
    );

    // ========================================================================
    // 5. OUTPUT MEMORY BRAM LOGIC
    // ========================================================================
    reg signed [DATA_WIDTH-1:0] c1_out [0:OUTPUT_SIZE-1];
    assign out_rd_data = c1_out[out_rd_addr];

    reg [PATCH_ADDR_WIDTH-1:0] patch_cnt;
    integer ch_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            patch_cnt <= {PATCH_ADDR_WIDTH{1'b0}};
        end else if (frame_clear) begin
            patch_cnt <= {PATCH_ADDR_WIDTH{1'b0}};
        end else if (pe_valid[0]) begin
            // Ghi k?t qu? C_OUT Channels song song vào BRAM
            for (ch_i = 0; ch_i < C_OUT; ch_i = ch_i + 1) begin
                c1_out[ch_i * PATCH_COUNT + patch_cnt] <= pe_output[ch_i];
            end

            // T?ng patch_cnt ??m t? 0 -> PATCH_COUNT - 1
            if (patch_cnt == PATCH_COUNT - 1) begin
                patch_cnt <= {PATCH_ADDR_WIDTH{1'b0}};
            end else begin
                patch_cnt <= patch_cnt + 1'b1;
            end
        end
    end

    // ========================================================================
    // 6. FSM CONTROL LOGIC (B?t chính xác s? ki?n hoàn thành)
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy        <= 1'b0;
            done_reg    <= 1'b0;
            frame_clear <= 1'b0;
        end else begin
            done_reg    <= 1'b0;
            frame_clear <= 1'b0;

            if (start && !busy) begin
                busy        <= 1'b1;
                frame_clear <= 1'b1; // Phát xung clear 1 clock
            end

            // Kích ho?t c? DONE khi PE ghi xong patch cu?i cùng
            if (busy && pe_valid[0] && (patch_cnt == PATCH_COUNT - 1)) begin
                busy     <= 1'b0;
                done_reg <= 1'b1; // Báo hoàn thành Frame!
            end
        end
    end

endmodule