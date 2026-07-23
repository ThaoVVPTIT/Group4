module window_generator #(
    parameter DATA_WIDTH = 8   // Độ rộng bit của mỗi pixel
)(
    input  wire                       clk,
    input  wire                       rst_n,
    
    // Tín hiệu điều khiển luồng
    input  wire                       pixel_valid,      // Dịch ma trận khi luồng dữ liệu song song từ Line Buffer đổ vào
    input  wire                       col_window_clear, // Reset trạng thái đếm cột (kích hoạt ở Clock N+1 sau khi hết hàng)
    input  wire                       window_clear,     // Xóa sạch dữ liệu ma trận thanh ghi khi bắt đầu một Frame ảnh mới
    
    // 3 luồng dữ liệu đầu vào (Luôn đảm bảo trùng khớp cột từ Line Buffer)
    input  wire [DATA_WIDTH-1:0]      row0_pixel,       // Hàng trên (cũ nhất)
    input  wire [DATA_WIDTH-1:0]      row1_pixel,       // Hàng giữa
    input  wire [DATA_WIDTH-1:0]      row2_pixel,       // Hàng dưới (hiện tại)
    
    // Giao tiếp đầu ra gửi sang PE Array
    output wire [DATA_WIDTH*9-1:0]    patch_data,       // Bus phẳng chứa 9 pixel song song
    output reg                        patch_valid       // Báo PE Array dữ liệu patch đã sẵn sàng
);

    // Ma trận thanh ghi dịch cửa sổ 3x3 chuyên dụng
    reg [DATA_WIDTH-1:0] win_00, win_01, win_02;
    reg [DATA_WIDTH-1:0] win_10, win_11, win_12;
    reg [DATA_WIDTH-1:0] win_20, win_21, win_22;

    // Bộ đếm trạng thái lấp đầy cửa sổ ngang (Độ sâu tối đa = 3, dùng 2 bit)
    // 0 -> chưa có gì; 1 -> có 1 cột; 2 -> có 2 cột; 3 -> đã lấp đầy >= 3 cột
    reg [1:0] col_fill_cnt;

 always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        //========================================================
        // Reset
        //========================================================
			win_00 <= {DATA_WIDTH{1'b0}}; win_01 <= {DATA_WIDTH{1'b0}}; win_02 <= {DATA_WIDTH{1'b0}};
            win_10 <= {DATA_WIDTH{1'b0}}; win_11 <= {DATA_WIDTH{1'b0}}; win_12 <= {DATA_WIDTH{1'b0}};
            win_20 <= {DATA_WIDTH{1'b0}}; win_21 <= {DATA_WIDTH{1'b0}}; win_22 <= {DATA_WIDTH{1'b0}};

        col_fill_cnt <= 2'b00;
        patch_valid  <= 1'b0;

    end
    else begin

        //========================================================
        // Clear Window (New Frame / New Row)
        //========================================================
        if (window_clear) begin

           win_00 <= {DATA_WIDTH{1'b0}}; win_01 <= {DATA_WIDTH{1'b0}}; win_02 <= {DATA_WIDTH{1'b0}};
            win_10 <= {DATA_WIDTH{1'b0}}; win_11 <= {DATA_WIDTH{1'b0}}; win_12 <= {DATA_WIDTH{1'b0}};
            win_20 <= {DATA_WIDTH{1'b0}}; win_21 <= {DATA_WIDTH{1'b0}}; win_22 <= {DATA_WIDTH{1'b0}};

            col_fill_cnt <= 2'b00;
            patch_valid  <= 1'b0;

        end
        else if (col_window_clear) begin

            col_fill_cnt <= 2'b00;
            patch_valid  <= 1'b0;

        end

        //========================================================
        // Receive New Column
        //========================================================
        else if (pixel_valid) begin

            //-----------------------------
            // Shift Window
            //-----------------------------
            win_00 <= win_01;
            win_01 <= win_02;
            win_02 <= row0_pixel;

            win_10 <= win_11;
            win_11 <= win_12;
            win_12 <= row1_pixel;

            win_20 <= win_21;
            win_21 <= win_22;
            win_22 <= row2_pixel;

            //-----------------------------
            // Column Counter
            //-----------------------------
            if (col_fill_cnt < 2'b11)
                col_fill_cnt <= col_fill_cnt + 1'b1;

            //-----------------------------
            // Patch Valid
            //-----------------------------
            if (col_fill_cnt >= 2'b10)
                patch_valid <= 1'b1;
            else
                patch_valid <= 1'b0;

        end
    end
end





    // 3. Ép phẳng ma trận 3x3 xuất song song sang PE Array
    assign patch_data = {
        win_00, win_01, win_02,
        win_10, win_11, win_12,
        win_20, win_21, win_22
    };

endmodule