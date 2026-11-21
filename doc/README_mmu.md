# Sv32 MMU（ステップ1：DTLB + PTW、M-mode + MPRV）

ブランチ `mmu-linux`。RTL は原本の `cpu/`、`fpga/` に入っている（作業は lab7_mmu で行った）。

設計検討は同じディレクトリの `riscv_rv32ima_mmu_design_summary.txt` を参照。ここでは実装した内容をまとめる。

対象ボード：**Arty A7 + DDR3（MEM_MIG）**（`fpga/fpga_config.vh`）。D$ は 16KB 4ウェイ（4KB × 4）。

## D$ の構成（fpga/fpga_top.v の define）

| define | 意味 |
|---|---|
| `FT_DWIDTH` | 1ウェイのサイズ（10 = 4KB、12 = 16KB） |
| `FT_DWAYS` | ウェイ数（1 / 2 / 4 / 8）。1 = 元の direct-map と同じ動作 |

D$ の容量 = `FT_DWAYS` × 2^(`FT_DWIDTH`+2) バイト。

| 設定例 | 構成 | MMU |
|---|---|---|
| `FT_DWIDTH 10` / `FT_DWAYS 4` | 16KB 4ウェイ（Arty の現在の設定） | 有効 |
| `FT_DWIDTH 10` / `FT_DWAYS 8` | 32KB 8ウェイ | 有効 |
| `FT_DWIDTH 10` / `FT_DWAYS 1` | 4KB direct-map（Tang / CMOD の設定） | 有効 |
| `FT_DWIDTH 12` / `FT_DWAYS 1` | 16KB direct-map（元の Arty 設定） | **無効**（satp.MODE は 0 に読める、変換しない） |

`FT_DWIDTH` が 10 を超えると、VIPT でエイリアスが起きるので MMU を無効にしている（cpu_top の `MMU_EN`）。

## 進め方（全体計画）

| ステップ | 内容 | 状態 |
|---|---|---|
| 1 | DTLB + PTW（D$経由）+ satp / MPRV / SUM / MXR、M-mode + MPRV で動作確認 | **実装・シミュレーション済み**（実機は未確認） |
| 2 | S/U-mode、trap の委譲（medeleg / mideleg）、S-mode CSR、sret | 未着手 |
| 3 | ITLB + IF ステージ対応（命令フェッチの変換） | 未着手 |
| 4 | SBI（OpenSBI か自作）+ MMU 版 Linux | 未着手 |

## 変換の条件

CPU は M-mode だけで動いているので、ステップ1で変換されるのは**データアクセスだけ**。

- `satp.MODE = 1` かつ `mstatus.MPRV = 1` かつ `mstatus.MPP != M` のとき、load / store / LR / SC / AMO が変換される
- 権限は MPP を使って判定する（MPP=U：U=1 のページだけ、MPP=S：U=1 のページは SUM=1 のときだけ）
- 命令フェッチは変換されない（M-mode なので仕様どおり）
- trap が起きると MPP=M になるので、ハンドラの中では変換されない
- `mret` は MPP != M のとき MPRV を 0 にする（仕様どおり）

## 構成

| 項目 | 内容 |
|---|---|
| DTLB | `cpu/dtlb.v`。16エントリのフルアソシアティブ、ASIDなし、ラウンドロビン置き換え。4KiBページと4MiBメガページ |
| PTW | `cpu/lsu_stage.v` の D$ ミス状態機械に組み込み。PTE は **D$ を通して**読む（設計メモのパターンA） |
| D$ | **16KB 4ウェイ・セットアソシアティブ**（1ウェイ 4KB、ライン 16B）、VIPT。index は VA[11:4]（EXで発行、従来どおり）、MA で 4ウェイのタグを DTLB の PA と比較。ウェイ選択は空きウェイ優先、なければラウンドロビン |
| PA | 32bit に切り詰め（PTE の PPN1[11:10] と satp.PPN[21:20] は無視） |
| A/D | HW では更新しない。A=0 は PTW でページフォルト、D=0 のページへのストアはページフォルト（Svade と同じ） |
| sfence.vma | DTLB を全部フラッシュ（rs1 / rs2 は見ない） |
| satp の書き込み | DTLB はフラッシュしない（仕様どおり、sfence.vma が必要） |

