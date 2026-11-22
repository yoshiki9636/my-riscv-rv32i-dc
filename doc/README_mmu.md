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
| 2 | S/U-mode、trap の委譲（medeleg / mideleg）、S-mode CSR、sret | **実装・シミュレーション済み**（`FT_SMODE`） |
| 3 | ITLB + IF ステージ対応（命令フェッチの変換）、I$ 4ウェイ（`FT_IWAYS`） | **実装・シミュレーション済み** |
| 4 | SBI（OpenSBI か自作）+ MMU 版 Linux | 未着手 |

## S/U-mode（ステップ2、`FT_SMODE`）

`fpga/fpga_top.v` の `FT_SMODE`（Arty 1、Tang / CMOD 0）で切り替える。0 のときは元の M-mode だけの CPU と同じ動作（mret は常に M に戻る）。

| 項目 | 内容 |
|---|---|
| 特権レベル | M / S / U。リセット後は M。trap で M か S へ、mret で MPP へ、sret で SPP（S / U）へ |
| trap の委譲 | medeleg（例外 0〜15、ただし 10 / 11 / 14 を除く）、mideleg（SSI / STI / SEI）。priv < M で委譲されていれば S-mode へ（stvec / sepc / scause / stval、SPP / SPIE / SIE） |
| S-mode CSR | sstatus / sie / stvec / scounteren（0）/ sscratch / sepc / scause / stval / sip / satp |
| M-mode の追加 | medeleg / mideleg / mcounteren（0）、mip / mie の SSIP / STIP / SEIP（M のソフトウェアが書く）、misa = IMASU |
| 割り込み | M レベル（外部・タイマ）は priv < M なら MIE に関係なく受け付ける（io_frc / interrupter に渡す `csr_rmie` も同じ条件）。S レベル（SSIP / STIP / SEIP）はレベル方式で、委譲先と SIE / MIE で受け付けを決める |
| 特権チェック（不正命令） | CSR：priv < csr[9:8]、読み出し専用 CSR（csr[11:10] = 11）への書き込み。mret（M 以外）、sret / sfence.vma（U） |
| ecall | 例外コードは U = 8、S = 9、M = 11 |
| 変換 | satp.MODE = 1 のとき、S / U-mode のデータアクセスは常に変換（M-mode は MPRV = 1 で MPP が S / U のとき） |

未対応（今後）：

- mstatus の TVM / TW / TSR（0 固定）、cycle / instret CSR（未実装で 0 が読める）
- **nommu Linux（M-mode カーネル）**：`FT_SMODE 1` では、カーネルが MPP = U でユーザプロセスに mret すると、本当に U-mode で動く。今の nommu カーネルで問題が出る場合は `FT_SMODE 0` にする

## time CSR と SEIP（ステップ4の準備）

| 項目 | 内容 |
|---|---|
| time / timeh（0xC01 / 0xC81） | io_frc の 64 ビットカウンタ（MTIME と同じ値、clk で動作）。読み出し専用（書き込みは不正命令）。S-mode は mcounteren.TM = 1、U-mode は mcounteren.TM と scounteren.TM の両方が 1 のときだけ読める（それ以外は不正命令） |
| mcounteren / scounteren | 3 ビット（CY / TM / IR）、TM だけが意味を持つ |
| SEIP | 外部割り込み（interrupter の `g_interrupt`、レベル）を mip.SEIP のハードウェア入力につないだ。interrupter は MEIE か mie.SEIE のどちらかが 1 なら割り込みのステータスを立てる。S-mode の Linux に渡すときは MEIE = 0、SEIE = 1、mideleg.SEI = 1 にする（M 側のエッジ割り込みは MEIE = 1 のときだけ） |
| mip の書き込み | csrrs / csrrc で mip を書き換えるとき、SEIP はソフトウェアのビットだけを対象にする（外部入力の値を取り込まない） |

いずれも `FT_SMODE 0` のときは無効（今までと同じ動作）。

## ITLB と I$（ステップ3）

