# OpenSBI（MMU Linux 用の M-mode ファームウェア）

`opensbi/platform/5stage/` は OpenSBI のツリー外プラットフォーム（`PLATFORM_DIR`）。
OpenSBI 本体は別に取得したソースを使う（動作確認：v1.8、コミット 6767861c）。

## ビルド
```
./build.sh                                        # fw_jump と fw_payload（テスト用ペイロード）
./build.sh FW_PAYLOAD_PATH=<Image> FW_FDT_PATH=<dtb>   # Linux を fw_payload に入れる
```
環境変数 `OPENSBI`（ソースの場所、既定 `~/linux/opensbi`）、`CROSS_COMPILE`（既定 `/opt/riscv32im.linux/bin/riscv32-unknown-linux-gnu-`）。
出力は `opensbi/build/platform/5stage/firmware/`。

## メモリ配置
| アドレス | 内容 |
|---|---|
| 0x0000_0000 | OpenSBI（約 310KB、RW 領域とヒープを含む） |
| 0x0020_0000 | DTB（Linux に a1 で渡す） |
| 0x0040_0000 | S-mode のカーネル（`FW_JUMP_ADDR` / `FW_PAYLOAD_OFFSET`、RV32 は 4MB 境界） |

## プラットフォーム（platform.c）
| 項目 | 内容 |
|---|---|
| コンソール | io_uart_out（0xC000_FC00）。putc は FULL（+0x04）を待って OUTC（+0x00）、getc は RXCH（+0x0C）の bit8 |
| タイマ | io_frc（0xC000_F800）。64 ビットカウンタ（time CSR と同じ）、比較値の書き込みと同時に CNTRL（bit2 = 0）で MTIP をクリア（M のタイマ割り込みはエッジで受けるため） |
| 周波数 | 50MHz（`STAGE5_TIMER_FREQ`、DTS の timebase-frequency と合わせる） |
| IPI / irqchip | なし（単一 hart。外部割り込みは interrupter から mip.MEIP / SEIP） |
| PMP | なし（OpenSBI のファームウェア領域は保護されない） |

OpenSBI の設定：mideleg = SSIP / STIP / SEIP、medeleg = 0xB109（ミスアラインのロード / ストアは委譲せず OpenSBI がエミュレート）、mcounteren = TM。

## シミュレーション（sim_mmu）
```
cd ../sim_mmu
./run_sbi.sh                                                    # fw_payload（テスト用ペイロード）
./run_sbi.sh ../sbi/opensbi/build/platform/5stage/firmware/fw_jump.elf tests/sbi_payload.S +MAXCYC=2000000
```
`tests/sbi_payload.S`：SBI base / probe、コンソール、set_timer による S のタイマ割り込み、time CSR、ミスアラインのエミュレーション、rfence。約 47 万サイクル（iverilog で約 2 分）。
