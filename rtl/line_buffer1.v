module line_buffer_model_ver1 #(
    parameter DATA_WIDTH = 8,
    parameter IMG_WIDTH  = 28
)(
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire                   pixel_valid,
    input  wire [DATA_WIDTH-1:0]  pixel_in,

    // D? li?u 3 hàng song song 
    output wire [DATA_WIDTH-1:0]  row0_pixel, // Hàng trên cùng (C? nh?t)
    output wire [DATA_WIDTH-1:0]  row1_pixel, // Hàng gi?a
    output wire [DATA_WIDTH-1:0]  row2_pixel, // Hàng d??i cùng (Hi?n t?i)

    // Tín hi?u ??ng b? tr?ng thái
    output wire                   rows_valid, // ??I THÀNH WIRE: Lên 1 ngay l?p t?c cùng nh?p v?i pixel_in th? 3
    output reg                    new_row     // Xung báo chuy?n hàng (Clock N+1)
);

    reg [DATA_WIDTH-1:0] mem_line0 [0:IMG_WIDTH-1];
    reg [DATA_WIDTH-1:0] mem_line1 [0:IMG_WIDTH-1];

    reg [$clog2(IMG_WIDTH)-1:0] col_cnt;
    reg [1:0]                   row_phase;
    reg                         row_end_tick;

    integer i;

    // =========================================================================
    // READ-BEFORE-WRITE (Gán tr?c ti?p b?ng m?ch t? h?p)
    // =========================================================================
    assign row2_pixel = pixel_in;
    assign row1_pixel = mem_line1[col_cnt];
    assign row0_pixel = mem_line0[col_cnt];

    // B?T B?NH: Chuy?n rows_valid sang assign t? h?p ?? TRI?T TIÊU TR? 1 CLOCK
    assign rows_valid = (pixel_valid && (row_phase == 2'b10));

    // =========================================================================
    // LOGIC ?I?U KHI?N HÀNG VÀ B? ??M
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_cnt      <= 0;
            row_phase    <= 2'b00;
            row_end_tick <= 1'b0;
            new_row      <= 1'b0;
            
            for (i = 0; i < IMG_WIDTH; i = i + 1) begin
                mem_line0[i] <= {DATA_WIDTH{1'b0}};
                mem_line1[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            // Xung chuy?n hàng nh?p N+1
            if (row_end_tick) begin
                new_row      <= 1'b1;
                row_end_tick <= 1'b0;
            end else begin
                new_row      <= 1'b0;
            end

            // X? lý lu?ng Stream d? li?u
            if (pixel_valid) begin
                mem_line1[col_cnt] <= pixel_in;
                mem_line0[col_cnt] <= mem_line1[col_cnt];

                if (col_cnt == IMG_WIDTH - 1) begin
                    col_cnt      <= 0;
                    row_end_tick <= 1'b1;
                    
                    if (row_phase < 2'b10) begin
                        row_phase <= row_phase + 1'b1;
                    end
                end else begin
                    col_cnt      <= col_cnt + 1'b1;
                    row_end_tick <= 1'b0;
                end
            end
        end
    end

endmodule