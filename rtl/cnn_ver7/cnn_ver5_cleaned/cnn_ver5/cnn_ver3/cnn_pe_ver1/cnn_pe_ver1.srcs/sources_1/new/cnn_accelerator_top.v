`timescale 1ns / 1ps
/*------------------------------------------------------------------------
 * Integrated Group-1 top: global scheduler + scheduler-controlled compute
 * engine.  dma_start/layer_select connect to the Group-2 memory controller;
 * dma_done acknowledges that the selected layer data source is available.
 *
 * The Group-1 project keeps the 169x64-bit Pool1 feature map in a local
 * staging RAM, because the supplied integration contract has no 64-bit
 * Memory-to-Conv2 data bus.  The second DMA handshake therefore schedules
 * the local replay.  It can later be replaced by a Group-2 read channel
 * without changing the scheduler/compute handshake.
 *------------------------------------------------------------------------*/
module cnn_accelerator_top (
    input  wire        aclk,
    input  wire        aresetn,

    // RISC-V control/status
    input  wire        start,
    output wire        busy,
    output wire        done,
    output wire        error,
    output wire        prediction_ready,

    // Memory/DMA control (per-image data source handshake)
    output wire        dma_start,
    input  wire        dma_done,
    output wire [1:0]  layer_select,
    input  wire        timeout_flag,

    // Weight-load memory-mapped port (Group 2). One-time load: Group 2/
    // RISC-V write every kernel/bias/mult/shift value for all 5 compute
    // layers, then raise weights_loaded_flag once. Address layout:
    //   [23:21] mod_sel   : 0=Conv1 1=Conv2 2=FC1 3=FC2 4=FC3
    //   [20:19] param_sel : 0=Kernel 1=Bias 2=Mult 3=Shift
    //   [18:0]  offset    : index within that array
    input  wire        dma_weight_we,
    input  wire [23:0] dma_weight_addr,
    input  wire [31:0] dma_weight_data,
    input  wire        weights_loaded_flag,

    // Input image stream (784 scaled pixels)
    output wire        s_axis_tready,
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,

    // Prediction stream (one beat, TLAST asserted)
    input  wire        m_axis_tready,
    output wire [7:0]  m_axis_tdata,
    output wire        m_axis_tvalid,
    output wire        m_axis_tlast
);

    wire scheduler_busy;
    wire sw_load_en_w;
    wire [1:0] sw_cfg_w;
    wire fc_start_w;
    wire layer_done_w;
    wire fc_done_w;

    wire [7:0] m_axis_tdata_w;
    wire       m_axis_tvalid_w;
    wire       m_axis_tlast_w;

    // Consume each raw start assertion at most once.  A pulse presented while
    // busy is intentionally rejected; holding it high cannot turn into a
    // delayed/repeated request after the pending AXI result is accepted.
    reg start_request_armed;
    wire start_request = start && start_request_armed;
    wire scheduler_start = start_request && !scheduler_busy &&
                           !m_axis_tvalid_w;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            start_request_armed <= 1'b1;
        else if (!start)
            start_request_armed <= 1'b1;
        else if (start_request)
            start_request_armed <= 1'b0;
    end

    // busy covers both computation and an unconsumed result beat.  done and
    // prediction_ready may therefore be high while busy is high under output
    // backpressure; the requester must consume the result, then issue start.
    assign busy = scheduler_busy || m_axis_tvalid_w;

    cnn_scheduler u_scheduler (
        .clk              (aclk),
        .rst_n            (aresetn),
        .start            (scheduler_start),
        .busy             (scheduler_busy),
        .done             (done),
        .error            (error),
        .prediction_ready (prediction_ready),
        .dma_start        (dma_start),
        .dma_done         (dma_done),
        .layer_select     (layer_select),
        .sw_load_en       (sw_load_en_w),
        .sw_cfg           (sw_cfg_w),
        .layer_done       (layer_done_w),
        .fc_start         (fc_start_w),
        .fc_done          (fc_done_w),
        .timeout_flag     (timeout_flag),
        .weights_loaded_flag (weights_loaded_flag)
    );

    axis_cnn_mnist_emnist u_core (
        .aclk             (aclk),
        .aresetn          (aresetn),
        .sw_load_en       (sw_load_en_w),
        .sw_cfg           (sw_cfg_w),
        .layer_select     (layer_select),
        .fc_start         (fc_start_w),
        .layer_done       (layer_done_w),
        .fc_done          (fc_done_w),
        .dma_weight_we    (dma_weight_we),
        .dma_weight_addr  (dma_weight_addr),
        .dma_weight_data  (dma_weight_data),
        .s_axis_tready    (s_axis_tready),
        .s_axis_tdata     (s_axis_tdata),
        .s_axis_tvalid    (s_axis_tvalid),
        .m_axis_tready    (m_axis_tready),
        .m_axis_tdata     (m_axis_tdata_w),
        .m_axis_tvalid    (m_axis_tvalid_w),
        .m_axis_tlast     (m_axis_tlast_w)
    );

    assign m_axis_tdata  = m_axis_tdata_w;
    assign m_axis_tvalid = m_axis_tvalid_w;
    assign m_axis_tlast  = m_axis_tlast_w;

endmodule
