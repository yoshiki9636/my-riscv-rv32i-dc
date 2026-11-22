/*
 * My RISC-V RV32I CPU
 *   FPGA LED output Module for Tang Premier
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

`define SUPPORT_M
`define SUPPORT_A

module ilu_stage
	#(parameter IWIDTH = 14,
	  parameter IWAYS = 1)   // I$ ways : 1 / 2 / 4 / 8 (2026-11-22)
	(
	input clk,
	input rst_n,

	// FORM TO IF
	input [31:2] pc_if,
	input [31:2] pc_id_pre,
	input pc_valid_id,
	input btb_spec_fetch,   // the fetch checked now is a discarded BTB-target fetch
    output [IWIDTH-3:0] ic_ram_wadr_all,
	input fencei_dcflush_end,
	input stall,
	output fencei_cond,
    //output [127:0] ic_ram_wdata_all,
    //output ic_ram_wen_all,
`ifdef SUPPORT_M
    output ic_stall_fin2_add_div,
    output ic_stall_fin_add_div,
	output ic_stall_add_div,
	output ic_stall_dly_add_div,
    input div_stall,
    input div_stall_fin,
    input div_stall_fin2,
    input div_stall_dly,
`else // SUPPORT_M
    output ic_stall_fin2,
    output ic_stall_fin,
	output ic_stall,
	output ic_stall_dly,
`endif // SUPPORT_M
`ifdef SUPPORT_A
	input amo_stall,
	input amo_stall_dly,
	input amo_stall_fin,
	input amo_stall_fin2,
`endif // SUPPORT_A

    //output ic_st_ok,
	// IC controls
	output ic_tag_hit_id,
	//output ic_st_wt_id,
	// tiny AXI read bus i/f
	output icr_start_rq,
	output [31:0] ic_rin_addr,
	//input [127:0] rdat_m_data,
	input ic_rdat_m_valid,
	input ic_finish_mrd, // not used
	// IC flush
	input start_icflush,
	// I$ ways (2026-11-22)
	output [7:0] ic_way_rd,       // way that hits for the ID fetch (instruction select)
	output [7:0] ic_fill_way,     // refill write way (one hot, with ic_rdat_m_valid)
	// ITLB (2026-11-22)
	input itrans_on,              // instruction fetch translation (satp.MODE & priv != M)
	input i_priv_u,               // current privilege is U (else S)
	input tlb_flush,              // sfence.vma
	input ipf_clr,                // a redirect : forget a cached fetch fault
	input i_walk_busy,            // lsu_stage : the I-side walk is running
	output iwalk_pend,            // ITLB miss in progress (ex_stage : hold interrupts)
	output ipf_id,                // the ID fetch takes an instruction page fault
	output i_walk_req,            // PTW request to lsu_stage
	output [31:12] i_walk_va,
	input i_walk_done,            // PTW : the ITLB is filled (ifill)
	input i_walk_fault,           // PTW : page fault
	input ifill,                  // ITLB fill (from the PTW)
	input [31:12] ifill_vpn,
	input ifill_mega,
	input [31:12] ifill_ppn,
	input [4:0] ifill_flags,      // { D, U, X, W, R }
	//output icflush_running,
	// reset pipeline
	input rst_pipe

	);

// fencei wait

// FIX (2026-10-28): the retry jump (fencei_cond) must not fire while the
// pipeline is stalled.  The instruction after fence.i runs once in its
// shadow (masked by fencei_wb_purge); if it is a load it misses the freshly
// flushed D$ and dc_stall is high exactly when fencei_wt[1] rose.  A jump
// during stall is lost by pc_if_pre (its stall hold has priority over
// jmp_cond) and by ex_stage's ~stall-gated jmp_purge_ma update, while
// pc_if_roll does take it: after the stall pc_id kept the old PC but the
// fetched instruction came from the new one, so EX paired PC N with the
// instruction at N+4 (one instruction lost, the next run twice).  Ordinary
// jumps are already gated by ~stall.  Hold the wait chain during stall
// (keeping a flush-end pulse that arrives during stall) and only emit
// fin/fin2/cond on ~stall cycles; without a stall the timing is unchanged.
// Reproduced by rtl_atomic_test/fencei_align_test.S (FENCE_OFS=8, DWIDTH=4).
reg [2:0] fencei_wt;
reg fencei_dfe_pend;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        fencei_dfe_pend <= 1'b0;
    else if (~stall)
        fencei_dfe_pend <= 1'b0;
    else if (fencei_dcflush_end)
        fencei_dfe_pend <= 1'b1;
end

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        fencei_wt <= 3'd0;
    else if (~stall)
        fencei_wt <= { fencei_wt[1:0], fencei_dcflush_end | fencei_dfe_pend };
end

wire fencei_stall = fencei_wt[0] | fencei_dcflush_end | fencei_dfe_pend;
wire fencei_stall_fin = fencei_wt[0] & ~stall;
wire fencei_stall_fin2 = fencei_wt[1] & ~stall;
assign fencei_cond = fencei_wt[1] & ~stall;
//wire fencei_stall = 1'b0;
//wire fencei_stall_fin = 1'b0;
//wire fencei_stall_fin2 = 1'b0;
//assign fencei_cond = fencei_dcflush_end;

`ifdef SUPPORT_M
// for div stall
wire ic_stall_fin2;
wire ic_stall_fin;
wire ic_stall;
wire ic_stall_dly;

assign ic_stall_fin2_add_div = ic_stall_fin2 | div_stall_fin2;
assign ic_stall_fin_add_div = ic_stall_fin | div_stall_fin;
assign ic_stall_add_div = ic_stall | div_stall;
assign ic_stall_dly_add_div = ic_stall_dly | div_stall_dly;
`endif // SUPPORT_M

//
// ---------------------------------------------------------------------------
// I$ : IWAYS way set associative (2026-11-22)
//   IWAYS = 1 is the original direct mapped I$ (same behavior).
//   1 way = 2^(IWIDTH+2) bytes, index = VA[IWIDTH+1:4], tag = PA[27:IWIDTH+2]
//   (IWIDTH <= 10 with the MMU : VIPT).  The ID fetch selects its way with
//   ic_way_rd (if_stage).  Refill way : the first invalid way, else round robin.
// ITLB (2026-11-22)
//   1 entry micro-ITLB (flip-flops) : the ID tag compare / permission use it.
//   micro-ITLB miss -> ITL1 (registered 16 entry ITLB result)
//     ITLB hit  : refill the micro-ITLB -> ICRP
//     ITLB miss : IWLK, the PTW runs in lsu_stage (i_walk_req), -> ICRP
//   ICRP : re-check the fetch : I$ hit / fault -> ICW3 -> LDRD, miss -> MEMR
//   A fault is kept in the micro-ITLB (iu_fault) until the next redirect.
//   ipf_id : the ID fetch faults (if_stage puts the fault marker in its place)
// ---------------------------------------------------------------------------
localparam TW = 26 - IWIDTH;
localparam NSET = 2**(IWIDTH-2);

reg [31:0] ic_curric_ent_radr_keeper;
// tag ram
wire ic_sel_tag;
reg [27:IWIDTH+2] ic_tag_adr_id;
reg [31:12] va_id;                       // VA page of the ID fetch
wire [27:IWIDTH+2] ic_tag_adr_if = ic_sel_tag ? ic_curric_ent_radr_keeper[27:IWIDTH+2] : pc_if[27:IWIDTH+2];
wire [IWIDTH+1:4]  ic_index_adr = ic_sel_tag ? ic_curric_ent_radr_keeper[IWIDTH+1:4] : pc_if[IWIDTH+1:4];
wire [27:IWIDTH+2] ic_tag_wadr;
wire [IWIDTH+1:4] ic_index_wadr;
wire ic_tag_wen;
reg [2:0] ic_fill_way_r;
wire [IWAYS*TW-1:0] ic_tag_flat;

genvar gw;
generate
for (gw = 0; gw < IWAYS; gw = gw + 1) begin : itag
ic_tag_1r1w #(.IRWIDTH(IWIDTH-2)) ic_tag_1r1w (
	.clk(clk),
	.ram_radr(ic_index_adr),
	.ram_rdata(ic_tag_flat[gw*TW +: TW]),
	.ram_wadr(ic_index_wadr),
	.ram_wdata(ic_tag_wadr),
	.ram_wen(ic_tag_wen & (ic_fill_way_r == gw))
	);
end
endgenerate

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        ic_tag_adr_id <= { (27-IWIDTH-1){ 1'b0 }} ;
        va_id <= 20'd0;
    end
	else if (rst_pipe) begin
        ic_tag_adr_id <= { (27-IWIDTH-1){ 1'b0 }} ;
        va_id <= 20'd0;
    end
	else if (~ic_stall & ~ic_stall_fin ) begin
		ic_tag_adr_id <= ic_tag_adr_if;
		va_id <= ic_sel_tag ? ic_curric_ent_radr_keeper[31:12] : pc_if[31:12];
    end
end

// ---- micro-ITLB ----
reg iu_valid;
reg iu_fault;
reg [31:12] iu_vpn;
reg [31:12] iu_ppn;
reg [4:0] iu_flags;                      // { D, U, X, W, R }
wire iu_hit = iu_valid & (iu_vpn == va_id);
wire iu_x_ok = ~iu_fault & iu_flags[2] & (i_priv_u ? iu_flags[3] : ~iu_flags[3]);
wire i_need = itrans_on & pc_valid_id & ~btb_spec_fetch;
wire imiss = i_need & ~iu_hit;
assign ipf_id = i_need & iu_hit & ~iu_x_ok;
wire iok = ~itrans_on | (iu_hit & iu_x_ok);

// ---- 16 entry ITLB : looked up with the ID VA every cycle, registered ----
wire m_hit;
wire [31:12] m_pa;
wire [4:0] m_flags;
reg m_hit_r;
reg [31:12] m_pa_r;
reg [4:0] m_flags_r;

dtlb #(.DWIDTH(IWIDTH)) itlb (
	.clk(clk),
	.rst_n(rst_n),
	.va(va_id),
	.hit(m_hit),
	.pa(m_pa),
	.flags(m_flags),
	.fill(ifill),
	.fill_vpn(ifill_vpn),
	.fill_mega(ifill_mega),
	.fill_ppn(ifill_ppn),
	.fill_flags(ifill_flags),
	.flush(tlb_flush)
	);

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		m_hit_r <= 1'b0;
		m_pa_r <= 20'd0;
		m_flags_r <= 5'd0;
	end
	else begin
		m_hit_r <= m_hit & ~tlb_flush;
		m_pa_r <= m_pa;
		m_flags_r <= m_flags;
	end
end

wire [3:0] ic_miss_current_w;
wire st_itl1 = (ic_miss_current_w == 4'd8);
wire st_iwlk = (ic_miss_current_w == 4'd9);
// PTW result : the 4KB page of the fetch (a megapage is expanded)
wire [31:12] ifill_ppn_4k = { ifill_ppn[31:22], ifill_mega ? va_id[21:12] : ifill_ppn[21:12] };

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		iu_valid <= 1'b0;
		iu_fault <= 1'b0;
		iu_vpn <= 20'd0;
		iu_ppn <= 20'd0;
		iu_flags <= 5'd0;
	end
	else if (tlb_flush) begin
		iu_valid <= 1'b0;
	end
	else if (st_itl1 & m_hit_r) begin
		iu_valid <= 1'b1;
		iu_fault <= 1'b0;
		iu_vpn <= va_id;
		iu_ppn <= m_pa_r;
		iu_flags <= m_flags_r;
	end
	else if (st_iwlk & ifill) begin
		iu_valid <= 1'b1;
		iu_fault <= 1'b0;
		iu_vpn <= va_id;
		iu_ppn <= ifill_ppn_4k;
		iu_flags <= ifill_flags;
	end
	else if (st_iwlk & i_walk_fault) begin
		iu_valid <= 1'b1;
		iu_fault <= 1'b1;
		iu_vpn <= va_id;
	end
	else if (ipf_clr & iu_fault) begin
		iu_valid <= 1'b0;
	end
end

assign i_walk_req = st_iwlk & ~iw_kill;
assign i_walk_va = va_id;

// ---- tag compare ----
wire [27:IWIDTH+2] cmp_tag = itrans_on ? iu_ppn[27:IWIDTH+2] : ic_tag_adr_id;

// dirty / valid bits
reg [IWAYS*NSET-1:0] ic_ent_valid;
reg [IWIDTH+1:4] ic_index_adr_dly;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ic_index_adr_dly <= { (IWIDTH-2){ 1'b0 }};
	else
        ic_index_adr_dly <= ic_index_adr;
end

wire [7:0] way_valid;
wire [7:0] way_eq;
generate
for (gw = 0; gw < 8; gw = gw + 1) begin : iwayv
	if (gw < IWAYS) begin : used
		assign way_valid[gw] = ic_ent_valid[gw*NSET + ic_index_adr_dly];
		assign way_eq[gw] = (cmp_tag == ic_tag_flat[gw*TW +: TW]);
	end
	else begin : unused
		assign way_valid[gw] = 1'b1;
		assign way_eq[gw] = 1'b0;
	end
end
endgenerate
wire [7:0] way_hit = way_eq & way_valid;
wire ic_hit_any = |way_hit;
assign ic_way_rd = way_hit;

reg [2:0] ic_rr_way;
function [2:0] first_inv;
input [7:0] v;
integer k;
begin
	first_inv = 3'd0;
	for (k = 7; k >= 0; k = k - 1)
		if (~v[k]) first_inv = k;
end
endfunction
wire [2:0] ic_vict_way = (&way_valid) ? ic_rr_way : first_inv(way_valid);
wire ic_vict_valid = way_valid[ic_vict_way];

assign ic_tag_hit_id = ic_hit_any & pc_valid_id & iok;
// btb_spec_fetch (2026-11-12): no refill for a BTB-target fetch whose result
// is discarded (see if_stage)
wire ic_tag_empty_id = ~ic_hit_any & ~ic_vict_valid & pc_valid_id & ~btb_spec_fetch & iok;
wire ic_tag_miss_id = ~ic_hit_any & ic_vict_valid & pc_valid_id & ~btb_spec_fetch & iok;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ic_ent_valid <= { (IWAYS*NSET){ 1'b0 }};
    else if (fencei_cond | start_icflush | rst_pipe)
        ic_ent_valid <= { (IWAYS*NSET){ 1'b0 }};
    else if (ic_tag_wen)
        ic_ent_valid[ic_fill_way_r*NSET + ic_index_adr_dly] <= 1'b1;
end

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ic_rr_way <= 3'd0;
    else if (ic_tag_wen)
        ic_rr_way <= (ic_rr_way == IWAYS-1) ? 3'd0 : ic_rr_way + 3'd1;
end

assign ic_fill_way = 8'd1 << ic_fill_way_r;

// ic state machine

`define ICMS_IDLE 4'b0000
`define ICMS_MEMR 4'b0001
`define ICMS_ICWT 4'b0010
`define ICMS_ICW2 4'b0011
`define ICMS_ICW3 4'b0100
`define ICMS_LDRD 4'b0110
`define ICMS_DEFO 4'b0111
`define ICMS_ITL1 4'b1000 // micro-ITLB miss : registered ITLB result
`define ICMS_IWLK 4'b1001 // ITLB miss : PTW in lsu_stage
`define ICMS_ICRP 4'b1010 // re-check the fetch after the ITLB refill

// Request channel manager state machine
reg [3:0] ic_miss_current;
assign ic_miss_current_w = ic_miss_current;

function [3:0] ic_miss_decode;
input [3:0] ic_miss_current;
input ic_tag_empty_id;
input ic_tag_miss_id;
input ic_rdat_m_valid;
input imiss;
input m_hit_r;
input walk_end;
input ic_hit_ok;     // ICRP : I$ hit or fetch fault (no refill)
input ikill;         // ITL1 / IWLK : the slot was redirected away, no walk
begin
    case(ic_miss_current)
		`ICMS_IDLE: begin
    		casex({imiss, ic_tag_empty_id, ic_tag_miss_id})
				3'b1xx: ic_miss_decode = `ICMS_ITL1;
				3'b01x: ic_miss_decode = `ICMS_MEMR;
				3'b001: ic_miss_decode = `ICMS_MEMR;
				3'b000: ic_miss_decode = `ICMS_IDLE;
				default: ic_miss_decode = `ICMS_DEFO;
    		endcase
		end
		`ICMS_MEMR: begin
    		case(ic_rdat_m_valid)
				1'b1: ic_miss_decode = `ICMS_ICWT;
				1'b0: ic_miss_decode = `ICMS_MEMR;
				default: ic_miss_decode = `ICMS_DEFO;
    		endcase
		end
		`ICMS_ICWT: ic_miss_decode = `ICMS_ICW2;
		`ICMS_ICW2: ic_miss_decode = `ICMS_ICW3;
		`ICMS_ICW3: ic_miss_decode = `ICMS_LDRD;
		`ICMS_LDRD: ic_miss_decode = `ICMS_IDLE;
		`ICMS_ITL1: ic_miss_decode = ikill ? `ICMS_ICW3 : m_hit_r ? `ICMS_ICRP : `ICMS_IWLK;
		`ICMS_IWLK: ic_miss_decode = ikill ? `ICMS_ICW3 : walk_end ? `ICMS_ICRP : `ICMS_IWLK;
		`ICMS_ICRP: ic_miss_decode = ic_hit_ok ? `ICMS_ICW3 : `ICMS_MEMR;
		`ICMS_DEFO: ic_miss_decode = `ICMS_DEFO;
		default:     ic_miss_decode = `ICMS_DEFO;
   	endcase
end
endfunction

// Redirect during an ITLB miss (2026-11-22) : when a jump / trap redirects the
// fetch in the cycle the micro-ITLB miss is found or in ITL1 / IWLK (before
// the walk is accepted), the ID slot is dead : no walk, ITL1 / IWLK end
// through ICW3 -> LDRD like an I$ miss under a jump (if_stage masks the slot
// with jump_under_ic_stall).  A walk for a dead slot must not run : its D$
// stall lasts until the LDRD cycle, so if_stage did not advance pc_id there
// while the I$ already read at the redirect target (the target instruction
// ran with the dead slot's PC; seen in Linux relocate_enable_mmu : sfence.vma,
// ret, the slot after ret missed the micro-ITLB).
//   - interrupts are held while the miss is handled (iwalk_pend -> irq_hold)
//   - a jump / exception from EX can not come in the cycle the walk is
//     accepted : ID is stalled (EX gets bubbles) and an EX instruction held by
//     a D$ stall moves in the cycle the MA access ends (iwalk_go needs no MA
//     access), one cycle before the walk can start
reg iw_kill;
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        iw_kill <= 1'b0;
    else if (rst_pipe | (ic_miss_current == `ICMS_LDRD))
        iw_kill <= 1'b0;
    else if (ipf_clr & (((ic_miss_current == `ICMS_IDLE) & imiss) |
                        (ic_miss_current == `ICMS_ITL1) | (ic_miss_current == `ICMS_IWLK)))
        iw_kill <= 1'b1;
end
assign iwalk_pend = (ic_miss_current == `ICMS_ITL1) | (ic_miss_current == `ICMS_IWLK) |
                    (ic_miss_current == `ICMS_ICRP);

// ICRP : the fetch hits, faults, or is not needed any more -> end the stall
wire icrp_ok = ~(ic_tag_empty_id | ic_tag_miss_id) | imiss;
wire [3:0] ic_miss_next = ic_miss_decode( ic_miss_current, ic_tag_empty_id, ic_tag_miss_id, ic_rdat_m_valid,
                                          imiss, m_hit_r, i_walk_done | i_walk_fault, icrp_ok,
                                          iw_kill & ~i_walk_busy );

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ic_miss_current <= `ICMS_IDLE;
	else if (rst_pipe)
        ic_miss_current <= `ICMS_IDLE;
    else
        ic_miss_current <= ic_miss_next;
end

// for timing
reg [31:2] pc_if_dly;
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        pc_if_dly <= 30'd0;
	else
        pc_if_dly <= pc_if;
end

// current read address keeper (refill : physical address)
wire [31:12] fetch_pa_page = itrans_on ? iu_ppn : pc_if_dly[31:12];
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ic_curric_ent_radr_keeper <= 32'd0;
	else if (rst_pipe)
        ic_curric_ent_radr_keeper <= 32'd0;
	else if ((ic_miss_current == `ICMS_IDLE) & (ic_tag_miss_id | ic_tag_empty_id))
		//ic_curric_ent_radr_keeper <= {pc_if, 2'd0};
		ic_curric_ent_radr_keeper <= {fetch_pa_page, pc_if_dly[11:2], 2'd0};
	else if ((ic_miss_current == `ICMS_IDLE) & imiss)
		// ITLB miss : the index (VA = PA in the page) is used while waiting
		ic_curric_ent_radr_keeper <= {pc_if_dly, 2'd0};
	else if ((ic_miss_current == `ICMS_ICRP) & (ic_tag_miss_id | ic_tag_empty_id))
		ic_curric_ent_radr_keeper <= {iu_ppn, ic_curric_ent_radr_keeper[11:0]};
end

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ic_fill_way_r <= 3'd0;
	else if (((ic_miss_current == `ICMS_IDLE) | (ic_miss_current == `ICMS_ICRP)) & (ic_tag_miss_id | ic_tag_empty_id))
        ic_fill_way_r <= ic_vict_way;
end

// core stall singal

`ifdef SUPPORT_A
assign ic_stall = ((ic_miss_current != `ICMS_LDRD)&(ic_miss_current != `ICMS_IDLE)) | ((ic_tag_miss_id | ic_tag_empty_id | imiss)&(ic_miss_current == `ICMS_IDLE)) | fencei_stall | amo_stall;
`else // SUPPORT_A
assign ic_stall = ((ic_miss_current != `ICMS_LDRD)&(ic_miss_current != `ICMS_IDLE)) | ((ic_tag_miss_id | ic_tag_empty_id | imiss)&(ic_miss_current == `ICMS_IDLE)) | fencei_stall;
`endif // SUPPORT_A
//assign ic_stall = (ic_miss_current != `ICMS_IDLE);
assign ic_sel_tag = ((ic_miss_current != `ICMS_LDRD)&(ic_miss_current != `ICMS_IDLE)) ;
//assign ic_st_ok = (dc_miss_current != `ICMS_MEMR);

// store data write timing
//assign ic_st_wt_id = (ic_miss_current != `ICMS_ICWT);

// load issue timing
reg ic_stall_dly_tmp;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ic_stall_dly_tmp <= 1'b0;
	else
        ic_stall_dly_tmp <= ic_stall;
end

`ifdef SUPPORT_A
assign ic_stall_fin = (ic_miss_current == `ICMS_ICW3) | fencei_stall_fin | amo_stall_fin;
assign ic_stall_fin2 = (ic_miss_current == `ICMS_LDRD) | fencei_stall_fin2 | amo_stall_fin2;
assign ic_stall_dly = ic_stall_dly_tmp | amo_stall_dly;

`else // SUPPORT_A
assign ic_stall_fin = (ic_miss_current == `ICMS_ICW3) | fencei_stall_fin;
assign ic_stall_fin2 = (ic_miss_current == `ICMS_LDRD) | fencei_stall_fin2;
assign ic_stall_dly = ic_stall_dly_tmp;
`endif // SUPPORT_A

// memory write bus i/f signals
//reg icw_start_rq_dc;
//reg icflush_wreq;
//wire [31:0] icw_in_addr_dcflush;

/*
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        icw_start_rq_dc <= 1'b0;
	else
        icw_start_rq_dc <= //ic_ram_ren_all;
end
//wire icw_start_rq_dc = ic_ram_ren_all;

reg [31:0] icw_in_addr_dly;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        icw_in_addr_dly <= 32'd0;
	else
        icw_in_addr_dly <= { pc_if[31:28], ic_tag_radr[27:IWIDTH+2],  pc_if[IWIDTH+1:0] };
end
*/

