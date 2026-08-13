# 100 MHz standalone timing target for cnn_accelerator_top on ZCU102.
# In the final block design, keep this requirement or replace it with the
# equivalent generated AXI clock constraint; do not apply both clocks.
create_clock -name aclk -period 10.000 -waveform {0.000 5.000} [get_ports aclk]
set_clock_uncertainty 0.200 [get_clocks aclk]

