//`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////////

//module top_sliding_window_ver1 #(
//    parameter DATA_WIDTH = 8,
//    parameter IMG_WIDTH  = 28,
//    parameter IMG_HEIGHT = 28,
//    parameter C_IN       = 6
//)(
//    input  wire                                             clk,
//    input  wire                                             rst_n,
    
//    // External Stream Input Interface
//    input  wire                                             pixel_valid,
//    input  wire [DATA_WIDTH-1:0]                            pixel_in,

//    // Output Interface for PE Array Matrix (3x3xC_IN Tensor)
//    output wire [DATA_WIDTH*9*C_IN-1:0]                     patch_cin_data,  // Complete 3x3xC_IN tensor (e.g., 432-bit for C_IN=6)
//    output wire                                             patch_cin_valid, // High pulse when all C_IN channels are fully packed

//    // System Monitoring Outputs
//    output wire [(C_IN <= 1 ? 0 : $clog2(C_IN)-1) : 0]      channel_idx,
//    output wire                                             frame_c_done
//);

//    // =========================================================================
//    // INTERCONNECT WIRES: Line Buffer ---> Window Generator
//    // =========================================================================
//    wire [DATA_WIDTH-1:0] row0_pixel; // Row N-2 pixel (Top row of 3x3)
//    wire [DATA_WIDTH-1:0] row1_pixel; // Row N-1 pixel (Middle row of 3x3)
//    wire [DATA_WIDTH-1:0] row2_pixel; // Row N pixel (Bottom row / Direct pixel_in)
//    wire                  rows_valid; // Active High when Line Buffer has accumulated at least 3 rows
//    wire                  new_row;    // Single clock pulse indicating transition to a new row

//    // =========================================================================
//    // INTERCONNECT WIRES: Window Generator ---> Channel Patch Buffer
//    // =========================================================================
//    wire [DATA_WIDTH*9-1:0] patch_3x3_data;  // Single-channel 3x3 patch data (72-bit for 8-bit width)
//    wire                    patch_3x3_valid; // High pulse indicating valid single-channel 3x3 patch

//    // =========================================================================
//    // MODULE 1: LINE BUFFER MODEL
//    // Purpose: Accumulates incoming pixel stream into 2 internal row buffers 
//    //          to output 3 vertically aligned pixels in the same column.
//    // =========================================================================
//    line_buffer_model_ver2 #(
//        .DATA_WIDTH(DATA_WIDTH),
//        .IMG_WIDTH (IMG_WIDTH),
//        .IMG_HEIGHT(IMG_HEIGHT),
//        .C_IN      (C_IN)
//    ) u_line_buffer (
//        // Clock & Reset
//        .clk          (clk),             // Global system clock
//        .rst_n        (rst_n),           // Active-low asynchronous reset

//        // External Inputs
//        .pixel_valid  (pixel_valid),     // Input from external pixel stream driver
//        .pixel_in     (pixel_in),        // Input 8-bit pixel data

//        // Control & Timing Outputs
//        .rows_valid   (rows_valid),      // Output to window_generator: Enables 3x3 sliding process
//        .new_row      (new_row),         // Output to window_generator: Clears horizontal window registers

//        // Parallel Pixel Outputs (3 vertical pixels in same column)
//        .row0_pixel   (row0_pixel),      // Output to window_generator: Top row pixel
//        .row1_pixel   (row1_pixel),      // Output to window_generator: Middle row pixel
//        .row2_pixel   (row2_pixel),      // Output to window_generator: Bottom row pixel

//        // Status Outputs
//        .channel_idx  (channel_idx),     // Output to top port & channel_patch_buffer: Current channel index (0 to C_IN-1)
//        .frame_c_done (frame_c_done)     // Output to top port & window_generator: Clears window on full frame/channel done
//    );

//    // =========================================================================
//    // MODULE 2: 3x3 WINDOW GENERATOR
//    // Purpose: Receives 3 vertical pixels per clock and uses shift registers 
//    //          to slide horizontally, forming a 3x3 single-channel patch.
//    // =========================================================================
//    window_generator_ver2 #(
//        .DATA_WIDTH(DATA_WIDTH)
//    ) u_window_gen (
//        // Clock & Reset
//        .clk              (clk),              // Global system clock
//        .rst_n            (rst_n),            // Active-low asynchronous reset

//        // Control Inputs
//        .pixel_valid      (rows_valid),       // Input from line_buffer: Shifts window only when 3 rows are valid
//        .col_window_clear (new_row),          // Input from line_buffer: Clears window registers at new row start
//        .window_clear     (frame_c_done),     // Input from line_buffer: Resets window registers on frame completion

//        // Parallel Pixel Inputs
//        .row0_pixel       (row0_pixel),       // Input from line_buffer: Top row pixel
//        .row1_pixel       (row1_pixel),       // Input from line_buffer: Middle row pixel
//        .row2_pixel       (row2_pixel),       // Input from line_buffer: Bottom row pixel

//        // Patch Outputs
//        .patch_3x3_data   (patch_3x3_data),   // Output to channel_patch_buffer: 72-bit single-channel 3x3 patch
//        .patch_3x3_valid  (patch_3x3_valid)   // Output to channel_patch_buffer: Valid flag for single 3x3 patch
//    );

