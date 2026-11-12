# Vivado の Tcl Console で: source <このファイルのパス>
# impl_1 を強化し、別戦略の impl_2..impl_4 も作る (並列で回して一番良いものを採用)
set d [file dirname [file normalize [info script]]]

proc cfg_run {r strat d} {
  set_property strategy $strat [get_runs $r]
  set_property STEPS.PLACE_DESIGN.TCL.PRE  [file join $d pre_place.tcl] [get_runs $r]
  set_property STEPS.ROUTE_DESIGN.TCL.PRE  [file join $d pre_route.tcl] [get_runs $r]
  set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs $r]
  set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs $r]
  set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs $r]
  set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.TCL.POST [file join $d post_route_physopt_loop.tcl] [get_runs $r]
}

cfg_run impl_1 Performance_ExplorePostRoutePhysOpt $d
foreach {r s} {impl_2 Performance_ExtraTimingOpt impl_3 Performance_NetDelay_high impl_4 Performance_Explore} {
  if {[llength [get_runs -quiet $r]] == 0} {
    create_run $r -parent_run synth_1 -flow {Vivado Implementation 2023}
  }
  cfg_run $r $s $d
}
puts "設定完了: launch_runs impl_1 impl_2 impl_3 impl_4 -jobs 24"
