`timescale 1ns / 1ps

module cnn_scheduler (
    input wire clk,
    input wire rst_n,

    // Giao tiếp với RISC-V (Nhóm 3)
    input wire start,
    output reg busy,
    output reg done,
    output reg error,              
    output reg prediction_ready,

    // Giao tiếp với Memory / DMA (Nhóm 2)
    output reg dma_start,
    input wire dma_done,
    output reg [1:0] layer_select,

    // Giao tiếp với Khối tính toán & Sliding Window (Nhóm 1 & 4)
    output reg sw_load_en,
    output reg [1:0] sw_cfg,       
    input wire layer_done,

    // Giao tiếp với khối Fully Connected
    output reg fc_start,
    input wire fc_done,

    // Cơ chế phát hiện lỗi: timeout khi chờ handshake quá lâu
    input wire timeout_flag,

    // Bao hieu toan bo trong so da duoc nap xong qua bus memory-mapped.
    input wire weights_loaded_flag
);

    // [REV3 - FIX DEADLOCK] Bo cac trang thai CONV1_WAIT_DMA / CONV2_DMA /
    // CONV2_WAIT_DMA. Ly do (bug bao cao thuc te khi mo phong):
    //
    //   1) sw_load_en truoc day CHI bat o CONV1_RUN, tuc la SAU khi
    //      dma_done_accept da xay ra.
    //   2) Nhung s_axis_tready (trong axis_cnn_mnist_emnist.v) lai chi len 1
    //      khi sw_load_en=1 (qua conv1_window_enable).
    //   3) N2 lai chi phat dma_done SAU KHI da day toan bo 784 byte anh toi
    //      TLAST qua FIFO AXI-Stream sau (chi sau 512 byte).
    //   4) FIFO 512 byte < 784 byte anh se day va khong the thoat du lieu
    //      vi CNN chua bao gio bat s_axis_tready (cho dma_done truoc).
    //
    //   => VONG CHO VONG (circular wait): CNN cho dma_done; dma_done cho
    //      FIFO thoat; FIFO cho s_axis_tready; s_axis_tready cho sw_load_en;
    //      sw_load_en lai cho dma_done. He thong treo cung, khong bao gio
    //      tien len.
    //
    // Fix: bat sw_load_en NGAY trong cung trang thai phat dma_start (CNN
    // tieu thu pixel dong thoi voi DMA dang day du lieu vao), va dung
    // layer_done (hoan thanh pipeline Conv1/Pool1) lam dieu kien duy nhat de
    // chuyen trang thai -- khong con cho dma_done nua.
    //
    // Voi Conv2: du lieu duoc replay tu p1_mem noi bo (xem
    // axis_cnn_mnist_emnist.v), khong doc gi tu Memory ca, nen KHONG can
    // dma_start/dma_done lan hai. Sau khi Conv1 xong (layer_done), chuyen
    // THANG sang CONV2_RUN.
    //
    // dma_start/dma_done duoc GIU NGUYEN trong danh sach cong (khong doi
    // interface voi Nhom 2) de tuong thich nguoc; dma_start van duoc phat
    // 1 xung de N2 biet ma bat dau day anh, nhung scheduler khong con
    // GATE trang thai cua minh theo dma_done nua.
    localparam [3:0]
        IDLE            = 4'd0,

        // --- Pha Convolution 1: nhan anh + chay Conv1 dong thoi ---
        CONV1_DMA       = 4'd1,   // 1 chu ky: phat dma_start + bat sw_load_en
        CONV1_RUN       = 4'd2,   // giu sw_load_en, cho layer_done cua Conv1

        // --- Pha Convolution 2: replay noi bo tu p1_mem, khong DMA ---
        CONV2_RUN       = 4'd3,

        // --- Pha Fully Connected ---
        FC_RUN          = 4'd4,
        FC_WAIT_DONE    = 4'd5,

        // --- Hoan thanh ---
        FINISH          = 4'd6,

        ERROR_STATE     = 4'd7,

        WAIT_WEIGHTS    = 4'd8;

    reg [3:0] current_state, next_state;

    // A request is accepted only while IDLE/FINISH and only once for each
    // assertion of start.  The requester must deassert start before another
    // transaction can be accepted.
    reg start_armed;
    wire start_accept = start && start_armed &&
                        ((current_state == IDLE) ||
                         (current_state == FINISH));

    // Tien trinh chuyen trang thai (Sequential Logic)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= WAIT_WEIGHTS;
            start_armed   <= 1'b1;
        end else begin
            current_state <= next_state;

            if (!start)
                start_armed <= 1'b1;
            else if (start_accept)
                start_armed <= 1'b0;
        end
    end

    // Tien trinh to hop quyet dinh trang thai tiep theo va dieu khien tin hieu (Combinational Logic)
    always @* begin
        // Gan gia tri mac dinh tranh mach chot (latch)
        next_state       = current_state;
        busy             = 1'b1;
        done             = 1'b0;
        error            = 1'b0;
        prediction_ready = 1'b0;
        dma_start        = 1'b0;
        layer_select     = 2'b00;
        sw_load_en       = 1'b0;
        sw_cfg           = 2'b00;
        fc_start         = 1'b0;

        case (current_state)
            WAIT_WEIGHTS: begin
                busy = 1'b1;
                if (weights_loaded_flag) begin
                    next_state = IDLE;
                end else begin
                    next_state = WAIT_WEIGHTS;
                end
            end

            IDLE: begin
                busy = 1'b0;
                if (start_accept) begin
                    next_state = CONV1_DMA;
                end
            end

            // ==================== CONV 1 ====================
            // [FIX] Phat dma_start VA bat sw_load_en trong CUNG mot chu ky.
            // CNN san sang tieu thu pixel truoc/dong thoi voi luc N2 bat
            // dau day du lieu, nen FIFO AXI-Stream cua N2 khong bao gio bi
            // day ma khong co loi ra.
            CONV1_DMA: begin
                dma_start    = 1'b1; // 1-cycle kick-off, bao N2 bat dau day anh
                layer_select = 2'b00;
                sw_cfg       = 2'b00;
                sw_load_en   = 1'b1; // bat NGAY, khong cho dma_done
                next_state   = CONV1_RUN;
            end

            // Giu sw_load_en muc cao lien tuc trong khi Conv1/Pool1 chay va
            // dong thoi tiep tuc nhan pixel tu AXIS. Chuyen tiep khi
            // layer_done_c1 bao toan bo 169 diem Pool1 da ghi xong.
            CONV1_RUN: begin
                sw_load_en   = 1'b1;
                sw_cfg       = 2'b00;
                layer_select = 2'b00;
                if (layer_done) begin
                    // [FIX] Conv2 dung replay tu p1_mem, khong can DMA/
                    // dma_done lan hai -- chuyen THANG sang CONV2_RUN.
                    next_state = CONV2_RUN;
                end else if (timeout_flag) begin
                    next_state = ERROR_STATE;
                end else begin
                    next_state = CONV1_RUN;
                end
            end

            // ==================== CONV 2 ====================
            // Khong con CONV2_DMA/CONV2_WAIT_DMA: du lieu Conv2 la ban
            // replay 169 vector tu p1_mem (xem axis_cnn_mnist_emnist.v),
            // hoan toan noi bo, khong phu thuoc N2.
            CONV2_RUN: begin
                sw_load_en   = 1'b1;
                sw_cfg       = 2'b01;
                layer_select = 2'b01;
                if (layer_done) begin
                    next_state = FC_RUN;
                end else if (timeout_flag) begin
                    next_state = ERROR_STATE;
                end else begin
                    next_state = CONV2_RUN;
                end
            end

            // ==================== FULLY CONNECTED ====================
            // [FIX] fc_done khong the len 1 ngay trong chinh chu ky fc_start
            // moi duoc pulse (fc_stream can nhieu chu ky pipeline moi ra
            // ket qua dau tien) -- khac voi dma_done_accept o CONV1_DMA
            // (co fast-path da duoc formal-proof trong tb_equiv.v). Vi vay
            // kiem tra fc_done/timeout_flag ngay trong FC_RUN la dieu kien
            // thua, chi lam FC_RUN va FC_WAIT_DONE giong het nhau. FC_RUN
            // chi phat xung fc_start 1 chu ky roi chuyen KHONG DIEU KIEN
            // sang FC_WAIT_DONE (giong CONV1_DMA -> CONV1_RUN); chi
            // FC_WAIT_DONE moi kiem tra fc_done/timeout_flag.
            FC_RUN: begin
                fc_start   = 1'b1;   // 1-cycle pulse
                next_state = FC_WAIT_DONE;
            end

            FC_WAIT_DONE: begin
                if (fc_done) begin
                    next_state = FINISH;
                end else if (timeout_flag) begin
                    next_state = ERROR_STATE;
                end else begin
                    next_state = FC_WAIT_DONE;
                end
            end

            // ==================== FINISH ====================
            FINISH: begin
                done             = 1'b1;
                prediction_ready = 1'b1;
                busy             = 1'b0;
                if (start_accept)
                    next_state = CONV1_DMA;
                else
                    next_state = FINISH;
            end

            // ==================== ERROR ==================== 
            ERROR_STATE: begin
                error      = 1'b1;
                busy       = 1'b0;
                next_state = ERROR_STATE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule