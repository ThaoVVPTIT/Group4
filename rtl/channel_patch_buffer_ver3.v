`timescale 1ns/1ps

// ============================================================================
// MODULE: channel_patch_buffer
// Ch?c n?ng: Gom l?n l??t các patch 3x3x1 c?a t?ng channel (channel_idx 0 -> C_IN-1),
//            khi ??n channel cu?i cùng thì ?óng gói thành Patch 3x3xC_IN 
//            và phát c? patch_cin_valid.
// ============================================================================

module channel_patch_buffer_ver3 #(
    parameter DATA_WIDTH = 8,
    parameter C_IN       = 6
)(
    input  wire                                             clk,
    input  wire                                             rst_n,

    // Tín hi?u ?i?u khi?n
    input  wire                                             frame_clear,      // Reset s?ch buffer khi chuy?n Frame

    // ??u vào Patch 3x3x1 t? Window Generator
    input  wire                                             patch_3x3_valid,
    input  wire [DATA_WIDTH*9-1:0]                          patch_3x3_data,
    input  wire [(C_IN <= 1 ? 0 : $clog2(C_IN)-1) : 0]      channel_idx,

    // ??u ra Tensor 3x3xC_IN
    output reg  [DATA_WIDTH*9*C_IN-1:0]                     patch_cin_data,
    output reg                                              patch_cin_valid
);

    // Buffer ch?a Patch 3x3x1 c?a t?ng Channel
    reg [DATA_WIDTH*9-1:0] patch_buffer [0:C_IN-1];

    integer i, c;

    // ========================================================================
    // COLLECT AND PACK CHANNEL PATCHES
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        // 1. ASYNCHRONOUS RESET
        if (!rst_n) begin
            patch_cin_data  <= {(DATA_WIDTH*9*C_IN){1'b0}};
            patch_cin_valid <= 1'b0;
            for (i = 0; i < C_IN; i = i + 1) begin
                patch_buffer[i] <= {(DATA_WIDTH*9){1'b0}};
            end
        end 

        // 2. SYNCHRONOUS FRAME CLEAR
        else if (frame_clear) begin
            patch_cin_data  <= {(DATA_WIDTH*9*C_IN){1'b0}};
            patch_cin_valid <= 1'b0;
            for (i = 0; i < C_IN; i = i + 1) begin
                patch_buffer[i] <= {(DATA_WIDTH*9){1'b0}};
            end
        end 

        // 3. NORMAL OPERATION
        else begin
            // M?c ??nh valid ch? kéo dài 1 clock cycle
            patch_cin_valid <= 1'b0;

            if (patch_3x3_valid) begin
                // L?u Patch c?a Channel hi?n t?i vào Buffer
                patch_buffer[channel_idx] <= patch_3x3_data;

                // Ki?m tra khi nh?n ?? Patch c?a Channel cu?i cùng
                if (channel_idx == C_IN - 1) begin
                    // Channel cu?i: Ghép tr?c ti?p t? patch_3x3_data (tránh tr? non-blocking)
                    patch_cin_data[DATA_WIDTH*9*(C_IN-1) +: DATA_WIDTH*9] <= patch_3x3_data;

                    // Các Channel tr??c: L?y t? patch_buffer ?ã l?u
                    for (c = 0; c < C_IN-1; c = c + 1) begin
                        patch_cin_data[DATA_WIDTH*9*c +: DATA_WIDTH*9] <= patch_buffer[c];
                    end

                    // Báo hoàn t?t gom tr?n v?n C_IN Channels (Ví d?: 3x3x6)
                    patch_cin_valid <= 1'b1;
                end
            end
        end
    end

endmodule