`timescale 1ns / 1ps

/*------------------------------------------------------------------------
 * Module: ws_conv_shared_engine
 *
 * One physical eight-lane convolution array shared by Conv1 and Conv2.
 * Each lane contains one 3x3 PE (nine signed INT8 multipliers), followed by
 * one shared lane of fixed-point requantization.
 *
 * Conv1 mode (1 -> 8):
 *   - all eight lanes operate in parallel;
 *   - two registered stages; initiation interval = one window.
 *
 * Conv2 mode (8 -> 24):
 *   - one 3x3x8 window is held locally;
 *   - the eight lanes iterate over C_in=0..7 and three C_out groups;
 *   - eight INT32 accumulators are output-stationary for the current pixel;
 *   - all 24 output bytes are assembled before one valid pulse.
 *
 * Weight RF:
 *   - 72 independent banks = 8 lanes x 9 taps;
 *   - depth 0 stores the Conv1 weight;
 *   - depths 1..24 store Conv2 [group][C_in] weights;
 *   - all weights remain resident while spatial windows are streamed.
 * This banked structure avoids a non-physical 72-read-port monolithic BRAM.
 *------------------------------------------------------------------------*/
module ws_conv_shared_engine #(
    parameter integer DATA_BITS = 8,
    parameter integer LANES     = 8
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         frame_clear,
    input  wire                         mode_conv2,

    input  wire                         c1_window_valid,
    output wire                         c1_window_ready,
    input  wire [(9*DATA_BITS)-1:0]     c1_window_flat,
    output wire [(8*DATA_BITS)-1:0]     c1_out_flat,
    output reg                          c1_out_valid,

    input  wire                         c2_window_valid,
    output wire                         c2_window_ready,
    input  wire [(8*9*DATA_BITS)-1:0]   c2_window_flat,
    output wire [(24*DATA_BITS)-1:0]    c2_out_flat,
    output reg                          c2_out_valid,

    input  wire                         weight_we_conv1,
    input  wire                         weight_we_conv2,
    input  wire [1:0]                   weight_param_sel,
    input  wire [18:0]                  weight_offset,
    input  wire [31:0]                  weight_data
);

    localparam integer WINDOW_BITS = 9*DATA_BITS;
    localparam integer C2_IN_CH    = 8;
    localparam integer C2_OUT_CH   = 24;
    localparam integer C2_GROUPS   = 3;
    localparam integer BANKS       = LANES*9;
    localparam integer RF_DEPTH    = 25; // Conv1 + 3 Conv2 groups x 8 C_in

    // ------------------------------------------------------------------
    // Divider-free OIHW DMA address conversion.
    //
    // Conv1's OIHW kernel address is already exactly lane*9+tap, hence the
    // low seven offset bits are the physical bank number.
    //
    // For Conv2, q=floor(offset/9) is [out_channel*8+in_channel] and the
    // remainder is the tap.  For every legal offset (0..1727), the unsigned
    // identity floor(offset*1821/2^14) == floor(offset/9) is exact.  1821 is
    // expanded below as a balanced shift/add network, so no generic / or %
    // operator remains on the write path.  The decoded write is registered;
    // this accepts one DMA word per clock while giving the decoder a clean
    // timing boundary before the 72 bank write enables.
    // ------------------------------------------------------------------
    wire [6:0] c1_write_bank_dec = weight_offset[6:0];

    wire [21:0] c2_div_x = {11'd0, weight_offset[10:0]};
    wire [21:0] c2_div_sum0 = (c2_div_x << 10) + (c2_div_x << 9);
    wire [21:0] c2_div_sum1 = (c2_div_x << 8)  + (c2_div_x << 4);
    wire [21:0] c2_div_sum2 = (c2_div_x << 3)  + (c2_div_x << 2);
    wire [21:0] c2_div_sum3 = c2_div_sum2 + c2_div_x;
    wire [21:0] c2_div9_scaled =
        (c2_div_sum0 + c2_div_sum1) + c2_div_sum3;

    wire [7:0]  c2_filter_linear_dec = c2_div9_scaled[21:14];
    wire [10:0] c2_filter_linear_ext = {3'd0, c2_filter_linear_dec};
    wire [10:0] c2_filter_times9 =
        (c2_filter_linear_ext << 3) + c2_filter_linear_ext;
    wire [10:0] c2_tap_remainder =
        weight_offset[10:0] - c2_filter_times9;

    // q={group[1:0], lane[2:0], cin[2:0]} for 24x8 filters.
    wire [1:0] c2_write_group_dec = c2_filter_linear_dec[7:6];
    wire [2:0] c2_write_lane_dec  = c2_filter_linear_dec[5:3];
    wire [2:0] c2_write_cin_dec   = c2_filter_linear_dec[2:0];
    wire [3:0] c2_write_tap_dec   = c2_tap_remainder[3:0];
    wire [6:0] c2_write_lane_ext  = {4'd0, c2_write_lane_dec};
    wire [6:0] c2_write_bank_dec  =
        (c2_write_lane_ext << 3) + c2_write_lane_ext +
        {3'd0, c2_write_tap_dec};
    wire [4:0] c2_write_depth_dec =
        5'd1 + {c2_write_group_dec, 3'b000} +
        {2'b00, c2_write_cin_dec};

    reg                 c1_kernel_we_q;
    reg [6:0]           c1_write_bank_q;
    reg [DATA_BITS-1:0] c1_weight_data_q;
    reg                 c2_kernel_we_q;
    reg [6:0]           c2_write_bank_q;
    reg [4:0]           c2_write_depth_q;
    reg [DATA_BITS-1:0] c2_weight_data_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c1_kernel_we_q    <= 1'b0;
            c1_write_bank_q   <= 7'd0;
            c1_weight_data_q  <= {DATA_BITS{1'b0}};
            c2_kernel_we_q    <= 1'b0;
            c2_write_bank_q   <= 7'd0;
            c2_write_depth_q  <= 5'd0;
            c2_weight_data_q  <= {DATA_BITS{1'b0}};
        end else begin
            c1_kernel_we_q <= weight_we_conv1 &&
                              (weight_param_sel == 2'd0) &&
                              (weight_offset < 72);
            c1_write_bank_q  <= c1_write_bank_dec;
            c1_weight_data_q <= weight_data[DATA_BITS-1:0];

            c2_kernel_we_q <= weight_we_conv2 &&
                              (weight_param_sel == 2'd0) &&
                              (weight_offset < 1728);
            c2_write_bank_q  <= c2_write_bank_dec;
            c2_write_depth_q <= c2_write_depth_dec;
            c2_weight_data_q <= weight_data[DATA_BITS-1:0];
        end
    end

    reg [2:0] c2_cin_idx;
    reg [1:0] c2_group_idx;
    localparam [1:0] C2_IDLE  = 2'd0,
                     C2_MAC   = 2'd1,
                     C2_QUANT = 2'd2;
    reg [1:0] c2_state;

    wire [4:0] active_weight_depth = mode_conv2
        ? (1 + c2_group_idx*C2_IN_CH + c2_cin_idx)
        : 0;

    wire [(BANKS*DATA_BITS)-1:0] active_weight_flat;

    genvar bank;
    generate
        for (bank = 0; bank < BANKS; bank = bank + 1) begin : g_weight_bank
            reg signed [DATA_BITS-1:0] weight_rf [0:RF_DEPTH-1];

            always @(posedge clk) begin
                if (c1_kernel_we_q && (c1_write_bank_q == bank))
                    weight_rf[0] <= c1_weight_data_q;

                if (c2_kernel_we_q && (c2_write_bank_q == bank))
                    weight_rf[c2_write_depth_q] <= c2_weight_data_q;
            end

            assign active_weight_flat[bank*DATA_BITS +: DATA_BITS] =
                weight_rf[active_weight_depth];
        end
    endgenerate

    // Bias/requant parameters remain resident beside the filter RF.
    reg signed [31:0] c1_bias  [0:7];
    reg signed [31:0] c1_mult  [0:7];
    reg        [7:0]  c1_shift [0:7];
    reg signed [31:0] c2_bias  [0:23];
    reg signed [31:0] c2_mult  [0:23];
    reg        [7:0]  c2_shift [0:23];

    always @(posedge clk) begin
        if (weight_we_conv1 && (weight_offset < 8)) begin
            case (weight_param_sel)
                2'd1: c1_bias [weight_offset[2:0]] <= weight_data;
                2'd2: c1_mult [weight_offset[2:0]] <= weight_data;
                2'd3: c1_shift[weight_offset[2:0]] <= weight_data[7:0];
                default: ;
            endcase
        end

        if (weight_we_conv2 && (weight_offset < 24)) begin
            case (weight_param_sel)
                2'd1: c2_bias [weight_offset[4:0]] <= weight_data;
                2'd2: c2_mult [weight_offset[4:0]] <= weight_data;
                2'd3: c2_shift[weight_offset[4:0]] <= weight_data[7:0];
                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // The only physical 8 x 3x3 PE array in the accelerator.
    // ------------------------------------------------------------------
    reg [(8*9*DATA_BITS)-1:0] c2_window_reg;
    wire [WINDOW_BITS-1:0] c2_active_window =
        c2_window_reg[c2_cin_idx*WINDOW_BITS +: WINDOW_BITS];
    wire [WINDOW_BITS-1:0] selected_window =
        mode_conv2 ? c2_active_window : c1_window_flat;
    wire pe_compute_enable = mode_conv2
        ? (c2_state == C2_MAC)
        : (c1_window_valid && c1_window_ready);
    wire [WINDOW_BITS-1:0] active_window = pe_compute_enable
        ? selected_window : {WINDOW_BITS{1'b0}};

    wire signed [31:0] lane_dot [0:LANES-1];
    genvar lane;
    generate
        for (lane = 0; lane < LANES; lane = lane + 1) begin : g_physical_lane
            // Isolate both operands while the lane is idle.  The sequential
            // dot/accumulator registers below are already clock-enabled by
            // their matching valid/state conditions.
            wire [WINDOW_BITS-1:0] lane_weight_active = pe_compute_enable
                ? active_weight_flat[lane*WINDOW_BITS +: WINDOW_BITS]
                : {WINDOW_BITS{1'b0}};

            ws_pe_lane_3x3 #(.DATA_BITS(DATA_BITS)) u_lane (
                .activation_flat (active_window),
                .weight_flat     (lane_weight_active),
                .dot_sum         (lane_dot[lane])
            );
        end
    endgenerate

    // Shared lane-local requantization hardware.  Its inputs are selected
    // from the Conv1 dot pipeline or the Conv2 output-stationary accumulator.
    reg signed [31:0] c1_dot_pipe [0:LANES-1];
    reg signed [31:0] c2_lane_acc [0:LANES-1];
    reg c1_dot_valid;

    reg [(LANES*32)-1:0] requant_acc_flat;
    reg [(LANES*32)-1:0] requant_mult_flat;
    reg [(LANES*8)-1:0]  requant_shift_flat;
    wire requant_enable = mode_conv2
        ? (c2_state == C2_QUANT)
        : c1_dot_valid;
    integer rq_lane;
    always @* begin
        requant_acc_flat   = {(LANES*32){1'b0}};
        requant_mult_flat  = {(LANES*32){1'b0}};
        requant_shift_flat = {(LANES*8){1'b0}};

        if (requant_enable) begin
            for (rq_lane = 0; rq_lane < LANES; rq_lane = rq_lane + 1) begin
                if (mode_conv2) begin
                    requant_acc_flat[rq_lane*32 +: 32] =
                        c2_lane_acc[rq_lane] + c2_bias[c2_group_idx*LANES + rq_lane];
                    requant_mult_flat[rq_lane*32 +: 32] =
                        c2_mult[c2_group_idx*LANES + rq_lane];
                    requant_shift_flat[rq_lane*8 +: 8] =
                        c2_shift[c2_group_idx*LANES + rq_lane];
                end else begin
                    requant_acc_flat[rq_lane*32 +: 32] =
                        c1_dot_pipe[rq_lane] + c1_bias[rq_lane];
                    requant_mult_flat[rq_lane*32 +: 32] = c1_mult[rq_lane];
                    requant_shift_flat[rq_lane*8 +: 8] = c1_shift[rq_lane];
                end
            end
        end
    end

    wire signed [DATA_BITS-1:0] requant_out [0:LANES-1];
    generate
        for (lane = 0; lane < LANES; lane = lane + 1) begin : g_requant_lane
            requantize_relu_lane #(.DATA_BITS(DATA_BITS)) u_requant (
                .acc_value       (requant_acc_flat[lane*32 +: 32]),
                .mult_value      (requant_mult_flat[lane*32 +: 32]),
                .shift_value     (requant_shift_flat[lane*8 +: 8]),
                .quantized_value (requant_out[lane])
            );
        end
    endgenerate

    // ------------------------------------------------------------------
    // Conv1 streaming pipeline.
    // ------------------------------------------------------------------
    reg signed [DATA_BITS-1:0] c1_out [0:7];

    genvar c1_pack;
    generate
        for (c1_pack = 0; c1_pack < 8; c1_pack = c1_pack + 1) begin : g_c1_pack
            assign c1_out_flat[c1_pack*DATA_BITS +: DATA_BITS] = c1_out[c1_pack];
        end
    endgenerate

    assign c1_window_ready = rst_n && !frame_clear && !mode_conv2;

    integer c1_seq_lane;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || frame_clear) begin
            c1_dot_valid <= 1'b0;
            c1_out_valid <= 1'b0;
            for (c1_seq_lane = 0; c1_seq_lane < LANES; c1_seq_lane = c1_seq_lane + 1) begin
                c1_dot_pipe[c1_seq_lane] <= 32'sd0;
                c1_out[c1_seq_lane]      <= {DATA_BITS{1'b0}};
            end
        end else if (mode_conv2) begin
            c1_dot_valid <= 1'b0;
            c1_out_valid <= 1'b0;
        end else begin
            c1_dot_valid <= c1_window_valid && c1_window_ready;
            c1_out_valid <= c1_dot_valid;

            if (c1_window_valid && c1_window_ready)
                for (c1_seq_lane = 0; c1_seq_lane < LANES; c1_seq_lane = c1_seq_lane + 1)
                    c1_dot_pipe[c1_seq_lane] <= lane_dot[c1_seq_lane];

            if (c1_dot_valid)
                for (c1_seq_lane = 0; c1_seq_lane < LANES; c1_seq_lane = c1_seq_lane + 1)
                    c1_out[c1_seq_lane] <= requant_out[c1_seq_lane];
        end
    end

    // ------------------------------------------------------------------
    // Conv2 tiled/output-stationary controller.
    // ------------------------------------------------------------------
    reg signed [DATA_BITS-1:0] c2_out [0:23];

    genvar c2_pack;
    generate
        for (c2_pack = 0; c2_pack < 24; c2_pack = c2_pack + 1) begin : g_c2_pack
            assign c2_out_flat[c2_pack*DATA_BITS +: DATA_BITS] = c2_out[c2_pack];
        end
    endgenerate

    assign c2_window_ready = rst_n && !frame_clear && mode_conv2 &&
                             (c2_state == C2_IDLE);

    integer c2_seq_lane;
    integer c2_reset_out;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || frame_clear) begin
            c2_state      <= C2_IDLE;
            c2_out_valid  <= 1'b0;
            c2_window_reg <= {(8*9*DATA_BITS){1'b0}};
            c2_cin_idx    <= 3'd0;
            c2_group_idx  <= 2'd0;
            for (c2_seq_lane = 0; c2_seq_lane < LANES; c2_seq_lane = c2_seq_lane + 1)
                c2_lane_acc[c2_seq_lane] <= 32'sd0;
            for (c2_reset_out = 0; c2_reset_out < 24; c2_reset_out = c2_reset_out + 1)
                c2_out[c2_reset_out] <= {DATA_BITS{1'b0}};
        end else if (!mode_conv2) begin
            c2_state     <= C2_IDLE;
            c2_out_valid <= 1'b0;
            c2_cin_idx   <= 3'd0;
            c2_group_idx <= 2'd0;
        end else begin
            c2_out_valid <= 1'b0;

            case (c2_state)
                C2_IDLE: begin
                    if (c2_window_valid && c2_window_ready) begin
                        c2_window_reg <= c2_window_flat;
                        c2_cin_idx   <= 3'd0;
                        c2_group_idx <= 2'd0;
                        for (c2_seq_lane = 0; c2_seq_lane < LANES; c2_seq_lane = c2_seq_lane + 1)
                            c2_lane_acc[c2_seq_lane] <= 32'sd0;
                        c2_state <= C2_MAC;
                    end
                end

                C2_MAC: begin
                    for (c2_seq_lane = 0; c2_seq_lane < LANES; c2_seq_lane = c2_seq_lane + 1) begin
                        if (c2_cin_idx == 0)
                            c2_lane_acc[c2_seq_lane] <= lane_dot[c2_seq_lane];
                        else
                            c2_lane_acc[c2_seq_lane] <=
                                c2_lane_acc[c2_seq_lane] + lane_dot[c2_seq_lane];
                    end

                    if (c2_cin_idx == C2_IN_CH-1)
                        c2_state <= C2_QUANT;
                    else
                        c2_cin_idx <= c2_cin_idx + 1'b1;
                end

                C2_QUANT: begin
                    for (c2_seq_lane = 0; c2_seq_lane < LANES; c2_seq_lane = c2_seq_lane + 1)
                        c2_out[c2_group_idx*LANES + c2_seq_lane] <=
                            requant_out[c2_seq_lane];

                    if (c2_group_idx == C2_GROUPS-1) begin
                        c2_out_valid <= 1'b1;
                        c2_state     <= C2_IDLE;
                    end else begin
                        c2_group_idx <= c2_group_idx + 1'b1;
                        c2_cin_idx   <= 3'd0;
                        for (c2_seq_lane = 0; c2_seq_lane < LANES; c2_seq_lane = c2_seq_lane + 1)
                            c2_lane_acc[c2_seq_lane] <= 32'sd0;
                        c2_state <= C2_MAC;
                    end
                end

                default: c2_state <= C2_IDLE;
            endcase
        end
    end

endmodule