//assign icw_start_rq = icw_start_rq_dc | icflush_wreq;

//assign icw_in_idsk = 16'd0;

//assign icw_in_addr = icflush_running ? icw_in_addr_dcflush : { pc_if[31:28], ic_tag_radr[27:IWIDTH+2],  pc_if[IWIDTH+1:0] };
//assign icw_in_addr = icflush_running ? icw_in_addr_dcflush : icw_in_addr_dly;

//assign icw_in_data = ic_ram_rdata_all;

// memory read bus i/f signals

wire ic_memr_stat = (ic_miss_current == `ICMS_MEMR);
reg ic_memr_stat_dly;
reg ic_memr_stat_dly2;
reg ic_memr_stat_dly3; // just debug test

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        ic_memr_stat_dly <= 1'b0;
        ic_memr_stat_dly2 <= 1'b0;
        ic_memr_stat_dly3 <= 1'b0;
	end
	else begin
        ic_memr_stat_dly <= ic_memr_stat;
        ic_memr_stat_dly2 <= ic_memr_stat_dly;
        ic_memr_stat_dly3 <= ic_memr_stat_dly2;
	end
end

//assign icr_start_rq = ic_memr_stat & ~ic_memr_stat_dly;
assign icr_start_rq = ic_memr_stat_dly2 & ~ic_memr_stat_dly3;

//assign ic_rin_addr = { pc_if, 2'd0 } ;
assign ic_rin_addr = ic_curric_ent_radr_keeper;


// to MA
//assign ic_ram_wdata_all = rdat_m_data;
//assign ic_ram_radr_all = icflush_running ? icflush_cntr : pc_if[IWIDTH+1:4];
assign ic_ram_wadr_all = ic_curric_ent_radr_keeper[IWIDTH+1:4];
//assign ic_ram_wen_all = rdat_m_valid;
//assign ic_ram_ren_all = ((dc_miss_current == `ICMS_IDLE) & (dc_miss_next == `ICMS_MEMW)) | icflush_running;

//tag write address
assign ic_tag_wadr = ic_curric_ent_radr_keeper[27:IWIDTH+2];
assign ic_index_wadr = ic_curric_ent_radr_keeper[IWIDTH+1:4];
assign ic_tag_wen =  ic_rdat_m_valid;

/*
// IC flush
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        //dcflush_cntr <= 9'd0;
        icflush_cntr <= { (IWIDTH-3){ 1'b0 }};
	else if ( start_dcflush )
        icflush_cntr <= {9{1'b1}};
	else if ((icflush_cntr >  {(IWIDTH-3){ 1'b0 }}) & icw_finish_wresp)
        icflush_cntr <= icflush_cntr -  {{ (IWIDTH-4){ 1'b0 }}, 1'b1};
end

reg [IWIDTH+1:4] icflush_cntr_dly;
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        icflush_cntr_dly <= { (IWIDTH-3){ 1'b0 }};
	else
        icflush_cntr_dly <= icflush_cntr;
end

wire icflush_cntr_not0 = (dcflush_cntr != { (IWIDTH-3){ 1'b0 }});
reg icflush_cntr_not0_dly;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
		dcflush_cntr_not0_dly <= 1'b0;
	else
		dcflush_cntr_not0_dly <= icflush_cntr_not0;
end

assign icflush_running = icflush_cntr_not0 | icflush_cntr_not0_dly;

wire icflush_wreq_pre = icflush_running & (dcflush_cntr_dly != icflush_cntr_not0_dly);

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
		dcflush_wreq <= 1'b0;
	else
		dcflush_wreq <= icflush_wreq_pre;
end

assign icw_in_addr_dcflush = { 4'd0, ic_tag_radr[27:IWIDTH+2],  icflush_cntr_dly, 4'd0 };
*/


endmodule
