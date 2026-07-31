`timescale 1ns / 1ps

// ============================================================================
// MODULE: pool_top (Modular Streaming Max-Pooling IP Core)
// Chu?n  : AXI-Stream Handshake + Scheduler Control
// Latency: Exact 5 Clock Cycles
// ============================================================================

module pool_top #(
    parameter DATA_WIDTH  = 8,
    parameter IMG_WIDTH   = 26,
    parameter IMG_HEIGHT  = 26,
    parameter KERNEL_SIZE = 2,
    parameter STRIDE      = 2,
    parameter C_OUT       = 6
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // GIAO DI?N SCHEDULER (TOP FSM)
    input  wire                         pool_start,        // Xung phát b?t ??u t? Scheduler
    output reg                          pool_ready,        // S?n sàng nh?n l?nh
    output reg                          pool_channel_done, // Xong 1 channel
    output reg                          pool_frame_done,   // Xong ?? C_OUT Channels

    // AXI-STREAM SLAVE (T? CONV PE ARRAY)
    input  wire                         s_axis_valid,
    input  wire signed [DATA_WIDTH-1:0] s_axis_data,
    output wire                         s_axis_ready,

    // AXI-STREAM MASTER (SANG BRAM POOL OUTPUT HO?C LAYER K? T?P)
    output wire                         m_axis_valid,
    output wire signed [DATA_WIDTH-1:0] m_axis_data,
    output wire                         m_axis_last        // Báo pixel cu?i cùng c?a Channel
);

    assign s_axis_ready = 1'b1; // M?ch Pipelined Streaming luôn s?n sàng nh?n d? li?u

    localparam OUT_PIXELS_PER_CH = (IMG_WIDTH / STRIDE) * (IMG_HEIGHT / STRIDE);
    
    reg [11:0] out_pixel_cnt;
    reg [4:0]  channel_cnt;
    reg        internal_clear;

    // ========================================================================
    // 1. FSM HANDSHAKE V?I SCHEDULER & T? ??NG CHUY?N CHANNEL
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pool_ready        <= 1'b1;
            pool_channel_done <= 1'b0;
            pool_frame_done   <= 1'b0;
            out_pixel_cnt     <= 12'd0;
            channel_cnt       <= 5'd0;
            internal_clear    <= 1'b0;
        end else begin
            pool_channel_done <= 1'b0;
            pool_frame_done   <= 1'b0;
            internal_clear    <= 1'b0;

            if (pool_start) begin
                pool_ready     <= 1'b0;
                internal_clear <= 1'b1; // Clear b? ??m khi b?t ??u
            end

            if (m_axis_valid) begin
                if (out_pixel_cnt == OUT_PIXELS_PER_CH - 1) begin
                    out_pixel_cnt     <= 12'd0;
                    pool_channel_done <= 1'b1; // Báo Scheduler xong 1 Channel
                    internal_clear    <= 1'b1; // Reset b? ??m ?ón Channel k? ti?p

                    if (channel_cnt == C_OUT - 1) begin
                        channel_cnt     <= 5'd0;
                        pool_frame_done <= 1'b1; // Báo Scheduler xong tr?n v?n c? Frame!
                        pool_ready      <= 1'b1;
                    end else begin
                        channel_cnt <= channel_cnt + 1'b1;
                    end
                end else begin
                    out_pixel_cnt <= out_pixel_cnt + 1'b1;
                end
            end
        end
    end

    wire sys_clear = pool_start || internal_clear;

    // ========================================================================
    // 2. K?T N?I CÁC SUB-MODULES
    // ========================================================================

    // 2.1. Line Buffer Module
    wire signed [DATA_WIDTH-1:0] row_prev_pixel;
    wire [7:0] col_cnt, row_cnt;
    wire valid_row;

    pool_line_buffer #(
        .DATA_WIDTH(DATA_WIDTH), 
        .IMG_WIDTH(IMG_WIDTH), 
        .KERNEL_SIZE(KERNEL_SIZE)
    ) u_line_buf (
        .clk            (clk), 
        .rst_n          (rst_n), 
        .pool_clear     (sys_clear),
        .pixel_valid    (s_axis_valid), 
        .pixel_in       (s_axis_data),
        .row_prev_pixel (row_prev_pixel), 
        .col_cnt        (col_cnt), 
        .row_cnt        (row_cnt), 
        .valid_row      (valid_row)
    );

    // 2.2. Window Generator Module
    wire signed [DATA_WIDTH-1:0] p0, p1, p2, p3;
    wire window_valid;

    pool_window_gen #(
        .DATA_WIDTH(DATA_WIDTH), 
        .KERNEL_SIZE(KERNEL_SIZE), 
        .STRIDE(STRIDE)
    ) u_window_gen (
        .clk            (clk), 
        .rst_n          (rst_n), 
        .pool_clear     (sys_clear),
        .pixel_valid    (s_axis_valid), 
        .pixel_in       (s_axis_data), 
        .row_prev_pixel (row_prev_pixel),
        .col_cnt        (col_cnt), 
        .row_cnt        (row_cnt), 
        .valid_row      (valid_row),
        .p_top_left(p0), .p_top_right(p1), 
        .p_bot_left(p2), .p_bot_right(p3),
        .window_valid   (window_valid)
    );

    // 2.3. Pipelined Max Tree Core
    wire core_valid;
    wire signed [DATA_WIDTH-1:0] core_data;

    pool_core #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_core (
        .clk       (clk), 
        .rst_n     (rst_n), 
        .pool_clear(sys_clear),
        .in_valid  (window_valid), 
        .p0(p0), .p1(p1), .p2(p2), .p3(p3),
        .out_valid (core_valid), 
        .pool_out  (core_data)
    );

    // ========================================================================
    // 3. MASTER AXI-STREAM ASSIGNMENT
    // ========================================================================
    assign m_axis_valid = core_valid;
    assign m_axis_data  = core_data;
    assign m_axis_last  = core_valid && (out_pixel_cnt == OUT_PIXELS_PER_CH - 1);

endmodule


// ============================================================================
// MODULE: pool_line_buffer (?Ã FIX S?CH L?I 'X' RAM)
// ============================================================================

module pool_line_buffer #(
    parameter DATA_WIDTH  = 8,
    parameter IMG_WIDTH   = 26,
    parameter KERNEL_SIZE = 2
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         pool_clear,
    input  wire                         pixel_valid,
    input  wire signed [DATA_WIDTH-1:0] pixel_in,
    
    output reg  signed [DATA_WIDTH-1:0] row_prev_pixel,
    output wire [7:0]                   col_cnt,
    output wire [7:0]                   row_cnt,
    output wire                         valid_row
);

    (* ram_style = "distributed" *) reg signed [DATA_WIDTH-1:0] line_buf [0:IMG_WIDTH-1];

    reg [7:0] col_cnt_reg;
    reg [7:0] row_cnt_reg;

    assign col_cnt   = col_cnt_reg;
    assign row_cnt   = row_cnt_reg;
    assign valid_row = (row_cnt_reg >= (KERNEL_SIZE - 1));

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || pool_clear) begin
            col_cnt_reg    <= 8'd0;
            row_cnt_reg    <= 8'd0;
            row_prev_pixel <= {DATA_WIDTH{1'b0}};
            
            // ? KH?C PHÚC TRI?T ??: XÓA S?CH BRAM V? 0 KHI RESET
            for (i = 0; i < IMG_WIDTH; i = i + 1) begin
                line_buf[i] <= {DATA_WIDTH{1'b0}};
            end
        end else if (pixel_valid) begin
            row_prev_pixel        <= line_buf[col_cnt_reg];
            line_buf[col_cnt_reg] <= pixel_in;

            if (col_cnt_reg == IMG_WIDTH - 1) begin
                col_cnt_reg <= 8'd0;
                if (row_cnt_reg < IMG_WIDTH)
                    row_cnt_reg <= row_cnt_reg + 1'b1;
            end else begin
                col_cnt_reg <= col_cnt_reg + 1'b1;
            end
        end
    end

endmodule


// ============================================================================
// MODULE: pool_window_gen
// ============================================================================

module pool_window_gen #(
    parameter DATA_WIDTH  = 8,
    parameter KERNEL_SIZE = 2,
    parameter STRIDE      = 2
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         pool_clear,
    input  wire                         pixel_valid,
    input  wire signed [DATA_WIDTH-1:0] pixel_in,
    input  wire signed [DATA_WIDTH-1:0] row_prev_pixel,
    input  wire [7:0]                   col_cnt,
    input  wire [7:0]                   row_cnt,
    input  wire                         valid_row,

    output reg  signed [DATA_WIDTH-1:0] p_top_left, p_top_right,
    output reg  signed [DATA_WIDTH-1:0] p_bot_left, p_bot_right,
    output wire                         window_valid
);

    wire valid_col = (col_cnt >= (KERNEL_SIZE - 1));

    wire row_odd = (row_cnt % STRIDE == (STRIDE - 1));
    wire col_odd = (col_cnt % STRIDE == (STRIDE - 1));

    assign window_valid = pixel_valid && valid_row && valid_col && row_odd && col_odd;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || pool_clear) begin
            p_top_left  <= -8'sd128; p_top_right <= -8'sd128;
            p_bot_left  <= -8'sd128; p_bot_right <= -8'sd128;
        end else if (pixel_valid) begin
            p_top_left  <= p_top_right;
            p_bot_left  <= p_bot_right;
            p_top_right <= row_prev_pixel;
            p_bot_right <= pixel_in;
        end
    end

endmodule


// ============================================================================
// MODULE: pool_core
// ============================================================================

module pool_core #(
    parameter DATA_WIDTH = 8
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         pool_clear,
    input  wire                         in_valid,

    input  wire signed [DATA_WIDTH-1:0] p0,
    input  wire signed [DATA_WIDTH-1:0] p1,
    input  wire signed [DATA_WIDTH-1:0] p2,
    input  wire signed [DATA_WIDTH-1:0] p3,

    output reg                          out_valid,
    output reg  signed [DATA_WIDTH-1:0] pool_out
);

    wire signed [DATA_WIDTH-1:0] max01 = (p0 > p1) ? p0 : p1;
    wire signed [DATA_WIDTH-1:0] max23 = (p2 > p3) ? p2 : p3;

    reg signed [DATA_WIDTH-1:0] max01_reg;
    reg signed [DATA_WIDTH-1:0] max23_reg;
    reg                         vld_stage1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || pool_clear) begin
            max01_reg  <= -8'sd128;
            max23_reg  <= -8'sd128;
            vld_stage1 <= 1'b0;
        end else begin
            vld_stage1 <= in_valid;
            if (in_valid) begin
                max01_reg <= max01;
                max23_reg <= max23;
            end
        end
    end

    wire signed [DATA_WIDTH-1:0] max_final = (max01_reg > max23_reg) ? max01_reg : max23_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || pool_clear) begin
            out_valid <= 1'b0;
            pool_out  <= -8'sd128;
        end else begin
            out_valid <= vld_stage1;
            if (vld_stage1) begin
                pool_out <= max_final;
            end
        end
    end

endmodule