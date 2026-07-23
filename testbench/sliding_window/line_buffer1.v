module line_buffer1 #(
    parameter DATA_WIDTH = 8,
    parameter IMG_WIDTH  = 28
)(
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire                   pixel_valid,
    input  wire [DATA_WIDTH-1:0]  pixel_in,

    // dữ liệu 3 hàng song song 
    output wire [DATA_WIDTH-1:0]  row0_pixel, // Hàng trên cùng (Cũ nhất - delay 2 dòng)
    output wire [DATA_WIDTH-1:0]  row1_pixel, // Hàng giữa     (delay 1 dòng)
    output wire [DATA_WIDTH-1:0]  row2_pixel, // Hàng dưới cùng (Hiện tại - không delay)

    // Tín hiệu đồng bộ trạng thái cấp cho window_generator
    output reg                    rows_valid, // Lên 1 ngay tại pixel đầu tiên của hàng thứ 3
    output reg                    new_row     // Xung báo chuyển hàng, tích cực tại Clock N+1 an toàn (Cách 1)
);

    // Sử dụng 2 mảng thanh ghi abstract để lưu trữ dữ liệu của 2 hàng trước đó
    reg [DATA_WIDTH-1:0] mem_line0 [0:IMG_WIDTH-1];
    reg [DATA_WIDTH-1:0] mem_line1 [0:IMG_WIDTH-1];

    // Bộ đếm vị trí cột logic nội bộ (0 đến IMG_WIDTH-1)
    reg [$clog2(IMG_WIDTH)-1:0] col_cnt;

    // Bộ đếm giai đoạn hàng để quản lý rows_valid
    // 0: Đang nạp hàng 0; 1: Đang nạp hàng 1; 2: Từ hàng 2 trở đi (Đủ dữ liệu)
    reg [1:0] row_phase;

    // Cờ báo hiệu đã xử lý xong pixel cuối cùng của hàng (tại Clock N)
    reg row_end_tick;

    // =========================================================================
    // CƠ CHẾ READ-BEFORE-WRITE (ĐỒNG BỘ THẲNG CỘT TUYỆT ĐỐI)
    // =========================================================================
    // Sử dụng mạch tổ hợp assign để lấy dữ liệu cũ ra truoc khi bị ghi đè tại cạnh lên clock.
    // Đảm bảo tại chu kỳ xử lý, cả 3 hàng đều chung một chỉ số cột logic `col_cnt`.
    assign row2_pixel = pixel_in;
    assign row1_pixel = mem_line1[col_cnt];
    assign row0_pixel = mem_line0[col_cnt];

    // =========================================================================
    // LOGIC ĐIỀU KHIỂN HÀNG VÀ ĐỒNG BỘ
    // =========================================================================
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_cnt      <= 0;
            row_phase    <= 2'b00;
            row_end_tick <= 1'b0;
            new_row      <= 1'b0;
            rows_valid   <= 1'b0;
            
            // Xóa mảng thanh ghi khi reset để tránh rác mô phỏng
            for (i = 0; i < IMG_WIDTH; i = i + 1) begin
                mem_line0[i] <= {DATA_WIDTH{1'b0}};
                mem_line1[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            // Tạo xung chuyển hàng an toàn ở chu kỳ N+1 (Cách 1)
            if (row_end_tick) begin
                new_row      <= 1'b1;
                row_end_tick <= 1'b0;
            end else begin
                new_row      <= 1'b0;
            end

            // Xử lý luồng dữ liệu stream
            if (pixel_valid) begin
                // Tiến hành ghi dịch chuyển dữ liệu theo chiều dọc vào mảng thanh ghi
                mem_line1[col_cnt] <= pixel_in;          // Nạp pixel hiện tại vào hàng giữa
                mem_line0[col_cnt] <= mem_line1[col_cnt]; // Đẩy pixel cũ của hàng giữa lên hàng trên cùng

                // Quản lý bộ đếm vị trí không gian
                if (col_cnt == IMG_WIDTH - 1) begin
                    col_cnt      <= 0;
                    row_end_tick <= 1'b1; // Đánh dấu đã nhận xong ô cuoi của một hàng tại Clock N
                    
                    // Tăng phase quản lý hàng (Bão hòa tại phase 2)
                    if (row_phase < 2'b10) begin
                        row_phase <= row_phase + 1'b1;
                    end
                end else begin
                    col_cnt      <= col_cnt + 1'b1;
                    row_end_tick <= 1'b0;
                end
            end

            // Khi kết thúc hàng thứ 2 (Hàng 1), row_phase cập nhật lên bằng 2.
            // Đúng chu kỳ tiếp theo, khi pixel_valid = 1 của hàng thứ 3 (Hàng 2) vừa chui vào, 
            // rows_valid vọt lên 1 chuẩn chỉ từ pixel đầu tiên của hàng 3.
            if (pixel_valid && (row_phase == 2'b10)) begin
                rows_valid <= 1'b1; // khi đã có 2 hàng trước đó
            end else begin
                rows_valid <= 1'b0;
            end
        end
    end

endmodule