| 項目 | 内容 |
|---|---|
| I$ | `FT_IWAYS`（1 / 2 / 4 / 8）× 2^(`FT_IWIDTH`+2) バイト。Arty は 4KB × 4ウェイ = 16KB。`FT_IWAYS 1` は元の direct-map と同じ動作。MMU には `FT_IWIDTH` ≦ 10 が必要（超えると MMU 無効） |
| 命令の選択 | 全ウェイを IF で読み、ID のタグ比較結果（`ic_way_rd`）でウェイを選ぶ |
| 命令フェッチの変換 | satp.MODE = 1 かつ priv が S / U のとき（MPRV は関係しない） |
| micro-ITLB | 1エントリ（FF）。ID のタグ比較と権限判定（X、U ページは U-mode だけ・S ページは S-mode だけ実行可）に使う |
| ITLB | 16エントリ（`dtlb.v` を流用）。毎サイクルの検索結果を FF に取り込む。micro-ITLB ミス → ITL1 → ヒットなら ICRP、ミスなら IWLK |
| PTW | lsu_stage の PTW を共有（D 側を優先。I 側は D$ の状態機械が IDLE で、MA にメモリアクセスがないときに開始し、RPRD / RPCK → DCW3 → LDRD で戻る） |
| 命令ページフォルト | cause 12、mtval = PC。フォルトした取り込みは予約エンコーディング `0x0BAD007F` を ID に渡し（if_stage の命令の一時保存を経ても PC と対応したまま運ばれる）、id_stage が不正命令として扱い、EX で cause 12 にする。フォルトは micro-ITLB に保持し、次のリダイレクトで捨てる |
| sfence.vma | DTLB / ITLB / micro-TLB をすべてフラッシュ |
| ITLB の状態（ilu_stage） | ITL1：ITLB の結果を見る、IWLK：PTW を待つ、ICRP：取り込みを再判定（ヒット / フォルト → ICW3 → LDRD、ミス → MEMR） |

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
| micro-TLB | `cpu/lsu_stage.v`。1エントリ（FF）。直前に使った変換（4KB 単位、メガページはアクセスした 4KB 分に展開）。MA のタグ比較・権限・I/O 判定はここから行う |
| PTW | `cpu/lsu_stage.v` の D$ ミス状態機械に組み込み。PTE は **D$ を通して**読む（設計メモのパターンA） |
| D$ | **16KB 4ウェイ・セットアソシアティブ**（1ウェイ 4KB、ライン 16B）、VIPT。index は VA[11:4]（EXで発行、従来どおり）、MA で 4ウェイのタグを DTLB の PA と比較。ウェイ選択は空きウェイ優先、なければラウンドロビン |
| PA | 32bit に切り詰め（PTE の PPN1[11:10] と satp.PPN[21:20] は無視） |
| A/D | HW では更新しない。A=0 は PTW でページフォルト、D=0 のページへのストアはページフォルト（Svade と同じ） |
| sfence.vma | DTLB を全部フラッシュ（rs1 / rs2 は見ない） |
| satp の書き込み | DTLB はフラッシュしない（仕様どおり、sfence.vma が必要） |

### タイミングの工夫（micro-TLB）

dc_stall → stall はもともとクリティカルパスなので、その経路に乗るものは FF から出すようにしている。

- MA のタグ比較に使う PA、権限判定、I/O 判定は、1エントリの **micro-TLB（FF）**から出す。追加されるのは VPN の 20 ビット比較だけで、タグ RAM の読み出しと並列に行われる
- 16エントリの DTLB は毎サイクル MA の VA で検索し、結果を FF に取り込む（DTLB → FF の 1 サイクル）。micro-TLB がミスしたときは TLBL 状態で 1 サイクルストールし、その結果で micro-TLB を更新する
- ページが変わるたびに 1 サイクルのストールが入る（同じページの連続アクセスでは入らない）
- ライトバック開始の判定（`ram_ren_all`、`dcr_start_rq`）は fence.i の条件を見ない（D$ ミス中は必ずストールしていて、fence.i によるフラッシュ開始と重ならないため、結果は同じ）。stall → fence.i → データ RAM アドレスの経路を切っている

### D$ 状態機械に追加した状態（cpu/lsu_stage.v）

| 状態 | 内容 |
|---|---|
| TLBL | micro-TLB ミス：FF に取り込んだ DTLB の結果を見る。ヒット → micro-TLB を更新して RPCK、ミス → PTRD（PTW） |
| PTRD | PTE アドレスでタグ RAM を読む |
| PTCK | PTE ラインのヒット判定、データ RAM 読み出し。ミスなら MEMW / MEMR → DCWT → PTRD |
| PTDT | PTE をデコード：次のレベル（PTRD）/ DTLB と micro-TLB に登録（RPRD）/ フォルト（FALT） |
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
| t06_utlb | micro-TLB ミス・DTLB ヒットの経路（8ページを交互にアクセス）、その経路での権限フォルトと I/O |
| t07_smode | S/U-mode（`VDEFS="-DTB_SMODE=1"`）：misa、M → S / U、特権チェック、ecall の例外コード、medeleg による委譲と sret、S-mode での変換（SUM / U ページ）、S レベル割り込み（委譲あり / なし） |
| t08_itlb | 命令フェッチの変換（`VDEFS="-DTB_SMODE=1"`）：S-mode のコードを VA ≠ PA で実行、命令ページフォルト（X なし・無効・U ページ）、20 ページで ITLB を溢れさせる、D 側 / I 側の PTW の混在、sfence.vma + fence.i でコードページを付け替え |
| t09_time_seip | time CSR（MTIME と一致して増える、書き込みは不正命令、mcounteren / scounteren によるアクセス権）、外部割り込みから S-mode への SEIP（tb の EXTINT、0xC000_FFC8）、mip の読み書きで SEIP の外部入力を取り込まないこと |
| t03_dcache_4way | 同じセットに 12 ライン（dirty の追い出し）、byte / half ストア、fence.i で全ウェイをフラッシュして DRAM から読み直し、MMU 有効時に PTE とデータを同じセットに集中 |

- `cmp_arch.sh <test.S> [master]`：サイクル番号を除いた命令レベルのトレース（レジスタ書き戻し・MMIO）を改造前 RTL と比べる。キャッシュ構成が違う場合に使う（タイマ割り込みのテストは、割り込みの入る位置が変わるので一致しないことがある）
- tb の構成は `fpga/fpga_config.vh` に従う（MEM_MIG：tb 内の MIG スタブ、MEM_SDRAM：sdram_if_sim.v）
- `VDEFS` で D$ 構成を上書きできる：`VDEFS="-DTB_DWAYS=8" ./run.sh ...`、`-DTB_DWIDTH=12`、`-DTB_IWIDTH=10`
