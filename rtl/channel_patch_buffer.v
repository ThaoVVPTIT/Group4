`timescale 1ns/1ps

module channel_patch_buffer #(
    parameter DATA_WIDTH = 8,
    parameter C_IN       = 6
)(
    input wire clk,
    input wire rst_n,
    input wire patch_3x3_valid,
    input wire [DATA_WIDTH*9-1:0] patch_3x3_data,
    //============================================================
    // CHANNEL INDEX
    //============================================================

    input wire [
        (C_IN <= 1 ? 0 : $clog2(C_IN)-1) : 0] channel_idx,

    //============================================================
    // OUTPUT: PATCH 3x3xC_IN
    //============================================================
    output reg [DATA_WIDTH*9*C_IN-1:0] patch_cin_data,
    output reg patch_cin_valid
);


    //============================================================
    // BUFFER CH?A PATCH 3x3 C?A T?NG CHANNEL
    //============================================================

    reg [DATA_WIDTH*9-1:0] patch_buffer [0:C_IN-1];


    integer i;
    integer c;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            patch_cin_valid <= 1'b0;
            patch_cin_data <= {(DATA_WIDTH*9*C_IN){1'b0}};
            for (i = 0; i < C_IN; i = i + 1) begin

                patch_buffer[i] <= {(DATA_WIDTH*9){1'b0}};

            end

        end

        else begin
            patch_cin_valid <= 1'b0;


            if (patch_3x3_valid) begin

                patch_buffer[channel_idx]
                    <= patch_3x3_data;

                if (channel_idx == C_IN - 1) begin


                    //================================================
                    // CHANNEL CU?I
                    // Dùng tr?c ti?p patch hi?n t?i
                    //================================================

                    patch_cin_data[DATA_WIDTH*9*(C_IN-1) +: DATA_WIDTH*9] <= patch_3x3_data;

                    for (c = 0; c < C_IN-1; c = c + 1 ) begin
                        patch_cin_data[
                            DATA_WIDTH*9*c +:
                            DATA_WIDTH*9
                        ]
                            <= patch_buffer[c];

                    end


                    //================================================
                    // BÁO ?Ã ?? C_IN CHANNEL
                    //================================================

                    patch_cin_valid <= 1'b1;

                end

            end

        end

    end

endmodule