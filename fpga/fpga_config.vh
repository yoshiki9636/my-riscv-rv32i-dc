/*
 * My RISC-V RV32I CPU
 *   FPGA build configuration
 *    Verilog header
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2026 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

`ifndef FPGA_CONFIG_VH
`define FPGA_CONFIG_VH

// ---- board select (choose one) ----
//   BOARD_ARTY_A7 : Arty A7  rst_n (active low); MEM_MIG: rgb_led0-3, gpio[7:0], SPI pins / MEM_QSPI: rgb_led0, gpio[5:0]
//                   clk_wiz_0 : MEM_MIG: clk_out1 = 200MHz (MIG ref), clk_out2 = clk (50MHz) / MEM_QSPI: clk_out1 = clk (50MHz) only
//   BOARD_CMOD_A7 : CMOD A7  rst_p (active high), rgb_led0, gpio[3:0], no SPI pins
//                   clk_wiz_0 : clk_out1 = clk (48MHz)
`define BOARD_ARTY_A7
//`define BOARD_CMOD_A7

// ---- main memory select (choose one) ----
//   MEM_MIG  : DDR3 via MIG (Arty A7 only)
//   MEM_QSPI : QSPI PSRAM via qspi_if
`define MEM_MIG
//`define MEM_QSPI

`endif // FPGA_CONFIG_VH
