# tcl_hooks : タイミング収束用 Vivado フック

置き場所は `syn/tcl_hooks/` です。プロジェクトのフォルダの外に置いているので、プロジェクトを作り直しても残ります。

RTL を変更せずに、配置・配線のパラメータだけでタイミングを収束させるためのスクリプト群です。
対象のクロックは CPU クロック `clk_out2_clk_wiz_0` です。
フックはすべて **Implementation**（配置配線）で動きます。Synthesis 側の設定は変えません。

## ファイル一覧

| ファイル | 実行されるタイミング | 内容 |
|---|---|---|
| `build_all.tcl` | 手動で実行 | 取り込みからビットストリーム生成までを一括で行います（下記） |
| `setup_runs.tcl` | 手動で 1 回だけ実行 | impl_1〜impl_4 に戦略とフックを設定します |
| `pre_place.tcl` | place_design の直前 (TCL.PRE) | CPU クロックに `set_clock_uncertainty -setup 1.000` を設定して過制約にします |
| `pre_route.tcl` | route_design の直前 (TCL.PRE) | uncertainty を 0 に戻します（本来の制約で配線し、最終判定します） |
| `post_route_physopt_loop.tcl` | post_route_phys_opt_design の直後 (TCL.POST) | WNS が負の間、`phys_opt_design -directive AggressiveExplore` を最大 4 回まで追加で実行します（改善しなくなった時点で打ち切ります） |

### 過制約を入れる理由

配置後の WNS が正だと、Vivado は phys_opt を省略します。
ところが配線後には遅延が増えて、負の WNS になることがあります（48MHz で WNS が悪化したのはこれが原因です。配置後 +0.178ns、配線後 -0.813ns でした）。
そこで配置のときだけ制約を厳しくして余裕を持たせ、配線の前に元に戻します。

## 一括実行（build_all.tcl）

次の手順を `build_all.tcl` 1 本で実行します。

1. `lab5_for_jump/` の RTL を、プロジェクト内の取り込みコピー（`project_5_jump_1.srcs/sources_1/imports/lab5_for_jump/`）に上書きします。
2. `setup_runs.tcl` で戦略とフックを設定します。毎回設定し直すので、フォルダを移動した後でもパスが正しくなります。
3. 合成し、impl_1〜4 を並列に配置配線します。
4. 各 run の WNS / TNS / WHS を表示し、hold 違反のない run の中から WNS が一番よいものを選びます。
5. その run を Active にして bitstream を作り、.bit のパスを表示します（WNS < 0 のときは作りません）。

```tcl
# GUI でプロジェクトを開いた状態で Tcl Console から（実行中は GUI が待ち状態になります）
source D:/riscv/jasa/my-riscv-rv32i-dc/syn/tcl_hooks/build_all.tcl
```
```bat
rem コマンドプロンプトからバッチで実行（プロジェクトは自動で開きます）
vivado -mode batch -source D:/riscv/jasa/my-riscv-rv32i-dc/syn/tcl_hooks/build_all.tcl
```

スクリプト先頭の「設定」で次を変えられます。

| 変数 | 既定 | 意味 |
|---|---|---|
| `rtl_files` | if_stage / ex_stage / cpu_top / ilu_stage | 上書きするファイル |
| `copy_rtl` | 1 | 0 にすると RTL をコピーせず、今のプロジェクトの内容のまま実行します |
| `jobs` | 24 | 並列ジョブ数 |
| `do_bitstream` | 1 | 0 にすると配置配線までで止めます |
| `force_bit` | 0 | 1 にすると、WNS < 0 でも一番よい run で bitstream を作ります |

## 個別に実行する場合

1. Vivado で `project_5_jump_1.xpr` を開きます。
2. Tcl Console で次を実行します（パスは自分の環境のものに置き換えてください。Windows 版 Vivado でもパス区切りは `/` です）。
   ```tcl
   source D:/riscv/jasa/my-riscv-rv32i-dc/syn/tcl_hooks/setup_runs.tcl
   ```
   次の設定が行われます。
   - impl_1 : 戦略を `Performance_ExplorePostRoutePhysOpt` にし、上の 3 つのフックを登録します。phys_opt と post-route phys_opt も有効にします。
   - impl_2 / impl_3 / impl_4 : 存在しなければ作成し、それぞれ `Performance_ExtraTimingOpt` / `Performance_NetDelay_high` / `Performance_Explore` に設定します。フックの設定は impl_1 と同じです。
3. 合成と、4 本の配置配線を並列に実行します。
   ```tcl
   reset_run synth_1
   launch_runs impl_1 impl_2 impl_3 impl_4 -jobs 24
   ```
   （`-jobs` は CPU のコア数に合わせて変えてください。GUI の Design Runs から各 run を選んで Launch しても同じです。）
4. 終わったら Design Runs 表の WNS を比べます。WNS ≥ 0 の run の中から一番よいものを選び、右クリック → **Make Active** を実行してから Generate Bitstream を行います。

設定はプロジェクト（.xpr）に保存されるので、`setup_runs.tcl` の実行は最初の 1 回だけで済みます。
ただし **このフォルダを移動・改名するとフックのパスが切れる** ので、その場合はもう一度 `source` してください。

## 調整ポイント

- 過制約の量：`pre_place.tcl` の `1.000`（ns）を変えます。目安は 0.8〜1.5 です。
  - 配置後の WNS が大きく負になって、配置自体が荒れる場合は小さくします。
  - 配置後の WNS が正なのに配線後に負になる場合は大きくします。
  - `pre_route.tcl` は必ず 0 に戻す設定のままにしてください（戻さないと、本来の制約より厳しい条件で判定されます）。
- クロック名：クロック構成を変えて名前が `clk_out2_clk_wiz_0` でなくなった場合は、両ファイルの `get_clocks` を書き換えます。
  名前は `report_clocks` で確認できます。
- `create_run` の `-flow {Vivado Implementation 2023}`：Vivado のバージョンが異なる場合は、使っているバージョンの年に合わせてください（impl_2〜4 を作るときだけ使います）。
- ログの確認：各 run の `runme.log` を `post-route physopt loop` で検索すると、ループ中の WNS の推移が分かります。

## フックを外す場合

Tcl Console で次を実行します（run ごとに行います）。

```tcl
foreach r {impl_1 impl_2 impl_3 impl_4} {
  set_property STEPS.PLACE_DESIGN.TCL.PRE  "" [get_runs $r]
  set_property STEPS.ROUTE_DESIGN.TCL.PRE  "" [get_runs $r]
  set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.TCL.POST "" [get_runs $r]
}
```

GUI では、Implementation Settings の各ステップにある `tcl.pre` / `tcl.post` の欄を空にしても外せます。
