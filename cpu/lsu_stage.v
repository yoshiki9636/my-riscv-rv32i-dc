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
	#(parameter DWIDTH = 14)
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
	// reset pipeline
	input rst_pipe,

	// FPGA (2026-08-27): registered mon taps -> cpu_top -> icr_start_rq_probe.
	// (Restored 2026-09-06 - a git checkout during an unrelated revert had
	// dropped these uncommitted ports; cpu_top.v connects all six.)
	output [15:0] dcflush_cntr_mon,
	output [3:0]  dc_miss_current_mon,
	output        dc_tag_miss_ma_mon,
	output        dc_tag_empty_ma_mon,
	output [15:0] dc_retry_repeat_cntr_mon,
	output [31:0] current_radr_keeper_mon

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

reg [DWIDTH+2:4] dcflush_cntr;
reg dc_stall_dly;
reg [31:0] current_radr_keeper;
// tag ram
wire dc_sel_tag; //=((dc_miss_current != `DCMS_LDRD)&(dc_miss_current != `DCMS_IDLE)&(dc_miss_current != `DCMS_MEMW)) ;
reg [27:DWIDTH+2] dc_tag_adr_ma;
//wire [27:DWIDTH+2] dc_tag_adr_ex = dc_stall_dly ? current_radr_keeper[27:DWIDTH+2] : rd_data_ex[27:DWIDTH+2];
//wire [27:DWIDTH+2] dc_tag_adr_ex = dc_sel_tag ? current_radr_keeper[27:DWIDTH+2] : rd_data_ex[27:DWIDTH+2];
wire [27:DWIDTH+2] dc_tag_adr_ex = dc_sel_tag ? rd_data_ma[27:DWIDTH+2] : rd_data_ex[27:DWIDTH+2];
wire [DWIDTH+1:4] dc_index_adr = dcflush_running ? dcflush_cntr[DWIDTH+1:4] :
                                 dc_sel_tag ? rd_data_ma[DWIDTH+1:4] : rd_data_ex[DWIDTH+1:4];
                                 //dc_sel_tag ? current_radr_keeper[DWIDTH+1:4] : rd_data_ex[DWIDTH+1:4];
                                 //dc_stall_dly ? current_radr_keeper[DWIDTH+1:4] : rd_data_ex[DWIDTH+1:4];
wire [27:DWIDTH+2] dc_tag_wadr;
wire [DWIDTH+1:4] dc_index_wadr;
wire [27:DWIDTH+2] dc_tag_radr;
wire dc_cache_valid_ma;
wire tag_wen;

