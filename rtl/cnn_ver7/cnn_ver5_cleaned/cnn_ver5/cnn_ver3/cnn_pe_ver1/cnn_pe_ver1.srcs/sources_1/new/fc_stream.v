`timescale 1ns / 1ps
/*------------------------------------------------------------------------
 *  Module: fc_stream
 *
 *  Shared, banked 8-MAC fully-connected engine for
 *      600 -> 120 -> 84 -> 47 -> argmax.
 *
 *  The module directly implements all three FC layers with one shared MAC
 *  array and no inter-layer copy FSMs:
 *
 *    - one activation is broadcast to MAC_LANES output-neuron lanes;
 *    - every kernel BRAM word contains MAC_LANES adjacent output weights;
 *    - the same physical lanes execute FC1, FC2 and FC3 in sequence;
 *    - FC1/FC2 use one shared, pipelined requantizer;
 *    - FC3 stores raw int32 logits and performs a strict-'>' argmax while
 *      the logits are retired (ties therefore keep the lowest class index).
 *
 *  Kernel DMA layout is NOT changed.  A linear address out*IN + in is
 *  decoded into {output_group, input, lane}; software may keep using the
 *  existing fc1_kernel/fc2_kernel/fc3_kernel files and address map.
 *------------------------------------------------------------------------*/
module fc_stream #(
    parameter integer MAC_LANES = 8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        fc_start,
    input  wire        valid_in,
    input  wire [(24*8)-1:0] data_in_flat,
    output wire        ready,
    output reg  [5:0]  predicted_class,
    output reg         valid_out,

    input  wire        weight_we_fc1,
    input  wire        weight_we_fc2,
    input  wire        weight_we_fc3,
    input  wire [1:0]  weight_param_sel,
    input  wire [18:0] weight_offset,
    input  wire [31:0] weight_data
);

    localparam integer FC1_INPUTS  = 600;
    localparam integer FC1_OUTPUTS = 120;
    localparam integer FC2_INPUTS  = 120;
    localparam integer FC2_OUTPUTS = 84;
    localparam integer FC3_INPUTS  = 84;
    localparam integer FC3_OUTPUTS = 47;

    localparam integer FC1_GROUPS = (FC1_OUTPUTS + MAC_LANES - 1) / MAC_LANES;
    localparam integer FC2_GROUPS = (FC2_OUTPUTS + MAC_LANES - 1) / MAC_LANES;
    localparam integer FC3_GROUPS = (FC3_OUTPUTS + MAC_LANES - 1) / MAC_LANES;
    localparam integer KERNEL_WORD_BITS = MAC_LANES * 8;
    localparam integer FC1_KERNEL_WORDS = FC1_GROUPS * FC1_INPUTS;
    localparam integer FC2_KERNEL_WORDS = FC2_GROUPS * FC2_INPUTS;
    localparam integer FC3_KERNEL_WORDS = FC3_GROUPS * FC3_INPUTS;
    localparam integer FC1_KERNEL_BANKS = 3;
    localparam integer FC1_KERNEL_BANK_DEPTH =
        (FC1_KERNEL_WORDS + FC1_KERNEL_BANKS - 1) / FC1_KERNEL_BANKS;

    // ------------------------------------------------------------------
    // Pool2 collection: 24 channels x 25 spatial positions.
    // The banked organization accepts all 24 channels in one clock and
    // preserves flatten order channel*25 + position.
    // ------------------------------------------------------------------
    wire signed [7:0] data_in [0:23];
    genvar gi_din;
    generate
        for (gi_din = 0; gi_din < 24; gi_din = gi_din + 1) begin : gen_din_unpack
            assign data_in[gi_din] = data_in_flat[gi_din*8 +: 8];
        end
    endgenerate

    reg       collecting;
    reg [4:0] pos_cnt;
    wire      flatten_accept = collecting && valid_in && (pos_cnt < 25);

    // These issue counters replace division/modulo by 25 on the inference
    // path.  They are reset for each FC1 output group and advance together
    // with the synchronous kernel read address.
    reg [4:0] flat_bank_issue;
    reg [4:0] flat_pos_issue;
    wire signed [7:0] flat_bank_rd [0:23];

    genvar gi_bank;
    generate
        for (gi_bank = 0; gi_bank < 24; gi_bank = gi_bank + 1) begin : gen_flat_bank
            reg signed [7:0] bank_mem [0:24];

            always @(posedge clk) begin
                if (flatten_accept)
                    bank_mem[pos_cnt] <= data_in[gi_bank];
            end

            assign flat_bank_rd[gi_bank] = bank_mem[flat_pos_issue];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pos_cnt <= 0;
        else if (flatten_accept)
            pos_cnt <= pos_cnt + 1'b1;
        else if (!collecting)
            pos_cnt <= 0;
    end

    // ------------------------------------------------------------------
    // Packed kernel storage.
    //
    // A word holds weights for adjacent output neurons:
    //   word[group*IN + input][lane*8 +: 8]
    //      == original_kernel[(group*MAC_LANES + lane)*IN + input]
    //
    // This layout supplies all MAC lanes with one BRAM read while retaining
    // the original output-major DMA address space.  Byte writes map naturally
    // to the byte-enable pins of Xilinx block RAM.
    // ------------------------------------------------------------------
    (* ram_style = "block" *)
    reg [KERNEL_WORD_BITS-1:0] f2_kernel [0:FC2_KERNEL_WORDS-1];
    (* ram_style = "block" *)
    reg [KERNEL_WORD_BITS-1:0] f3_kernel [0:FC3_KERNEL_WORDS-1];

    reg signed [31:0] f1_bias  [0:FC1_OUTPUTS-1];
    reg signed [31:0] f1_mult  [0:FC1_OUTPUTS-1];
    reg         [7:0] f1_shift [0:FC1_OUTPUTS-1];
    reg signed [31:0] f2_bias  [0:FC2_OUTPUTS-1];
    reg signed [31:0] f2_mult  [0:FC2_OUTPUTS-1];
    reg         [7:0] f2_shift [0:FC2_OUTPUTS-1];
    reg signed [31:0] f3_bias  [0:FC3_OUTPUTS-1];

    // Combinational translation is only active on the one-time weight-load
    // path; it is absent from the inference critical path.  Constant divisors
    // are elaborated by synthesis and preserve random-access DMA semantics.
    wire [6:0] f1_wr_neuron = weight_offset / FC1_INPUTS;
    wire [9:0] f1_wr_tap    = weight_offset % FC1_INPUTS;
    wire [13:0] f1_wr_word  = (f1_wr_neuron / MAC_LANES) * FC1_INPUTS + f1_wr_tap;
    wire [3:0] f1_wr_lane   = f1_wr_neuron % MAC_LANES;

    wire [6:0] f2_wr_neuron = weight_offset / FC2_INPUTS;
    wire [6:0] f2_wr_tap    = weight_offset % FC2_INPUTS;
    wire [10:0] f2_wr_word  = (f2_wr_neuron / MAC_LANES) * FC2_INPUTS + f2_wr_tap;
    wire [3:0] f2_wr_lane   = f2_wr_neuron % MAC_LANES;

    wire [5:0] f3_wr_neuron = weight_offset / FC3_INPUTS;
    wire [6:0] f3_wr_tap    = weight_offset % FC3_INPUTS;
    wire [8:0] f3_wr_word   = (f3_wr_neuron / MAC_LANES) * FC3_INPUTS + f3_wr_tap;
    wire [3:0] f3_wr_lane   = f3_wr_neuron % MAC_LANES;

    // Explicit byte enables are essential for packed BRAM inference.  A
    // variable part-select write can be interpreted as 64 independent bit
    // enables, wasting one shallow RAM primitive per bit.  The fixed-width
    // loop below matches the Xilinx byte-write template and still preserves
    // the original random-access DMA address contract.
    wire [MAC_LANES-1:0] f1_kernel_byte_we =
        (weight_we_fc1 && (weight_param_sel == 2'd0) &&
         (weight_offset < FC1_INPUTS*FC1_OUTPUTS))
        ? ({{(MAC_LANES-1){1'b0}}, 1'b1} << f1_wr_lane)
        : {MAC_LANES{1'b0}};
    wire [MAC_LANES-1:0] f2_kernel_byte_we =
        (weight_we_fc2 && (weight_param_sel == 2'd0) &&
         (weight_offset < FC2_INPUTS*FC2_OUTPUTS))
        ? ({{(MAC_LANES-1){1'b0}}, 1'b1} << f2_wr_lane)
        : {MAC_LANES{1'b0}};
    wire [MAC_LANES-1:0] f3_kernel_byte_we =
        (weight_we_fc3 && (weight_param_sel == 2'd0) &&
         (weight_offset < FC3_INPUTS*FC3_OUTPUTS))
        ? ({{(MAC_LANES-1){1'b0}}, 1'b1} << f3_wr_lane)
        : {MAC_LANES{1'b0}};

    integer f2_write_byte;
    integer f3_write_byte;

    always @(posedge clk) begin
        if (weight_we_fc1) begin
            case (weight_param_sel)
                2'd1: if (weight_offset < FC1_OUTPUTS)
                    f1_bias[weight_offset[6:0]] <= weight_data;
                2'd2: if (weight_offset < FC1_OUTPUTS)
                    f1_mult[weight_offset[6:0]] <= weight_data;
                2'd3: if (weight_offset < FC1_OUTPUTS)
                    f1_shift[weight_offset[6:0]] <= weight_data[7:0];
                default: ;
            endcase
        end
    end

    always @(posedge clk) begin
        if (weight_we_fc2) begin
            for (f2_write_byte = 0; f2_write_byte < MAC_LANES;
                 f2_write_byte = f2_write_byte + 1)
                if (f2_kernel_byte_we[f2_write_byte])
                    f2_kernel[f2_wr_word][f2_write_byte*8 +: 8]
                        <= weight_data[7:0];

            case (weight_param_sel)
                2'd1: if (weight_offset < FC2_OUTPUTS)
                    f2_bias[weight_offset[6:0]] <= weight_data;
                2'd2: if (weight_offset < FC2_OUTPUTS)
                    f2_mult[weight_offset[6:0]] <= weight_data;
                2'd3: if (weight_offset < FC2_OUTPUTS)
                    f2_shift[weight_offset[6:0]] <= weight_data[7:0];
                default: ;
            endcase
        end
    end

    always @(posedge clk) begin
        if (weight_we_fc3) begin
            for (f3_write_byte = 0; f3_write_byte < MAC_LANES;
                 f3_write_byte = f3_write_byte + 1)
                if (f3_kernel_byte_we[f3_write_byte])
                    f3_kernel[f3_wr_word][f3_write_byte*8 +: 8]
                        <= weight_data[7:0];

            case (weight_param_sel)
                2'd1: if (weight_offset < FC3_OUTPUTS)
                    f3_bias[weight_offset[5:0]] <= weight_data;
                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Shared activation storage and MAC datapath.
    // FC1 and FC2 outputs need distinct memories because FC2 must finish
    // reading all 120 FC1 values before lower addresses may be overwritten.
    // ------------------------------------------------------------------
    reg signed [7:0]  fc1_activation [0:FC1_OUTPUTS-1];
    reg signed [7:0]  fc2_activation [0:FC2_OUTPUTS-1];
    reg signed [31:0] fc3_logits     [0:FC3_OUTPUTS-1];

    localparam [1:0] LAYER_FC1 = 2'd0,
                     LAYER_FC2 = 2'd1,
                     LAYER_FC3 = 2'd2;

    localparam [3:0] ST_IDLE       = 4'd0,
                     ST_COLLECT    = 4'd1,
                     ST_WAIT_START = 4'd2,
                     ST_GROUP_INIT = 4'd3,
                     ST_PRIME      = 4'd4,
                     ST_MAC        = 4'd5,
                     ST_QUANT      = 4'd6,
                     ST_Q_DRAIN    = 4'd7,
                     ST_FC3_RETIRE = 4'd8;

    reg [3:0] state;
    reg [1:0] active_layer;
    reg       fc_start_pending;

    reg [13:0] kernel_group_base;
    reg [13:0] kernel_rd_addr;
    reg [6:0]  output_group_base;
    reg [9:0]  tap_issue;
    reg [9:0]  tap_use;
    reg signed [7:0] activation_pipe;

    wire [KERNEL_WORD_BITS-1:0] f1_kernel_word;
    reg [KERNEL_WORD_BITS-1:0] f2_kernel_word;
    reg [KERNEL_WORD_BITS-1:0] f3_kernel_word;
    wire [KERNEL_WORD_BITS-1:0] active_kernel_word =
        (active_layer == LAYER_FC1) ? f1_kernel_word :
        (active_layer == LAYER_FC2) ? f2_kernel_word : f3_kernel_word;

    wire kernel_read_enable = (state == ST_PRIME) || (state == ST_MAC);

    // Independent clock enables keep inactive layer BRAMs quiet.  The address
    // and registered output form a synchronous one-cycle BRAM read port.
    // FC1 is split into eight byte lanes and three 3000-word depth banks.
    // Each depth bank then fits one 4Kx9 RAMB36 per lane.  A single 9000-word
    // array is rounded to two 8K depth regions and consumes four RAMB36 per
    // lane, even though the stored bit count only needs three.
    wire [1:0] f1_write_bank =
        (f1_wr_word >= 2*FC1_KERNEL_BANK_DEPTH) ? 2'd2 :
        (f1_wr_word >=   FC1_KERNEL_BANK_DEPTH) ? 2'd1 : 2'd0;
    wire [13:0] f1_write_local_full =
        (f1_write_bank == 2'd2) ? f1_wr_word - 2*FC1_KERNEL_BANK_DEPTH :
        (f1_write_bank == 2'd1) ? f1_wr_word -   FC1_KERNEL_BANK_DEPTH :
                                  f1_wr_word;
    wire [13:0] f1_write_local = f1_write_local_full;

    wire [1:0] f1_read_bank =
        (kernel_rd_addr >= 2*FC1_KERNEL_BANK_DEPTH) ? 2'd2 :
        (kernel_rd_addr >=   FC1_KERNEL_BANK_DEPTH) ? 2'd1 : 2'd0;
    wire [13:0] f1_read_local_full =
        (f1_read_bank == 2'd2) ? kernel_rd_addr - 2*FC1_KERNEL_BANK_DEPTH :
        (f1_read_bank == 2'd1) ? kernel_rd_addr -   FC1_KERNEL_BANK_DEPTH :
                                 kernel_rd_addr;
    wire [13:0] f1_read_local = f1_read_local_full;
    reg  [1:0]  f1_read_bank_q;

    always @(posedge clk) begin
        if (kernel_read_enable && (active_layer == LAYER_FC1))
            f1_read_bank_q <= f1_read_bank;
    end

    genvar f1_kernel_lane;
    genvar f1_kernel_bank;
    generate
        for (f1_kernel_lane = 0; f1_kernel_lane < MAC_LANES;
             f1_kernel_lane = f1_kernel_lane + 1) begin : gen_f1_kernel_lane
            for (f1_kernel_bank = 0;
                 f1_kernel_bank < FC1_KERNEL_BANKS;
                 f1_kernel_bank = f1_kernel_bank + 1) begin : gen_depth_bank
                (* ram_style = "block" *)
                reg [7:0] f1_kernel_byte_mem [0:FC1_KERNEL_BANK_DEPTH-1];
                reg [7:0] f1_kernel_byte_q;

                always @(posedge clk) begin
                    if (f1_kernel_byte_we[f1_kernel_lane] &&
                        (f1_write_bank == f1_kernel_bank))
                        f1_kernel_byte_mem[f1_write_local]
                            <= weight_data[7:0];
                    if (kernel_read_enable &&
                        (active_layer == LAYER_FC1) &&
                        (f1_read_bank == f1_kernel_bank))
                        f1_kernel_byte_q
                            <= f1_kernel_byte_mem[f1_read_local];
                end
            end

            assign f1_kernel_word[f1_kernel_lane*8 +: 8] =
                (f1_read_bank_q == 2'd0) ?
                    gen_depth_bank[0].f1_kernel_byte_q :
                (f1_read_bank_q == 2'd1) ?
                    gen_depth_bank[1].f1_kernel_byte_q :
                    gen_depth_bank[2].f1_kernel_byte_q;
        end
    endgenerate

    always @(posedge clk) begin
        if (kernel_read_enable && (active_layer == LAYER_FC2))
            f2_kernel_word <= f2_kernel[kernel_rd_addr];
    end

    always @(posedge clk) begin
        if (kernel_read_enable && (active_layer == LAYER_FC3))
            f3_kernel_word <= f3_kernel[kernel_rd_addr];
    end

    // Register the matching activation beside the synchronous weight read.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            activation_pipe <= 0;
        end else if (kernel_read_enable) begin
            case (active_layer)
                LAYER_FC1: activation_pipe <= flat_bank_rd[flat_bank_issue];
                LAYER_FC2: activation_pipe <= fc1_activation[tap_issue];
                default:   activation_pipe <= fc2_activation[tap_issue];
            endcase
        end
    end

    reg signed [31:0] accumulator [0:MAC_LANES-1];
    integer lane;

    function signed [7:0] packed_weight;
        input [KERNEL_WORD_BITS-1:0] packed_word;
        input integer lane_number;
        begin
            packed_weight = packed_word[lane_number*8 +: 8];
        end
    endfunction

    wire [9:0] active_input_last =
        (active_layer == LAYER_FC1) ? FC1_INPUTS-1 :
        (active_layer == LAYER_FC2) ? FC2_INPUTS-1 : FC3_INPUTS-1;
    wire [7:0] active_output_count =
        (active_layer == LAYER_FC1) ? FC1_OUTPUTS :
        (active_layer == LAYER_FC2) ? FC2_OUTPUTS : FC3_OUTPUTS;

    // ------------------------------------------------------------------
    // Shared pipelined requantizer for FC1/FC2.
    // Stage 1 registers acc*mult.  Stage 2 performs the original positive
    // half-LSB rounding, arithmetic shift, ReLU and int8 saturation.  This
    // preserves the original fixed-point arithmetic while breaking the
    // multiply/shift timing path and instantiating one 32x32 multiplier.
    // ------------------------------------------------------------------
    reg [3:0] quant_lane;
    reg       quant_valid;
    reg signed [63:0] quant_product;
    reg [7:0] quant_shift;
    reg [6:0] quant_output_index;

    function signed [7:0] requantize_relu_product;
        input signed [63:0] product_value;
        input        [7:0]  shift_value;
        reg signed [63:0] rounded_product;
        reg signed [31:0] quantized_value;
        begin
            rounded_product = product_value;
            if (shift_value > 0) begin
                rounded_product = product_value +
                                  (64'sd1 << (shift_value - 1));
                quantized_value = rounded_product >>> shift_value;
            end else begin
                quantized_value = product_value;
            end

            if (quantized_value < 0)
                requantize_relu_product = 8'sd0;
            else if (quantized_value > 127)
                requantize_relu_product = 8'sd127;
            else
                requantize_relu_product = quantized_value[7:0];
        end
    endfunction

    wire quant_commit = quant_valid &&
                        ((state == ST_QUANT) || (state == ST_Q_DRAIN));
    wire signed [7:0] quantized_activation =
        requantize_relu_product(quant_product, quant_shift);

    // Synchronous-only output writes keep the small activation memories
    // inference-friendly and separate from the asynchronously reset FSM.
    always @(posedge clk) begin
        if (quant_commit) begin
            if (active_layer == LAYER_FC1)
                fc1_activation[quant_output_index] <= quantized_activation;
            else
                fc2_activation[quant_output_index] <= quantized_activation;
        end
    end

    reg [3:0] retire_lane;
    reg signed [31:0] argmax_value;
    reg [5:0] argmax_index;
    wire [6:0] retire_output_index = output_group_base + retire_lane;

    always @(posedge clk) begin
        if ((state == ST_FC3_RETIRE) &&
            (retire_output_index < FC3_OUTPUTS))
            fc3_logits[retire_output_index] <= accumulator[retire_lane];
    end

    assign ready = collecting && (pos_cnt < 25) &&
                   ((state == ST_IDLE) || (state == ST_COLLECT));

    // ------------------------------------------------------------------
    // Collection, layer scheduling, MAC execution, requant and argmax.
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= ST_IDLE;
            active_layer        <= LAYER_FC1;
            collecting          <= 1'b1;
            fc_start_pending    <= 1'b0;
            predicted_class     <= 0;
            valid_out           <= 1'b0;
            kernel_group_base   <= 0;
            kernel_rd_addr      <= 0;
            output_group_base   <= 0;
            tap_issue           <= 0;
            tap_use             <= 0;
            flat_bank_issue     <= 0;
            flat_pos_issue      <= 0;
            quant_lane          <= 0;
            quant_valid         <= 1'b0;
            quant_product       <= 0;
            quant_shift         <= 0;
            quant_output_index  <= 0;
            retire_lane         <= 0;
            argmax_value        <= 0;
            argmax_index        <= 0;
            for (lane = 0; lane < MAC_LANES; lane = lane + 1)
                accumulator[lane] <= 0;
        end else begin
            valid_out <= 1'b0;

            // A scheduler pulse may arrive on or before the last Pool2 beat.
            if (fc_start)
                fc_start_pending <= 1'b1;

            case (state)
                ST_IDLE: begin
                    collecting <= 1'b1;
                    if (flatten_accept)
                        state <= ST_COLLECT;
                end

                ST_COLLECT: begin
                    if (pos_cnt == 25) begin
                        collecting <= 1'b0;
                        state <= ST_WAIT_START;
                    end
                end

                ST_WAIT_START: begin
                    collecting <= 1'b0;
                    if (fc_start || fc_start_pending) begin
                        fc_start_pending  <= 1'b0;
                        active_layer     <= LAYER_FC1;
                        kernel_group_base <= 0;
                        output_group_base <= 0;
                        state            <= ST_GROUP_INIT;
                    end
                end

                // Load eight biases and issue tap zero. Invalid lanes in the
                // last partial group are held at zero and never retired.
                ST_GROUP_INIT: begin
                    tap_issue       <= 0;
                    tap_use         <= 0;
                    kernel_rd_addr  <= kernel_group_base;
                    flat_bank_issue <= 0;
                    flat_pos_issue  <= 0;

                    for (lane = 0; lane < MAC_LANES; lane = lane + 1) begin
                        if ((output_group_base + lane) < active_output_count) begin
                            case (active_layer)
                                LAYER_FC1:
                                    accumulator[lane] <= f1_bias[output_group_base + lane];
                                LAYER_FC2:
                                    accumulator[lane] <= f2_bias[output_group_base + lane];
                                default:
                                    accumulator[lane] <= f3_bias[output_group_base + lane];
                            endcase
                        end else begin
                            accumulator[lane] <= 0;
                        end
                    end
                    state <= ST_PRIME;
                end

                // At this edge the BRAM/activation registers capture tap 0;
                // prepare tap 1 for the first MAC edge.
                ST_PRIME: begin
                    tap_issue      <= 1;
                    tap_use        <= 0;
                    kernel_rd_addr <= kernel_group_base + 1'b1;
                    if (active_layer == LAYER_FC1)
                        flat_pos_issue <= 1;
                    state <= ST_MAC;
                end

                // Eight output neurons advance per clock.  The conditional
                // accumulator enable is exact zero-gating: zero activation or
                // zero weight leaves the DSP accumulator unchanged.
                ST_MAC: begin
                    for (lane = 0; lane < MAC_LANES; lane = lane + 1) begin
                        if (((output_group_base + lane) < active_output_count) &&
                            (activation_pipe != 0) &&
                            (packed_weight(active_kernel_word, lane) != 0)) begin
                            accumulator[lane] <= accumulator[lane] +
                                $signed(activation_pipe) *
                                $signed(packed_weight(active_kernel_word, lane));
                        end
                    end

                    if (tap_use == active_input_last) begin
                        if (active_layer == LAYER_FC3) begin
                            retire_lane <= 0;
                            state <= ST_FC3_RETIRE;
                        end else begin
                            quant_lane  <= 0;
                            quant_valid <= 1'b0;
                            state <= ST_QUANT;
                        end
                    end else begin
                        tap_use <= tap_use + 1'b1;

                        // The final address is already present when tap_use
                        // reaches the penultimate value; do not step past RAM.
                        if (tap_issue < active_input_last) begin
                            tap_issue      <= tap_issue + 1'b1;
                            kernel_rd_addr <= kernel_rd_addr + 1'b1;

                            if (active_layer == LAYER_FC1) begin
                                if (flat_pos_issue == 24) begin
                                    flat_pos_issue  <= 0;
                                    flat_bank_issue <= flat_bank_issue + 1'b1;
                                end else begin
                                    flat_pos_issue <= flat_pos_issue + 1'b1;
                                end
                            end
                        end
                    end
                end

                // Issue one requant operation per cycle. The previous lane,
                // if valid, commits concurrently through quant_commit above.
                ST_QUANT: begin
                    quant_valid        <= 1'b1;
                    quant_output_index <= output_group_base + quant_lane;

                    if (active_layer == LAYER_FC1) begin
                        quant_product <=
                            $signed(accumulator[quant_lane]) *
                            $signed(f1_mult[output_group_base + quant_lane]);
                        quant_shift <= f1_shift[output_group_base + quant_lane];
                    end else begin
                        quant_product <=
                            $signed(accumulator[quant_lane]) *
                            $signed(f2_mult[output_group_base + quant_lane]);
                        quant_shift <= f2_shift[output_group_base + quant_lane];
                    end

                    if ((quant_lane == MAC_LANES-1) ||
                        ((output_group_base + quant_lane) ==
                         (active_output_count - 1'b1))) begin
                        state <= ST_Q_DRAIN;
                    end else begin
                        quant_lane <= quant_lane + 1'b1;
                    end
                end

                // Commit the last registered requant result, then either move
                // to the next output group or reuse the lanes for next layer.
                ST_Q_DRAIN: begin
                    quant_valid <= 1'b0;

                    if (quant_output_index == (active_output_count - 1'b1)) begin
                        if (active_layer == LAYER_FC1) begin
                            active_layer       <= LAYER_FC2;
                            kernel_group_base  <= 0;
                            output_group_base  <= 0;
                        end else begin
                            active_layer       <= LAYER_FC3;
                            kernel_group_base  <= 0;
                            output_group_base  <= 0;
                        end
                    end else begin
                        output_group_base <= output_group_base + MAC_LANES;
                        if (active_layer == LAYER_FC1)
                            kernel_group_base <= kernel_group_base + FC1_INPUTS;
                        else
                            kernel_group_base <= kernel_group_base + FC2_INPUTS;
                    end
                    state <= ST_GROUP_INIT;
                end

                // FC3 is deliberately unquantized. Retire logits in ascending
                // class order and use strict '>' so ties keep the lower index.
                ST_FC3_RETIRE: begin
                    if (retire_output_index == 0) begin
                        argmax_value <= accumulator[retire_lane];
                        argmax_index <= 0;
                    end else if (accumulator[retire_lane] > argmax_value) begin
                        argmax_value <= accumulator[retire_lane];
                        argmax_index <= retire_output_index[5:0];
                    end

                    if (retire_output_index == FC3_OUTPUTS-1) begin
                        predicted_class <=
                            (accumulator[retire_lane] > argmax_value) ?
                            retire_output_index[5:0] : argmax_index;
                        valid_out        <= 1'b1;
                        collecting       <= 1'b1;
                        fc_start_pending <= 1'b0;
                        quant_valid      <= 1'b0;
                        state            <= ST_IDLE;
                    end else if (retire_lane == MAC_LANES-1) begin
                        retire_lane       <= 0;
                        output_group_base <= output_group_base + MAC_LANES;
                        kernel_group_base <= kernel_group_base + FC3_INPUTS;
                        state             <= ST_GROUP_INIT;
                    end else begin
                        retire_lane <= retire_lane + 1'b1;
                    end
                end

                default: begin
                    state      <= ST_IDLE;
                    collecting <= 1'b1;
                end
            endcase
        end
    end

endmodule
