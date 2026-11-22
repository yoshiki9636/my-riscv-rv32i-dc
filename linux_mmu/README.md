# MMU Linux（S-mode、OpenSBI）

nommu Linux（M-mode）とは別に、S-mode で動く MMU 付き Linux を作るためのファイル。

| ファイル | 内容 |
|---|---|
| `myuart.c` | UART ドライバ（MMU 版）。レジスタは ioremap 経由、早期コンソールは `earlycon=myuart,mmio32,0xc000fc00`、RX 割り込みは SEIP（riscv-intc の hwirq 9） |
| `my_fpga_mmu.dts` | DTS。メモリ 128MB、0〜2MB は OpenSBI 用（reserved-memory、no-map）、clint なし（タイマは SBI と time CSR） |
| `mmu.config` | nommu の .config に重ねる設定（M-mode を外し、MMU / SBI / RISCV_TIMER / BINFMT_ELF） |
| `build.sh` | カーネル + DTB + OpenSBI fw_payload をまとめてビルド |

## カーネルのソース
nommu のツリー（`~/linux/linux`）は M-mode 用に `head.S` などを書き換えてあるので使わない。
コミット済みの HEAD（アップストリーム）から別にコピーを作る：
```
mkdir -p ~/linux/linux-mmu
git -C ~/linux/linux archive HEAD -- . ':!lab3_dram' ':!rtl_atomic_test' | tar -x -C ~/linux/linux-mmu
```
`build.sh` が `myuart.c` をコピーし、`drivers/tty/serial/Kconfig` / `Makefile` に項目を追加する。

## ビルド
```
./build.sh            # 初回は設定も作る（~/linux/linux/.config + mmu.config）
./build.sh config     # 設定を作り直す
```
| 変数 | 既定値 |
|---|---|
| `KSRC` | `~/linux/linux-mmu` |
| `KOUT` | `~/linux/build-mmu` |
| `CPIO` | `~/linux/linux/initramfs.cpio`（static-pie の busybox、MMU でもそのまま動く） |
| `BASE` | `~/linux/linux/.config`（nommu の設定） |

出力：`../sbi/opensbi/build/platform/5stage/firmware/fw_payload.hex`（OpenSBI + カーネル + DTB、`Image.hex` と同じ形式でアドレス 0 から）。

## メモリ配置
| アドレス | 内容 |
|---|---|
| 0x0000_0000 | OpenSBI（M-mode） |
| 0x0020_0000 | DTB |
| 0x0040_0000 | カーネル（仮想アドレス 0xC000_0000 から） |
