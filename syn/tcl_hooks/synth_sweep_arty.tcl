# synth_sweep_arty.tcl : Arty A7 (lab6, project_lab6_arty_t100_1) を「合成設定だけ」変えて
#                        50MHz (clk_out2_clk_wiz_0 = 20ns) のタイミングを収束させる
#
#   - RTL は変更しない。配置配線 (impl) の戦略も impl_1 と同じものをそのまま使う。
#   - 合成設定の違う synth_1..N を並列に回し、それぞれの子 impl を配置配線して
#     hold 違反なし・WNS 最良の組を Active にして bitstream を作る。
#   - 合成の自動インクリメンタル (前回の dcp を参照) は無効にする (結果が前回の合成に
#     引きずられて揺れるのを防ぐ)。
#   - オプションで「合成のときだけ」CPU クロックに setup uncertainty を足す (過制約)。
#     合成専用の制約セット constrs_synth_oc を作り、USED_IN_IMPLEMENTATION=false で入れるので
#     impl の判定は本来の 20ns のまま。
#
# 使い方 (どちらでも可)
#   (1) Vivado GUI でプロジェクトを開き、Tcl Console で
#         source D:/riscv/jasa/my-riscv-rv32i-dc/syn/tcl_hooks/synth_sweep_arty.tcl
#   (2) コマンドプロンプトからバッチ実行 (プロジェクトは自動で開く)
#         vivado -mode batch -source D:/riscv/jasa/my-riscv-rv32i-dc/syn/tcl_hooks/synth_sweep_arty.tcl

# ---------------- 設定 ----------------
set hook_dir  [file dirname [file normalize [info script]]]
set repo_dir  [file normalize [file join $hook_dir .. ..]]
set proj_xpr  [file join $repo_dir syn project_lab6_arty_t100_1 project_lab6_arty_t100_1.xpr]

set cpu_clk      clk_out2_clk_wiz_0  ;# 対象クロック (report_clocks で確認)
set synth_oc_ns  1.500 ;# 合成時だけ足す setup uncertainty [ns] (目安 1.0〜3.0)
set jobs         8     ;# 並列ジョブ数 (1 run あたりメモリ 3〜4GB 程度を見込む)
set setup_only   0     ;# 1 にすると run の設定だけして実行しない
set do_bitstream 1     ;# 0 にすると配置配線まで
set force_bit    0     ;# 1 にすると WNS<0 でも一番良い組で bitstream を作る

# 合成バリエーション : {合成run  子impl run  合成戦略  過制約(0/1)  追加の合成引数(ARGS.xxx 値 ...)}
#   synth_1 は今まで通りの既定設定 (比較用のベースライン)
set variants {
  {synth_1 impl_1 {Vivado Synthesis Defaults} 0 {}}
  {synth_2 impl_2 Flow_PerfOptimized_high     1 {}}
  {synth_3 impl_3 Flow_PerfOptimized_high     1 {RETIMING true}}
  {synth_4 impl_4 Flow_AlternateRoutability   1 {}}
}
# --------------------------------------

proc msg {s} { puts "### synth_sweep: $s" }

# ---- 1. プロジェクトを開く (未オープンの場合のみ) ----
if {[catch {current_project} cur] || $cur eq ""} {
  msg "open_project $proj_xpr"
  open_project $proj_xpr
}

set synth_flow [get_property FLOW [get_runs synth_1]]
set impl_flow  [get_property FLOW [get_runs impl_1]]
set impl_strat [get_property STRATEGY [get_runs impl_1]]
msg "synth flow = $synth_flow / impl flow = $impl_flow / impl strategy = $impl_strat (全 impl 共通)"

# ---- 2. 合成専用の過制約 XDC と制約セット constrs_synth_oc ----
set oc_xdc [file join $hook_dir synth_only_overconstrain.xdc]
set fh [open $oc_xdc w]
puts $fh "# synth_sweep_arty.tcl が自動生成 (手で編集しない)。合成専用: USED_IN_IMPLEMENTATION=false"
puts $fh "set_clock_uncertainty -setup [format %.3f $synth_oc_ns] \[get_clocks $cpu_clk\]"
close $fh

set oc_set constrs_synth_oc
if {[llength [get_filesets -quiet $oc_set]] == 0} {
  create_fileset -constrset $oc_set
}
# 中身を毎回作り直す (constrs_1 の変更やフォルダ移動に追従させる)
set old [get_files -quiet -of_objects [get_filesets $oc_set]]
if {[llength $old]} { remove_files -fileset $oc_set $old }
set base_xdcs {}
foreach f [get_files -quiet -of_objects [get_filesets constrs_1]] { lappend base_xdcs [get_property NAME $f] }
if {[llength $base_xdcs]} { add_files -fileset $oc_set -norecurse $base_xdcs }
add_files -fileset $oc_set -norecurse $oc_xdc
set oc_file [get_files -of_objects [get_filesets $oc_set] $oc_xdc]
set_property USED_IN_SYNTHESIS      true  $oc_file
set_property USED_IN_IMPLEMENTATION false $oc_file

