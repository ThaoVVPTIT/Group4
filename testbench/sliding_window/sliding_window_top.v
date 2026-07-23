module sliding_window_top #(
    parameter DATA_WIDTH = 8,
    parameter IMG_WIDTH  = 28
)(
    // =========================================================
    // SYSTEM SIGNALS
    // =========================================================
    input  wire                   clk,
    input  wire                   rst_n,

    // =========================================================
    // INPUT PIXEL STREAM
    // =========================================================
    input  wire                   pixel_valid,
    input  wire [DATA_WIDTH-1:0]  pixel_in,

    // =========================================================
    // CONTROL SIGNAL
    // =========================================================
    // Xóa toàn bộ cửa sổ khi bắt đầu frame mới
    input  wire                   window_clear,

    // =========================================================
    // OUTPUT TO PE ARRAY
    // =========================================================
    output wire [DATA_WIDTH*9-1:0] patch_data,
    output wire                    patch_valid,

    // =========================================================
    // OPTIONAL STATUS SIGNALS
    // =========================================================
    output wire                    rows_valid,
    output wire                    new_row
);

    // =========================================================
    // INTERNAL SIGNALS
    // FROM LINE BUFFER TO WINDOW GENERATOR
    // =========================================================

    wire [DATA_WIDTH-1:0] row0_pixel;
    wire [DATA_WIDTH-1:0] row1_pixel;
    wire [DATA_WIDTH-1:0] row2_pixel;

    // =========================================================
    // 1. LINE BUFFER
    // =========================================================

    line_buffer_model #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH (IMG_WIDTH)
    ) u_line_buffer (
        .clk         (clk),
        .rst_n       (rst_n),

        .pixel_valid (pixel_valid),
        .pixel_in    (pixel_in),

        .row0_pixel  (row0_pixel),
        .row1_pixel  (row1_pixel),
        .row2_pixel  (row2_pixel),

        .rows_valid  (rows_valid),
        .new_row     (new_row)
    );

    // =========================================================
    // 2. WINDOW GENERATOR
    // =========================================================

    window_generator #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_window_generator (
        .clk               (clk),
        .rst_n             (rst_n),

        // Dữ liệu pixel từ Line Buffer
        .row0_pixel        (row0_pixel),
        .row1_pixel        (row1_pixel),
        .row2_pixel        (row2_pixel),

        // Cho phép nhận dữ liệu khi Line Buffer đã đủ 3 hàng
        .pixel_valid       (pixel_valid && rows_valid),

        // Sang hàng mới -> reset trạng thái lấp đầy cửa sổ ngang
        .col_window_clear  (new_row),

        // Reset toàn bộ cửa sổ khi bắt đầu frame mới
        .window_clear      (window_clear),

        // Output sang PE Array
        .patch_data        (patch_data),
        .patch_valid       (patch_valid)
    );

endmodule