### タイミングの工夫

dc_stall の経路に乗る判定は、エントリごとに並列に計算してから hit ベクタと AND-OR する（16:1 の MUX を通さない）。

- `tag_eq`：ヒットしたエントリの PA[27:12] が D$ タグ RAM の出力と一致するか
- `perm_ok`：ヒットしたエントリがこのアクセスを許すか
- `pa_io`：PA[31:30] = 11（I/O 領域）かどうか。TLB に登録するときに計算しておく（設計メモ5の is_io_entry）

### D$ 状態機械に追加した状態（cpu/lsu_stage.v）

| 状態 | 内容 |
|---|---|
| PTRD | PTE アドレスでタグ RAM を読む |
| PTCK | PTE ラインのヒット判定、データ RAM 読み出し。ミスなら MEMW / MEMR → DCWT → PTRD |
| PTDT | PTE をデコード：次のレベル（PTRD）/ TLB 登録（RPRD）/ フォルト（FALT） |
| RPRD | 元の MA アクセスのタグを読み直す |
| RPCK | 元の MA アクセスを判定：ヒット → DCW3 → LDRD、ミス → MEMW / MEMR |
| FALT | ページフォルト（最後のストールサイクル。dc_stall_fin を出す） |
| PFX | ページフォルトの trap を取るサイクル（ストールなし。dc_stall_fin2 と pf_exc を出す） |

ストールの終わり方は、通常の D$ リフィルと同じ（DCW3 → LDRD、または FALT → PFX）。if_stage が見ている dc_stall_fin / dc_stall_fin2 の並びが変わらないようにしている。

### ページフォルトの trap

- 原因：load = 13、store / AMO = 15。mtval = VA、mepc = フォルトした命令（pc_ma）
- PFX のサイクルで `pf_exc` が g_exception に入る。EX にいる後続の命令はパージされ、MA の命令は書き戻されない
- 同じサイクルの割り込みは保留し、ページフォルトを優先する
- AMO の load がフォルトした場合：AMO 状態機械は最後まで回してストアだけを止め、AMO が終わった次の ~stall サイクルで trap を取る（mepc = AMO の PC）。途中で止めると if_stage に amo_stall_fin が届かないため
- I/O アクセスは、PTW を通った場合でも1回だけ出す（`io_ok_ma`：IDLE か LDRD のときだけ）

### セットアソシアティブ D$ の構造
- タグ RAM とデータ RAM をウェイ数だけ並べる（generate）。ロードは MA で全ウェイを同時に読み、WB でヒットしたウェイを選ぶ
- ストアとリフィルは、該当するウェイだけに書く。リフィル先は空きウェイ優先、なければラウンドロビン
- フラッシュ（fence.i）は（ウェイ, index）の全組を回す。`FT_DWAYS > 1` のときは書き戻した時点で dirty を落とす（`FT_DWAYS 1` は元の動作のまま）

### その他の変更

- `cpu/csr_array.v`：mscratch / sscratch / mtval / mie の CSR 書き込みを `~stall` のサイクルだけにした（mtvec や mstatus と同じ）。ページフォルトでパージされる CSR 命令が、ストール中に先に書き込んでしまうのを防ぐため
- `mex_stage` のキャンセル条件にページフォルトの trap を追加

## 制約・注意

