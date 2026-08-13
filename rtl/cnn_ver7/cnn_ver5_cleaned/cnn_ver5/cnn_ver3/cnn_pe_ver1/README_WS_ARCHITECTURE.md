# SEMIT 8-lane resident-weight/output-stationary convolution datapath

> Tài liệu tổng thể và kết quả mới nhất của `cnn_ver5` nằm trong
> [README_CNN_VER5.md](README_CNN_VER5.md). Tài liệu này mô tả chi tiết riêng
> datapath convolution 8 lane.

## Hardware mapping

- Conv1 uses the single eight-lane physical array in parallel. Each lane
  contains nine signed INT8 multipliers and a row-wise balanced adder tree.
  Because `C_in=1` and `C_out=8`, Conv1 accepts one valid 3x3 window per clock.
- Conv2 reuses those same physical lanes. One 3x3x8 window is held while the
  engine iterates over eight input channels and three groups of eight output
  channels. Eight INT32 lane accumulators preserve partial sums.
- Bias, multiplier, shift, rounding, ReLU, and INT8 clamp execute per lane
  only after the final input channel.
- Conv2 assembles all three groups before pulsing `valid_out`, preserving the
  existing 24-channel MaxPool/FC interface.
- Kernel storage preserves the existing OIHW DMA order:
  `out_channel -> input_channel -> kernel_row -> kernel_column`.

The active synthesis top instantiates one shared array, so the physical
convolution multiplier count is 72 total instead of 72 plus 1728 in the old
fully-unrolled implementation. The integrated `axis_cnn_mnist_emnist` top
uses `ws_conv_shared_engine` directly. Unreachable legacy convolution, FC,
PE, and Argmax modules have been removed from the RTL source set.

This is intentionally a hybrid dataflow: every kernel remains resident in a
banked local RF, while Conv2 keeps eight partial sums stationary for the
current output pixel and selects a new `[C_out group][C_in]` weight slice each
MAC cycle. It is therefore more precise to call the implementation
resident-weight/output-stationary than a strict weight-stationary spatial
array. A strict spatial weight-stationary schedule would require three map
passes plus an additional feature-map assembly RAM and would be much more
invasive to the current SEMIT stream interface.

## Backpressure

The internal `conv2_input_ready` path propagates the tiled engine state to the
Pool1 replay logic. Pool1 addresses advance only on
`p1_replay_active && conv2_input_ready`. Line/window buffers already advance
only on accepted valid beats, so a held window cannot be dropped or
overwritten.

Top-level AXI, DMA, scheduler, Pool, FC, and weight-address interfaces remain
unchanged.

## Numerical regression

Icarus Verilog, from PowerShell in this directory:

```powershell
.\run_ws_dataflow_iverilog.ps1
```

Vivado batch mode, from this directory:

```tcl
vivado -mode batch -source run_ws_dataflow.tcl
```

Simulation top: `tb_ws_dataflow`.

The testbench checks exact values and fails immediately on mismatch. Expected
counts are 676 Conv1, 169 Pool1, 121 Conv2, and 25 Pool2 output positions. It
also checks tap/channel ordering, all three Conv2 output groups, eight-channel
accumulation, bias, rounding, ReLU, saturation, and ready/valid backpressure.

`tb_axis_cnn.v` supports two modes. The default synthetic mode is a structural
scheduler/DMA/AXI regression. `+REAL_WEIGHTS` loads every checked-in `.mem`
parameter through the same DMA port and makes label mismatch fatal. Run all
focused, structural, and real-weight checks with `run_ver5_regression.ps1`.

## Implementation notes

- The 72 shallow weight banks are intended as local RF/distributed memory;
  they are not described as a 72-read-port BRAM.
- The project targets ZCU102 part `xczu9eg-ffvb1156-2-e`. A standalone 100 MHz
  core constraint is included. Add the lab's board/interface pin constraints
  before generating a system bitstream.
- The active datapath contains 72 signed INT8 convolution multiply operators
  and eight shared requantization multiply operators. Confirm their final
  LUT/DSP mapping and utilization from a Vivado synthesis report.
