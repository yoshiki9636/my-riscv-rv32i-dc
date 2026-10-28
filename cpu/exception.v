/*
 * My RISC-V RV32I CPU
 *   CPU Interrupter
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2023 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module exception(
	input clk,
	input rst_n,
	// from external
	input illegal_ops_ex,
	input misal_ld_ex,
	input misal_st_ex,
	// from csr
	output g_exception

	);

// illegal operations and misaligned load/store (2026-10-28)
assign g_exception = illegal_ops_ex | misal_ld_ex | misal_st_ex;
//assign g_exception = 1'b0;

endmodule
