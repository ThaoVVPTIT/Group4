`timescale 1ns / 1ps

// ============================================================================
// MODULE: conv1_top
// Chuc nang: Top-level Tích chap Conv1 (28x28x1 -> 26x26x6)
//            - Tích h?p Line Buffer (v3) + Window Generator (v3) + PE Array (Generate)
//              và OUTPUT_ADDR_WIDTH (12-bit cho out_rd_addr).
// ============================================================================

module conv1_top_ver2 #(
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
    input  wire                         start,        // Bat 1 clock ?? bat dau Frame moi
    output wire                         ready,        // Báo he thong ranh (ready = 1)
    output wire                         done,         // Báo hoàn thành toàn bo Frame (4056 pixels)

    // Giao di?n Stream Pixel ??u vào
    input  wire                         pixel_valid,  // C? báo pixel_in h?p l?
    input  wire signed [DATA_WIDTH-1:0] pixel_in,     // D? li?u Pixel INT8

    // Giao di?n ??c BRAM Feature Map ??u ra (Linh ho?t ?? r?ng bit ??a ch? OUTPUT_ADDR_WIDTH)
    input  wire [((C_OUT * (IMG_WIDTH - KERNEL_SIZE + 1) * (IMG_HEIGHT - KERNEL_SIZE + 1)) <= 1 ? 0 : $clog2(C_OUT * (IMG_WIDTH - KERNEL_SIZE + 1) * (IMG_HEIGHT - KERNEL_SIZE + 1)) - 1) : 0] out_rd_addr,
    output wire signed [DATA_WIDTH-1:0] out_rd_data
);

    // ========================================================================
    // LOCAL PARAMETERS & ADDR WIDTH CALCULATION
    // ========================================================================
    localparam OUTPUT_WIDTH     = IMG_WIDTH - KERNEL_SIZE + 1;  // 26
    localparam OUTPUT_HEIGHT    = IMG_HEIGHT - KERNEL_SIZE + 1; // 26
    localparam PATCH_COUNT      = OUTPUT_WIDTH * OUTPUT_HEIGHT;  // 676
    localparam OUTPUT_SIZE      = C_OUT * PATCH_COUNT;            // 4056

    // Tách b?ch 2 tham s? ?? r?ng bus ??a ch?
    localparam PATCH_ADDR_WIDTH  = (PATCH_COUNT <= 1) ? 1 : $clog2(PATCH_COUNT); // 10-bit (0..675)
    localparam OUTPUT_ADDR_WIDTH = (OUTPUT_SIZE <= 1)  ? 1 : $clog2(OUTPUT_SIZE);  // 12-bit (0..4055)

    reg busy;
    reg done_reg;
    reg frame_clear;

    assign ready = !busy;
    assign done  = done_reg;

    // Gate tín hi?u stream an toàn: Ch? cho phép pixel ?i vào Line Buffer khi m?ch BUSY
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
        .frame_clear  (frame_clear),      // ??ng b? frame_clear
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
        .frame_clear      (frame_clear),      // ??ng b? frame_clear
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
    reg signed [DATA_WIDTH-1:0] c1_kernel [0:C_OUT*9-1]; // 6 filters * 9 weights = 54
    reg signed [31:0]           c1_bias   [0:C_OUT-1];   // 6 bias values
    reg signed [31:0]           c1_mult   [0:C_OUT-1];   // 6 quantization multipliers
    reg [7:0]                   c1_shift  [0:C_OUT-1];   // 6 shift values

    initial begin
        $readmemh("weights_hex/conv1_kernel.hex",     c1_kernel);
        $readmemh("weights_hex/conv1_bias.hex",       c1_bias);
        $readmemh("weights_hex/conv1_multiplier.hex", c1_mult);
        $readmemh("weights_hex/conv1_shift.hex",      c1_shift);
    end

    // Tách Patch 72-bit thành 9 Pixels 8-bit có d?u (p0 -> p8)
    wire signed [DATA_WIDTH-1:0] p0, p1, p2, p3, p4, p5, p6, p7, p8;
    assign p0 = patch_3x3_data[71:64]; assign p1 = patch_3x3_data[63:56]; assign p2 = patch_3x3_data[55:48];
    assign p3 = patch_3x3_data[47:40]; assign p4 = patch_3x3_data[39:32]; assign p5 = patch_3x3_data[31:24];
    assign p6 = patch_3x3_data[23:16]; assign p7 = patch_3x3_data[15:8];  assign p8 = patch_3x3_data[7:0];

    wire signed [DATA_WIDTH-1:0] pe_output [0:C_OUT-1];
    wire                         pe_valid  [0:C_OUT-1];

    // ========================================================================
    // 4. GENERATE ARRAY PE MODULES (Linh ho?t thay ??i C_OUT)
    // ========================================================================
    genvar f;
    generate
        for (f = 0; f < C_OUT; f = f + 1) begin : GEN_PE
            conv1_pe u_pe (
                .clk          (clk),
                .rst_n        (rst_n),
                .frame_clear  (frame_clear),
                .patch_valid  (patch_3x3_valid),

                .p0(p0), .p1(p1), .p2(p2),
                .p3(p3), .p4(p4), .p5(p5),
                .p6(p6), .p7(p7), .p8(p8),

                .w0(c1_kernel[f*9 + 0]),
                .w1(c1_kernel[f*9 + 1]),
                .w2(c1_kernel[f*9 + 2]),
                .w3(c1_kernel[f*9 + 3]),
                .w4(c1_kernel[f*9 + 4]),
                .w5(c1_kernel[f*9 + 5]),
                .w6(c1_kernel[f*9 + 6]),
                .w7(c1_kernel[f*9 + 7]),
                .w8(c1_kernel[f*9 + 8]),

                .bias        (c1_bias[f]),
                .multiplier  (c1_mult[f]),
                .shift       (c1_shift[f]),

                .output_data (pe_output[f]),
                .output_valid(pe_valid[f])
            );
        end
    endgenerate

    // ========================================================================
    // 5. OUTPUT MEMORY BRAM LOGIC ([Channel][Spatial] Layout)
    // ========================================================================
    reg signed [DATA_WIDTH-1:0] c1_out [0:OUTPUT_SIZE-1];
    assign out_rd_data = c1_out[out_rd_addr];

    // S? d?ng PATCH_ADDR_WIDTH (10-bit) chu?n xác cho b? ??m patch_cnt (0..675)
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

            if (patch_cnt == PATCH_COUNT - 1) begin
                patch_cnt <= {PATCH_ADDR_WIDTH{1'b0}};
            end else begin
                patch_cnt <= patch_cnt + 1'b1;
            end
        end
    end

    // ========================================================================
    // 6. FSM CONTROL LOGIC
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
                frame_clear <= 1'b1; // Phát xung clear 1 clock nh?p ??u
            end

            // Ki?m tra khi ghi xong patch cu?i cùng (Patch 675)
            if (pe_valid[0] && (patch_cnt == PATCH_COUNT - 1)) begin
                busy     <= 1'b0;
                done_reg <= 1'b1; // Báo DONE hoàn thành Frame!
            end
        end
    end

endmodule
