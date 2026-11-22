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
 * - looked up every cycle with the MA VA; lsu_stage registers the result and
 *   refills its 1 entry micro-TLB from it (the DTLB is off the dc_stall path).
 *   Permission / I/O checks are done on the micro-TLB.
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
	output hit,
	output [31:12] pa,      // PA of the page (megapage : PA[21:12] = VA[21:12])
	output [4:0] flags,     // { D, U, X, W, R } of the matched entry

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
reg [NENT_W-1:0] rr_ptr;

// lookup
wire [NENT-1:0] hit_vec;
wire [31:12] pa_ent [0:NENT-1];

genvar g;
generate
for (g = 0; g < NENT; g = g + 1) begin : ent
	wire vpn1_eq = (e_vpn[g][31:22] == va[31:22]);
	wire vpn0_eq = (e_vpn[g][21:12] == va[21:12]);
	assign hit_vec[g] = e_valid[g] & vpn1_eq & (e_mega[g] | vpn0_eq);
	// megapage : PA[21:12] = VA[21:12]
	assign pa_ent[g] = { e_ppn[g][31:22], e_mega[g] ? va[21:12] : e_ppn[g][21:12] };
end
endgenerate

assign hit = |hit_vec;

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

function [4:0] flags_sel;
input [NENT-1:0] hv;
input [NENT*5-1:0] fl;
integer k;
begin
	flags_sel = 5'd0;
	for (k = 0; k < NENT; k = k + 1)
		flags_sel = flags_sel | ({5{hv[k]}} & fl[k*5 +: 5]);
end
endfunction

wire [NENT*5-1:0] flags_flat;
generate
for (g = 0; g < NENT; g = g + 1) begin : flf
	assign flags_flat[g*5 +: 5] = e_flags[g];
end
endgenerate

assign flags = flags_sel(hit_vec, flags_flat);

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
	end
	else if (fill) begin
		e_mega[rr_ptr] <= fill_mega;
	end
end

endmodule
