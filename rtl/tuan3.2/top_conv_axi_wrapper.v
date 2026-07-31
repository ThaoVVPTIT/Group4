`timescale 1ns / 1ps

// ============================================================================
// MODULE: conv_feature_extractor_wrapper
// Ch?c n?ng: ?óng gói kh?i Conv1-Pool1-Conv2-Pool2 ?? chu?n hóa giao ti?p.
// M?c ?ích : Giúp d? dàng c?m vào Scheduler (scheduler.v) và AXI4-Lite sau này.
// ============================================================================

module conv_feature_extractor_wrapper #(
    parameter DATA_WIDTH  = 8,
    parameter C_OUT_POOL2 = 16
)(
    input  wire clk,
    input  wire rst_n,

    // ========================================================================
    // 1. CHU?N GIAO TI?P CONTROL HANDSHAKE (Dành riêng cho Scheduler)
    // ========================================================================
    input  wire        sched_pe_compute_en,  // Scheduler h?/nâng l?nh ch?y (pe_compute_en)
    output wire        sched_pe_ready,       // Báo s?n sàng cho Scheduler (pe_ready)
    output wire        sched_pe_done,        // Báo hoàn thành cho Scheduler (pe_done)

    // ========================================================================
    // 2. CHU?N GIAO TI?P STREAM DATA IN (Dành cho LineBuffer / Sliding Window / DMA)
    // ========================================================================
    input  wire        axis_in_valid,        // Tín hi?u valid d? li?u vào
    input  wire signed [DATA_WIDTH-1:0] axis_in_data, // D? li?u pixel (8-bit)
    output wire        axis_in_ready,        // Báo ready nh?n data

    // ========================================================================
    // 3. CHU?N GIAO TI?P STREAM DATA OUT (Dành cho Flatten / FC / RAM Buffer)
    // ========================================================================
    output wire        axis_out_valid,       // Tín hi?u valid d? li?u ra
    output wire signed [DATA_WIDTH*C_OUT_POOL2-1:0] axis_out_data, // Bus 128-bit (16ch x 8bit)
    output wire        axis_out_last         // Tín hi?u báo xong frame/layer
);

    // ========================================================================
    // KH?I T?O KH?I THU?T TOÁN TÍNH TOÁN CORE (top_conv_feature_extractor)
    // ========================================================================
    top_conv_feature_extractor #(
        .DATA_WIDTH  (DATA_WIDTH),
        .C_OUT_POOL1 (6),
        .C_OUT_POOL2 (C_OUT_POOL2)
    ) u_feature_extractor_core (
        .clk                 (clk),
        .rst_n               (rst_n),

        // Map tr?c ti?p c?ng Control Handshake v?i giao ti?p c?a Scheduler
        .pe_compute_en       (sched_pe_compute_en),
        .pe_ready            (sched_pe_ready),
        .pe_done             (sched_pe_done),

        // Map Stream Data In
        .pixel_valid         (axis_in_valid),
        .pixel_in            (axis_in_data),

        // Map Stream Data Out
        .pool2_out_valid     (axis_out_valid),
        .pool2_out_ch        (axis_out_data),
        .pool2_out_last      (axis_out_last)
    );

    // Chu?n hóa ???ng ready vào
    assign axis_in_ready = sched_pe_ready;

endmodule