`timescale 1ns/1ps

module tb_scheduler;

    localparam ST_IDLE         = 4'd0;
    localparam ST_READ_CONFIG  = 4'd1;
    localparam ST_CHECK_CONFIG = 4'd2;
    localparam ST_START_DMA    = 4'd3;
    localparam ST_WAIT_DMA     = 4'd4;
    localparam ST_START_WINDOW = 4'd5;
    localparam ST_WAIT_PATCH   = 4'd6;
    localparam ST_START_PE     = 4'd7;
    localparam ST_WAIT_PE      = 4'd8;
    localparam ST_CHECK_LAYER  = 4'd9;
    localparam ST_START_FC     = 4'd10;
    localparam ST_WAIT_FC      = 4'd11;
    localparam ST_DONE         = 4'd12;

    reg         clk, rst_n;
    reg         start;
    reg  [3:0]  kernel_size, stride, padding, num_conv_layers;
    reg         layer_has_pooling;
    reg  [31:0] mem_base_addr;
    wire        busy, done, prediction_ready, error;
    wire [2:0]  error_code;
    wire [3:0]  sched_state;

    wire        sw_load_en;
    wire [3:0]  sw_kernel_cfg, sw_stride_cfg, sw_padding_cfg;
    wire        patch_valid, patch_last;

    wire        pe_compute_en, pe_layer_has_pooling;
    wire        pe_ready, pe_done;

    wire        fc_start;
    reg         fc_done_drv;

    wire        buffer_swap, bram_ready, dma_start;
    reg         dma_done_drv;

    reg [3:0] state_timer;
    reg [3:0] prev_state;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin state_timer <= 0; prev_state <= ST_IDLE; end
        else begin
            if (sched_state != prev_state) state_timer <= 0;
            else state_timer <= state_timer + 1;
            prev_state <= sched_state;
        end
    end

    // ---- Số Patch mỗi lớp (cố định = 2 cho test này) + patch_last latch ----
    localparam NUM_PATCHES_PER_LAYER = 4'd2;
    reg [3:0] patch_num;
    reg patch_last_latched;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) patch_num <= 0;
        else if (sched_state == ST_READ_CONFIG && state_timer == 0) patch_num <= 0;
        else if (patch_valid) patch_num <= patch_num + 1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) patch_last_latched <= 0;
        else if (patch_valid) patch_last_latched <= (patch_num == NUM_PATCHES_PER_LAYER - 1);
    end

    // ---- Mô hình giả lập các phân hệ khác ----
    assign bram_ready  = 1'b1;
    assign dma_done     = dma_done_drv;
    wire dma_done_pulse = (sched_state == ST_WAIT_DMA)   && (state_timer == 4'd3);
    assign patch_valid  = (sched_state == ST_WAIT_PATCH) && (state_timer == 4'd2);
    assign patch_last   = patch_last_latched;
    assign pe_ready      = 1'b1;
    assign pe_done       = (sched_state == ST_WAIT_PE) && (state_timer == 4'd4);
    assign fc_done       = fc_done_drv;
    wire fc_done_pulse   = (sched_state == ST_WAIT_FC) && (state_timer == 4'd5);
    wire layer_cfg_valid = (sched_state == ST_READ_CONFIG) && (state_timer == 4'd2);

    wire dma_done;

    always @(*) dma_done_drv = dma_done_pulse;
    always @(*) fc_done_drv  = fc_done_pulse;

    scheduler #(
        .DMA_TIMEOUT(64), .PATCH_TIMEOUT(64), .PE_TIMEOUT(64), .FC_TIMEOUT(64)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .start(start),
        .layer_cfg_valid(layer_cfg_valid),
        .kernel_size(kernel_size), .stride(stride), .padding(padding),
        .layer_has_pooling(layer_has_pooling),
        .num_conv_layers(num_conv_layers),
        .mem_base_addr(mem_base_addr),
        .busy(busy), .done(done), .prediction_ready(prediction_ready),
        .error(error), .error_code(error_code), .sched_state(sched_state),

        .sw_load_en(sw_load_en), .sw_kernel_cfg(sw_kernel_cfg),
        .sw_stride_cfg(sw_stride_cfg), .sw_padding_cfg(sw_padding_cfg),
        .patch_valid(patch_valid), .patch_last(patch_last),

        .pe_compute_en(pe_compute_en), .pe_layer_has_pooling(pe_layer_has_pooling),
        .pe_ready(pe_ready), .pe_done(pe_done),

        .fc_start(fc_start), .fc_done(fc_done),

        .buffer_swap(buffer_swap), .bram_ready(bram_ready),
        .dma_start(dma_start), .dma_done(dma_done)
    );

    always #5 clk = ~clk;

    function [8*14-1:0] state_name;
        input [3:0] s;
        begin
            case (s)
                ST_IDLE:         state_name = "IDLE";
                ST_READ_CONFIG:  state_name = "READ_CONFIG";
                ST_CHECK_CONFIG: state_name = "CHECK_CONFIG";
                ST_START_DMA:    state_name = "START_DMA";
                ST_WAIT_DMA:     state_name = "WAIT_DMA";
                ST_START_WINDOW: state_name = "START_WINDOW";
                ST_WAIT_PATCH:   state_name = "WAIT_PATCH";
                ST_START_PE:     state_name = "START_PE";
                ST_WAIT_PE:      state_name = "WAIT_PE";
                ST_CHECK_LAYER:  state_name = "CHECK_LAYER";
                ST_START_FC:     state_name = "START_FC";
                ST_WAIT_FC:      state_name = "WAIT_FC";
                ST_DONE:         state_name = "DONE";
                default:         state_name = "UNKNOWN";
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst_n && sched_state != prev_state)
            $display("[t=%0t ns] state -> %0s", $time, state_name(sched_state));
    end

    initial begin
        $dumpfile("scheduler_wave.vcd");
        $dumpvars(0, tb_scheduler);
    end

    integer errors;
    initial begin
        errors = 0;
        clk = 0; rst_n = 0; start = 0;
        kernel_size = 4'd5; stride = 4'd1; padding = 4'd0;
        layer_has_pooling = 1'b1;
        num_conv_layers = 4'd2;      // 2 lớp Convolution cho test này
        mem_base_addr = 32'h1000_0000;

        $display("================================================");
        $display(" TESTBENCH v5: 2 lop Conv (2 Patch/lop) + 1 luot FC");
        $display("================================================");

        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        start = 1;
        @(posedge clk);
        start = 0;

        wait (done == 1'b1);
        $display("------------------------------------------------");
        $display("[t=%0t ns] done=1, prediction_ready=%0b, error=%0b, error_code=%0b",
                  $time, prediction_ready, error, error_code);

        if (prediction_ready !== 1'b1) begin
            $display("FAIL: prediction_ready khong duoc assert cung luc done");
            errors = errors + 1;
        end
        if (error !== 1'b0) begin
            $display("FAIL: error bi assert ngoai y muon");
            errors = errors + 1;
        end

        repeat (5) @(posedge clk);

        if (errors == 0)
            $display("==================== PASS: tat ca kiem tra deu dung ====================");
        else
            $display("==================== FAIL: %0d loi duoc phat hien ====================", errors);

        $finish;
    end

    initial begin
        #30000;
        $display("WATCHDOG: mo phong vuot qua 30000 ns -> co the FSM bi treo");
        $finish;
    end

endmodule