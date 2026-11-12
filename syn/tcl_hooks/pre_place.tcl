# place_design TCL.PRE : CPUクロックだけ配置時に過制約 (配置見積りの楽観分を補正)
# 値は 0.8〜1.5 程度で調整。route前に pre_route.tcl で解除する。
set_clock_uncertainty -setup 1.000 [get_clocks clk_out2_clk_wiz_0]
