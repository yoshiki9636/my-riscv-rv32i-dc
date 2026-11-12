# build_all.tcl : RTL取り込み → フック設定 → 合成 → impl_1..4 並列配置配線
#                 → 一番良い run を Active にして bitstream 生成 までを 1 本で行う
#
# 使い方 (どちらでも可)
#   (1) Vivado GUI でプロジェクトを開き、Tcl Console で
#         source D:/riscv/jasa/my-riscv-rv32i-dc/syn/tcl_hooks/build_all.tcl
#   (2) コマンドプロンプトからバッチ実行 (プロジェクトは自動で開く)
#         vivado -mode batch -source D:/riscv/jasa/my-riscv-rv32i-dc/syn/tcl_hooks/build_all.tcl
#
# 下の「設定」を書き換えて使う。

# ---------------- 設定 ----------------
set hook_dir  [file dirname [file normalize [info script]]]
set repo_dir  [file normalize [file join $hook_dir .. ..]]

set proj_xpr  [file join $repo_dir syn project_5_jump_1 project_5_jump_1.xpr]
set rtl_src   [file join $repo_dir lab5_for_jump]
# プロジェクト内の取り込みコピーで、src から上書きするファイル
set rtl_files {if_stage.v ex_stage.v cpu_top.v ilu_stage.v}

set copy_rtl     1     ;# 0 にすると RTL コピーをしない (今のプロジェクト内容のまま回す)
set impl_runs    {impl_1 impl_2 impl_3 impl_4}
set jobs         24    ;# 並列ジョブ数 (CPU コア数に合わせる)
set do_bitstream 1     ;# 0 にすると配置配線まで
set force_bit    0     ;# 1 にすると WNS<0 でも一番良い run で bitstream を作る
# --------------------------------------

proc msg {s} { puts "### build_all: $s" }

# ---- 1. プロジェクトを開く (未オープンの場合のみ) ----
if {[catch {current_project} cur] || $cur eq ""} {
  msg "open_project $proj_xpr"
  open_project $proj_xpr
}
set proj_dir [get_property DIRECTORY [current_project]]
set imp_dir  [file join $proj_dir "[get_property NAME [current_project]].srcs" sources_1 imports lab5_for_jump]

# ---- 2. RTL を取り込みコピーへ上書き ----
if {$copy_rtl} {
  foreach f $rtl_files {
    set s [file join $rtl_src $f]
    set d [file join $imp_dir $f]
    if {![file exists $s]} { error "source not found: $s" }
    if {![file exists $d]} { error "imported copy not found: $d (プロジェクトの取り込み先を確認)" }
    file copy -force $s $d
    msg "copied $f"
  }
}

# ---- 3. 戦略とフックを (毎回) 設定 : フォルダ移動後でもパスが正しくなる ----
source [file join $hook_dir setup_runs.tcl]

# ---- 4. 合成 + 配置配線 (並列) ----
reset_run synth_1
foreach r $impl_runs { reset_run $r }
msg "launch_runs $impl_runs -jobs $jobs"
launch_runs {*}$impl_runs -jobs $jobs
foreach r $impl_runs { wait_on_run $r }

if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
  error "synth_1 が失敗しました: [get_property STATUS [get_runs synth_1]]"
}

# ---- 5. 結果の比較 ----
set best ""
set best_wns -1e9
msg "---------------- 結果 ----------------"
foreach r $impl_runs {
  set st  [get_property STATUS [get_runs $r]]
  set ok  [expr {[get_property PROGRESS [get_runs $r]] eq "100%"}]
  if {!$ok} {
    msg [format "%-7s FAILED  (%s)" $r $st]
    continue
  }
  set wns [get_property STATS.WNS [get_runs $r]]
  set whs [get_property STATS.WHS [get_runs $r]]
  set tns [get_property STATS.TNS [get_runs $r]]
  msg [format "%-7s WNS=%7.3f  TNS=%9.3f  WHS=%7.3f  [%s]" $r $wns $tns $whs [get_property STRATEGY [get_runs $r]]]
  if {$whs < 0} { continue }          ;# hold 違反の run は採用しない
  if {$wns > $best_wns} { set best $r; set best_wns $wns }
}
msg "--------------------------------------"

if {$best eq ""} { error "採用できる run がありません (全 run 失敗 or hold 違反)" }
msg "best = $best (WNS=$best_wns)"

if {$best_wns < 0 && !$force_bit} {
  msg "タイミング未収束のため bitstream は作りません (force_bit=1 で強制)"
  return
}

# ---- 6. 一番良い run を Active にして bitstream ----
current_run -implementation [get_runs $best]
if {$do_bitstream} {
  msg "write_bitstream on $best"
  launch_runs $best -to_step write_bitstream -jobs $jobs
  wait_on_run $best
  set bits [glob -nocomplain -directory [get_property DIRECTORY [get_runs $best]] *.bit]
  if {[llength $bits] == 0} { error "bitstream が見つかりません: [get_property STATUS [get_runs $best]]" }
  msg "bitstream: [lindex $bits 0]"
}
msg "done"
