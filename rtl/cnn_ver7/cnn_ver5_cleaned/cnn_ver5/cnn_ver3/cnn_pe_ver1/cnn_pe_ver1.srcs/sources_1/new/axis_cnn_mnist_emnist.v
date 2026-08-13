`timescale 1ns / 1ps
/*------------------------------------------------------------------------
 * Module: axis_cnn_mnist_emnist
 *
 * Scheduler-controlled EMNIST compute engine:
 *   AXIS image (784 x 8 bit)
 *     -> Conv1 1x8, 3x3 -> Pool1 13x13x8
 *     -> local Pool1 staging RAM (169 x 64 bit)
 *     -> Conv2 8x24, 3x3 -> Pool2 5x5x24
 *     -> FC 600-120-84-47 -> Argmax -> one-beat AXIS result
 *
 * sw_load_en is a level enable for the selected layer.  Conv1 consumes the
 * input AXIS only in configuration 00.  Conv2 replays the complete Pool1
 * feature map only in configuration 01.  This staging RAM is required: the
 * old direct Pool1-to-Conv2 connection was full-streaming and could finish
 * Conv2 before the scheduler selected it.
 *------------------------------------------------------------------------*/
module axis_cnn_mnist_emnist
    (
        input  wire        aclk,
        input  wire        aresetn,

        // Scheduler -> compute/sliding-window control
        input  wire        sw_load_en,
        input  wire [1:0]  sw_cfg,
        input  wire [1:0]  layer_select,
        input  wire        fc_start,

        // Compute -> scheduler completion events (one clock each)
        output wire        layer_done,
        output wire        fc_done,

        // Weight-load memory-mapped port (Group 2), see cnn_accelerator_top
        // for the [mod_sel|param_sel|offset] address layout.
        input  wire        dma_weight_we,
        input  wire [23:0] dma_weight_addr,
        input  wire [31:0] dma_weight_data,

        // AXI-Stream slave: one 28x28 image, already scaled to 0..127
        output wire        s_axis_tready,
        input  wire [7:0]  s_axis_tdata,
        input  wire        s_axis_tvalid,

        // AXI-Stream master: one result beat per image
        input  wire        m_axis_tready,
        output wire [7:0]  m_axis_tdata,
        output wire        m_axis_tvalid,
        output wire        m_axis_tlast
    );

    localparam integer IMG_PIXELS = 784;
    localparam integer P1_POINTS  = 169;
    localparam integer P2_POINTS  = 25;

    wire rst_n = aresetn;
    wire clk   = aclk;

    // ------------------------------------------------------------------
    // Weight-load address decode (Group 2 memory-mapped write).
    // Only one region is ever selected at a time; param_sel/offset/data
    // are broadcast to every compute layer and gated by each we_* line.
    // ------------------------------------------------------------------
    wire [2:0]  w_mod_sel   = dma_weight_addr[23:21];
    wire [1:0]  w_param_sel = dma_weight_addr[20:19];
    wire [18:0] w_offset    = dma_weight_addr[18:0];

    wire we_conv1 = dma_weight_we && (w_mod_sel == 3'd0);
    wire we_conv2 = dma_weight_we && (w_mod_sel == 3'd1);
    wire we_fc1   = dma_weight_we && (w_mod_sel == 3'd2);
    wire we_fc2   = dma_weight_we && (w_mod_sel == 3'd3);
    wire we_fc3   = dma_weight_we && (w_mod_sel == 3'd4);

    wire conv1_window_enable = sw_load_en &&
                               (layer_select == 2'b00) &&
                               (sw_cfg       == 2'b00);
    wire conv2_window_enable = sw_load_en &&
                               (layer_select == 2'b01) &&
                               (sw_cfg       == 2'b01);

    // ------------------------------------------------------------------
    // Input-frame accounting and AXI admission control
    // ------------------------------------------------------------------
    reg [10:0] px_cnt;
    reg        frame_busy;
    reg        frame_clear;

    reg [7:0]  m_axis_tdata_reg;
    reg        m_axis_tvalid_reg;
    wire       conv1_input_ready;

    wire s_axis_fire = s_axis_tvalid && s_axis_tready;
    wire m_axis_fire = m_axis_tvalid_reg && m_axis_tready;

    // The scheduler opens the input only after Conv1 DMA has completed.
    // frame_clear has priority in both sliding-window buffers, so no AXI
    // beat is acknowledged in that cycle.
    assign s_axis_tready = rst_n && !frame_clear &&
                           conv1_window_enable &&
                           conv1_input_ready &&
                           (!frame_busy || (px_cnt < IMG_PIXELS));

    wire signed [7:0] pixel_in = s_axis_tdata;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            px_cnt      <= 0;
            frame_busy  <= 0;
            frame_clear <= 0;
        end else begin
            frame_clear <= 0;

            if (m_axis_fire) begin
                px_cnt      <= 0;
                frame_busy  <= 0;
                frame_clear <= 1;
            end else if (!frame_busy) begin
                if (s_axis_fire) begin
                    px_cnt     <= 1;
                    frame_busy <= 1;
                end
            end else if (s_axis_fire && (px_cnt < IMG_PIXELS)) begin
                px_cnt <= px_cnt + 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Conv1 + Pool1
    // ------------------------------------------------------------------
    wire [(8*8)-1:0] c1_out_flat;
    wire             c1_valid;
    wire [(8*8)-1:0] p1_out_flat;
    wire             p1_valid;
    wire [(9*8)-1:0] c1_window_flat;
    wire             c1_window_valid;

    conv1_buf_new u_conv1_window (
        .clk            (clk),
        .rst_n          (rst_n),
        .frame_clear    (frame_clear),
        .valid_in       (s_axis_fire),
        .data_in        (pixel_in),
        .win_flat       (c1_window_flat),
        .valid_out_buf  (c1_window_valid)
    );

    maxpool_relu #(
        .CH(8), .DATA_BITS(8), .WIDTH(26), .HEIGHT(26)
    ) u_pool1 (
        .clk            (clk),
        .rst_n          (rst_n),
        .valid_in       (c1_valid),
        .conv_out_flat  (c1_out_flat),
        .max_value_flat (p1_out_flat),
        .valid_out_relu (p1_valid)
    );

    // ------------------------------------------------------------------
    // Pool1 staging memory and layer-1 completion
    // ------------------------------------------------------------------
    reg [7:0] p1_wr_pos;
    reg [7:0] p1_rd_pos;
    reg       p1_replay_active;
    reg       p1_replay_valid_reg;
    reg       conv2_window_enable_d;
    reg       layer_done_c1;

    /*
     * Store one complete 8-channel feature vector per address.  The former
     * eight independent asynchronous arrays created a combinational RAM-to-
     * line-buffer path and could be implemented as distributed RAM.  A
     * synchronous wide RAM plus the replay holding register below is both a
     * natural simple-dual-port BRAM shape and a proper ready/valid producer.
     *
     * This is deliberately one frame deep.  With the current top-level
     * contract there is only one accepted start/result transaction and the
     * shared PE array cannot run Conv1(N+1) while it runs Conv2(N).  A second
     * bank would therefore consume RAM without enabling any legal overlap.
     */
    (* ram_style = "block" *) reg [(8*8)-1:0] p1_mem [0:P1_POINTS-1];
    reg [(8*8)-1:0] p1_replay_data;
    wire [(8*8)-1:0] p1_replay_flat = p1_replay_data;

    always @(posedge clk) begin
        if (rst_n && !frame_clear && p1_valid)
            p1_mem[p1_wr_pos] <= p1_out_flat;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || frame_clear) begin
            p1_wr_pos    <= 0;
            layer_done_c1 <= 0;
        end else begin
            layer_done_c1 <= 0;
            if (p1_valid) begin
                if (p1_wr_pos == P1_POINTS-1) begin
                    p1_wr_pos     <= 0;
                    layer_done_c1 <= 1;
                end else begin
                    p1_wr_pos <= p1_wr_pos + 1'b1;
                end
            end
        end
    end

    // Replay exactly 169 positions after the scheduler selects Conv2.
    // p1_replay_data is a one-entry prefetch/holding register.  Once primed,
    // it sustains one vector per clock and remains stable for arbitrary
    // Conv2 backpressure while keeping the BRAM read path synchronous.
    wire conv2_input_ready;
    wire p1_replay_start = conv2_window_enable && !conv2_window_enable_d;
    wire p1_replay_fire = p1_replay_valid_reg && conv2_input_ready;
    wire p1_replay_slot_available = !p1_replay_valid_reg || p1_replay_fire;
    wire p1_mem_read_en = p1_replay_start ||
                          (p1_replay_slot_available && p1_replay_active);
    wire [7:0] p1_mem_read_addr = p1_replay_start ? 8'd0 : p1_rd_pos;
    // conv2_buf_new has a valid-only input, so expose the accepted transfer
    // pulse rather than the held producer-valid level.
    wire p1_replay_valid = p1_replay_fire;

    // Keep the RAM read in a clock-only process so FPGA synthesis can infer
    // a synchronous block-RAM read port; validity is reset separately.
    always @(posedge clk) begin
        if (rst_n && !frame_clear && p1_mem_read_en)
            p1_replay_data <= p1_mem[p1_mem_read_addr];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || frame_clear) begin
            p1_rd_pos             <= 0;
            p1_replay_active      <= 0;
            p1_replay_valid_reg   <= 0;
            conv2_window_enable_d <= 0;
        end else begin
            conv2_window_enable_d <= conv2_window_enable;

            // sw_load_en starts a complete local read transaction.  Pool2
            // produces its 25th useful output before Conv2 has drained the
            // discarded last row/column of the 11x11 map, so the replay must
            // finish all 169 inputs even if the scheduler advances to FC.
            if (p1_replay_start) begin
                // Prime address zero on the mode-switch edge.  The BRAM
                // output register is therefore valid during the first full
                // Conv2 cycle, with no replay-start bubble.
                p1_rd_pos           <= 1;
                p1_replay_active    <= 1;
                p1_replay_valid_reg <= 1;
            end else if (p1_replay_slot_available) begin
                if (p1_replay_active) begin
                    p1_replay_valid_reg <= 1;

                    if (p1_rd_pos == P1_POINTS-1) begin
                        p1_replay_active <= 0;
                    end else begin
                        p1_rd_pos <= p1_rd_pos + 1'b1;
                    end
                end else begin
                    p1_replay_valid_reg <= 0;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Conv2 + Pool2
    // ------------------------------------------------------------------
    wire [(24*8)-1:0] c2_out_flat;
    wire              c2_valid;
    wire [(24*8)-1:0] p2_out_flat;
    wire              p2_valid;
    wire [(8*9*8)-1:0] c2_window_flat;
    wire               c2_window_valid;
    wire               c2_calc_window_ready;

    // Hold the replay address while a complete registered window is waiting
    // or while the shared physical PE array is busy with the prior window.
    assign conv2_input_ready = rst_n && !frame_clear &&
                               c2_calc_window_ready && !c2_window_valid;

    conv2_buf_new #(.IN_CH(8)) u_conv2_window (
        .clk             (clk),
        .rst_n           (rst_n),
        .frame_clear     (frame_clear),
        .valid_in        (p1_replay_valid),
        .data_in_flat    (p1_replay_flat),
        .win_flat        (c2_window_flat),
        .valid_out_buf   (c2_window_valid)
    );

    // A single 8-lane PE array is physically shared by Conv1 and Conv2.
    ws_conv_shared_engine u_shared_conv (
        .clk                 (clk),
        .rst_n               (rst_n),
        .frame_clear         (frame_clear),
        .mode_conv2          (layer_select == 2'b01),
        .c1_window_valid     (c1_window_valid),
        .c1_window_ready     (conv1_input_ready),
        .c1_window_flat      (c1_window_flat),
        .c1_out_flat         (c1_out_flat),
        .c1_out_valid        (c1_valid),
        .c2_window_valid     (c2_window_valid),
        .c2_window_ready     (c2_calc_window_ready),
        .c2_window_flat      (c2_window_flat),
        .c2_out_flat         (c2_out_flat),
        .c2_out_valid        (c2_valid),
        .weight_we_conv1     (we_conv1),
        .weight_we_conv2     (we_conv2),
        .weight_param_sel   (w_param_sel),
        .weight_offset      (w_offset),
        .weight_data        (dma_weight_data)
    );

    maxpool_relu #(
        .CH(24), .DATA_BITS(8), .WIDTH(11), .HEIGHT(11)
    ) u_pool2 (
        .clk            (clk),
        .rst_n          (rst_n),
        .valid_in       (c2_valid),
        .conv_out_flat  (c2_out_flat),
        .max_value_flat (p2_out_flat),
        .valid_out_relu (p2_valid)
    );

    // With the reused 8-lane engine, the 25th useful Pool2 beat occurs before
    // Conv2 has drained the discarded final row/column of its 11x11 output.
    // Complete the layer only after all 121 Conv2 positions have been emitted;
    // Pool2 and FC have already received their required 25 beats by then.
    reg [6:0] c2_out_pos;
    reg       layer_done_c2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || frame_clear) begin
            c2_out_pos    <= 0;
            layer_done_c2 <= 0;
        end else begin
            layer_done_c2 <= 0;
            if (c2_valid) begin
                if (c2_out_pos == 7'd120) begin
                    c2_out_pos    <= 0;
                    layer_done_c2 <= 1;
                end else begin
                    c2_out_pos <= c2_out_pos + 1'b1;
                end
            end
        end
    end

    // layer_select remains stable while the corresponding enable is active.
    // The mux therefore presents each one-cycle completion event to the
    // scheduler without exposing an event from the other layer.
    assign layer_done = (layer_select == 2'b00) ? layer_done_c1 :
                        (layer_select == 2'b01) ? layer_done_c2 : 1'b0;

    // ------------------------------------------------------------------
    // Flatten + FC + Argmax.  fc_stream first collects all 25 Pool2 beats,
    // then waits for the scheduler's fc_start pulse.
    // ------------------------------------------------------------------
    wire [5:0] predicted_class;
    wire       fc_valid_out;

    fc_stream u_fc (
        .clk             (clk),
        .rst_n           (rst_n),
        .fc_start        (fc_start),
        .valid_in        (p2_valid),
        .data_in_flat    (p2_out_flat),
        .ready           (),
        .predicted_class (predicted_class),
        .valid_out       (fc_valid_out),
        .weight_we_fc1      (we_fc1),
        .weight_we_fc2      (we_fc2),
        .weight_we_fc3      (we_fc3),
        .weight_param_sel   (w_param_sel),
        .weight_offset      (w_offset),
        .weight_data        (dma_weight_data)
    );

    assign fc_done = fc_valid_out;

    // ------------------------------------------------------------------
    // One-beat AXI result skid register.  The class and TLAST remain stable
    // for arbitrary output backpressure.
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tdata_reg  <= 0;
            m_axis_tvalid_reg <= 0;
        end else begin
            if (m_axis_fire)
                m_axis_tvalid_reg <= 0;

            if (fc_valid_out) begin
                m_axis_tdata_reg  <= {2'b00, predicted_class};
                m_axis_tvalid_reg <= 1;
            end
        end
    end

    assign m_axis_tdata  = m_axis_tdata_reg;
    assign m_axis_tvalid = m_axis_tvalid_reg;
    assign m_axis_tlast  = m_axis_tvalid_reg;

endmodule
