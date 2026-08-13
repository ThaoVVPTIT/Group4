# CNN Ver5 - bản tối ưu cho AI Accelerator SEMIT

`cnn_ver5` giữ nguyên giao tiếp tích hợp của `cnn_ver3_1`, nhưng thay datapath
FC tuần tự bằng 8 MAC lane dùng chung, rút gọn đường dữ liệu convolution và
chuyển bộ đệm Pool1 sang RAM đọc đồng bộ có prefetch. Bản này đã qua regression
end-to-end với toàn bộ file trọng số `.mem` hiện có.

## Kết quả đã đo

Các số dưới đây được đo bằng cùng testbench end-to-end, từ pixel đầu tiên được
nhận tới kết quả AXI của một frame. Clock mô phỏng là 100 MHz; phép đo loại thời
gian nạp trọng số một lần và pha start trước pixel đầu tiên.

| Chỉ số | `cnn_ver3_1` | `cnn_ver5` | Thay đổi |
|---|---:|---:|---:|
| Latency | 92.932 cycle | 15.558 cycle | giảm 83,26% |
| Thời gian tại 100 MHz | 929,32 us | 155,58 us | nhanh 5,97 lần |
| Thông lượng core tuần tự lý thuyết | 1.076 inference/s | 6.428 inference/s | tăng 5,97 lần |

Thông lượng trên chưa bao gồm thời gian ESP-CAM, UART, DDR và phần mềm. FC mới
hoàn tất sau 11.165 cycle, nhanh khoảng 7,9 lần so với chuỗi FC cũ. FC hiện vẫn
chiếm khoảng 71,8% latency end-to-end; vì vậy tăng convolution lên 16 lane ở
thời điểm này không xử lý đúng bottleneck chính.

## Các thay đổi theo mục 8.3

### 1. Tối ưu FC trước

- Một engine 8 MAC lane được tái sử dụng cho FC1, FC2 và FC3.
- Mỗi activation được broadcast tới 8 neuron đầu ra; kernel được đóng gói
  64 bit để cấp đủ 8 trọng số mỗi chu kỳ.
- Không đổi địa chỉ DMA bên ngoài: kernel vẫn được nạp theo
  `output * input_count + input`.
- FC1/FC2 dùng chung một requantizer có pipeline; giữ nguyên rounding,
  arithmetic shift, ReLU và clamp INT8.
- FC3 giữ logit INT32 và argmax dùng so sánh strict `>` theo thứ tự lớp tăng,
  nên trường hợp hòa vẫn chọn chỉ số nhỏ như thiết kế cũ.
- Loại bỏ các FSM copy trung gian giữa ba module FC tuần tự.

### 2. Pipeline cây cộng và requant

- Engine convolution vốn đã có thanh ghi sau dot-product/accumulator và sau
  requant; các tầng này được giữ để không phá valid/ready hoặc tăng II.
- Cây cộng 3x3 được cân bằng theo hàng và thu hẹp chính xác từ 32 xuống 19 bit
  cho INT8. Miền số của tổng 9 tích vẫn được bảo toàn.
- Requant FC1/FC2 được tách thành hai tầng: đăng ký tích 64 bit, sau đó làm
  rounding/shift/ReLU/clamp.

### 3. Buffering

- Tám RAM Pool1 `169 x 8` đọc bất đồng bộ được thay bằng một RAM
  `169 x 64`, có chỉ dẫn suy diễn block RAM và cổng đọc đồng bộ.
- Một holding/prefetch slot giữ dữ liệu ổn định khi Conv2 backpressure và vẫn
  cấp tối đa một vector mỗi chu kỳ khi engine sẵn sàng.
- Chưa thêm ping-pong frame N/N+1 vì giao thức hiện tại chỉ cho một transaction:
  scheduler không queue `start`, input AXI không có `TLAST`/frame tag, DMA không
  có prefetch descriptor và Conv1/Conv2 dùng chung PE array. Thêm bank thứ hai
  trong điều kiện này chỉ tăng RAM mà không tạo overlap hợp lệ.
- Muốn bật double buffering thật sự cần bổ sung queue descriptor/start, ranh
  giới frame trên DMA, handshake prefetch và quyền sở hữu từng bank.

### 4. Weight-load decoder

- Decoder kernel Conv1 ánh xạ trực tiếp `bank = offset`.
- Decoder Conv2 loại toàn bộ `/9`, `/72`, `%9`, `%72`. Phép chia 9 được thay
  bằng mạng shift-add hằng số 1821, chính xác cho toàn miền offset 0..1727.
- Địa chỉ write được đăng ký một tầng, vẫn nhận liên tục một weight mỗi clock.
  Kernel convolution cuối cùng cần một cạnh clock để đi qua tầng này trước khi
  bắt đầu inference; scheduler/DMA hiện tại đã có khoảng đệm lớn hơn yêu cầu đó.

### 5. Clock enable và zero gating

- Các thanh ghi accumulator, output và cổng đọc kernel chỉ cập nhật khi layer
  tương ứng hoạt động.
- Operand isolation đưa activation/weight về zero khi lane idle.
- MAC có activation hoặc weight bằng zero được zero-gate mà không đổi kết quả
  signed INT8; requant cũng bỏ switching khi accumulator/multiplier bằng zero.

### 6. Quyết định giữ 8 lane

Không tăng lên 16 lane. Sau tối ưu, FC chiếm khoảng 71,8% latency và convolution
không còn là bottleneck lớn nhất. Giữ 8 lane phù hợp mục tiêu cân bằng hiệu năng,
DSP/LUT và công suất; chỉ nên scale sau khi routed report trên thiết bị thật cho
thấy còn dư tài nguyên và profiling hệ thống chứng minh CNN compute là giới hạn.

## Tương thích tích hợp