tag_1r1w #(.DRWIDTH(DWIDTH-2)) tag_1r1w (
	.clk(clk),
	.ram_radr(dc_index_adr),
	.ram_rdata(dc_tag_radr),
	.ram_wadr(dc_index_wadr),
	.ram_wdata(dc_tag_wadr),
	.ram_wen(tag_wen)
	);

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dc_tag_adr_ma <= { (27-DWIDTH-1){ 1'b0 }} ;
	else if (rst_pipe)
        dc_tag_adr_ma <= { (27-DWIDTH-1){ 1'b0 }} ;
	//else if (~dc_stall | dc_stall_fin )
	//else if (~dc_stall & ~dc_stall_fin )
	else
		dc_tag_adr_ma <= dc_tag_adr_ex;
end


wire cmd_ldst_ma = (cmd_ld_ma | cmd_st_ma) & (rd_data_ma[31:30] != 2'b11) ;
wire dc_tag_equal = (dc_tag_adr_ma == dc_tag_radr);
assign dc_tag_hit_ma = dc_tag_equal & dc_cache_valid_ma & cmd_ldst_ma;
wire dc_tag_empty_ma = ~dc_cache_valid_ma & cmd_ldst_ma;
wire dc_tag_miss_ma = ~dc_tag_equal & dc_cache_valid_ma & cmd_ldst_ma;

// dirty / valid bits
reg [(2**(DWIDTH-2))-1:0] ent_dirty_bit_ma;
reg [(2**(DWIDTH-2))-1:0] ent_valid_bit_ma;

//wire [27:13] dc_cache_dirty_adr = rd_data_ma[12:4];
//wire [DWIDTH+1:4] dc_cache_dirty_adr = rd_data_ma[DWIDTH+1:4];
//wire [DWIDTH+1:4] dc_cache_dirty_adr = current_radr_keeper[DWIDTH+1:4];
reg [DWIDTH+1:4] dc_index_adr_dly;

//wire [DWIDTH+1:4] dc_cache_dirty_adr = dc_index_adr;
wire [DWIDTH+1:4] dc_cache_dirty_adr = dc_index_adr_dly;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ent_dirty_bit_ma <= { (2**(DWIDTH-2)){ 1'b0 }};
    else if (dc_cache_clr_bits | rst_pipe)
        ent_dirty_bit_ma <= { (2**(DWIDTH-2)){ 1'b0 }};
    else if (dc_cache_wr_ma)
        ent_dirty_bit_ma[dc_cache_dirty_adr] <= 1'b1;
    else if (tag_wen)
        ent_dirty_bit_ma[dc_index_wadr] <= 1'b0;
end

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ent_valid_bit_ma <= { (2**(DWIDTH-2)){ 1'b0 }};
    //else if (dc_cache_clr_bits | rst_pipe)
    else if (dc_cache_clr_bits | dcflush_start | rst_pipe)
        ent_valid_bit_ma <= { (2**(DWIDTH-2)){ 1'b0 }};
    else if (tag_wen)
        //ent_valid_bit_ma[dc_index_wadr] <= 1'b1;
        ent_valid_bit_ma[dc_index_adr_dly] <= 1'b1;
end

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dc_index_adr_dly <= { (DWIDTH-2){ 1'b0 }};
	else if (~dc_stall & ~dc_stall_fin )
        dc_index_adr_dly <= dc_index_adr;
end

wire [DWIDTH+1:4] dc_index_adr_dly_flush = dcflush_running ? dcflush_cntr[DWIDTH+1:4] : dc_index_adr_dly;

//assign dc_cache_valid_ma = ent_valid_bit_ma[dc_cache_dirty_adr];
//wire dc_cache_dirty_ma = ent_dirty_bit_ma[dc_cache_dirty_adr] & dc_tag_miss_ma;
//assign dc_cache_valid_ma = ent_valid_bit_ma[dc_index_adr_dly];
//wire dc_cache_dirty_ma = ent_dirty_bit_ma[dc_index_adr_dly] & (dc_tag_miss_ma | dcflush_running) ;
assign dc_cache_valid_ma = ent_valid_bit_ma[dc_index_adr_dly_flush];
wire dc_cache_dirty_ma = ent_dirty_bit_ma[dc_index_adr_dly_flush] & (dc_tag_miss_ma | dcflush_running) ;

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

// Request channel manager state machine
wire dcflush_nohit_ent;
reg [3:0] dc_miss_current;

function [3:0] dc_miss_decode;
input [3:0] dc_miss_current;
input dc_tag_empty_ma;
input dc_tag_miss_ma;
input dc_cache_dirty_ma;
input dcw_finish_wresp;
input rdat_m_valid;
input dcflush_start;
input dcflush_running;
begin
    case(dc_miss_current)
		`DCMS_IDLE: begin
    		casex({dcflush_start,dc_tag_empty_ma, dc_tag_miss_ma, dc_cache_dirty_ma})
				4'b1xxx: dc_miss_decode = `DCMS_FLSH; // for fencei D$ flush function
				4'b01xx: dc_miss_decode = `DCMS_MEMR;
				4'b000x: dc_miss_decode = `DCMS_IDLE;
				4'b0011: dc_miss_decode = `DCMS_MEMW;
				4'b0010: dc_miss_decode = `DCMS_MEMR;
				default: dc_miss_decode = `DCMS_DEFO;
    		endcase
		end
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
		`DCMS_DCWT: dc_miss_decode = `DCMS_DCW2;
		`DCMS_DCW2: dc_miss_decode = `DCMS_DCW3;
		`DCMS_DCW3: dc_miss_decode = `DCMS_LDRD;
		`DCMS_LDRD: dc_miss_decode = `DCMS_IDLE;
		`DCMS_DEFO: dc_miss_decode = `DCMS_DEFO;
		default:     dc_miss_decode = `DCMS_DEFO;
   	endcase
end
endfunction

wire [3:0] dc_miss_next = dc_miss_decode( dc_miss_current, dc_tag_empty_ma, dc_tag_miss_ma, dc_cache_dirty_ma, dcw_finish_wresp, rdat_m_valid, dcflush_start, dcflush_running );

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
	else if ((dc_miss_current == `DCMS_IDLE) & (dc_tag_miss_ma | dc_tag_empty_ma))
		current_radr_keeper <= rd_data_ma;
end

// FPGA (2026-08-27, restored 2026-09-06 after a git checkout dropped it):
// D$-side livelock-retry detection, mirrors ilu_stage.v's
// ic_retry_repeat_cntr - a genuine single re-miss on the same address is
// vanishingly rare, so hundreds of consecutive repeats is a clean
// corrupted-tag/livelock signature. Feeds icr_start_rq_probe.v's freeze
// trigger alongside the I$ counter (whichever fires first freezes both
// sides' snapshots atomically, for direct cross-comparison).
reg [31:0] dc_prev_miss_addr;
reg [15:0] dc_retry_repeat_cntr;
wire dc_new_miss_entry = (dc_miss_current == `DCMS_IDLE) & (dc_tag_miss_ma | dc_tag_empty_ma);
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		dc_prev_miss_addr    <= 32'd0;
		dc_retry_repeat_cntr <= 16'd0;
	end else if (rst_pipe) begin
		dc_prev_miss_addr    <= 32'd0;
		dc_retry_repeat_cntr <= 16'd0;
	end else if (dc_new_miss_entry) begin
		dc_prev_miss_addr <= rd_data_ma;
		if ((rd_data_ma == dc_prev_miss_addr) & (dc_retry_repeat_cntr != 16'hffff))
			dc_retry_repeat_cntr <= dc_retry_repeat_cntr + 16'd1;
		else if (rd_data_ma != dc_prev_miss_addr)
			dc_retry_repeat_cntr <= 16'd1;
	end
end

// core stall singal
assign dc_stall = ((dc_miss_current != `DCMS_LDRD)&(dc_miss_current != `DCMS_IDLE)) | ((dc_tag_miss_ma | dc_tag_empty_ma)&(dc_miss_current != `DCMS_LDRD));

// FPGA (2026-09-15, ILA diagnostic v3): dbg_repeat_miss_trigger (v2) fired
// immediately/constantly on real hardware - a 4-line D$ makes a single
// coincidental same-address re-miss common in ordinary code, not just the
// bug. Raising the bar to dbg_retry_repeat_cntr_ila>=8 then never fired at
// all across a full boot-to-hang cycle - combined with the earlier
// SYS_RQP_STATUS/RDCNT finding that the fully-hung state has req_rqempty=1
// and zero further dispatches forever, this says the real mechanism is
// NOT a sustained same-address retry loop: at most a handful of repeats
// happen, then something else gets stuck with no further activity at all
// (no new_miss_entry, no tag_wen, ever again). This new counter targets
// exactly that - consecutive cycles of dc_stall=1 with no tag_wen (i.e.
// no refill ever completing to relieve the stall), which a genuine
// multi-cycle refill (even a dirty-writeback one, ~50 cycles worst case
// per project history) will never come close to, but a true permanent
// stall reaches trivially. Pure observational counter (view/trigger only,
// drives no functional logic) - unlike the 2026-09-06 dc_stall_wd attempt
// that caused real timing violations by feeding a similar counter BACK
// into ent_valid_bit_ma, this one fans out only to ILA probe muxes added
// post-synthesis, so it carries none of that risk.
reg [15:0] dc_stall_stuck_cntr;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		dc_stall_stuck_cntr <= 16'd0;
	else if (~dc_stall | tag_wen | rst_pipe)
		dc_stall_stuck_cntr <= 16'd0;
	else if (dc_stall_stuck_cntr != 16'hffff)
		dc_stall_stuck_cntr <= dc_stall_stuck_cntr + 16'd1;
end
(* mark_debug = "true" *) wire [15:0] dbg_dc_stall_stuck_cntr_ila = dc_stall_stuck_cntr;
assign dc_sel_tag = ((dc_miss_current != `DCMS_LDRD)&(dc_miss_current != `DCMS_IDLE)) ;
assign dc_st_ok = ((dc_miss_current != `DCMS_MEMW)&(dc_miss_current != `DCMS_MEMR));

// store data write timing
assign dc_st_wt_ma = (dc_miss_current != `DCMS_DCWT);

// load issue timing
assign dc_stall_fin = (dc_miss_current == `DCMS_DCW3);
assign dc_stall_fin2 = (dc_miss_current == `DCMS_LDRD);
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
        dcw_in_addr_dly <= { rd_data_ma[31:28], dc_tag_radr[27:DWIDTH+2],  rd_data_ma[DWIDTH+1:0] };
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

assign dcr_start_rq = ((dc_miss_current == `DCMS_MEMW)|(dc_miss_current == `DCMS_IDLE)) & (dc_miss_next == `DCMS_MEMR);
assign dcr_rin_addr = rd_data_ma;
assign rqfull_1 = 1'b0;

// to MA
//assign ram_wadr_all = current_radr_keeper[12:4];
assign ram_wdata_all = rdat_m_data;
assign ram_radr_all = dcflush_running ? dcflush_cntr[DWIDTH+1:4] : rd_data_ma[DWIDTH+1:4];
assign ram_wadr_all = current_radr_keeper[DWIDTH+1:4];
assign ram_wen_all = rdat_m_valid;
assign ram_ren_all = (((dc_miss_current == `DCMS_IDLE) |(dc_miss_current == `DCMS_FLSH)) & (dc_miss_next == `DCMS_MEMW));

//tag write address
assign dc_tag_wadr = current_radr_keeper[27:DWIDTH+2];
assign dc_index_wadr = current_radr_keeper[DWIDTH+1:4];
assign tag_wen =  rdat_m_valid;

// FPGA (2026-09-15, ILA diagnostic v2, see project memory
// project_slub_debug_u_axi_hang): v1 of this block hypothesized a specific
// mechanism (dc_index_wadr vs dc_index_adr_dly disagreeing on the exact
// tag_wen cycle) and triggered on that one narrow condition - disproven
// both in simulation (lsu_stage_local_tb.v Test 9, 20525+ checks, never
// fired) and on real hardware (ILA armed across a full cold-boot-to-hang
// cycle, never fired). Rather than keep guessing narrow single-bit
// hypotheses one at a time, v2 triggers on the actual literal symptom
// definition - dc_new_miss_entry (a fresh miss detected from IDLE) whose
// address is the SAME as the immediately preceding miss's address
// (dc_prev_miss_addr, already computed a few lines above for
// dc_retry_repeat_cntr) - i.e. the exact moment a genuine same-address
// re-miss happens, the literal "valid line, tag never matches" event,
// with no assumption about WHY. Captures a much wider signal set around
// it (FSM state, both tag/index copies, the raw tag compare, the full
// valid-bit vector, the refill-data-valid pulse) so the actual mechanism
// can be read directly off the waveform instead of guessed in advance.
(* mark_debug = "true" *) wire dbg_repeat_miss_trigger = dc_new_miss_entry & (rd_data_ma == dc_prev_miss_addr);
// FPGA (2026-09-15): dbg_repeat_miss_trigger alone fires on ANY single
// same-address re-miss, including the harmless, occasional coincidental
// ones a 4-line D$ makes fairly common in ordinary code (e.g. a
// store-then-reload of the same word evicted and refilled twice in a
// row) - confirmed on real hardware as firing immediately/constantly.
// The actual bug is a SUSTAINED run of these (dc_retry_repeat_cntr
// climbing many times in a row, not just reaching 1) - expose the
// counter itself so the ILA trigger can be set to e.g.
// dbg_retry_repeat_cntr_ila >= 8 (Trigger Setup lets you pick a compare
// operator, not just equality, for multi-bit probes) instead of the
// single-event wire above.
(* mark_debug = "true" *) wire [15:0] dbg_retry_repeat_cntr_ila = dc_retry_repeat_cntr;
(* mark_debug = "true" *) wire dbg_valid_tag_index_mismatch = tag_wen & (dc_index_adr_dly != dc_index_wadr);
(* mark_debug = "true" *) wire [DWIDTH+1:4] dbg_index_wadr_ila = dc_index_wadr;
(* mark_debug = "true" *) wire [DWIDTH+1:4] dbg_index_adr_dly_ila = dc_index_adr_dly;
(* mark_debug = "true" *) wire [DWIDTH+1:4] dbg_index_adr_ila = dc_index_adr;
(* mark_debug = "true" *) wire dbg_tag_wen_ila = tag_wen;
(* mark_debug = "true" *) wire dbg_rdat_m_valid_ila = rdat_m_valid;
(* mark_debug = "true" *) wire [3:0] dbg_dc_miss_current_ila = dc_miss_current;
(* mark_debug = "true" *) wire [27:DWIDTH+2] dbg_dc_tag_adr_ma_ila = dc_tag_adr_ma;
(* mark_debug = "true" *) wire [27:DWIDTH+2] dbg_dc_tag_radr_ila = dc_tag_radr;
(* mark_debug = "true" *) wire [(2**(DWIDTH-2))-1:0] dbg_ent_valid_bit_ma_ila = ent_valid_bit_ma;
(* mark_debug = "true" *) wire [31:0] dbg_dc_prev_miss_addr_ila = dc_prev_miss_addr;
(* mark_debug = "true" *) wire dbg_dc_stall_ila = dc_stall;
(* mark_debug = "true" *) wire dbg_dc_tag_hit_ila = dc_tag_hit_ma;
(* mark_debug = "true" *) wire dbg_dc_tag_miss_ila = dc_tag_miss_ma;
(* mark_debug = "true" *) wire [31:0] dbg_rd_data_ma_ila = rd_data_ma;

// DC flush
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dcflush_cntr <= { (DWIDTH-1){ 1'b1 }};
	else if ( dcflush_start )
        dcflush_cntr <= { 1'b0, { (DWIDTH-2){ 1'b1 }}};
	else if ((dcflush_cntr !=  {(DWIDTH-1){ 1'b1 }}) & (dcw_finish_wresp | dcflush_nohit_ent))
        dcflush_cntr <= dcflush_cntr -  {{ (DWIDTH-2){ 1'b0 }}, 1'b1};
end

reg [DWIDTH+1:4] dcflush_cntr_dly;
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dcflush_cntr_dly <= { (DWIDTH-2){ 1'b0 }};
	else
        dcflush_cntr_dly <= dcflush_cntr;
end

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
        dcflush_cntr_ok_r <= (dcflush_cntr != { (DWIDTH-1){ 1'b0 }});
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

assign dcw_in_addr_dcflush = { 4'd0, dc_tag_radr[27:DWIDTH+2],  dcflush_cntr_dly, 4'd0 };

// dc wirte back state signal to IF stage to cancel ic_after_dc

assign dc_wbback_state = (dc_miss_current == `DCMS_MEMW) ; // will remove

// FPGA (2026-08-27, restored 2026-09-06): registered mon taps. current_radr_
// keeper / dcflush_cntr feed D$ tag/index RAM address generation (a tight
// timing path per feedback_register_debug_mon_taps), so every mon output
// gets its own 1-stage buffer here rather than being exposed combinationally.
reg [15:0] dcflush_cntr_mon_r;
reg [3:0]  dc_miss_current_mon_r;
reg        dc_tag_miss_ma_mon_r;
reg        dc_tag_empty_ma_mon_r;
reg [15:0] dc_retry_repeat_cntr_mon_r;
reg [31:0] current_radr_keeper_mon_r;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		dcflush_cntr_mon_r         <= 16'd0;
		dc_miss_current_mon_r      <= 4'd0;
		dc_tag_miss_ma_mon_r       <= 1'b0;
		dc_tag_empty_ma_mon_r      <= 1'b0;
		dc_retry_repeat_cntr_mon_r <= 16'd0;
		current_radr_keeper_mon_r  <= 32'd0;
	end else begin
		// source from the ALREADY-registered dcflush_cntr_dly, not raw
		// dcflush_cntr - raw dcflush_cntr[7] -> D$ tag RAM addr -> ... ->
		// if_stage/pc_if_roll is a known-marginal path and a fresh FF load
		// on it reopens the WNS violation (feedback_register_debug_mon_taps).
		dcflush_cntr_mon_r         <= {{(16-(DWIDTH-2)){1'b0}}, dcflush_cntr_dly};
		dc_miss_current_mon_r      <= dc_miss_current;
		dc_tag_miss_ma_mon_r       <= dc_tag_miss_ma;
		dc_tag_empty_ma_mon_r      <= dc_tag_empty_ma;
		dc_retry_repeat_cntr_mon_r <= dc_retry_repeat_cntr;
		current_radr_keeper_mon_r  <= current_radr_keeper;
	end
end
assign dcflush_cntr_mon         = dcflush_cntr_mon_r;
assign dc_miss_current_mon      = dc_miss_current_mon_r;
assign dc_tag_miss_ma_mon       = dc_tag_miss_ma_mon_r;
assign dc_tag_empty_ma_mon      = dc_tag_empty_ma_mon_r;
assign dc_retry_repeat_cntr_mon = dc_retry_repeat_cntr_mon_r;
assign current_radr_keeper_mon  = current_radr_keeper_mon_r;

endmodule
