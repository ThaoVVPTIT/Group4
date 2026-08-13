`timescale 1ns / 1ps
/*------------------------------------------------------------------------
 * Testbench: tb_axis_cnn
 *
 * Self-checking testbench for cnn_accelerator_top.
 *
 * [FIX so voi ban cu] Truoc day co mot check "DMA request count" gia dinh
 * MOI FRAME phai co dung 2 lan dma_start (1 cho Conv1, 1 cho Conv2), theo
 * kien truc cu khi Conv2 cung phai cho dma_done tu N2. Kien truc da duoc
 * sua (xem cnn_scheduler.v): Conv2 replay du lieu NOI BO tu p1_mem, khong
 * con goi DMA lan hai nua. Vi vay so luong dma_start dung phai la 1/frame.
 * Neu ai do sua scheduler quay lai kieu cu (2 lan DMA/frame), check ben
 * duoi se bao FAIL ro rang thay vi im lang.
 *
 * Testbench nay:
 *   1) Nap toan bo 88,583 tham so trong so qua bus dma_weight_* (dung
 *      cong thuc dia chi giong axis_cnn_mnist_emnist.v / fc_stream.v).
 *   2) Voi moi frame: bat start, N2-model gui anh 784 pixel qua AXI-Stream
 *      CO CHEN BUBBLE ngau nhien (test s_axis_tready backpressure).
 *   3) Kiem so lan dma_start (=1/frame, xem [FIX] o tren).
 *   4) Kiem thoi gian busy/done/prediction_ready hop le.
 *   5) Test backpressure phia output (m_axis_tready tre) de kiem tra skid
 *      register giu du lieu on dinh.
 *   6) Cho nhieu frame lien tiep (khong reset giua cac frame).
 *   7) Bao cao PASS/FAIL tong ket, khong $finish giua chung khi loi nho
 *      (tich luy fail_count), chi $finish that su khi watchdog timeout
 *      hoac ket thuc toan bo test.
 *------------------------------------------------------------------------*/
module tb_axis_cnn;

    // ------------------------------------------------------------------
    // Cau hinh test
    // ------------------------------------------------------------------
    localparam integer NUM_FRAMES                    = 3;
    localparam integer EXPECTED_DMA_REQUESTS_PER_FRAME = 1; // [FIX] truoc la 2
    localparam integer CLK_PERIOD                     = 10;    // 100 MHz
    localparam integer GLOBAL_TIMEOUT_NS              = 5_000_000; // watchdog

    // ------------------------------------------------------------------
    // Kich thuoc khong gian trong so (khop dia chi trong
    // cnn_accelerator_top.v / axis_cnn_mnist_emnist.v / fc_stream.v)
    // ------------------------------------------------------------------
    localparam integer CONV1_KDEPTH = 72,   CONV1_PDEPTH = 8;
    localparam integer CONV2_KDEPTH = 1728, CONV2_PDEPTH = 24;
    localparam integer FC1_IN = 600, FC1_OUT = 120, FC1_KDEPTH = FC1_IN*FC1_OUT, FC1_PDEPTH = 120;
    localparam integer FC2_IN = 120, FC2_OUT = 84,  FC2_KDEPTH = FC2_IN*FC2_OUT, FC2_PDEPTH = 84;
    localparam integer FC3_IN = 84,  FC3_OUT = 47,  FC3_KDEPTH = FC3_IN*FC3_OUT, FC3_PDEPTH = 47;
    // Tong: 72+8+8+8 + 1728+24+24+24 + 72000+120+120+120 + 10080+84+84+84
    //       + 3948+47 = 88,583  (khop dong log "All 88,583 weight
    //       parameters loaded.")

    // ------------------------------------------------------------------
    // Clock / reset
    // ------------------------------------------------------------------
    reg aclk    = 1'b0;
    reg aresetn = 1'b0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // ------------------------------------------------------------------
    // DUT ports
    // ------------------------------------------------------------------
    reg         start;
    wire        busy, done, error_flag, prediction_ready;
    wire        dma_start;
    reg         dma_done;
    wire [1:0]  layer_select;
    reg         timeout_flag;

    reg         dma_weight_we;
    reg  [23:0] dma_weight_addr;
    reg  [31:0] dma_weight_data;
    reg         weights_loaded_flag;

    reg         s_axis_tvalid;
    reg  [7:0]  s_axis_tdata;
    wire        s_axis_tready;

    reg         m_axis_tready;
    wire [7:0]  m_axis_tdata;
    wire        m_axis_tvalid;
    wire        m_axis_tlast;

    // ------------------------------------------------------------------
    // DUT instantiation
    // ------------------------------------------------------------------
    cnn_accelerator_top dut (
        .aclk              (aclk),
        .aresetn           (aresetn),
        .start             (start),
        .busy              (busy),
        .done              (done),
        .error             (error_flag),
        .prediction_ready  (prediction_ready),
        .dma_start         (dma_start),
        .dma_done          (dma_done),
        .layer_select      (layer_select),
        .timeout_flag      (timeout_flag),
        .dma_weight_we     (dma_weight_we),
        .dma_weight_addr   (dma_weight_addr),
        .dma_weight_data   (dma_weight_data),
        .weights_loaded_flag (weights_loaded_flag),
        .s_axis_tready     (s_axis_tready),
        .s_axis_tdata      (s_axis_tdata),
        .s_axis_tvalid     (s_axis_tvalid),
        .m_axis_tready     (m_axis_tready),
        .m_axis_tdata      (m_axis_tdata),
        .m_axis_tvalid     (m_axis_tvalid),
        .m_axis_tlast      (m_axis_tlast)
    );

    glbl glbl ();

    // ------------------------------------------------------------------
    // So dem PASS/FAIL toan cuc
    // ------------------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;

    task check_true;
        input        cond;
        input [1023:0] msg; // chuoi thong bao (as bit vector, dung %s)
        begin
            if (cond) begin
                pass_count = pass_count + 1;
                $display("[%0t] [PASS] %s", $time, msg);
            end else begin
                fail_count = fail_count + 1;
                $display("[%0t] [FAIL] %s", $time, msg);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Dem so lan dma_start trong 1 frame (dieu can sua theo [FIX] tren)
    // ------------------------------------------------------------------
    integer dma_request_count;
    always @(posedge aclk) begin
        if (!aresetn)
            dma_request_count <= 0;
        else if (dma_start)
            dma_request_count <= dma_request_count + 1;
    end

    task reset_dma_request_count;
        begin
            @(posedge aclk);
            dma_request_count = 0;
        end
    endtask

    task check_layer_counts;
        input integer frame_num;
        reg [1023:0] msg;
        begin
            $sformat(msg,
                "DMA request count for frame %0d: got %0d, expected %0d",
                frame_num, dma_request_count, EXPECTED_DMA_REQUESTS_PER_FRAME);
            check_true(dma_request_count === EXPECTED_DMA_REQUESTS_PER_FRAME, msg);
        end
    endtask

    // ------------------------------------------------------------------
    // Weight-load helper task
    //   mod_sel   [23:21] : 0=Conv1 1=Conv2 2=FC1 3=FC2 4=FC3
    //   param_sel [20:19] : 0=Kernel 1=Bias 2=Mult 3=Shift
    //   offset    [18:0]
    // ------------------------------------------------------------------
    task automatic write_weight;
        input [2:0]  mod_sel;
        input [1:0]  param_sel;
        input [18:0] offset;
        input [31:0] data;
        begin
            dma_weight_addr = {mod_sel, param_sel, offset};
            dma_weight_data = data;
            dma_weight_we   = 1'b1;
            @(posedge aclk);
            dma_weight_we   = 1'b0;
        end
    endtask

    // Deterministic synthetic pattern generator (khong can file trong so
    // that; du de kiem tra dataflow/protocol, KHONG dung de kiem do chinh
    // xac nhan dang, giong nhu "synthetic structural coefficients" trong
    // log goc).
    function [31:0] synth_val;
        input integer idx;
        input integer salt;
        begin
            synth_val = (idx * 32'h9E3779B9 + salt) & 32'h0000007F; // gon trong INT8/mult nho
        end
    endfunction

    integer wi;
    task automatic load_all_weights;
        begin
            $display("[%0t] Loading weight parameters via DMA bus...", $time);

            // ---- Conv1 ----
            for (wi = 0; wi < CONV1_KDEPTH; wi = wi + 1)
                write_weight(3'd0, 2'd0, wi[18:0], synth_val(wi, 1));
            for (wi = 0; wi < CONV1_PDEPTH; wi = wi + 1)
                write_weight(3'd0, 2'd1, wi[18:0], 32'sd0);        // bias = 0
            for (wi = 0; wi < CONV1_PDEPTH; wi = wi + 1)
                write_weight(3'd0, 2'd2, wi[18:0], 32'sd1);        // mult = 1
            for (wi = 0; wi < CONV1_PDEPTH; wi = wi + 1)
                write_weight(3'd0, 2'd3, wi[18:0], 32'd8);         // shift = 8

            // ---- Conv2 ----
            for (wi = 0; wi < CONV2_KDEPTH; wi = wi + 1)
                write_weight(3'd1, 2'd0, wi[18:0], synth_val(wi, 2));
            for (wi = 0; wi < CONV2_PDEPTH; wi = wi + 1)
                write_weight(3'd1, 2'd1, wi[18:0], 32'sd0);
            for (wi = 0; wi < CONV2_PDEPTH; wi = wi + 1)
                write_weight(3'd1, 2'd2, wi[18:0], 32'sd1);
            for (wi = 0; wi < CONV2_PDEPTH; wi = wi + 1)
                write_weight(3'd1, 2'd3, wi[18:0], 32'd8);

            // ---- FC1 ----
            for (wi = 0; wi < FC1_KDEPTH; wi = wi + 1)
                write_weight(3'd2, 2'd0, wi[18:0], synth_val(wi, 3));
            for (wi = 0; wi < FC1_PDEPTH; wi = wi + 1)
                write_weight(3'd2, 2'd1, wi[18:0], 32'sd0);
            for (wi = 0; wi < FC1_PDEPTH; wi = wi + 1)
                write_weight(3'd2, 2'd2, wi[18:0], 32'sd1);
            for (wi = 0; wi < FC1_PDEPTH; wi = wi + 1)
                write_weight(3'd2, 2'd3, wi[18:0], 32'd8);

            // ---- FC2 ----
            for (wi = 0; wi < FC2_KDEPTH; wi = wi + 1)
                write_weight(3'd3, 2'd0, wi[18:0], synth_val(wi, 4));
            for (wi = 0; wi < FC2_PDEPTH; wi = wi + 1)
                write_weight(3'd3, 2'd1, wi[18:0], 32'sd0);
            for (wi = 0; wi < FC2_PDEPTH; wi = wi + 1)
                write_weight(3'd3, 2'd2, wi[18:0], 32'sd1);
            for (wi = 0; wi < FC2_PDEPTH; wi = wi + 1)
                write_weight(3'd3, 2'd3, wi[18:0], 32'd8);

            // ---- FC3 (chi Kernel + Bias, khong Mult/Shift - logit tho) ----
            for (wi = 0; wi < FC3_KDEPTH; wi = wi + 1)
                write_weight(3'd4, 2'd0, wi[18:0], synth_val(wi, 5));
            for (wi = 0; wi < FC3_PDEPTH; wi = wi + 1)
                write_weight(3'd4, 2'd1, wi[18:0], 32'sd0);

            $display("[%0t] All %0d weight parameters loaded.", $time,
                CONV1_KDEPTH+3*CONV1_PDEPTH + CONV2_KDEPTH+3*CONV2_PDEPTH +
                FC1_KDEPTH+3*FC1_PDEPTH + FC2_KDEPTH+3*FC2_PDEPTH +
                FC3_KDEPTH+FC3_PDEPTH);

            @(posedge aclk);
            weights_loaded_flag = 1'b1;
        end
    endtask

    // ------------------------------------------------------------------
    // Anh test + nhan (doc tu file neu co; mac dinh 0 neu khong tim thay)
    // ------------------------------------------------------------------
    reg [7:0] image_mem [0:783];
    reg [7:0] label_mem  [0:0];   // $readmemh doi hoi mot memory, khong the doc thang vao 1 reg vo huong
    reg [7:0] expected_label;

    task automatic load_test_vectors;
        begin
            // Sua duong dan cho khop project neu can.
            $readmemh("test_image.mem", image_mem);
            $readmemh("test_label.mem", label_mem);
            expected_label = label_mem[0];
        end
    endtask

    // ------------------------------------------------------------------
    // N2 model: gui 784 pixel qua AXI-Stream, chen bubble ngau nhien de
    // kiem tra s_axis_tready backpressure. Sau khi day xong, phat dma_done
    // 1 xung (N2 van bao "DMA xong" cho log/monitor, du scheduler hien tai
    // khong con gate theo tin hieu nay cho Conv1 -- xem [FIX] o
    // cnn_scheduler.v).
    // ------------------------------------------------------------------
    task automatic send_image_with_bubbles;
        integer i;
        begin
            $display("[%0t] Sending frame with input-valid bubbles...", $time);
            i = 0;
            s_axis_tvalid = 1'b0;
            while (i < 784) begin
                if (!s_axis_tvalid && (($urandom % 4) == 0)) begin
                    // chen 1 chu ky bubble truoc khi day pixel tiep theo
                    @(posedge aclk);
                end else begin
                    s_axis_tdata  = image_mem[i];
                    s_axis_tvalid = 1'b1;
                    @(posedge aclk);
                    if (s_axis_tready) begin
                        i = i + 1;
                        s_axis_tvalid = 1'b0;
                    end
                    // neu tready=0: giu nguyen tdata/tvalid, thu lai vong sau
                end
            end
            s_axis_tvalid = 1'b0;
            $display("[%0t] Frame input complete.", $time);

            // Bao DMA xong (chi mang tinh thong bao/log, xem comment tren)
            @(posedge aclk);
            dma_done = 1'b1;
            @(posedge aclk);
            dma_done = 1'b0;
        end
    endtask

    // Tu dong kich hoat viec gui anh khi thay dma_start cho Conv1
    // (layer_select == 2'b00). Neu (do loi hoi quy) scheduler lai phat
    // dma_start lan hai cho Conv2 (layer_select == 2'b01), N2-model KHONG
    // phan hoi du lieu that (dung dung mo phong "N2 khong con day anh cho
    // Conv2 nua" nhu bao cao thuc te) -- chi de dma_request_count bat
    // duoc va check_layer_counts se bao FAIL ro rang.
    reg image_send_pending;
    always @(posedge aclk) begin
        if (!aresetn)
            image_send_pending <= 1'b0;
        else if (dma_start && (layer_select == 2'b00))
            image_send_pending <= 1'b1;
        else if (image_send_pending)
            image_send_pending <= 1'b0;
    end

    // ------------------------------------------------------------------
    // Doc AXI-Stream ket qua (1 beat, TLAST=1), voi test backpressure:
    // giu m_axis_tready = 0 mot vai chu ky truoc khi cho phep, kiem tra
    // du lieu on dinh (skid register) trong luc do.
    // ------------------------------------------------------------------
    reg [7:0] captured_result;
    task automatic receive_prediction_with_backpressure;
        integer stall_cycles;
        reg [7:0] snapshot;
        begin
            m_axis_tready = 1'b0;
            wait (m_axis_tvalid == 1'b1);

            snapshot = m_axis_tdata;
            stall_cycles = ($urandom % 5) + 1;
            repeat (stall_cycles) begin
                @(posedge aclk);
                check_true(m_axis_tvalid === 1'b1,
                    "m_axis_tvalid stays asserted while tready=0");
                check_true(m_axis_tdata === snapshot,
                    "m_axis_tdata stable while tready=0 (skid register holds)");
                check_true(m_axis_tlast === 1'b1,
                    "m_axis_tlast asserted on the single result beat");
            end

            @(negedge aclk);
            m_axis_tready = 1'b1;
            @(posedge aclk);
            check_true((m_axis_tvalid && m_axis_tready) === 1'b1,
                "m_axis handshake completes after backpressure released");
            captured_result = m_axis_tdata;
            @(negedge aclk);
            m_axis_tready = 1'b0;
        end
    endtask

    // ------------------------------------------------------------------
    // Chay 1 frame hoan chinh: start -> gui anh -> nhan ket qua -> kiem tra
    // ------------------------------------------------------------------
    task automatic run_one_frame;
        input integer frame_num;
        reg [1023:0] msg;
        begin
            reset_dma_request_count();
            #1; // cho NBA cua DUT "chot" xong truoc khi doc busy (tranh race)

            check_true(busy === 1'b0, "busy = 0 truoc khi start frame moi");

            @(negedge aclk);
            start = 1'b1;
            @(posedge aclk);
            #1; // tuong tu, doi mot delta truoc khi doc busy
            check_true(busy === 1'b1, "busy len 1 ngay sau khi start duoc chap nhan");
            @(negedge aclk);
            start = 1'b0; // 1-cycle pulse, giong hanh vi start_armed trong scheduler

            // N2-model tu kich hoat gui anh khi thay dma_start cho Conv1
            wait (image_send_pending == 1'b1);
            send_image_with_bubbles();

            // Nhan ket qua (co test backpressure output)
            receive_prediction_with_backpressure();

            check_true(prediction_ready === 1'b1,
                "prediction_ready = 1 khi ket qua da san sang");
            check_true(error_flag === 1'b0,
                "error = 0 (khong roi vao ERROR_STATE) sau 1 frame binh thuong");

            $sformat(msg,
                "Frame %0d prediction: AXI result=0x%02h, expected label=0x%02h (informational, synthetic weights)",
                frame_num, captured_result, expected_label);
            $display("[%0t] %s", $time, msg);

            check_layer_counts(frame_num);
        end
    endtask

    // ------------------------------------------------------------------
    // Watchdog toan cuc: neu mo phong treo qua lau, bao loi ro rang thay
    // vi cham timeout mo phong vo han.
    // ------------------------------------------------------------------
    initial begin
        #(GLOBAL_TIMEOUT_NS);
        $display("[%0t] FATAL: Global watchdog timeout - simulation treo.", $time);
        fail_count = fail_count + 1;
        $display("==== SUMMARY: %0d PASS / %0d FAIL ====", pass_count, fail_count);
        $finish;
    end

    // ------------------------------------------------------------------
    // Chuoi test chinh
    // ------------------------------------------------------------------
    integer f;
    initial begin
        start               = 1'b0;
        dma_done            = 1'b0;
        timeout_flag        = 1'b0;
        dma_weight_we       = 1'b0;
        dma_weight_addr     = 24'd0;
        dma_weight_data     = 32'd0;
        weights_loaded_flag = 1'b0;
        s_axis_tvalid       = 1'b0;
        s_axis_tdata        = 8'd0;
        m_axis_tready       = 1'b0;

        // Reset
        aresetn = 1'b0;
        repeat (5) @(posedge aclk);
        @(negedge aclk);
        aresetn = 1'b1;

        load_test_vectors();
        load_all_weights();

        for (f = 1; f <= NUM_FRAMES; f = f + 1) begin
            run_one_frame(f);
        end

        $display("==== SUMMARY: %0d PASS / %0d FAIL ====", pass_count, fail_count);
        if (fail_count == 0)
            $display("==== TESTBENCH RESULT: PASS ====");
        else
            $display("==== TESTBENCH RESULT: FAIL ====");

        $finish;
    end

endmodule