# ---- 3. 合成 run / 子 impl run の設定 ----
set synth_runs {}
set impl_runs  {}
foreach v $variants {
  lassign $v s i strat oc args

  if {[llength [get_runs -quiet $s]] == 0} {
    create_run $s -flow $synth_flow -constrset constrs_1
  }
  set_property strategy $strat [get_runs $s]      ;# 戦略を先に (ARGS がリセットされるため)
  foreach {k val} $args {
    set_property STEPS.SYNTH_DESIGN.ARGS.$k $val [get_runs $s]
  }
  set_property CONSTRSET [expr {$oc && $synth_oc_ns > 0 ? $oc_set : "constrs_1"}] [get_runs $s]
  # 自動インクリメンタル合成を無効化
  catch {set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs $s]}
  catch {set_property INCREMENTAL_CHECKPOINT {} [get_runs $s]}

  if {[llength [get_runs -quiet $i]] == 0} {
    create_run $i -parent_run $s -flow $impl_flow -constrset constrs_1
  }
  if {[get_property PARENT [get_runs $i]] ne $s} {
    error "$i の親が $s ではありません ([get_property PARENT [get_runs $i]])。variants の run 名を変えてください"
  }
  set_property CONSTRSET constrs_1 [get_runs $i]
  if {$i ne "impl_1"} { set_property strategy $impl_strat [get_runs $i] }

  lappend synth_runs $s
  lappend impl_runs  $i
  msg [format "%-8s -> %-7s  %-28s  OC=%s  %s" $s $i $strat \
        [expr {$oc && $synth_oc_ns > 0 ? "${synth_oc_ns}ns" : "off"}] $args]
}

if {$setup_only} {
  msg "設定のみ完了。実行: launch_runs $impl_runs -jobs $jobs"
  return
}

# ---- 4. 合成 + 配置配線 (並列) ----
foreach s $synth_runs { reset_run $s }
foreach i $impl_runs  { reset_run $i }
msg "launch_runs $impl_runs -jobs $jobs"
launch_runs {*}$impl_runs -jobs $jobs
foreach i $impl_runs { wait_on_run $i }

# ---- 5. 結果の比較 ----
set best ""
set best_wns -1e9
msg "---------------- 結果 ----------------"
foreach v $variants {
  lassign $v s i strat oc args
  if {[get_property PROGRESS [get_runs $s]] ne "100%"} {
    msg [format "%-8s synth FAILED (%s)" $s [get_property STATUS [get_runs $s]]]
    continue
  }
  if {[get_property PROGRESS [get_runs $i]] ne "100%"} {
    msg [format "%-8s %-7s impl FAILED (%s)" $s $i [get_property STATUS [get_runs $i]]]
    continue
  }
  set wns [get_property STATS.WNS [get_runs $i]]
  set tns [get_property STATS.TNS [get_runs $i]]
  set whs [get_property STATS.WHS [get_runs $i]]
  msg [format "%-8s %-7s WNS=%7.3f  TNS=%9.3f  WHS=%7.3f  Fmax(CPU)~%5.1fMHz  \[%s OC=%s %s\]" \
        $s $i $wns $tns $whs [expr {1000.0 / (20.0 - $wns)}] $strat $oc $args]
  if {$whs < 0} { continue }
  if {$wns > $best_wns} { set best $v; set best_wns $wns }
}
msg "--------------------------------------"
msg "(Fmax は WNS が CPU クロック (20ns) のパスで決まっている前提の目安)"

if {$best eq ""} { error "採用できる組がありません (全 run 失敗 or hold 違反)" }
lassign $best bs bi
msg "best = $bs / $bi (WNS=$best_wns)"

# 一番良い組を Active に (次回 GUI から Run Synthesis/Implementation してもこの設定になる)
current_run -synthesis      [get_runs $bs]
current_run -implementation [get_runs $bi]

if {$best_wns < 0 && !$force_bit} {
  msg "タイミング未収束のため bitstream は作りません (force_bit=1 で強制 / synth_oc_ns を変えて再実行)"
  return
}

# ---- 6. bitstream ----
if {$do_bitstream} {
  msg "write_bitstream on $bi"
  launch_runs $bi -to_step write_bitstream -jobs $jobs
  wait_on_run $bi
  set bits [glob -nocomplain -directory [get_property DIRECTORY [get_runs $bi]] *.bit]
  if {[llength $bits] == 0} { error "bitstream が見つかりません: [get_property STATUS [get_runs $bi]]" }
  msg "bitstream: [lindex $bits 0]"
}
msg "done"
