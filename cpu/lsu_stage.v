/*
 * My RISC-V RV32I CPU
 *   FPGA LED output Module for Tang Premier
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module lsu_stage
	#(parameter DWIDTH = 14,
	  parameter DWAYS = 1)  // D$ ways : 1 / 2 / 4 / 8 (2026-11-22)
	(
	input clk,
	input rst_n,

	input [31:0] rd_data_ex,
	input [31:0] rd_data_ma,
	input cmd_ld_ma,
	input cmd_st_ma,
	input jmp_purge_ma,

    // to MA
    output [DWIDTH-3:0] ram_radr_all,
    input [127:0] ram_rdata_all,
    output ram_ren_all,
    output [DWIDTH-3:0] ram_wadr_all,
    output [127:0] ram_wdata_all,
    output ram_wen_all,
    output dc_stall_fin2,
    output dc_stall_fin,
    output dc_st_ok,
	output dc_wb_mask,
	// DC controls
	output dc_tag_hit_ma,
	output [7:0] dc_way_hit_ma,   // D$ ways : store write enable per way (2026-11-22)
	output [7:0] dc_way_rd,       // way that hits for the current access (data RAM read select)
	output [7:0] dc_fill_way,     // refill write way (one hot, with ram_wen_all)
	output reg [2:0] dc_rdall_way,// way of ram_rdata_all (victim / flush write back), registered
	output dc_st_wt_ma,
	input dc_cache_wr_ma,
	input dc_cache_clr_bits,
	output dc_stall,
	// tiny AXI wirte bus i/f
	output dcw_start_rq,
	output [31:0] dcw_in_addr,
	output [15:0] dcw_in_mask,
	output [127:0] dcw_in_data,
	input dcw_finish_wresp,
	// tiny AXI read bus i/f
	output dcr_start_rq,
	output [31:0] dcr_rin_addr,
	output rqfull_1,
	input [127:0] rdat_m_data,
	input rdat_m_valid,
	input finish_mrd,
	// DC flush
	input fencei_condition_ex,
	output fencei_dcflush_end,
	input start_dcflush,
	output dcflush_running,
	// to IF
	output dc_wbback_state,
	// MMU (Sv32 DTLB + PTW, 2026-11-22)
	input trans_on,             // data address translation enabled (CSR : satp.MODE & MPRV & MPP!=M)
	input [19:0] satp_ppn,      // root page table PPN (PA is 32bit : PPN[19:0])
	input mmu_priv_u,           // effective privilege of the data access is U (else S)
	input mmu_sum,              // mstatus.SUM
	input mmu_mxr,              // mstatus.MXR
	input cmd_amold_ma,         // MA access is the load phase of an AMO (checked as a store)
	input tlb_flush,            // sfence.vma
	input [31:0] dc_rdata_raw,  // data RAM read data (1 word) : PTE
	output ptw_rd_sel,          // data RAM read address <- ptw_pa (PTE read)
	output [31:0] ptw_pa,       // PTE physical address
	output [31:0] pa_ma,        // physical address of the MA access
	output mmu_ok_ma,           // MA access is translated and allowed (1 when trans_on = 0)
	output io_ok_ma,            // MA I/O access may be issued in this cycle
	output pf_exc,              // page fault : take the trap in this cycle (~stall)
	output pf_store,            // page fault type 1 : store/AMO (15) 0 : load (13)
	// reset pipeline
	input rst_pipe

	);
//
// flush function

wire dcflush_start_raw = fencei_condition_ex | start_dcflush;

// FPGA FIX (2026-07-19): the dc_miss FSM only samples dcflush_start in
// DCMS_IDLE, but a fence.i can execute exactly on a DCMS_LDRD cycle
// (dc_stall is low there, and a fence.i frozen in EX behind a missing
// load/store - e.g. patch_text's store followed by fence.i - resumes on
// that very cycle).  The start pulse was silently dropped: no flush, no
// fencei_dcflush_end, no fencei_cond - and with ex_stage's new
// fencei_wb_purge that also means the purge latch never clears and the
// CPU wedges with every writeback masked.  Latch the request and replay
// it when the FSM reaches IDLE (MEMW/MEMR states are unreachable here
// because dc_stall blocks fence.i from executing during them).
reg dcflush_pend;
wire [3:0] dc_miss_current_w;

// 4'b0000 = DCMS_IDLE (macro is defined further down in this file)
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dcflush_pend <= 1'b0;
    else if (dc_miss_current_w == 4'b0000)
        dcflush_pend <= 1'b0;
    else if (dcflush_start_raw)
        dcflush_pend <= 1'b1;
end

wire dcflush_start = dcflush_start_raw |
                     (dcflush_pend & (dc_miss_current_w == 4'b0000));

// { done, way, index } (way : WBITS bits, none when DWAYS = 1)
reg [DWIDTH-2+((DWAYS >= 8) ? 3 : (DWAYS >= 4) ? 2 : (DWAYS >= 2) ? 1 : 0):0] dcflush_cntr;
reg dc_stall_dly;
reg [31:0] current_radr_keeper;

// ---------------------------------------------------------------------------
// MMU (Sv32, 2026-11-22)
//   DTLB lookup in MA with the VA (rd_data_ma).  The D$ is VIPT : its index
//   (VA[DWIDTH+1:4], inside the 4KB page offset when DWIDTH <= 10) is issued
//   in EX as before, and the tag RAM output is compared in MA with the PA
//   from the DTLB.
//   TLB miss  : the PTW runs inside the D$ miss state machine (PTRD/PTCK/PTDT)
//               and reads the PTEs THROUGH the D$ (coherent with the stores
//               the OS made to the page table).  After a fill, RPRD/RPCK
//               replay the MA access (tag re-read) and the normal path
//               (hit -> DCW3/LDRD, miss -> MEMR/MEMW) finishes it.
//   page fault: FALT (stall, dc_stall_fin) -> PFX (no stall, pf_exc).  pf_exc
//               joins g_exception in ex_stage : the younger instruction in EX
//               is purged, mepc = pc_ma, the MA access is masked.
//   trans_on = 0 : pa = va, every MMU term is inactive (same behavior as before).
// ---------------------------------------------------------------------------
reg ptw_act;
reg ptw_lvl;
reg [31:0] ptw_pa_r;
wire [3:0] dc_miss_current_m; // = dc_miss_current (state macros are defined below)

wire st_idle_m = (dc_miss_current_m == 4'b0000); // DCMS_IDLE
wire st_ldrd_m = (dc_miss_current_m == 4'b0110); // DCMS_LDRD
wire st_ptck_m = (dc_miss_current_m == 4'b1010); // DCMS_PTCK
wire st_rprd_m = (dc_miss_current_m == 4'b1100); // DCMS_RPRD
wire st_pfx_m  = (dc_miss_current_m == 4'b1111); // DCMS_PFX

wire cmd_ldst_raw = cmd_ld_ma | cmd_st_ma;
wire is_store_ma = cmd_st_ma | cmd_amold_ma;
wire mmu_need = trans_on & cmd_ldst_raw;
wire tlb_hit;
wire tlb_perm_ok;
wire tlb_pa_io;
wire [31:12] tlb_pa;
wire tlb_fill;
wire [31:0] pte = dc_rdata_raw;

dtlb #(.DWIDTH(DWIDTH)) dtlb (
	.clk(clk),
	.rst_n(rst_n),
	.va(rd_data_ma[31:12]),
	.is_store(is_store_ma),
	.priv_u(mmu_priv_u),
	.sum(mmu_sum),
	.mxr(mmu_mxr),
	.hit(tlb_hit),
	.perm_ok(tlb_perm_ok),
	.pa_io(tlb_pa_io),
	.pa(tlb_pa),
	.fill(tlb_fill),
	.fill_vpn(rd_data_ma[31:12]),
	.fill_mega(ptw_lvl),
	.fill_ppn(pte[29:10]),
	.fill_flags({ pte[7], pte[4], pte[3], pte[2], pte[1] }), // D U X W R
	.flush(tlb_flush)
	);

wire mmu_ok = ~mmu_need | (tlb_hit & tlb_perm_ok);
wire mmu_miss = mmu_need & ~tlb_hit;
wire mmu_fault = mmu_need & tlb_hit & ~tlb_perm_ok;

assign pa_ma = trans_on ? { tlb_pa, rd_data_ma[11:0] } : rd_data_ma;
wire pa_is_io = trans_on ? tlb_pa_io : (rd_data_ma[31:30] == 2'b11);
assign mmu_ok_ma = mmu_ok;
// I/O : issue only once (IDLE or LDRD) when the access went through the PTW
assign io_ok_ma = ~trans_on | (mmu_ok & (st_idle_m | st_ldrd_m));

// address of the current D$ access (PTE read while the PTW runs)
wire [31:0] acc_adr = ptw_act ? ptw_pa_r : pa_ma;
wire [DWIDTH+1:4] acc_idx = ptw_act ? ptw_pa_r[DWIDTH+1:4] : rd_data_ma[DWIDTH+1:4];
assign ptw_pa = ptw_pa_r;
assign ptw_rd_sel = st_ptck_m;

// PTE decode (PTDT state)
wire pte_v = pte[0];
wire pte_r = pte[1];
wire pte_w = pte[2];
wire pte_x = pte[3];
wire pte_a = pte[6];
wire pte_invalid = ~pte_v | (~pte_r & pte_w);
wire pte_leaf = pte_r | pte_x;
wire pte_mis = ptw_lvl & (pte[19:10] != 10'd0); // misaligned megapage
wire pte_fill = ~pte_invalid & pte_leaf & ~pte_mis & pte_a;
wire pte_next = ~pte_invalid & ~pte_leaf & ptw_lvl;
wire ptw_bad_adr = ptw_pa_r[31]; // page table must be in DRAM

assign pf_exc = st_pfx_m;
assign pf_store = is_store_ma;

// ---------------------------------------------------------------------------
// D$ : DWAYS way set associative (2026-11-22)
//   DWAYS = 1 / 2 / 4 / 8 (fpga_top FT_DWAYS).  DWAYS = 1 is the original
//   direct mapped D$ (same behavior, cycle exact).
//   1 way = 2^(DWIDTH+2) bytes (DWIDTH = 10 : 4KB / way)
//   index = VA[DWIDTH+1:4].  With the MMU it must be inside the 4KB page
//   offset (DWIDTH <= 10) so that the D$ can be VIPT without aliases; when
//   DWIDTH > 10 the MMU is disabled (cpu_top MMU_EN).  tag = PA[27:DWIDTH+2].
//   refill way : the first invalid way, else round robin (rr_way)
//   valid / dirty : per way and index (flattened : way * NSET + index)
//   flush (fence.i) : every (way, index) is visited by dcflush_cntr
//   way vectors on the ports are 8 bit (bits >= DWAYS are 0), way numbers 3 bit
// ---------------------------------------------------------------------------
localparam TW = 26 - DWIDTH;              // tag width
localparam NSET = 2**(DWIDTH-2);          // sets
localparam WBITS = (DWAYS >= 8) ? 3 : (DWAYS >= 4) ? 2 : (DWAYS >= 2) ? 1 : 0;

wire dc_sel_tag;
wire [DWIDTH+1:4] dcf_idx;                // flush counter : index
wire [2:0] dcf_way;                       // flush counter : way
// MMU (2026-11-22): the MA tag is taken directly from the MA address
// (rd_data_ma / DTLB PA / PTE address) instead of the registered EX address
// (dc_tag_adr_ma).  It was the same value in every state that uses it.
wire [DWIDTH+1:4] dc_index_adr = dcflush_running ? dcf_idx :
                                 dc_sel_tag ? acc_idx : rd_data_ex[DWIDTH+1:4];
wire [27:DWIDTH+2] dc_tag_wadr;
wire [DWIDTH+1:4] dc_index_wadr;
wire tag_wen;
reg [2:0] fill_way_r;                     // refill way (latched with current_radr_keeper)
wire [DWAYS*TW-1:0] dc_tag_flat;

genvar gw;
generate
for (gw = 0; gw < DWAYS; gw = gw + 1) begin : dtag
tag_1r1w #(.DRWIDTH(DWIDTH-2)) tag_1r1w (
	.clk(clk),
	.ram_radr(dc_index_adr),
	.ram_rdata(dc_tag_flat[gw*TW +: TW]),
	.ram_wadr(dc_index_wadr),
	.ram_wdata(dc_tag_wadr),
	.ram_wen(tag_wen & (fill_way_r == gw))
	);
end
endgenerate

function [TW-1:0] tag_sel;
input [2:0] w;
input [DWAYS*TW-1:0] tags;
integer k;
begin
	tag_sel = tags[TW-1:0];
	for (k = 1; k < DWAYS; k = k + 1)
		if (w == k) tag_sel = tags[k*TW +: TW];
end
endfunction

// dirty / valid bits
reg [DWAYS*NSET-1:0] ent_dirty;
reg [DWAYS*NSET-1:0] ent_valid;
reg [DWIDTH+1:4] dc_index_adr_dly;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dc_index_adr_dly <= { (DWIDTH-2){ 1'b0 }};
	// MMU (2026-11-22): PTE read / replay of the MA access
	else if (dc_miss_current_m == 4'b1001) // DCMS_PTRD
        dc_index_adr_dly <= ptw_pa_r[DWIDTH+1:4];
	else if (st_rprd_m)
        dc_index_adr_dly <= rd_data_ma[DWIDTH+1:4];
	else if (~dc_stall & ~dc_stall_fin )
        dc_index_adr_dly <= dc_index_adr;
end

// MMU (2026-11-22)
//   cmd_ldst_ma : D$ access of this cycle
//     PTW running : PTE read (PTCK state only)
//     otherwise   : MA load/store to a cacheable PA, translated and allowed.
//                   RPRD (tag not yet re-read) and PFX (faulting access) are masked.
wire ptw_pseudo = st_ptck_m;
wire cmd_ldst_ma = ptw_act ? ptw_pseudo :
                   (cmd_ldst_raw & ~pa_is_io & mmu_ok & ~st_rprd_m & ~st_pfx_m);
wire [27:DWIDTH+2] cmp_tag = ptw_act ? ptw_pa_r[27:DWIDTH+2] :
                             trans_on ? tlb_pa[27:DWIDTH+2] : rd_data_ma[27:DWIDTH+2];

wire [DWIDTH+1:4] vidx = dcflush_running ? dcf_idx : dc_index_adr_dly;
wire [7:0] way_valid;
wire [7:0] way_dirty;
wire [7:0] way_eq;
generate
for (gw = 0; gw < 8; gw = gw + 1) begin : wayv
	if (gw < DWAYS) begin : used
		assign way_valid[gw] = ent_valid[gw*NSET + vidx];
		assign way_dirty[gw] = ent_dirty[gw*NSET + vidx];
		assign way_eq[gw] = (cmp_tag == dc_tag_flat[gw*TW +: TW]);
	end
	else begin : unused
		assign way_valid[gw] = 1'b1; // never chosen as an empty way
		assign way_dirty[gw] = 1'b0;
		assign way_eq[gw] = 1'b0;
	end
end
endgenerate
wire [7:0] way_hit = way_eq & way_valid;
wire dc_hit_any = |way_hit;

// refill way : the first invalid way, else round robin
reg [2:0] rr_way;
function [2:0] first_inv;
input [7:0] v;
integer k;
begin
	first_inv = 3'd0;
	for (k = 7; k >= 0; k = k - 1)
		if (~v[k]) first_inv = k;
end
endfunction
wire [2:0] vict_way = (&way_valid) ? rr_way : first_inv(way_valid);
wire vict_valid = way_valid[vict_way];
wire vict_dirty = way_dirty[vict_way];
wire [27:DWIDTH+2] vict_tag = tag_sel(vict_way, dc_tag_flat);

assign dc_tag_hit_ma = dc_hit_any & cmd_ldst_ma & ~ptw_act;
assign dc_way_hit_ma = way_hit & { 8{ cmd_ldst_ma & ~ptw_act }};
assign dc_way_rd = way_hit;
wire ptw_hit = dc_hit_any & ptw_pseudo;
wire dc_tag_empty_ma = ~dc_hit_any & ~vict_valid & cmd_ldst_ma;
wire dc_tag_miss_ma = ~dc_hit_any & vict_valid & cmd_ldst_ma;
wire dc_cache_dirty_ma = dcflush_running ? way_dirty[dcf_way] : (vict_dirty & dc_tag_miss_ma);

wire dcf_wb_issue; // flush : write back of (dcf_way, dcf_idx) is issued

integer wi;
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ent_dirty <= { (DWAYS*NSET){ 1'b0 }};
    else if (dc_cache_clr_bits | rst_pipe)
        ent_dirty <= { (DWAYS*NSET){ 1'b0 }};
    else if (dc_cache_wr_ma) begin
        for (wi = 0; wi < DWAYS; wi = wi + 1)
            if (dc_way_hit_ma[wi]) ent_dirty[wi*NSET + dc_index_adr_dly] <= 1'b1;
    end
    else if (tag_wen)
        ent_dirty[fill_way_r*NSET + dc_index_wadr] <= 1'b0;
    // DWAYS > 1 : a flushed (invalid) line does not stay dirty (DWAYS = 1 keeps
    // the original behavior : the line is written back again by the next flush)
    else if (dcf_wb_issue & (DWAYS > 1))
        ent_dirty[dcf_way*NSET + dcf_idx] <= 1'b0;
end

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ent_valid <= { (DWAYS*NSET){ 1'b0 }};
    else if (dc_cache_clr_bits | dcflush_start | rst_pipe)
        ent_valid <= { (DWAYS*NSET){ 1'b0 }};
    else if (tag_wen)
        ent_valid[fill_way_r*NSET + dc_index_adr_dly] <= 1'b1;
end

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        rr_way <= 3'd0;
    else if (tag_wen)
        rr_way <= (rr_way == DWAYS-1) ? 3'd0 : rr_way + 3'd1;
end

// dc state machine

`define DCMS_IDLE 4'b0000
`define DCMS_MEMW 4'b0001
`define DCMS_MEMR 4'b0010
`define DCMS_DCWT 4'b0011
`define DCMS_DCW2 4'b0100
`define DCMS_DCW3 4'b0101
`define DCMS_LDRD 4'b0110
`define DCMS_DEFO 4'b0111
`define DCMS_FLSH 4'b1000
// MMU (2026-11-22)
`define DCMS_PTRD 4'b1001 // PTW : tag RAM read with the PTE address
`define DCMS_PTCK 4'b1010 // PTW : PTE line hit check / data RAM read (miss -> MEMW/MEMR -> DCWT -> PTRD)
`define DCMS_PTDT 4'b1011 // PTW : PTE decode -> next level / TLB fill / fault
`define DCMS_RPRD 4'b1100 // replay : tag RAM read with the MA address
`define DCMS_RPCK 4'b1101 // replay : MA access check (hit -> DCW3 -> LDRD)
`define DCMS_FALT 4'b1110 // page fault (last stall cycle)
`define DCMS_PFX  4'b1111 // page fault : trap is taken (no stall)

// Request channel manager state machine
wire dcflush_nohit_ent;
reg [3:0] dc_miss_current;
assign dc_miss_current_m = dc_miss_current;

function [3:0] dc_miss_decode;
input [3:0] dc_miss_current;
input dc_tag_empty_ma;
input dc_tag_miss_ma;
input dc_cache_dirty_ma;
input dcw_finish_wresp;
input rdat_m_valid;
input dcflush_start;
input dcflush_running;
input mmu_miss;
input mmu_fault;
input ptw_act;
input ptw_hit;
input ptw_bad_adr;
input pte_fill;
input pte_next;
begin
    case(dc_miss_current)
		`DCMS_IDLE: begin
    		casex({dcflush_start, mmu_fault, mmu_miss, dc_tag_empty_ma, dc_tag_miss_ma, dc_cache_dirty_ma})
				6'b1xxxxx: dc_miss_decode = `DCMS_FLSH; // for fencei D$ flush function
				6'b01xxxx: dc_miss_decode = `DCMS_FALT;
				6'b001xxx: dc_miss_decode = `DCMS_PTRD;
				6'b0001xx: dc_miss_decode = `DCMS_MEMR;
				6'b00000x: dc_miss_decode = `DCMS_IDLE;
				6'b000011: dc_miss_decode = `DCMS_MEMW;
				6'b000010: dc_miss_decode = `DCMS_MEMR;
				default: dc_miss_decode = `DCMS_DEFO;
    		endcase
		end
		`DCMS_PTRD: dc_miss_decode = ptw_bad_adr ? `DCMS_FALT : `DCMS_PTCK;
		`DCMS_PTCK: begin
    		casex({ptw_hit, dc_tag_empty_ma, dc_tag_miss_ma, dc_cache_dirty_ma})
				4'b1xxx: dc_miss_decode = `DCMS_PTDT;
				4'b01xx: dc_miss_decode = `DCMS_MEMR;
				4'b0011: dc_miss_decode = `DCMS_MEMW;
				4'b0010: dc_miss_decode = `DCMS_MEMR;
				default: dc_miss_decode = `DCMS_DEFO;
    		endcase
		end
		`DCMS_PTDT: dc_miss_decode = pte_next ? `DCMS_PTRD :
		                             pte_fill ? `DCMS_RPRD : `DCMS_FALT;
		`DCMS_RPRD: dc_miss_decode = `DCMS_RPCK;
		`DCMS_RPCK: begin
    		casex({mmu_fault, mmu_miss, dc_tag_empty_ma, dc_tag_miss_ma, dc_cache_dirty_ma})
				5'b1xxxx: dc_miss_decode = `DCMS_FALT;
				5'b01xxx: dc_miss_decode = `DCMS_PTRD;
				5'b001xx: dc_miss_decode = `DCMS_MEMR;
				5'b00011: dc_miss_decode = `DCMS_MEMW;
				5'b00010: dc_miss_decode = `DCMS_MEMR;
				5'b0000x: dc_miss_decode = `DCMS_DCW3; // hit / not D$ : DCW3 -> LDRD
				default: dc_miss_decode = `DCMS_DEFO;
    		endcase
		end
		`DCMS_FALT: dc_miss_decode = `DCMS_PFX;
		`DCMS_PFX:  dc_miss_decode = `DCMS_IDLE;
		`DCMS_FLSH: begin
    		casex( {dcflush_running, dc_tag_empty_ma, dc_cache_dirty_ma})
				4'b101: dc_miss_decode = `DCMS_MEMW; // flash this entry
				4'b11x: dc_miss_decode = `DCMS_FLSH; // no flash this entry
				4'b100: dc_miss_decode = `DCMS_FLSH; // no flash this entry
				4'b0xx: dc_miss_decode = `DCMS_IDLE; // end of flush
				default: dc_miss_decode = `DCMS_IDLE;
    		endcase
		end
		`DCMS_MEMW: begin
    		casex({dcw_finish_wresp, dcflush_running})
				2'b11: dc_miss_decode = `DCMS_FLSH;
				2'b10: dc_miss_decode = `DCMS_MEMR;
				2'b0x: dc_miss_decode = `DCMS_MEMW;
				default: dc_miss_decode = `DCMS_DEFO;
    		endcase
		end
		`DCMS_MEMR: begin
    		case(rdat_m_valid)
				1'b1: dc_miss_decode = `DCMS_DCWT;
				1'b0: dc_miss_decode = `DCMS_MEMR;
				default: dc_miss_decode = `DCMS_DEFO;
    		endcase
		end
		`DCMS_DCWT: dc_miss_decode = ptw_act ? `DCMS_PTRD : `DCMS_DCW2; // PTE line filled -> read it again
		`DCMS_DCW2: dc_miss_decode = `DCMS_DCW3;
		`DCMS_DCW3: dc_miss_decode = `DCMS_LDRD;
		`DCMS_LDRD: dc_miss_decode = `DCMS_IDLE;
		`DCMS_DEFO: dc_miss_decode = `DCMS_DEFO;
		default:     dc_miss_decode = `DCMS_DEFO;
   	endcase
end
endfunction

wire [3:0] dc_miss_next = dc_miss_decode( dc_miss_current, dc_tag_empty_ma, dc_tag_miss_ma, dc_cache_dirty_ma, dcw_finish_wresp, rdat_m_valid, dcflush_start, dcflush_running,
                                          mmu_miss, mmu_fault, ptw_act, ptw_hit, ptw_bad_adr, pte_fill, pte_next );

// MMU (2026-11-22) : PTW registers / TLB fill
wire st_ptrd = (dc_miss_current == `DCMS_PTRD);
wire st_ptdt = (dc_miss_current == `DCMS_PTDT);
wire ptw_start = (dc_miss_next == `DCMS_PTRD) &
                 ((dc_miss_current == `DCMS_IDLE) | (dc_miss_current == `DCMS_RPCK));

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        ptw_act <= 1'b0;
        ptw_lvl <= 1'b0;
        ptw_pa_r <= 32'd0;
    end
	else if (rst_pipe) begin
        ptw_act <= 1'b0;
        ptw_lvl <= 1'b0;
    end
	else if (ptw_start) begin
        // level 1 PTE : satp.PPN * 4096 + VPN1 * 4
        ptw_act <= 1'b1;
        ptw_lvl <= 1'b1;
        ptw_pa_r <= { satp_ppn, rd_data_ma[31:22], 2'b00 };
    end
	else if (st_ptdt & pte_next) begin
        // level 0 PTE : PTE.PPN * 4096 + VPN0 * 4
        ptw_lvl <= 1'b0;
        ptw_pa_r <= { pte[29:10], rd_data_ma[21:12], 2'b00 };
    end
	else if ((st_ptdt & ~pte_next) | (st_ptrd & ptw_bad_adr)) begin
        ptw_act <= 1'b0;
    end
end

assign tlb_fill = st_ptdt & pte_fill;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dc_miss_current <= `DCMS_IDLE;
	else if (rst_pipe)
        dc_miss_current <= `DCMS_IDLE;
    else
        dc_miss_current <= dc_miss_next;
end

// mirror for the dcflush_pend block above (declared before the macros)
assign dc_miss_current_w = dc_miss_current;

// current read address keeper

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        current_radr_keeper <= 32'd0;
	else if (rst_pipe)
        current_radr_keeper <= 32'd0;
	else if (((dc_miss_current == `DCMS_IDLE) | (dc_miss_current == `DCMS_PTCK) | (dc_miss_current == `DCMS_RPCK))
	         & (dc_tag_miss_ma | dc_tag_empty_ma))
		current_radr_keeper <= acc_adr; // MMU (2026-11-22): physical address
end

// refill way (4 way D$) : latched with current_radr_keeper
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        fill_way_r <= 3'd0;
	else if (((dc_miss_current == `DCMS_IDLE) | (dc_miss_current == `DCMS_PTCK) | (dc_miss_current == `DCMS_RPCK))
	         & (dc_tag_miss_ma | dc_tag_empty_ma))
        fill_way_r <= vict_way;
end

assign dc_fill_way = 8'd1 << fill_way_r;

// core stall singal
// MMU (2026-11-22): PFX (page fault trap cycle) does not stall, a TLB miss /
// fault of the MA access starts a stall in IDLE
assign dc_stall = ((dc_miss_current != `DCMS_LDRD)&(dc_miss_current != `DCMS_IDLE)&(dc_miss_current != `DCMS_PFX))
                | ((dc_tag_miss_ma | dc_tag_empty_ma | mmu_miss | mmu_fault)&(dc_miss_current == `DCMS_IDLE));

assign dc_sel_tag = ((dc_miss_current != `DCMS_LDRD)&(dc_miss_current != `DCMS_IDLE)&(dc_miss_current != `DCMS_PFX)) ;
assign dc_st_ok = ((dc_miss_current != `DCMS_MEMW)&(dc_miss_current != `DCMS_MEMR));

// store data write timing
assign dc_st_wt_ma = (dc_miss_current != `DCMS_DCWT);

// load issue timing
// MMU (2026-11-22): a page fault ends the stall like a refill (FALT = DCW3,
// PFX = LDRD) so that if_stage sees the same stall-end sequence
assign dc_stall_fin = (dc_miss_current == `DCMS_DCW3) | (dc_miss_current == `DCMS_FALT);
assign dc_stall_fin2 = (dc_miss_current == `DCMS_LDRD) | (dc_miss_current == `DCMS_PFX);
//assign dc_wb_mask = dc_stall_fin2 & cmd_ld_ma & (dc_tag_miss_ma | dc_tag_empty_ma);
assign dc_wb_mask = 1'b0;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dc_stall_dly <= 1'b0;
	else
        dc_stall_dly <= dc_stall;
end

// memory write bus i/f signals
reg dcw_start_rq_dc;
//reg dcflush_wreq;
wire [31:0] dcw_in_addr_dcflush;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dcw_start_rq_dc <= 1'b0;
	else
        dcw_start_rq_dc <= ram_ren_all;
end
//wire dcw_start_rq_dc = ram_ren_all;

reg [31:0] dcw_in_addr_dly;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dcw_in_addr_dly <= 32'd0;
	else
        dcw_in_addr_dly <= { acc_adr[31:28], vict_tag,  acc_adr[DWIDTH+1:0] };
end

//assign dcw_start_rq = dcw_start_rq_dc | dcflush_wreq;
assign dcw_start_rq = dcw_start_rq_dc;

assign dcw_in_mask = 16'd0;

reg dcflush_cntr_ok_dly2;
//assign dcw_in_addr = dcflush_running ? dcw_in_addr_dcflush : { rd_data_ma[31:28], dc_tag_radr[27:DWIDTH+2],  rd_data_ma[DWIDTH+1:0] };
assign dcw_in_addr = (dcflush_running | dcflush_cntr_ok_dly2) ? dcw_in_addr_dcflush : dcw_in_addr_dly;
//assign dcw_in_addr = dcw_in_addr_dly;

assign dcw_in_data = ram_rdata_all;

// memory read bus i/f signals

assign dcr_start_rq = ((dc_miss_current == `DCMS_MEMW)|(dc_miss_current == `DCMS_IDLE)|
                        (dc_miss_current == `DCMS_PTCK)|(dc_miss_current == `DCMS_RPCK)) & (dc_miss_next == `DCMS_MEMR);
assign dcr_rin_addr = acc_adr;
assign rqfull_1 = 1'b0;

// to MA
//assign ram_wadr_all = current_radr_keeper[12:4];
assign ram_wdata_all = rdat_m_data;
assign ram_radr_all = dcflush_running ? dcf_idx : acc_idx;

// way of the line read by ram_ren_all (its data comes 1 cycle later)
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dc_rdall_way <= 3'd0;
	else
        dc_rdall_way <= dcflush_running ? dcf_way : vict_way;
end

assign dcf_wb_issue = dcflush_running & ram_ren_all;
assign ram_wadr_all = current_radr_keeper[DWIDTH+1:4];
assign ram_wen_all = rdat_m_valid;
assign ram_ren_all = (((dc_miss_current == `DCMS_IDLE) |(dc_miss_current == `DCMS_FLSH)|
                       (dc_miss_current == `DCMS_PTCK) |(dc_miss_current == `DCMS_RPCK)) & (dc_miss_next == `DCMS_MEMW));

//tag write address
assign dc_tag_wadr = current_radr_keeper[27:DWIDTH+2];
assign dc_index_wadr = current_radr_keeper[DWIDTH+1:4];
assign tag_wen =  rdat_m_valid;


// DC flush
// D$ ways (2026-11-22) : the counter covers { way, index }
//   CW = number of { way, index } bits, dcflush_cntr[CW] = done (all ones = idle)
localparam CW = DWIDTH - 2 + WBITS;
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dcflush_cntr <= { (CW+1){ 1'b1 }};
	else if ( dcflush_start )
        dcflush_cntr <= { 1'b0, { CW{ 1'b1 }}};
	else if ((dcflush_cntr !=  {(CW+1){ 1'b1 }}) & (dcw_finish_wresp | dcflush_nohit_ent))
        dcflush_cntr <= dcflush_cntr -  {{ CW{ 1'b0 }}, 1'b1};
end

reg [CW:0] dcflush_cntr_dly;
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dcflush_cntr_dly <= { (CW+1){ 1'b0 }};
	else
        dcflush_cntr_dly <= dcflush_cntr;
end

assign dcf_idx = dcflush_cntr[DWIDTH-3:0];
wire [2:0] dcf_way_dly;
generate
if (WBITS == 0) begin : dcf_w0
	assign dcf_way = 3'd0;
	assign dcf_way_dly = 3'd0;
end
else begin : dcf_wn
	assign dcf_way = dcflush_cntr[CW-1:DWIDTH-2];
	assign dcf_way_dly = dcflush_cntr_dly[CW-1:DWIDTH-2];
end
endgenerate

//assign dcflush_cntr_ok = (dcflush_cntr != { (DWIDTH-1){ 1'b1 }});
// FIX (2026-10-27): timing - the all-ones compare above sat at the head of
// the critical path dcflush_cntr -> dcflush_running -> valid-bit mux ->
// dc_stall -> stall -> PC / tag RAM address (WNS -0.06ns with DWIDTH=12).
// Register it instead, tracking dcflush_cntr's next value cycle-exactly:
// reset = all ones (ok=0), dcflush_start = {0,1..1} (ok=1), and a decrement
// reaches all ones only from 0.
reg dcflush_cntr_ok_r;
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dcflush_cntr_ok_r <= 1'b0;
	else if ( dcflush_start )
        dcflush_cntr_ok_r <= 1'b1;
	else if (dcflush_cntr_ok_r & (dcw_finish_wresp | dcflush_nohit_ent))
        dcflush_cntr_ok_r <= (dcflush_cntr != { (CW+1){ 1'b0 }});
end
wire dcflush_cntr_ok = dcflush_cntr_ok_r;

reg dcflush_cntr_ok_dly;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n) begin
		dcflush_cntr_ok_dly <= 1'b0;
		dcflush_cntr_ok_dly2 <= 1'b0;
	end
	else begin
		dcflush_cntr_ok_dly <= dcflush_cntr_ok;
		dcflush_cntr_ok_dly2 <= dcflush_cntr_ok_dly;
	end
end

assign dcflush_running = dcflush_cntr_ok | dcflush_cntr_ok_dly;
//assign fencei_dcflush_end = ~dcflush_cntr_ok & dcflush_cntr_ok_dly;
assign fencei_dcflush_end = ~dcflush_cntr_ok_dly & dcflush_cntr_ok_dly2;

assign dcflush_nohit_ent = (dc_miss_current == `DCMS_FLSH) & (dc_tag_empty_ma | ~dc_cache_dirty_ma);

//assign dcflush_running = dcflush_cntr_not0 | dcflush_cntr_not0_dly;

//wire dcflush_wreq_pre = dcflush_running & dcflush_cntr_not0_dly;

//always @ (posedge clk or negedge rst_n) begin
    //if (~rst_n)
		//dcflush_wreq <= 1'b0;
	//else
		//dcflush_wreq <= dcflush_wreq_pre;
//end

assign dcw_in_addr_dcflush = { 4'd0, tag_sel(dcf_way_dly, dc_tag_flat),  dcflush_cntr_dly[DWIDTH-3:0], 4'd0 };

// dc wirte back state signal to IF stage to cancel ic_after_dc

assign dc_wbback_state = (dc_miss_current == `DCMS_MEMW) ; // will remove


endmodule
