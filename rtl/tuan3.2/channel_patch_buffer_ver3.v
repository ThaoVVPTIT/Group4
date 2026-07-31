`timescale 1ns/1ps

// ============================================================================
// MODULE: channel_patch_buffer_ver3
// Chuc nang: Gom lan luot cac patch 3x3x1 cua tang channel (channel_idx 0 -> C_IN-1),
//            khi den channel cuoi cùng thi dong goi thanh Patch 3x3xC_IN 
//            va phat co patch_cin_valid.
// ============================================================================

module channel_patch_buffer_ver3 #(
    parameter DATA_WIDTH = 8,
    parameter C_IN       = 6
)(
    input  wire                                             clk,
    input  wire                                             rst_n,

    // Tin hieu dieu khien
    input  wire                                             frame_clear,      // Reset sach buffer khi chuyen Frame

    // Dau vao Patch 3x3x1 tu Window Generator
    input  wire                                             patch_3x3_valid,
    input  wire [DATA_WIDTH*9-1:0]                          patch_3x3_data,
    input  wire [(C_IN <= 1 ? 0 : $clog2(C_IN)-1) : 0]      channel_idx,

    // Dau ra Tensor 3x3xC_IN
    output reg  [DATA_WIDTH*9*C_IN-1:0]                     patch_cin_data,
    output reg                                              patch_cin_valid
);

    // Buffer chua Patch 3x3x1 cua tang Channel
    reg [DATA_WIDTH*9-1:0] patch_buffer [0:C_IN-1];

    // Bo dem xac nhan da trai qua it nhat 1 chu ky nap du 6 channels dau tien
    reg first_full_frame;

    integer i, c;

    // ========================================================================
    // COLLECT AND PACK CHANNEL PATCHES
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        // 1. ASYNCHRONOUS RESET
        if (!rst_n) begin
            patch_cin_data   <= {(DATA_WIDTH*9*C_IN){1'b0}};
            patch_cin_valid  <= 1'b0;
            first_full_frame <= 1'b0;
            for (i = 0; i < C_IN; i = i + 1) begin
                patch_buffer[i] <= {(DATA_WIDTH*9){1'b0}};
            end
        end 

        // 2. SYNCHRONOUS FRAME CLEAR
        else if (frame_clear) begin
            patch_cin_data   <= {(DATA_WIDTH*9*C_IN){1'b0}};
            patch_cin_valid  <= 1'b0;
            first_full_frame <= 1'b0;
            for (i = 0; i < C_IN; i = i + 1) begin
                patch_buffer[i] <= {(DATA_WIDTH*9){1'b0}};
            end
        end 

        // 3. NORMAL OPERATION
        else begin
            // Mac dinh valid chi keo dai 1 clock cycle
            patch_cin_valid <= 1'b0;

            if (patch_3x3_valid) begin
                // Luu Patch cua Channel hien tai vao Buffer
                patch_buffer[channel_idx] <= patch_3x3_data;

                // Khi cham kenh dau tien (channel_idx == 0), bat co bat dau chu ky
                if (channel_idx == 0) begin
                    first_full_frame <= 1'b1;
                end

                // CHI PHAT VALID KHI: Trai qua kenh 0 truoc do VA dang dung o kenh cuoi (C_IN - 1)
                if ((channel_idx == C_IN - 1) && first_full_frame) begin
                    
                    // Channel cuoi: Ghep truc tiep tu patch_3x3_data
                    patch_cin_data[DATA_WIDTH*9*(C_IN-1) +: DATA_WIDTH*9] <= patch_3x3_data;

                    // Cac Channel truoc: Lay tu patch_buffer da luu
                    for (c = 0; c < C_IN-1; c = c + 1) begin
                        patch_cin_data[DATA_WIDTH*9*c +: DATA_WIDTH*9] <= patch_buffer[c];
                    end

                    // Báo hoàn tat gom 6 channels
                    patch_cin_valid <= 1'b1;
                end
            end
        end
    end

endmodule

//`timescale 1ns/1ps

//// ============================================================================
//// MODULE: channel_patch_buffer_ver3 (?Ã FIX CHU?N CHO BUS PARALLEL 6 CHANNELS)
//// Ch?c n?ng: Chuy?n ti?p th?ng Tensor 3x3x6 t? WindowGen sang PE Array
//// ============================================================================

//module channel_patch_buffer_ver3 #(
//    parameter DATA_WIDTH = 8,
//    parameter C_IN       = 6
//)(
//    input  wire                                             clk,
//    input  wire                                             rst_n,
//    input  wire                                             frame_clear,

//    // ??u vào Patch 3x3x6 (432-bit) t? Window Generator
//    input  wire                                             patch_3x3_valid,
//    input  wire [DATA_WIDTH*9*C_IN-1:0]                     patch_3x3_data,
//    input  wire [(C_IN <= 1 ? 0 : $clog2(C_IN)-1) : 0]     channel_idx,

//    // ??u ra Tensor 3x3xC_IN sang PE Array
//    output reg  [DATA_WIDTH*9*C_IN-1:0]                     patch_cin_data,
//    output reg                                             patch_cin_valid
//);

//    // ========================================================================
//    // DIRECT PASSTHROUGH LOGIC (KHI D? LI?U 6 CHANNELS ?Ã CH?Y SONG SONG)
//    // ========================================================================
//    always @(posedge clk or negedge rst_n) begin
//        if (!rst_n || frame_clear) begin
//            patch_cin_data  <= {(DATA_WIDTH*9*C_IN){1'b0}};
//            patch_cin_valid <= 1'b0;
//        end else begin
//            patch_cin_valid <= patch_3x3_valid;
//            if (patch_3x3_valid) begin
//                patch_cin_data <= patch_3x3_data; // N?i th?ng bus 432-bit sang PE
//            end else begin
//                patch_cin_data <= {(DATA_WIDTH*9*C_IN){1'b0}};
//            end
//        end
//    end

//endmodule