- MMU を使うときは `FT_DWIDTH` を 10 以下にすること（11 以上では MMU が無効になる）
- valid / dirty は FF で、`FT_DWAYS` × 256 × 2 個（4ウェイで 2048 個、8ウェイで 4096 個）。Tang は `FT_DWAYS 1` のまま
- 8ウェイでもウェイ選択はラウンドロビン（擬似 LRU は未実装）
- **修正済みの既存バグ（MMU とは無関係、master の RTL でも起きる）**：D$ ミスのストール中に I$ ミスが重なり、その直後の fence.i の D$ フラッシュが I$ ストール中に始まると、if_stage の `use_collision` が 1 のまま残った（フラッシュは `dc_stall_fin2` を出さずに終わるため）。fence.i のリトライ後に ID が古い命令を出し続け、IF がプリフェッチを続けて止まる。`cpu/if_stage.v` で、fence.i のリトライジャンプ（`fencei_cond`）で `use_collision` を解除するように修正した。再現テストは `sim_mmu/tests/t05_fencei_dmiss.S`
- タイミング（Gowin の Fmax）は未確認。DTLB の CAM が dc_stall → stall の経路に加わっている
- DMA は変換しない（物理アドレスのまま）
- PMP は未実装

## シミュレーション（リポジトリトップの sim_mmu/）

```
cd sim_mmu
./run.sh tests/t00_basic.S          # MMU なしの基本テスト
./run.sh tests/t01_mmu_mprv.S       # MMU 機能テスト
ASFLAGS=-DTIMER_INTERVAL=157 ./run.sh tests/t02_mmu_irq.S   # 割り込み + TLB ストレス
VDEFS="-DTB_DWAYS=1" ./cmp.sh <test.S> [master] [maxcyc]  # MMU なしで master の RTL とサイクル単位で比較
```

- `tb_mmu.v`：cpu_top → axi_bus_top → dram_top →（MEM_MIG：tb 内の MIG スタブ / MEM_SDRAM：`sdram_if_sim.v`）（1MB の動作モデル）、io_frc（タイマ）
- テストの結果は MMIO で返す：0xC000_FFC0 に 1 = PASS / それ以外 = FAIL コード、0xC000_FFC4 = 1文字出力
- RTL は原本（`rtl_files.txt` に列挙した cpu/、io/、buslogics/、mig/ など）を読む。比較元は `git show <rev>:<path>` で取り出す
- `+TRACE`：trap を表示、`+COMMIT`：レジスタ書き戻し / MMIO / D$ ライトバックを表示

| テスト | 内容 |
|---|---|
| t00_basic | MMU なしの load / store / ループ |
| t01_mmu_mprv | 4KiB / メガページの変換、各種ページフォルト（V=0、W&~R、A=0、D=0、W なし、SUM、U/S、MXR、メガページの位置ずれ、L0 の非リーフ）、フォルトした load が rd を書かないこと、後続命令が1回だけ実行されること、エイリアス、メガページ経由の I/O、TLB 置き換え（24ページ）、sfence.vma、AMO / LR / SC、AMO のフォルト、mret での MPRV クリア |
| t02_mmu_irq | 32ページで TLB を溢れさせ、PTE と データの D$ 競合、タイマ割り込み、ページフォルトを混ぜたストレス |
| t04_mmu_disabled | `FT_DWIDTH` > 10 で MMU が無効になること（`VDEFS="-DTB_DWIDTH=12 -DTB_DWAYS=1"` で実行。MMU 有効の構成では FAIL code 2 になるのが正しい） |
| t05_fencei_dmiss | D$ ミスの直後の fence.i（I$ が空の状態）。`ASFLAGS=-DNOFS=0..3` で I$ ライン内の位置を変える |
| t03_dcache_4way | 同じセットに 12 ライン（dirty の追い出し）、byte / half ストア、fence.i で全ウェイをフラッシュして DRAM から読み直し、MMU 有効時に PTE とデータを同じセットに集中 |

- `cmp_arch.sh <test.S> [master]`：サイクル番号を除いた命令レベルのトレース（レジスタ書き戻し・MMIO）を改造前 RTL と比べる。キャッシュ構成が違う場合に使う（タイマ割り込みのテストは、割り込みの入る位置が変わるので一致しないことがある）
- tb の構成は `fpga/fpga_config.vh` に従う（MEM_MIG：tb 内の MIG スタブ、MEM_SDRAM：sdram_if_sim.v）
- `VDEFS` で D$ 構成を上書きできる：`VDEFS="-DTB_DWAYS=8" ./run.sh ...`、`-DTB_DWIDTH=12`、`-DTB_IWIDTH=10`
