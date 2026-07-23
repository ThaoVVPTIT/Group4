module scheduler #(
    parameter DMA_TIMEOUT   = 64,   // số chu kỳ chờ tối đa cho DMA
    parameter PATCH_TIMEOUT = 64,   // số chu kỳ chờ tối đa cho Sliding Window
    parameter PE_TIMEOUT    = 64,   // số chu kỳ chờ tối đa cho PE Array (gồm ReLU+Pool)
    parameter FC_TIMEOUT    = 64    // số chu kỳ chờ tối đa cho FC Engine
) (
    input  wire        clk,
    input  wire        rst_n,

    // ---- RISC-V Controller (Configuration Registers / AXI4-Lite) ----
    input  wire        start,
    input  wire        layer_cfg_valid,
    input  wire [3:0]  kernel_size,
    input  wire [3:0]  stride,
    input  wire [3:0]  padding,
    input  wire        layer_has_pooling, // chuyển tiếp cho Compute Engine biết có Pool hay không
    input  wire [3:0]  num_conv_layers,
    input  wire [31:0] mem_base_addr,
    output reg         busy,
    output reg         done,
    output reg         prediction_ready,
    output reg         error,
    output reg  [2:0]  error_code,   // 000=none,001=DMA,010=PE,100=Patch,101=InvalidConfig,110=FC
    output reg  [3:0]  sched_state,

    // ---- Sliding Window Generator (nội bộ Nhóm 4) ----
    output reg         sw_load_en,
    output reg  [3:0]  sw_kernel_cfg,
    output reg  [3:0]  sw_stride_cfg,
    output reg  [3:0]  sw_padding_cfg,
    input  wire        patch_valid,
    input  wire        patch_last,        // Patch cuối cùng của lớp hiện tại

    // ---- PE Array / Compute Engine (Nhóm 1) ----
    // ĐÃ XÁC NHẬN: MAC + ReLU + Pooling chạy pipeline nội bộ trong khối này,
    // Scheduler chỉ cần 1 tín hiệu pe_done duy nhất, không cần act_en/pool_en/pool_done.
    output reg         pe_compute_en,
    output reg         pe_layer_has_pooling, // báo cho Compute Engine biết có bật Pool không
    input  wire        pe_ready,
    input  wire        pe_done,           // MAC + ReLU + Pool đã xong cho Patch này

    // ---- FC Engine (Nhóm 1, sau khi hết lớp Convolution) ----
    output reg         fc_start,
    input  wire        fc_done,

    // ---- Memory Architecture (Nhóm 2) ----
    output reg         buffer_swap,
    input  wire        bram_ready,
    output reg         dma_start,
    input  wire        dma_done
);

    // ---- Mã hoá trạng thái (v5 - 13 trạng thái) ----
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

    // Mã lỗi
    localparam ERR_NONE  = 3'b000;
    localparam ERR_DMA   = 3'b001;
    localparam ERR_PE    = 3'b010;
    localparam ERR_PATCH = 3'b100;
    localparam ERR_CFG   = 3'b101;
    localparam ERR_FC    = 3'b110;

    reg [3:0] state, next_state;

    reg [3:0]  total_layers;
    reg [3:0]  layer_count;
    reg [3:0]  kernel_r, stride_r, padding_r;
    reg        layer_has_pooling_r;
    reg [31:0] mem_addr_r;

    reg [15:0] wait_timer;
    wire is_wait_state = (state == ST_WAIT_DMA)   || (state == ST_WAIT_PATCH) ||
                          (state == ST_WAIT_PE)    || (state == ST_WAIT_FC);

    wire timeout_hit =
        (state == ST_WAIT_DMA   && wait_timer >= DMA_TIMEOUT)   ||
        (state == ST_WAIT_PATCH && wait_timer >= PATCH_TIMEOUT) ||
        (state == ST_WAIT_PE    && wait_timer >= PE_TIMEOUT)    ||
        (state == ST_WAIT_FC    && wait_timer >= FC_TIMEOUT);

    wire cfg_invalid = (kernel_r == 4'd0) || (stride_r == 4'd0);

    // ---- Thanh ghi trạng thái (đồng bộ) ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= ST_IDLE;
        else if (timeout_hit || (state == ST_CHECK_CONFIG && cfg_invalid))
            state <= ST_IDLE;
        else
            state <= next_state;
    end

    // ---- Bộ đếm timeout ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wait_timer <= 16'd0;
        else if (state != next_state)
            wait_timer <= 16'd0;
        else if (is_wait_state)
            wait_timer <= wait_timer + 16'd1;
    end

    // ---- Logic chuyển trạng thái kế tiếp (tổ hợp) ----
    always @(*) begin
        next_state = state;
        case (state)
            ST_IDLE:
                if (start) next_state = ST_READ_CONFIG;

            ST_READ_CONFIG:
                if (layer_cfg_valid) next_state = ST_CHECK_CONFIG;

            ST_CHECK_CONFIG:
                if (!cfg_invalid) next_state = ST_START_DMA;

            ST_START_DMA:
                next_state = ST_WAIT_DMA;

            ST_WAIT_DMA:
                if (dma_done && bram_ready) next_state = ST_START_WINDOW;

            ST_START_WINDOW:
                next_state = ST_WAIT_PATCH;

            ST_WAIT_PATCH:
                if (patch_valid) next_state = ST_START_PE;

            ST_START_PE:
                if (pe_ready) next_state = ST_WAIT_PE;

            ST_WAIT_PE:
                // pe_done = đã xong MAC + ReLU + Pool cho Patch này (Nhóm 1 xác nhận
                // 3 bước này chạy pipeline nội bộ, không cần Scheduler điều khiển riêng)
                if (pe_done) begin
                    if (!patch_last)
                        next_state = ST_START_WINDOW;   // còn Patch trong lớp -> lặp lại
                    else
                        next_state = ST_CHECK_LAYER;    // hết Patch của lớp này
                end

            ST_CHECK_LAYER:
                // Còn lớp Convolution tiếp theo -> quay lại READ_CONFIG.
                // Hết lớp Convolution -> chuyển sang xử lý Fully Connected.
                if (layer_count + 4'd1 < total_layers)
                    next_state = ST_READ_CONFIG;
                else
                    next_state = ST_START_FC;

            ST_START_FC:
                next_state = ST_WAIT_FC;

            ST_WAIT_FC:
                // TODO: hiện chỉ hỗ trợ 1 lần gọi FC engine duy nhất (giả định FC
                // Engine của Nhóm 1 tự xử lý nội bộ FC1->FC2->Softmax). Nếu Nhóm 1
                // cần Scheduler điều phối từng lớp FC riêng lẻ, cần bổ sung vòng lặp
                // tương tự CHECK_LAYER ở đây - CHƯA XÁC NHẬN, cần hỏi lại Nhóm 1.
                if (fc_done) next_state = ST_DONE;

            ST_DONE:
                next_state = ST_IDLE;

            default:
                next_state = ST_IDLE;
        endcase
    end

    // ---- Logic đầu ra & thanh ghi nội bộ (đồng bộ) ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy                 <= 1'b0;
            done                 <= 1'b0;
            prediction_ready     <= 1'b0;
            error                <= 1'b0;
            error_code           <= ERR_NONE;
            sched_state          <= ST_IDLE;

            sw_load_en           <= 1'b0;
            sw_kernel_cfg        <= 4'd0;
            sw_stride_cfg        <= 4'd0;
            sw_padding_cfg       <= 4'd0;

            pe_compute_en        <= 1'b0;
            pe_layer_has_pooling <= 1'b0;
            fc_start             <= 1'b0;

            buffer_swap          <= 1'b0;
            dma_start            <= 1'b0;

            total_layers         <= 4'd0;
            layer_count          <= 4'd0;
            kernel_r             <= 4'd0;
            stride_r             <= 4'd0;
            padding_r            <= 4'd0;
            layer_has_pooling_r  <= 1'b0;
            mem_addr_r           <= 32'd0;
        end else begin
            sched_state <= state;

            sw_load_en       <= 1'b0;
            pe_compute_en    <= 1'b0;
            fc_start         <= 1'b0;
            buffer_swap      <= 1'b0;
            dma_start        <= 1'b0;
            done             <= 1'b0;
            prediction_ready <= 1'b0;

            if (timeout_hit) begin
                error <= 1'b1;
                busy  <= 1'b0;
                case (state)
                    ST_WAIT_DMA:   error_code <= ERR_DMA;
                    ST_WAIT_PATCH: error_code <= ERR_PATCH;
                    ST_WAIT_PE:    error_code <= ERR_PE;
                    ST_WAIT_FC:    error_code <= ERR_FC;
                    default:       error_code <= ERR_NONE;
                endcase
            end else if (state == ST_CHECK_CONFIG && cfg_invalid) begin
                error      <= 1'b1;
                error_code <= ERR_CFG;
                busy       <= 1'b0;
            end

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy        <= 1'b1;
                        error       <= 1'b0;
                        error_code  <= ERR_NONE;
                        layer_count <= 4'd0;
                    end
                end

                ST_READ_CONFIG: begin
                    if (layer_cfg_valid) begin
                        kernel_r            <= kernel_size;
                        stride_r            <= stride;
                        padding_r           <= padding;
                        layer_has_pooling_r <= layer_has_pooling;
                        mem_addr_r          <= mem_base_addr;
                        if (layer_count == 4'd0)
                            total_layers <= num_conv_layers;
                    end
                end

                ST_START_DMA: begin
                    dma_start <= 1'b1;
                end

                ST_START_WINDOW: begin
                    sw_load_en     <= 1'b1;
                    sw_kernel_cfg  <= kernel_r;
                    sw_stride_cfg  <= stride_r;
                    sw_padding_cfg <= padding_r;
                end

                ST_START_PE: begin
                    if (pe_ready) begin
                        pe_compute_en        <= 1'b1;
                        pe_layer_has_pooling <= layer_has_pooling_r;
                    end
                end

                ST_CHECK_LAYER: begin
                    layer_count <= layer_count + 4'd1;
                    if (layer_count + 4'd1 < total_layers)
                        buffer_swap <= 1'b1;
                end

                ST_START_FC: begin
                    fc_start <= 1'b1;
                end

                ST_DONE: begin
                    busy             <= 1'b0;
                    done             <= 1'b1;
                    prediction_ready <= 1'b1;
                end

                default: ;
            endcase
        end
    end

endmodule