//    // =========================================================================
//    // MODULE 3: CHANNEL PATCH BUFFER
//    // Purpose: Collects and buffers 3x3 patches from Channel 0 to Channel C_IN-1 
//    //          at the same spatial coordinate, then packs them into a single 
//    //          wide bus (3x3xC_IN) with Zero-Latency for the PE Array.
//    // =========================================================================
//    channel_patch_buffer #(
//        .DATA_WIDTH(DATA_WIDTH),
//        .C_IN      (C_IN)
//    ) u_channel_patch_buffer (
//        // Clock & Reset
//        .clk             (clk),              // Global system clock
//        .rst_n           (rst_n),            // Active-low asynchronous reset

//        // Inputs from Window Generator
//        .patch_3x3_valid (patch_3x3_valid),  // Input from window_generator: Single patch valid flag
//        .patch_3x3_data  (patch_3x3_data),   // Input from window_generator: 72-bit single 3x3 patch data

//        // Input from Line Buffer
//        .channel_idx     (channel_idx),      // Input from line_buffer: Channel index tag for buffer routing

//        // Top-Level Outputs
//        .patch_cin_valid (patch_cin_valid),  // Output to Top Port: Pulse indicating full 3x3xC_IN tensor is ready
//        .patch_cin_data  (patch_cin_data)    // Output to Top Port: Packed multi-channel tensor bus (432-bit)
//    );

//endmodule


`timescale 1ns / 1ps

module top_sliding_window_ver1 #(
    parameter DATA_WIDTH = 8,
    parameter IMG_WIDTH  = 28,
    parameter IMG_HEIGHT = 28,
    parameter C_IN       = 6
)(
    input  wire                                             clk,
    input  wire                                             rst_n,
    
    // External Stream Input Interface
    input  wire                                             pixel_valid,
    input  wire [DATA_WIDTH-1:0]                            pixel_in,

    // =========================================================================
    // INTERFACE STAGE 1: LINE BUFFER OUTPUTS (QUAN SÁT LU?NG 3 HÀNG)
    // =========================================================================
    output wire [DATA_WIDTH-1:0]                            row0_pixel, // Pixel Hàng 1
    output wire [DATA_WIDTH-1:0]                            row1_pixel, // Pixel Hàng 2
    output wire [DATA_WIDTH-1:0]                            row2_pixel, // Pixel Hàng 3 (Nh?n tr?c ti?p)
    output wire                                             rows_valid, // C? báo ?? 3 hàng ?? g?i Window Gen

    // =========================================================================
    // INTERFACE STAGE 2: WINDOW GEN OUTPUTS (QUAN SÁT PATCH 3x3 ??N KÊNH)
    // =========================================================================
    output wire [DATA_WIDTH*9-1:0]                          patch_3x3_data,
    output wire                                             patch_3x3_valid,

    // =========================================================================
    // INTERFACE STAGE 3: CHANNEL BUFFER OUTPUTS (TENSOR 3x3xC_IN CHO PE ARRAY)
    // =========================================================================
    output wire [DATA_WIDTH*9*C_IN-1:0]                     patch_cin_data,
    output wire                                             patch_cin_valid,

    // Status Monitors
    output wire [(C_IN <= 1 ? 0 : $clog2(C_IN)-1) : 0]      channel_idx,
    output wire                                             frame_c_done
);

    wire new_row;

    // =========================================================================
    // MODULE 1: LINE BUFFER MODEL
    // =========================================================================
    line_buffer_model_ver2 #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .C_IN      (C_IN)
    ) u_line_buffer (
        .clk          (clk),
        .rst_n        (rst_n),
        .pixel_valid  (pixel_valid),
        .pixel_in     (pixel_in),
        .rows_valid   (rows_valid),
        .new_row      (new_row),
        .row0_pixel   (row0_pixel),
        .row1_pixel   (row1_pixel),
        .row2_pixel   (row2_pixel),
        .channel_idx  (channel_idx),
        .frame_c_done (frame_c_done)
    );

    // =========================================================================
    // MODULE 2: 3x3 WINDOW GENERATOR
    // =========================================================================
    window_generator_ver2 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_window_gen (
        .clk              (clk),
        .rst_n            (rst_n),
        .pixel_valid      (rows_valid),
        .col_window_clear (new_row),
        .window_clear     (frame_c_done),
        .row0_pixel       (row0_pixel),
        .row1_pixel       (row1_pixel),
        .row2_pixel       (row2_pixel),
        .patch_3x3_data   (patch_3x3_data),
        .patch_3x3_valid  (patch_3x3_valid)
    );

    // =========================================================================
    // MODULE 3: CHANNEL PATCH BUFFER
    // =========================================================================
    channel_patch_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .C_IN      (C_IN)
    ) u_channel_patch_buffer (
        .clk             (clk),
        .rst_n           (rst_n),
        .patch_3x3_valid (patch_3x3_valid),
        .patch_3x3_data  (patch_3x3_data),
        .channel_idx     (channel_idx),
        .patch_cin_valid (patch_cin_valid),
        .patch_cin_data  (patch_cin_data)
    );

endmodule