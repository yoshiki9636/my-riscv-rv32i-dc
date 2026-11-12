# post_route_phys_opt_design TCL.POST : 改善が止まるまで追加で phys_opt を回す
for {set i 0} {$i < 4} {incr i} {
  set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
  if {$wns >= 0} { break }
  phys_opt_design -directive AggressiveExplore
  set wns2 [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
  puts "post-route physopt loop $i : WNS $wns -> $wns2"
  if {$wns2 <= $wns} { break }
}
