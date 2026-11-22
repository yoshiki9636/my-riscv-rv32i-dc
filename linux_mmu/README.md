# MMU Linux（S-mode、OpenSBI）

nommu Linux（M-mode）とは別に、S-mode で動く MMU 付き Linux を作るためのファイル。

| ファイル | 内容 |
|---|---|
| `myuart.c` | UART ドライバ（MMU 版）。レジスタは ioremap 経由、早期コンソールは `earlycon=myuart,mmio32,0xc000fc00`、RX 割り込みは SEIP（riscv-intc の hwirq 9） |
| `my_fpga_mmu.dts` | DTS。メモリ 128MB、0〜2MB は OpenSBI 用（reserved-memory、no-map）、clint なし（タイマは SBI と time CSR） |
| `mmu.config` | nommu の .config に重ねる設定（M-mode を外し、MMU / SBI / RISCV_TIMER / BINFMT_ELF） |
| `build.sh` | カーネル + DTB + OpenSBI fw_payload をまとめてビルド |
| `mkinitramfs.sh` | MMU 用の initramfs（`~/linux/initramfs-mmu.cpio`）を gen_init_cpio で作る（root 不要） |

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
| `CPIO` | `~/linux/initramfs-mmu.cpio`（MMU 用 busybox、`mkinitramfs.sh` で作る）。`~/linux/linux/initramfs.cpio`（nommu 用 busybox）も MMU でそのまま動く |
| `BASE` | `~/linux/linux/.config`（nommu の設定） |

出力：`../sbi/opensbi/build/platform/5stage/firmware/fw_payload.hex`（OpenSBI + カーネル + DTB、`Image.hex` と同じ形式でアドレス 0 から）。

## メモリ配置
| アドレス | 内容 |
|---|---|
| 0x0000_0000 | OpenSBI（M-mode） |
| 0x0020_0000 | DTB |
| 0x0040_0000 | カーネル（仮想アドレス 0xC000_0000 から） |

## ユーザーランド（MMU 用 busybox）
nommu 用（`~/linux/busybox-1.36.1-musl`、`CONFIG_NOMMU=y`、hush、static-pie）とは別に、
MMU 用を `~/linux/busybox-1.36.1-mmu` でビルドする。

- 設定：musl 版の .config から `CONFIG_NOMMU` を外し、シェルを ash（`CONFIG_SH_IS_ASH`、
  ジョブ制御・エイリアス・bash 互換などを有効）にした。hush も残している
- ビルド：`make CC=~/linux/musl-rv32/bin/riscv32-musl-gcc`（musl 1.2.5、static、rv32ima / ilp32）
- initramfs：`./mkinitramfs.sh`（busybox、`~/linux/initramfs-mmu/` の init と bin/mtest、
  /dev/console・null・ttyMY0）


## ユーザーランド（Buildroot、glibc + bash）
`buildroot/` に設定とビルドスクリプトを置いている（Buildroot 2026.08.2）。

| ファイル | 内容 |
|---|---|
| `buildroot/fpga_rv32ima_glibc_defconfig` | RV32IMA（F / D / C なし）、ilp32、内部ツールチェーン（gcc 15 + glibc、カーネルヘッダ 6.18）、bash を `/bin/sh` に（busybox の SHOW_OTHERS が必要）、busybox init、getty on console、initramfs（cpio） |
| `buildroot/build.sh` | `~/linux/buildroot-2026.08.2` で `O=~/linux/br-out` にビルド（WSL : PATH の空白を含む項目を外して実行） |

```
git clone --depth 1 --branch 2026.08.2 https://gitlab.com/buildroot.org/buildroot.git ~/linux/buildroot-2026.08.2
./buildroot/build.sh                                         # 初回 15 分程度（28 コア）
CPIO=~/linux/br-out/images/rootfs.cpio ./build.sh config     # カーネル + fw_payload.hex
```
ログインは `root`（パスワードなし）。rootfs.cpio は約 6.3MB、fw_payload.hex は約 13.6MB（イメージ）。