Các cổng top-level, address map trọng số, thứ tự OIHW, scheduler, DMA request,
AXI input/output và mã lớp EMNIST không đổi. Top synthesis vẫn là
`cnn_accelerator_top`; top simulation mặc định trong project là `tb_axis_cnn`.

Project đã được nhắm tới part ZCU102 `xczu9eg-ffvb1156-2-e`. Metadata board
ZCU104 cũ đã được loại bỏ để tránh phụ thuộc một phiên bản board-file cụ thể.

## Regression

Chạy tại thư mục chứa file này:

```powershell
.\run_ver5_regression.ps1
```

Suite thực hiện ba bước:

1. kiểm tra số học và backpressure riêng cho convolution;
2. kiểm tra end-to-end scheduler, DMA, AXI hold/TLAST và hai frame không reset
   bằng hệ số synthetic;
3. nạp toàn bộ kernel/bias/multiplier/shift thật qua đúng cổng DMA, sau đó yêu
   cầu kết quả của cả hai frame phải khớp `test_label.mem`.

Kết quả hiện tại:

- Conv1/Pool1: `676/169` vị trí mỗi frame;
- Conv2/Pool2: `121/25` vị trí mỗi frame;
- Conv2 nhận đúng 169 vector và giữ valid đúng khi backpressure;
- real-weight end-to-end: `2/2`, class 44 (`q`);
- latency: `15.558` cycle cho cả hai frame;
- compile toàn top bằng Icarus Verilog-2001: PASS.

Test real-weight mới chỉ chứng minh bit-exact trên vector ảnh được lưu trong
project, không thay thế đánh giá accuracy trên toàn bộ tập EMNIST.

## Synthesis và timing trên Vivado

Vivado 2025.1 đã synthesize thành công toàn bộ top trên part WebPACK
`xc7a100tcsg324-1`: 0 error, 0 critical warning. Mục đích của lần chạy này là
kiểm tra synthesizability, single-driver và RAM/DSP inference bằng đúng Vivado;
nó không phải kết quả implementation của ZCU102.

So sánh synth tương đối trên cùng tool, part và setting:

| Tài nguyên | `cnn_ver3_1` | `cnn_ver5` | Thay đổi |
|---|---:|---:|---:|
| LUT | 26.071 | 28.106 | +7,81% |
| FF | 23.790 | 22.447 | -5,65% |
| RAMB36 | 29 | 30 | +1 block |
| DSP | 46 | 36 | -21,74% |

FC kernel của hai bản đều dùng 29 RAMB36. Block RAM tăng thêm duy nhất là RAM
Pool1 `169 x 64`, đổi lại loại 288 LUTRAM ở tầng buffer đó. FC1 được chia thành
3 depth-bank x 8 byte-lane để vừa đúng hình học RAMB36 và vẫn đọc 8 weight mỗi
clock. Đây là trade-off hợp lý: latency giảm 83,26%, FF/DSP giảm, còn LUT tăng
7,81% để tạo datapath FC song song.

Có thể tái tạo hai report so sánh bằng:

```powershell
vivado -mode batch -source run_ver3_1_synth_baseline.tcl
vivado -mode batch -source run_ver5_synth_sanity.tcl
```

Hai report được lưu trong `ver5_reports`. Không dùng WNS của part sanity để kết
luận timing XCZU9EG.

### Flow target XCZU9EG

Constraint độc lập đặt `aclk = 100 MHz` và uncertainty 0,2 ns. Chạy:

```powershell
vivado -mode batch -source run_ver5_implementation.tcl
```

Script tạo `ver5_reports`, chạy synth/place/route out-of-context trên XCZU9EG và
xuất report utilization, timing, clock, DRC, power cùng checkpoint. Script dừng
với lỗi nếu thiếu setup/hold path, setup hoặc hold slack âm, hay có DRC severity
`Error`.

Vivado nằm tại `E:\Xilinx\2025.1\Vivado\bin\vivado.bat` trên máy hiện tại nhưng
không có trong `PATH`. Flow target đã được khởi động và đọc RTL/XDC thành công,
sau đó dừng tại `synth_design` vì thiếu license `Synthesis/xczu9eg`. Do đó công
suất và WNS routed XCZU9EG chưa thể xác nhận tại đây; cần chạy lại trên máy có
license của lab. XDC hiện tại chỉ là timing constraint cho core độc lập; khi
tích hợp phải bổ sung constraint clock/interface/I/O thực của hệ thống.

## Các file chính đã thay đổi

- `cnn_pe_ver1.srcs/sources_1/new/fc_stream.v`: engine FC 8 lane.
- `cnn_pe_ver1.srcs/sources_1/new/ws_conv_shared_engine.v`: decoder,
  pipeline điều khiển và gating convolution.
- `cnn_pe_ver1.srcs/sources_1/new/ws_pe_lane_3x3.v`: MAC 3x3 và cây cộng 19 bit.
- `cnn_pe_ver1.srcs/sources_1/new/requantize_relu_lane.v`: requant/gating.
- `cnn_pe_ver1.srcs/sources_1/new/axis_cnn_mnist_emnist.v`: RAM Pool1 đồng bộ
  và prefetch chịu backpressure.
- `cnn_pe_ver1.srcs/sim_1/new/tb_axis_cnn.v`: chế độ `+REAL_WEIGHTS`.
- `run_ver5_regression.ps1`: regression tự động.
- `run_ver5_synth_sanity.tcl`, `run_ver3_1_synth_baseline.tcl`: synth sanity và
  so sánh tài nguyên trên cùng part WebPACK.
- `run_ver5_implementation.tcl`,
  `cnn_pe_ver1.srcs/constrs_1/new/cnn_ver5_timing.xdc`: implementation và bằng
  chứng timing/resource.
