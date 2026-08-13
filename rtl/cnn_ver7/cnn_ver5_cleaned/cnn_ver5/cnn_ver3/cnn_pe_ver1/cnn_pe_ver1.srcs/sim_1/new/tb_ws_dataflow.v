`timescale 1ns / 1ps

/*------------------------------------------------------------------------
 * Self-checking dataflow test for the proposed SEMIT accelerator mapping:
 *
 *   Conv1 (8 physical lanes, II=1) -> Pool1 -> TB staging RAM
 *     -> Conv2 (the same 8 lanes reused over 8 C_in and 3 C_out groups)
 *     -> Pool2
 *
 * The test verifies:
 *   - row-major sliding-window/tap order;
 *   - OIHW weight address order and all eight Conv1 lanes;
 *   - Conv2 input-channel accumulation and all three output groups;
 *   - bias, requantization rounding, ReLU, and clamp-to-127;
 *   - ready/valid backpressure while Conv2 holds one 3x3x8 window;
 *   - exact 676/169/121/25 Conv/Pool output counts.
 *------------------------------------------------------------------------*/
module tb_ws_dataflow;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n       = 1'b0;
    reg frame_clear = 1'b0;
    reg mode_conv2  = 1'b0;

    // ------------------------------------------------------------------
    // Conv1 + Pool1
    // ------------------------------------------------------------------
    reg               c1_in_valid = 1'b0;
    wire              c1_in_ready;
    reg signed [7:0]  c1_in_data = 8'sd0;
    wire [63:0]       c1_out_flat;
    wire              c1_out_valid;
    wire [63:0]       p1_out_flat;
    wire              p1_out_valid;
    wire [71:0]       c1_window_flat;
    wire              c1_window_valid;

    reg               c1_weight_we = 1'b0;
    reg [1:0]         c1_param_sel = 2'd0;
    reg [18:0]        c1_weight_offset = 19'd0;
    reg [31:0]        c1_weight_data = 32'd0;

    conv1_buf_new u_conv1_window (
        .clk               (clk),
        .rst_n             (rst_n),
        .frame_clear       (frame_clear),
        .valid_in          (c1_in_valid && c1_in_ready),
        .data_in           (c1_in_data),
        .win_flat          (c1_window_flat),
        .valid_out_buf     (c1_window_valid)
    );

    maxpool_relu #(
        .CH(8), .DATA_BITS(8), .WIDTH(26), .HEIGHT(26)
    ) u_pool1 (
        .clk            (clk),
        .rst_n          (rst_n),
        .valid_in       (c1_out_valid),
        .conv_out_flat  (c1_out_flat),
        .max_value_flat (p1_out_flat),
        .valid_out_relu (p1_out_valid)
    );

    // ------------------------------------------------------------------
    // Conv2 + Pool2
    // ------------------------------------------------------------------
    reg               c2_in_valid = 1'b0;
    wire              c2_in_ready;
    reg [63:0]        c2_in_flat = 64'd0;
    wire [191:0]      c2_out_flat;
    wire              c2_out_valid;
    wire [191:0]      p2_out_flat;
    wire              p2_out_valid;
    wire [575:0]      c2_window_flat;
    wire              c2_window_valid;
    wire              c2_calc_window_ready;

    reg               c2_weight_we = 1'b0;
    reg [1:0]         c2_param_sel = 2'd0;
    reg [18:0]        c2_weight_offset = 19'd0;
    reg [31:0]        c2_weight_data = 32'd0;

    wire [1:0]  shared_param_sel = c1_weight_we ? c1_param_sel : c2_param_sel;
    wire [18:0] shared_weight_offset = c1_weight_we
        ? c1_weight_offset : c2_weight_offset;
    wire [31:0] shared_weight_data = c1_weight_we
        ? c1_weight_data : c2_weight_data;

    assign c2_in_ready = rst_n && !frame_clear && c2_calc_window_ready &&
                         !c2_window_valid;

    conv2_buf_new #(.IN_CH(8)) u_conv2_window (
        .clk               (clk),
        .rst_n             (rst_n),
        .frame_clear       (frame_clear),
        .valid_in          (c2_in_valid && c2_in_ready),
        .data_in_flat      (c2_in_flat),
        .win_flat          (c2_window_flat),
        .valid_out_buf     (c2_window_valid)
    );

    // The same physical PE/requant lanes serve both phases.
    ws_conv_shared_engine u_shared_conv (
        .clk                 (clk),
        .rst_n               (rst_n),
        .frame_clear         (frame_clear),
        .mode_conv2          (mode_conv2),
        .c1_window_valid     (c1_window_valid),
        .c1_window_ready     (c1_in_ready),
        .c1_window_flat      (c1_window_flat),
        .c1_out_flat         (c1_out_flat),
        .c1_out_valid        (c1_out_valid),
        .c2_window_valid     (c2_window_valid),
        .c2_window_ready     (c2_calc_window_ready),
        .c2_window_flat      (c2_window_flat),
        .c2_out_flat         (c2_out_flat),
        .c2_out_valid        (c2_out_valid),
        .weight_we_conv1     (c1_weight_we),
        .weight_we_conv2     (c2_weight_we),
        .weight_param_sel   (shared_param_sel),
        .weight_offset      (shared_weight_offset),
        .weight_data        (shared_weight_data)
    );

    maxpool_relu #(
        .CH(24), .DATA_BITS(8), .WIDTH(11), .HEIGHT(11)
    ) u_pool2 (
        .clk            (clk),
        .rst_n          (rst_n),
        .valid_in       (c2_out_valid),
        .conv_out_flat  (c2_out_flat),
        .max_value_flat (p2_out_flat),
        .valid_out_relu (p2_out_valid)
    );

    // Pool1 staging model: spatial-major beats, eight channels per beat.
    reg [7:0] p1_saved [0:1351];
    integer reference_c1 [0:5407];
    integer reference_p1 [0:1351];
    integer reference_c2 [0:2903];
    integer reference_p2 [0:599];

    integer c1_count;
    integer p1_count;
    integer c2_count;
    integer p2_count;
    integer c2_stall_cycles;
    integer c2_input_fire_count;

    integer mon_c1_ch;
    integer mon_p1_ch;
    integer mon_c2_ch;
    integer mon_p2_ch;
    integer expected_value;

    function integer model_input_pixel;
        input integer y;
        input integer x;
        begin
            // Non-linear but still within 0..127.  It distinguishes all nine
            // spatial taps, unlike a purely affine ramp.
            model_input_pixel = 3*y + x + ((y*x) % 7);
        end
    endfunction

    function integer model_c1_weight;
        input integer channel;
        input integer tap_index;
        begin
            if (channel <= 6)
                model_c1_weight = (tap_index == channel) ? 1 : 0;
            else if (tap_index == 7)
                model_c1_weight = -1;
            else if (tap_index == 8)
                model_c1_weight = 1;
            else
                model_c1_weight = 0;
        end
    endfunction

    function integer model_c1_bias;
        input integer channel;
        begin
            model_c1_bias = (channel == 7) ? 64 : 0;
        end
    endfunction

    function integer model_c1_value;
        input integer y;
        input integer x;
        input integer channel;
        integer tap_index;
        integer tap_y;
        integer tap_x;
        integer acc_value;
        begin
            acc_value = model_c1_bias(channel);
            for (tap_index = 0; tap_index < 9; tap_index = tap_index + 1) begin
                tap_y = tap_index / 3;
                tap_x = tap_index % 3;
                acc_value = acc_value +
                    model_input_pixel(y + tap_y, x + tap_x) *
                    model_c1_weight(channel, tap_index);
            end
            if (acc_value < 0)
                model_c1_value = 0;
            else if (acc_value > 127)
                model_c1_value = 127;
            else
                model_c1_value = acc_value;
        end
    endfunction

    function integer model_p1_value;
        input integer pool_y;
        input integer pool_x;
        input integer channel;
        integer dy;
        integer dx;
        integer candidate;
        integer maximum;
        begin
            maximum = -2147483647;
            for (dy = 0; dy < 2; dy = dy + 1)
                for (dx = 0; dx < 2; dx = dx + 1) begin
                    candidate = model_c1_value(2*pool_y + dy, 2*pool_x + dx, channel);
                    if (candidate > maximum)
                        maximum = candidate;
                end
            model_p1_value = maximum;
        end
    endfunction

    function integer expected_c1;
        input integer position;
        input integer channel;
        begin
            expected_c1 = model_c1_value(position/26, position%26, channel);
        end
    endfunction

    function integer expected_p1;
        input integer position;
        input integer channel;
        begin
            expected_p1 = model_p1_value(position/13, position%13, channel);
        end
    endfunction

    function integer model_c2_weight;
        input integer channel;
        input integer input_channel;
        input integer tap_index;
        integer selector;
        begin
            if (channel <= 21) begin
                selector = (3*channel + 5*input_channel + 2*tap_index) % 7;
                if (selector == 0)
                    model_c2_weight = 1;
                else if (selector == 1)
                    model_c2_weight = -1;
                else
                    model_c2_weight = 0;
            end else begin
                model_c2_weight = 0;
            end
        end
    endfunction

    function integer model_c2_bias;
        input integer channel;
        begin
            if (channel <= 21)
                model_c2_bias = 4096 + 32*channel;
            else if (channel == 22)
                model_c2_bias = -10000;
            else
                model_c2_bias = 10000;
        end
    endfunction

    function integer expected_c2_at;
        input integer y;
        input integer x;
        input integer channel;
        integer input_channel;
        integer tap_index;
        integer tap_y;
        integer tap_x;
        integer acc_value;
        integer q_value;
        begin
            acc_value = model_c2_bias(channel);
            for (input_channel = 0; input_channel < 8; input_channel = input_channel + 1)
                for (tap_index = 0; tap_index < 9; tap_index = tap_index + 1) begin
                    tap_y = tap_index / 3;
                    tap_x = tap_index % 3;
                    acc_value = acc_value +
                        reference_p1[((y + tap_y)*13 + (x + tap_x))*8 + input_channel] *
                        model_c2_weight(channel, input_channel, tap_index);
                end

            // Conv2 uses multiplier=1 and shift=6 in this test.
            q_value = (acc_value + 32) >>> 6;
            if (q_value < 0)
                expected_c2_at = 0;
            else if (q_value > 127)
                expected_c2_at = 127;
            else
                expected_c2_at = q_value;
        end
    endfunction

    function integer expected_c2;
        input integer position;
        input integer channel;
        integer y;
        integer x;
        begin
            y = position / 11;
            x = position % 11;
            expected_c2 = expected_c2_at(y, x, channel);
        end
    endfunction

    function integer expected_p2;
        input integer position;
        input integer channel;
        integer pool_y;
        integer pool_x;
        integer dy;
        integer dx;
        integer candidate;
        integer maximum;
        begin
            pool_y = position / 5;
            pool_x = position % 5;
            maximum = -2147483647;
            for (dy = 0; dy < 2; dy = dy + 1)
                for (dx = 0; dx < 2; dx = dx + 1) begin
                    candidate = expected_c2_at(2*pool_y + dy, 2*pool_x + dx, channel);
                    if (candidate > maximum)
                        maximum = candidate;
                end
            expected_p2 = maximum;
        end
    endfunction

    // Numerical monitors.  Any mismatch is a hard failure; unlike the legacy
    // scheduler TB, mismatch branches never increment a pass counter.
    always @(posedge clk) begin
        if (!rst_n) begin
            c1_count          = 0;
            p1_count          = 0;
            c2_count          = 0;
            p2_count          = 0;
            c2_stall_cycles   = 0;
            c2_input_fire_count = 0;
        end else begin
            if (c2_in_valid && !c2_in_ready)
                c2_stall_cycles = c2_stall_cycles + 1;
            if (c2_in_valid && c2_in_ready)
                c2_input_fire_count = c2_input_fire_count + 1;

            if (c1_out_valid) begin
                if (c1_count >= 676)
                    $fatal(1, "Conv1 produced more than 676 positions");
                for (mon_c1_ch = 0; mon_c1_ch < 8; mon_c1_ch = mon_c1_ch + 1) begin
                    expected_value = reference_c1[c1_count*8 + mon_c1_ch];
                    if ($signed(c1_out_flat[mon_c1_ch*8 +: 8]) !== expected_value)
                        $fatal(1,
                            "Conv1 mismatch pos=%0d ch=%0d got=%0d expected=%0d",
                            c1_count, mon_c1_ch,
                            $signed(c1_out_flat[mon_c1_ch*8 +: 8]), expected_value);
                end
                c1_count = c1_count + 1;
            end

            if (p1_out_valid) begin
                if (p1_count >= 169)
                    $fatal(1, "Pool1 produced more than 169 positions");
                for (mon_p1_ch = 0; mon_p1_ch < 8; mon_p1_ch = mon_p1_ch + 1) begin
                    expected_value = reference_p1[p1_count*8 + mon_p1_ch];
                    if ($signed(p1_out_flat[mon_p1_ch*8 +: 8]) !== expected_value)
                        $fatal(1,
                            "Pool1 mismatch pos=%0d ch=%0d got=%0d expected=%0d",
                            p1_count, mon_p1_ch,
                            $signed(p1_out_flat[mon_p1_ch*8 +: 8]), expected_value);
                    p1_saved[p1_count*8 + mon_p1_ch] =
                        p1_out_flat[mon_p1_ch*8 +: 8];
                end
                p1_count = p1_count + 1;
            end

            if (c2_out_valid) begin
                if (c2_count >= 121)
                    $fatal(1, "Conv2 produced more than 121 positions");
                for (mon_c2_ch = 0; mon_c2_ch < 24; mon_c2_ch = mon_c2_ch + 1) begin
                    expected_value = reference_c2[c2_count*24 + mon_c2_ch];
                    if ($signed(c2_out_flat[mon_c2_ch*8 +: 8]) !== expected_value)
                        $fatal(1,
                            "Conv2 mismatch pos=%0d ch=%0d got=%0d expected=%0d",
                            c2_count, mon_c2_ch,
                            $signed(c2_out_flat[mon_c2_ch*8 +: 8]), expected_value);
                end
                c2_count = c2_count + 1;
            end

            if (p2_out_valid) begin
                if (p2_count >= 25)
                    $fatal(1, "Pool2 produced more than 25 positions");
                for (mon_p2_ch = 0; mon_p2_ch < 24; mon_p2_ch = mon_p2_ch + 1) begin
                    expected_value = reference_p2[p2_count*24 + mon_p2_ch];
                    if ($signed(p2_out_flat[mon_p2_ch*8 +: 8]) !== expected_value)
                        $fatal(1,
                            "Pool2 mismatch pos=%0d ch=%0d got=%0d expected=%0d",
                            p2_count, mon_p2_ch,
                            $signed(p2_out_flat[mon_p2_ch*8 +: 8]), expected_value);
                end
                p2_count = p2_count + 1;
            end
        end
    end

    task write_c1_parameter;
        input [1:0] select;
        input integer offset;
        input integer value;
        begin
            @(negedge clk);
            c1_weight_we     = 1'b1;
            c1_param_sel     = select;
            c1_weight_offset = offset;
            c1_weight_data   = value;
            @(negedge clk);
            c1_weight_we     = 1'b0;
        end
    endtask

    task write_c2_parameter;
        input [1:0] select;
        input integer offset;
        input integer value;
        begin
            @(negedge clk);
            c2_weight_we     = 1'b1;
            c2_param_sel     = select;
            c2_weight_offset = offset;
            c2_weight_data   = value;
            @(negedge clk);
            c2_weight_we     = 1'b0;
        end
    endtask

    task send_c2_position;
        input integer position;
        integer send_ch;
        begin
            @(negedge clk);
            for (send_ch = 0; send_ch < 8; send_ch = send_ch + 1)
                c2_in_flat[send_ch*8 +: 8] = p1_saved[position*8 + send_ch];
            c2_in_valid = 1'b1;

            begin : wait_for_c2_ready
                while (1) begin
                    @(posedge clk);
                    if (c2_in_ready)
                        disable wait_for_c2_ready;
                end
            end

            @(negedge clk);
            c2_in_valid = 1'b0;
        end
    endtask

    integer out_ch;
    integer input_ch;
    integer tap;
    integer input_pos;
    integer timeout_cycles;
    integer ref_position;
    integer ref_channel;
    integer ref_pool_y;
    integer ref_pool_x;
    integer ref_dy;
    integer ref_dx;
    integer ref_candidate;
    integer ref_maximum;

    initial begin
        // Build the independent golden tensors once at time zero.  Keeping
        // these values in reference RAM makes every cycle-by-cycle monitor a
        // cheap lookup while retaining the full mathematical convolution
        // oracle (including signed OIHW kernels and requantization).
        for (ref_position = 0; ref_position < 676;
             ref_position = ref_position + 1)
            for (ref_channel = 0; ref_channel < 8;
                 ref_channel = ref_channel + 1)
                reference_c1[ref_position*8 + ref_channel] =
                    expected_c1(ref_position, ref_channel);

        for (ref_position = 0; ref_position < 169;
             ref_position = ref_position + 1)
            for (ref_channel = 0; ref_channel < 8;
                 ref_channel = ref_channel + 1)
                reference_p1[ref_position*8 + ref_channel] =
                    expected_p1(ref_position, ref_channel);

        for (ref_position = 0; ref_position < 121;
             ref_position = ref_position + 1)
            for (ref_channel = 0; ref_channel < 24;
                 ref_channel = ref_channel + 1)
                reference_c2[ref_position*24 + ref_channel] =
                    expected_c2(ref_position, ref_channel);

        for (ref_position = 0; ref_position < 25;
             ref_position = ref_position + 1) begin
            ref_pool_y = ref_position / 5;
            ref_pool_x = ref_position % 5;
            for (ref_channel = 0; ref_channel < 24;
                 ref_channel = ref_channel + 1) begin
                ref_maximum = -2147483647;
                for (ref_dy = 0; ref_dy < 2; ref_dy = ref_dy + 1)
                    for (ref_dx = 0; ref_dx < 2; ref_dx = ref_dx + 1) begin
                        ref_candidate = reference_c2[
                            ((2*ref_pool_y + ref_dy)*11 +
                             (2*ref_pool_x + ref_dx))*24 + ref_channel];
                        if (ref_candidate > ref_maximum)
                            ref_maximum = ref_candidate;
                    end
                reference_p2[ref_position*24 + ref_channel] = ref_maximum;
            end
        end

        // Reset all streaming state.
        repeat (6) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Conv1: asymmetric kernels cover all nine taps. Channel 7 uses a
        // signed (-tap7 + tap8) kernel to verify signed INT8 multiplication.
        for (out_ch = 0; out_ch < 8; out_ch = out_ch + 1)
            for (tap = 0; tap < 9; tap = tap + 1)
                write_c1_parameter(2'd0, out_ch*9 + tap,
                                   model_c1_weight(out_ch, tap));
        for (out_ch = 0; out_ch < 8; out_ch = out_ch + 1) begin
            write_c1_parameter(2'd1, out_ch, model_c1_bias(out_ch));
            write_c1_parameter(2'd2, out_ch, 1);
            write_c1_parameter(2'd3, out_ch, 0);
        end

        // Conv2: sparse asymmetric signed weights distinguish every C_in,
        // tap and output group, thereby checking the complete OIHW mapping.
        for (out_ch = 0; out_ch < 24; out_ch = out_ch + 1)
            for (input_ch = 0; input_ch < 8; input_ch = input_ch + 1)
                for (tap = 0; tap < 9; tap = tap + 1)
                    write_c2_parameter(2'd0,
                        (out_ch*8 + input_ch)*9 + tap,
                        model_c2_weight(out_ch, input_ch, tap));
        for (out_ch = 0; out_ch < 24; out_ch = out_ch + 1) begin
            write_c2_parameter(2'd1, out_ch, model_c2_bias(out_ch));
            write_c2_parameter(2'd2, out_ch, 1);
            write_c2_parameter(2'd3, out_ch, 6);
        end

        // Stream a non-symmetric image to prove row/column/tap ordering.
        // Conv1 is pipelined and must remain ready for every accepted pixel.
        c1_in_valid = 1'b0;
        for (input_pos = 0; input_pos < 784; input_pos = input_pos + 1) begin
            @(negedge clk);
            if ((input_pos % 53) == 17) begin
                c1_in_valid = 1'b0;
                @(negedge clk); // deterministic source bubble
            end
            c1_in_data  = model_input_pixel(input_pos/28, input_pos%28);
            c1_in_valid = 1'b1;
            @(posedge clk);
            if (!c1_in_ready)
                $fatal(1, "Conv1 unexpectedly backpressured input pixel %0d", input_pos);
        end
        @(negedge clk);
        c1_in_valid = 1'b0;

        timeout_cycles = 0;
        while ((p1_count < 169) && (timeout_cycles < 10000)) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        if (c1_count != 676 || p1_count != 169)
            $fatal(1, "Conv1/Pool1 count mismatch: c1=%0d p1=%0d", c1_count, p1_count);

        // Replay the verified Pool1 tensor.  valid/data are held stable while
        // the tiled Conv2 engine deasserts input_ready.
        @(negedge clk);
        mode_conv2 = 1'b1;
        for (input_pos = 0; input_pos < 169; input_pos = input_pos + 1) begin
            if ((input_pos % 19) == 7)
                @(posedge clk); // deterministic replay bubble
            send_c2_position(input_pos);
        end

        timeout_cycles = 0;
        while (((c2_count < 121) || (p2_count < 25)) &&
               (timeout_cycles < 20000)) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end

        if (c2_count != 121 || p2_count != 25)
            $fatal(1, "Conv2/Pool2 count mismatch: c2=%0d p2=%0d", c2_count, p2_count);
        if (c2_input_fire_count != 169)
            $fatal(1, "Conv2 input handshake count mismatch: got=%0d expected=169",
                   c2_input_fire_count);
        if (c2_stall_cycles == 0)
            $fatal(1, "Conv2 ready/valid backpressure was not exercised");

        // Drain longer than the output pipeline so a late 122nd/26th beat
        // cannot hide behind an immediate $finish.
        repeat (100) @(posedge clk);
        if (c1_count != 676 || p1_count != 169 ||
            c2_count != 121 || p2_count != 25)
            $fatal(1, "Late extra output detected after drain guard");

        // The reusable ready/valid contract must reject a beat during clear.
        @(negedge clk);
        frame_clear = 1'b1;
        c2_in_valid = 1'b1;
        #1;
        if (c2_in_ready !== 1'b0)
            $fatal(1, "Conv2 advertised ready during frame_clear");
        @(posedge clk);
        @(negedge clk);
        frame_clear = 1'b0;
        c2_in_valid = 1'b0;
        mode_conv2  = 1'b0;
        #1;
        if (c1_in_ready !== 1'b1)
            $fatal(1, "Shared PE array did not return to Conv1-ready after clear");

        $display("============================================================");
        $display(" PASS: 8-lane shared-PE dataflow is numerically correct");
        $display(" Conv1 outputs : %0d (expected 676)", c1_count);
        $display(" Pool1 outputs : %0d (expected 169)", p1_count);
        $display(" Conv2 outputs : %0d (expected 121)", c2_count);
        $display(" Pool2 outputs : %0d (expected 25)", p2_count);
        $display(" Conv2 inputs  : %0d (expected 169)", c2_input_fire_count);
        $display(" Conv2 stalled-valid cycles observed: %0d", c2_stall_cycles);
        $display(" Verified: tap order, 3 C_out groups, 8 C_in accumulation,");
        $display("           bias, rounding, ReLU, clamp, pooling and backpressure.");
        $display("============================================================");
        $finish;
    end

    // Independent watchdog catches deadlock or a dropped held-valid window.
    initial begin
        repeat (100000) @(posedge clk);
        $fatal(1, "Global watchdog expired");
    end

endmodule
