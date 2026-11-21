/*
 * My RISC-V RV32I CPU
 *   Data TLB (Sv32) Module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2026 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 *
 * - fully associative, 16 entries (NENT), no ASID (sfence.vma flushes all)
 * - 4KiB page / 4MiB megapage
 * - PA is truncated to 32bit (PTE PPN1[11:10] are ignored)
 * - an entry is filled only when the PTE is valid and A=1 (see lsu_stage PTW),
 *   so A is not stored.  D is stored : a store to a D=0 page is a page fault
 *   (Svade style, the OS sets D and executes sfence.vma)
 * - everything that sits on the dc_stall path is computed per entry in
 *   parallel and AND-ORed with the hit vector (no 16:1 mux in front of it):
 *     perm_ok : matched entry allows this access
 *     pa_io   : matched entry's PA[31:30] == 2'b11 (I/O region, precomputed)
 * - replacement : round robin
 */

module dtlb
	#(parameter NENT = 16,
	  parameter NENT_W = 4,
	  parameter DWIDTH = 10)
	(
	input clk,
	input rst_n,

	// lookup (MA stage)
	input [31:12] va,
	input is_store,      // store / sc.w / AMO
	input priv_u,        // effective privilege is U (else S)
	input sum,           // mstatus.SUM
	input mxr,           // mstatus.MXR
	output hit,
	output perm_ok,
	output pa_io,
	output [31:12] pa,

	// fill (from PTW)
	input fill,
	input [31:12] fill_vpn,
	input fill_mega,
	input [31:12] fill_ppn,   // {PPN1[9:0], PPN0}
	input [4:0] fill_flags,   // {D, U, X, W, R}

	// flush (sfence.vma)
	input flush
	);

reg [NENT-1:0] e_valid;
reg [NENT-1:0] e_mega;
reg [31:12] e_vpn [0:NENT-1];
reg [31:12] e_ppn [0:NENT-1];
reg [4:0] e_flags [0:NENT-1];
reg [NENT-1:0] e_io;
reg [NENT_W-1:0] rr_ptr;

// lookup
wire [NENT-1:0] hit_vec;
wire [NENT-1:0] perm_vec;
wire [31:12] pa_ent [0:NENT-1];

genvar g;
generate
for (g = 0; g < NENT; g = g + 1) begin : ent
	wire vpn1_eq = (e_vpn[g][31:22] == va[31:22]);
	wire vpn0_eq = (e_vpn[g][21:12] == va[21:12]);
	assign hit_vec[g] = e_valid[g] & vpn1_eq & (e_mega[g] | vpn0_eq);
	// megapage : PA[21:12] = VA[21:12]
	assign pa_ent[g] = { e_ppn[g][31:22], e_mega[g] ? va[21:12] : e_ppn[g][21:12] };
	// flags : [4] D, [3] U, [2] X, [1] W, [0] R
	wire f_d = e_flags[g][4];
	wire f_u = e_flags[g][3];
	wire f_x = e_flags[g][2];
	wire f_w = e_flags[g][1];
	wire f_r = e_flags[g][0];
	wire priv_ok = priv_u ? f_u : (~f_u | sum);
	wire acc_ok = is_store ? (f_w & f_d) : (f_r | (mxr & f_x));
	assign perm_vec[g] = priv_ok & acc_ok;
end
endgenerate

assign hit = |hit_vec;
assign perm_ok = |(hit_vec & perm_vec);
assign pa_io = |(hit_vec & e_io);

// PA : AND-OR mux (only one entry hits)
function [31:12] pa_sel;
input [NENT-1:0] hv;
input [NENT*20-1:0] pas;
integer k;
begin
	pa_sel = 20'd0;
	for (k = 0; k < NENT; k = k + 1)
		pa_sel = pa_sel | ({20{hv[k]}} & pas[k*20 +: 20]);
end
endfunction

wire [NENT*20-1:0] pa_flat;
generate
for (g = 0; g < NENT; g = g + 1) begin : paf
	assign pa_flat[g*20 +: 20] = pa_ent[g];
end
endgenerate

assign pa = pa_sel(hit_vec, pa_flat);

// fill / flush
integer n;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		e_valid <= { NENT{ 1'b0 }};
		rr_ptr <= { NENT_W{ 1'b0 }};
	end
	else if (flush) begin
		e_valid <= { NENT{ 1'b0 }};
	end
	else if (fill) begin
		e_valid[rr_ptr] <= 1'b1;
		rr_ptr <= rr_ptr + { {(NENT_W-1){ 1'b0 }}, 1'b1 };
	end
end

always @ (posedge clk) begin
	if (fill) begin
		e_vpn[rr_ptr] <= fill_vpn;
		e_ppn[rr_ptr] <= fill_ppn;
		e_flags[rr_ptr] <= fill_flags;
	end
end

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		e_mega <= { NENT{ 1'b0 }};
		e_io <= { NENT{ 1'b0 }};
	end
	else if (fill) begin
		e_mega[rr_ptr] <= fill_mega;
		e_io[rr_ptr] <= (fill_ppn[31:30] == 2'b11);
	end
end

endmodule
