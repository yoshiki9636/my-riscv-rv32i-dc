# route_design TCL.PRE : 過制約を元に戻す (本来の uncertainty で配線・最終判定)
set_clock_uncertainty -setup 0.000 [get_clocks clk_out2_clk_wiz_0]
