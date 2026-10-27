/*
 * My RISC-V RV32I CPU
 *   CPU Instruction Fetch Stage Module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 * @version		0.2 add ecall
 */

module if_stage
	#(parameter IWIDTH = 14)
	(
	input clk,
	input rst_n,
	// to ID stage
	output [31:0] inst_id,
	output [31:2] pc_id,
	// from EX stage : jmp/br
	input jmp_condition_ex,
	input fencei_cond,
	input [31:2] jmp_adr_ex,
	output [31:2] jmp_adr_if,
	input ecall_condition_ex,
	input mret_condition_ex,
    input interrupt_condition_ex,
    input timer_condition_ex,
    input jump_between_stall,
	input [31:2] csr_mtvec_ex,
	//input cmd_mret_ex,
	input [31:2] csr_mepc_ex,
	input cmd_sret_ex,
	input [31:2] csr_sepc_ex,
	input cmd_uret_ex,
    //input g_interrupt,
    //input g_interrupt_1shot,
	output post_jump_cmd_cond,
	input g_exception,
	// from monitor
	input [IWIDTH+1:2] i_ram_radr,
	output [31:0] i_ram_rdata,
	input [IWIDTH+1:2] i_ram_wadr, // unused
	input [31:0] i_ram_wdata, // unused
	input i_ram_wen, // unused
	input i_read_sel,

	// from dram bus
	input [127:0] ic_rdat_m_data,
	input [15:0] ic_rdat_m_mask, // unused
	input ic_rdat_m_valid,

	// from/to ilu
	input [IWIDTH-3:0] ic_ram_wadr_all,

	output [31:2] pc_if,
	output reg [31:2] pc_id_pre,
	//output pc_valid_id, // currently set to 1'b1

	// other place
	input pc_start,
	input [31:2] start_adr_lat,
	input dc_wbback_state,
	input stall,
	input stall_1shot,
	input stall_dly,
	input stall_ld,
	input stall_ld_ex,
	input rst_pipe,
	input dc_stall_fin,
	input dc_stall_fin2,
	input ic_stall,
	input ic_stall_dly,
	input ic_stall_fin,
	input ic_stall_fin2,
	output reg stall_ld_add,
	//output dc_stall_patch,
	output [31:0] pc_data,

	// ic_dc_overlap_monitor tap (2026-08-09) - new output port only, no
	// functional signal touched; exposes the existing internal
	// cache_miss_current FSM register (see IDST_* defines below) so
	// ic_dc_overlap_monitor.v can count entries/dwell time in the true
	// I$+D$ overlap states without adding any logic inside if_stage.v
	// itself. Same "pure tap" precedent as fwdmon_*/trc_* ports.
	output [3:0] icdcmon_cache_miss_current,

	// pc_hang_probe taps (2026-09-06) - pure taps of the collision-replay
	// latches (all already `reg` here), no functional signal touched. The
	// hang has every stall/miss FSM idle with pc_ex frozen, so by
	// elimination pc_id is pinned by use_collision stuck at 1 (its
	// dc_stall_fin2 clear pulse lost). See pc_hang_probe.v.
	output dbg_use_collision,
	output dbg_jump_under_ic_stall,
	output dbg_use_collision_clear_pending
	);

// valid signal
//assign pc_valid_id = 1'b1; // zantei
//reg [31:2] pc_if;
reg [1:0] post_intr_ecall_exception;
//wire intr_ecall_exception = ecall_condition_ex | g_interrupt | g_exception ;
wire intr_ecall_exception = interrupt_condition_ex | timer_condition_ex;
wire jump_cmd_cond = (jmp_condition_ex | mret_condition_ex | ecall_condition_ex | fencei_cond | cmd_sret_ex | cmd_uret_ex | g_exception) & ~(|post_intr_ecall_exception);

//wire jmp_cond = intr_ecall_exception | ( jump_cmd_cond & ~post_intr_ecall_exception);
wire jmp_cond = intr_ecall_exception | jump_cmd_cond;
wire [31:2] jmp_adr = (intr_ecall_exception | ecall_condition_ex | g_exception) ? csr_mtvec_ex : jmp_adr_if;
                      //mret_condition_ex ? csr_mepc_ex :
                      //cmd_sret_ex ? csr_sepc_ex : jmp_adr_ex;

assign jmp_adr_if = mret_condition_ex ? csr_mepc_ex :
                    fencei_cond ? pc_id - 30'd1 : // retry for self modify code
                    cmd_sret_ex ? csr_sepc_ex : jmp_adr_ex;

reg keep_jmp_between;
reg [31:2] pc_if_between;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		keep_jmp_between <= 1'b0;
	else if (jmp_cond)
		keep_jmp_between <= 1'b0;
	else if (jump_between_stall)
		keep_jmp_between <= 1'b1;
end

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		pc_if_between <= 30'd0;
	else if (jump_between_stall)
		pc_if_between <= jmp_adr;
end

reg use_collision;
reg [31:2] pc_if_pre;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		pc_if_pre <= 30'd0;
	else if (pc_start)
		pc_if_pre <= start_adr_lat;
	//else if (interrupt_condition_ex | timer_condition_ex)
	else if (interrupt_condition_ex | timer_condition_ex)
		pc_if_pre <= jmp_adr;
	else if (keep_jmp_between)
		pc_if_pre <= pc_if_between;
	else if (stall | stall_ld)
		pc_if_pre <= pc_if_pre;	
	else if (jmp_cond)
		pc_if_pre <= jmp_adr;
	else if (ic_stall)
		pc_if_pre <= pc_if_pre;	
	else
		pc_if_pre <= pc_if + 30'd1;
end

reg [31:2] pc_if_roll;

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        pc_if_roll <= 30'd0;
	else if (pc_start)
		pc_if_roll <= start_adr_lat;
	else if (interrupt_condition_ex | timer_condition_ex)
        pc_if_roll <= jmp_adr;
	else if (keep_jmp_between)
		pc_if_roll <= pc_if_between;
	else if (jmp_cond)
        pc_if_roll <= jmp_adr;
	else if (~ic_stall)
        pc_if_roll <= pc_if_pre;
end

//assign pc_if = pc_if_pre;
assign pc_if = ic_stall_dly ? pc_if_roll : pc_if_pre;

//reg [31:2] pc_id_pre;
reg [31:2] pc_collision;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		pc_id_pre <= 30'd0;
	else if (rst_pipe)
		pc_id_pre <= 30'd0;
	else if (ic_stall | stall | stall_ld)
		pc_id_pre <= pc_id_pre;	
	else
		pc_id_pre <= pc_if;
end

wire inst_collision_smpl1;

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        pc_collision <= 30'd0;
	else if (rst_pipe)
        pc_collision <= 30'd0;	
	else if ((stall_1shot & stall_ld_ex)|inst_collision_smpl1)
        pc_collision <= pc_id;
end

assign pc_id = use_collision ?  pc_collision : pc_id_pre;
assign pc_data = {pc_if, 2'd0};

// instruction RAM

//wire [11:0] inst_radr_if; // input
wire [31:0] inst_rdata_id; // output
wire [IWIDTH+1:2] iram_radr;

//assign inst_radr_if = pc_if[IWIDTH+1:2]; // depend on size of iram
assign iram_radr = i_read_sel ? i_ram_radr : pc_if[IWIDTH+1:2] ;
assign i_ram_rdata = inst_rdata_id;

/*
inst_1r1w #(.IWIDTH(IWIDTH)) inst_1r1w (
	.clk(clk),
	.ram_radr(iram_radr),
	.ram_rdata(inst_rdata_id),
	.ram_wadr(i_ram_wadr),
	.ram_wdata(i_ram_wdata),
	.ram_wen(i_ram_wen)
	);
*/
inst_ram #(.IWIDTH(IWIDTH)) inst_ram (
	.clk(clk),
	.rst_n(rst_n),
	.ram_radr_part(iram_radr),
	.ram_rdata(inst_rdata_id),
	// direct write from monitor unsupported
	//.ram_wadr(i_ram_wadr),
	//.ram_wdata(i_ram_wdata),
	//.ram_wen(i_ram_wen),
	.ram_wadr_all(ic_ram_wadr_all),
	.ram_wdata_all(ic_rdat_m_data),
	.ram_wen_all(ic_rdat_m_valid)
	);

reg [31:0] inst_roll;
reg [31:0] inst_collision;
reg [2:0] dc_after_ic;
reg [2:0] ic_after_dc;

wire ic_stall_1shot = ic_stall & ~ic_stall_dly;

wire inst_roll_smpl_tim1;
wire inst_roll_smpl_tim2;
wire inst_roll_smpl_tim3;

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        inst_roll <= 32'h0000_0013;
	else if (rst_pipe)
        inst_roll <= 32'h0000_0013;	
	else if (inst_roll_smpl_tim1|inst_roll_smpl_tim2|inst_roll_smpl_tim3)
        inst_roll <= inst_rdata_id;
	else if (~ic_stall & ( stall_1shot | ~stall_dly & stall_ld ))
        inst_roll <= inst_rdata_id;
end


/*
always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        inst_roll <= 32'h0000_0013;
	else if (rst_pipe)
        inst_roll <= 32'h0000_0013;	
	//else if (ic_stall_1shot & stall_1shot)
        //inst_roll <= inst_rdata_id;
	//else if (ic_stall_fin2 & stall )
	//else if (ic_stall_fin  & stall & (dc_after_ic == 3'b010 ) & (ic_after_dc == 3'b100))
        //inst_roll <= inst_rdata_id;
	else if (ic_stall_fin2 & stall & (dc_after_ic == 3'b010 ) & (ic_after_dc == 3'b100))
        inst_roll <= inst_roll;
	else if (ic_stall_fin  & stall & (dc_after_ic == 3'b010 ) & (ic_after_dc == 3'b011))
        //inst_roll <= inst_rdata_id;
        inst_roll <= inst_roll;
	else if (ic_stall_fin2 & stall & (dc_after_ic == 3'b010 ) & (ic_after_dc == 3'b011))
        inst_roll <= inst_roll;
	else if (ic_stall_fin2 & stall & (dc_after_ic == 3'b010 ))
        inst_roll <= inst_rdata_id;
	else if (ic_stall_fin2 & stall & (dc_after_ic == 3'b110 ) & (ic_after_dc == 3'b100))
        inst_roll <= inst_roll;
	else if (ic_stall_fin2 & stall & (dc_after_ic == 3'b110 ) & (ic_after_dc == 3'b110))
        inst_roll <= inst_roll;
	else if (ic_stall_fin2 & stall & (dc_after_ic == 3'b110 ))
        inst_roll <= inst_rdata_id;
	//else if (ic_stall_fin & stall )
	//else if (ic_stall_fin2 & stall & (dc_after_ic == 3'b010 ) & (ic_after_dc == 3'b010))
        //inst_roll <= inst_rdata_id;
	//else if ( stall_1shot | ~stall_dly & stall_ld )
	//else if ((~ic_stall | (ic_after_dc != 2'b00)) & ( stall_1shot | ~stall_dly & stall_ld ))
	else if (~ic_stall & ( stall_1shot | ~stall_dly & stall_ld ))
        inst_roll <= inst_rdata_id;
end
*/

reg post_jump_cmd_c;
reg post_jump_cmd_c2;
reg stall_ld_ex_smpl;

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
		stall_ld_ex_smpl <= 1'b0;
	else if (~ic_stall)
		stall_ld_ex_smpl <= 1'b0;
	else if (ic_stall & ~ic_stall_dly & ~post_jump_cmd_c & ~post_jump_cmd_c2 & stall_ld_ex)
		stall_ld_ex_smpl <= 1'b1;
end

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        inst_collision <= 32'h0000_0013;
	else if (rst_pipe)
        inst_collision <= 32'h0000_0013;	
	else if ((stall_1shot & stall_ld_ex)|inst_collision_smpl1)
        inst_collision <= inst_roll;
end

// FPGA (2026-07-31): use_collision's clear (dc_stall_fin2) used to be
// unconditional, independent of jump_under_ic_stall. If dc_stall_fin2
// pulsed on a cycle where jump_under_ic_stall was masking inst_id to
// NOP (see the 2026-07-17 fix above), use_collision cleared itself out
// from under the mask before the armed replay (inst_collision) ever
// got a chance to be delivered - a silent loss of a load/store replay,
// confirmed in simulation (if_stage_collision_race_tb.v Scenario A).
// Unlike the stale-I$-fetch case the 2026-07-17 fix covers, this is NOT
// safe to just drop: pc_collision is captured from pc_id (an ID-stage
// PC, generally an earlier/unrelated instruction to whatever mepc ends
// up pointing at), so mret/mepc re-execution does not recover it.
// Fix: defer the clear while masked (use_collision_clear_pending latch
// below remembers it), and apply it the cycle the mask lifts - by then
// (use_collision & ~jump_under_ic_stall) has already delivered
// inst_collision for that same cycle (nonblocking assignment: this
// clear takes effect for the FOLLOWING cycle), so exactly one correct
// post-mask delivery is guaranteed before use_collision finally clears.
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
        use_collision <= 1'b0;
	else if (rst_pipe)
        use_collision <= 1'b0;
	else if (dc_stall_fin2 & ~jump_under_ic_stall)
        use_collision <= 1'b0;
	else if (use_collision_clear_pending & ~jump_under_ic_stall)
        use_collision <= 1'b0;
	else if ((stall_1shot & stall_ld_ex)|inst_collision_smpl1)
        use_collision <= 1'b1;
end

reg use_collision_clear_pending;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
        use_collision_clear_pending <= 1'b0;
	else if (rst_pipe)
        use_collision_clear_pending <= 1'b0;
	else if (use_collision_clear_pending & ~jump_under_ic_stall)
        use_collision_clear_pending <= 1'b0; // consumed this cycle, see use_collision above
	else if (dc_stall_fin2 & jump_under_ic_stall)
        use_collision_clear_pending <= 1'b1; // remember to clear once the mask lifts
end

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        stall_ld_add <= 1'b0;
	else if (rst_pipe)
        stall_ld_add <= 1'b0;
	else if (dc_stall_fin)
        stall_ld_add <= 1'b0;
	else if (stall_1shot & stall_ld_ex )
        stall_ld_add <= 1'b1;
end

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        ic_after_dc <= 3'b000;
	else if (~ic_stall & ~stall)
        ic_after_dc <= 3'b000;
	else if (dc_wbback_state & (ic_after_dc == 3'b001))
        ic_after_dc <= 3'b100;
	else if (dc_wbback_state & (ic_after_dc[1:0] == 2'b10))
        ic_after_dc <= 3'b000;
	else if (ic_stall_1shot & stall_1shot)
        //ic_after_dc <= 3'b010;
        ic_after_dc <= 3'b110;
	//else if (~ic_stall & stall & (ic_after_dc == 3'b000))
	else if (~ic_stall & stall & (ic_after_dc == 3'b000))
        ic_after_dc <= 3'b001;
	else if (ic_stall & stall & (ic_after_dc == 3'b001))
        ic_after_dc <= 3'b010;
	else if (ic_stall & ~stall & (ic_after_dc == 3'b010))
        ic_after_dc <= 3'b011;
	//else
        //ic_after_dc <= 2'b00;
end

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        dc_after_ic <= 3'b000;
	else if (~ic_stall & ~stall)
        dc_after_ic <= 3'b000;
	else if (ic_stall & ~stall & (dc_after_ic == 3'b000))
        dc_after_ic <= 3'b001;
	else if (dc_wbback_state & ic_stall & stall & (ic_after_dc != 3'b000))
        dc_after_ic <= 3'b110;
	else if (ic_stall & stall & (dc_after_ic == 3'b001))
        dc_after_ic <= 3'b010;
	else if (~ic_stall & stall & (dc_after_ic == 3'b010))
        dc_after_ic <= 3'b011;
	else if (~ic_stall & stall & (dc_after_ic == 3'b110))
        dc_after_ic <= 3'b111;
	//else
        //ic_after_dc <= 2'b00;
end

/*
                 //((dc_after_ic == 3'b111) & dc_stall_fin2) ? inst_rdata_id : // 
assign inst_id = ((ic_after_dc == 3'b011) & ic_stall_fin2) ? use_collision ? inst_collision : inst_roll : // for ic stall after dc stall
                 ((dc_after_ic == 3'b011) & dc_stall_fin2) ? use_collision ? inst_collision : inst_roll : // 
                 ((dc_after_ic == 3'b111) & dc_stall_fin2) ? use_collision ? inst_collision : inst_roll : // 
                 ( stall_ld_ex_smpl & ic_stall_fin2) ? inst_roll :
                 //((ic_stall|ic_stall_dly)&dc_stall_fin2) ? inst_roll : // 1shot ok dc stall inside ic stall
                 (ic_stall|ic_stall_dly) ? 32'h0000_0013 : // nop for icache stall
                 use_collision  ?  inst_collision : // for load store btb
                 (stall_dly | stall_ld_ex) ? inst_roll : // for load bypass pattern without store
                 inst_rdata_id; // other condisitons
*/
wire dc_fin_after_ic;
wire ic_fin_after_dc;
wire syn_fin;
reg jump_under_ic_stall;
wire inst_masked_in_icdc_sync_start;
//reg inst_mask_condition_with_jmp_lat;

assign inst_id =
                 //(inst_masked_in_icdc_sync_start | inst_mask_condition_with_jmp_lat) ? 32'h0000_0013 :
                 (inst_masked_in_icdc_sync_start) ? 32'h0000_0013 :
                 // FPGA (2026-07-17): close a remaining hole in the 2026-07-16
                 // "interrupt-during-ic_stall" mask. jump_under_ic_stall forces
                 // NOP so a stale in-flight instruction can't be double-executed
                 // (once into the ISR, again after mret via mepc) — but it sat
                 // BELOW use_collision here, so when a load/store D$-stall replay
                 // (use_collision -> inst_collision/pc_collision) overlapped an
                 // interrupt taken mid-ic_stall, the replayed STORE leaked past
                 // the mask and double-executed (ISR-dependent, narrow overlap =
                 // rare/non-deterministic = the wild/stale-pointer corruption).
                 // Gate the collision replay with ~jump_under_ic_stall so the
                 // redirect mask wins (NOP is safe; the instruction re-runs after
                 // mret from mepc).
                 (use_collision & ~jump_under_ic_stall)  ?  inst_collision : // for load store btb
				 jump_under_ic_stall ?  32'h0000_0013 : // for test
                 dc_fin_after_ic ? inst_roll : //ok
                 ic_fin_after_dc ? inst_roll : //ok
                 (stall_ld_ex_smpl & ic_stall_fin2) ? inst_roll :
                 syn_fin ? 32'h0000_0013 : // nop for icache stall //ok?
                 (ic_stall|ic_stall_dly) ? 32'h0000_0013 : // nop for icache stall //ok
                 (stall_dly | stall_ld_ex) ? inst_roll : // for load bypass pattern without store
                 inst_rdata_id; // other condisitons

// post interrupt / ecall timing
always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        post_intr_ecall_exception <= 2'd0;
	else
        post_intr_ecall_exception <= {post_intr_ecall_exception[0], intr_ecall_exception};
end

// post cump command condition
wire jump_only = jmp_condition_ex | mret_condition_ex | fencei_cond;

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
        post_jump_cmd_c <= 1'b0;
        post_jump_cmd_c2 <= 1'b0;
	end
	else begin
        post_jump_cmd_c <= jump_cmd_cond;
        post_jump_cmd_c2 <= post_jump_cmd_c;
	end
end

reg jump_only_c1;
reg jump_only_c2;

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
        jump_only_c1 <= 1'b0;
        jump_only_c2 <= 1'b0;
	end
	//else if (~stall & ~ic_stall) begin
	else if (~ic_stall_dly) begin
        jump_only_c1 <= jump_only;
        jump_only_c2 <= jump_only_c1;
	end
end

assign post_jump_cmd_cond = jump_only_c1 | jump_only_c2;
//assign post_jump_cmd_cond = post_jump_cmd_c | post_jump_cmd_c2;

// patch for ic_stall & dc_stall

//assign dc_stall_patch = ~ic_stall & (dc_after_ic == 3'd6) & (ic_after_dc == 3'd3);


// icdc stall state machine

`define IDST_IDLE 4'b0000
`define IDST_ISND 4'b0001
`define IDST_ISWD 4'b0010
`define IDST_ISAF 4'b0011
`define IDST_DSNI 4'b0101
`define IDST_DSWI 4'b0110
`define IDST_DSAF 4'b0111
`define IDST_SYWB 4'b1110
`define IDST_SYAI 4'b1111
`define IDST_SYAD 4'b1101

// Request channel manager state machine
reg [3:0] cache_miss_current;

function [3:0] cache_miss_decode;
input [3:0] cache_miss_current;
input ic_stall;
input dc_stall;
begin
    case(cache_miss_current)
		`IDST_IDLE: begin
    		casex({ic_stall, dc_stall})
				2'b11: cache_miss_decode = `IDST_SYWB;
				2'b10: cache_miss_decode = `IDST_ISND;
				2'b01: cache_miss_decode = `IDST_DSNI;
				2'b00: cache_miss_decode = `IDST_IDLE;
				default: cache_miss_decode = `IDST_IDLE;
    		endcase
		end
		`IDST_ISND: begin
    		casex({ic_stall, dc_stall})
				2'b11: cache_miss_decode = `IDST_ISWD;
				2'b10: cache_miss_decode = `IDST_ISND;
				2'b01: cache_miss_decode = `IDST_DSNI;
				2'b00: cache_miss_decode = `IDST_IDLE;
				default: cache_miss_decode = `IDST_IDLE;
    		endcase
		end
		`IDST_ISWD: begin
    		casex({ic_stall, dc_stall})
				2'b11: cache_miss_decode = `IDST_ISWD;
				2'b10: cache_miss_decode = `IDST_ISWD; // not occured
				2'b01: cache_miss_decode = `IDST_DSAF;
				2'b00: cache_miss_decode = `IDST_IDLE; // not occured
				default: cache_miss_decode = `IDST_IDLE;
    		endcase
		end
		`IDST_ISAF: begin
    		casex({ic_stall, dc_stall})
				2'b11: cache_miss_decode = `IDST_ISWD;
				2'b10: cache_miss_decode = `IDST_ISAF;
				2'b01: cache_miss_decode = `IDST_DSNI; // not occuerd
				2'b00: cache_miss_decode = `IDST_IDLE;
				default: cache_miss_decode = `IDST_IDLE;
    		endcase
		end

		`IDST_DSNI: begin
    		casex({ic_stall, dc_stall})
				2'b11: cache_miss_decode = `IDST_DSWI;
				2'b10: cache_miss_decode = `IDST_ISND;
				2'b01: cache_miss_decode = `IDST_DSNI;
				2'b00: cache_miss_decode = `IDST_IDLE;
				default: cache_miss_decode = `IDST_IDLE;
    		endcase
		end
		`IDST_DSWI: begin
    		casex({ic_stall, dc_stall})
				2'b11: cache_miss_decode = `IDST_DSWI;
				2'b10: cache_miss_decode = `IDST_ISAF;
				2'b01: cache_miss_decode = `IDST_DSAF; // not occured but occured
				2'b00: cache_miss_decode = `IDST_IDLE; // not occured
				default: cache_miss_decode = `IDST_IDLE;
    		endcase
		end
		`IDST_DSAF: begin
    		casex({ic_stall, dc_stall})
				2'b11: cache_miss_decode = `IDST_DSWI; // not occured
				2'b10: cache_miss_decode = `IDST_ISAF; // not occured
				2'b01: cache_miss_decode = `IDST_DSAF;
				2'b00: cache_miss_decode = `IDST_IDLE;
				default: cache_miss_decode = `IDST_IDLE;
    		endcase
		end

		`IDST_SYWB: begin
    		casex({ic_stall, dc_stall})
				2'b11: cache_miss_decode = `IDST_SYWB;
				2'b10: cache_miss_decode = `IDST_SYAI;
				2'b01: cache_miss_decode = `IDST_SYAD;
				2'b00: cache_miss_decode = `IDST_IDLE; // not occured
				default: cache_miss_decode = `IDST_IDLE;
    		endcase
		end
		`IDST_SYAI: begin
    		casex({ic_stall, dc_stall})
				2'b11: cache_miss_decode = `IDST_ISWD; // not occured
				2'b10: cache_miss_decode = `IDST_SYAI; 
				2'b01: cache_miss_decode = `IDST_DSNI; // not occured
				2'b00: cache_miss_decode = `IDST_IDLE;
				default: cache_miss_decode = `IDST_IDLE;
    		endcase
		end
		`IDST_SYAD: begin
    		casex({ic_stall, dc_stall})
				2'b11: cache_miss_decode = `IDST_ISWD; // not occured
				2'b10: cache_miss_decode = `IDST_ISND; // not occured 
				2'b01: cache_miss_decode = `IDST_SYAD;
				2'b00: cache_miss_decode = `IDST_IDLE;
				default: cache_miss_decode = `IDST_IDLE;
    		endcase
		end

		default: cache_miss_decode = `IDST_IDLE;
   	endcase
end
endfunction

wire [3:0] cache_miss_next = cache_miss_decode( cache_miss_current, ic_stall, stall );

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        cache_miss_current <= `IDST_IDLE;
    else
        cache_miss_current <= cache_miss_next;
end

assign icdcmon_cache_miss_current = cache_miss_current;

assign dc_fin_after_ic = (cache_miss_current == `IDST_DSAF) & ic_stall_fin2;
assign ic_fin_after_dc = (cache_miss_current == `IDST_ISAF) & ic_stall_fin2;
assign syn_fin         = (cache_miss_current == `IDST_SYAI) & ic_stall_fin2;

assign inst_roll_smpl_tim1 = (cache_miss_next == `IDST_DSNI)&(cache_miss_current == `IDST_IDLE);
assign inst_roll_smpl_tim2 = (cache_miss_next == `IDST_DSAF)&(cache_miss_current == `IDST_ISWD);
assign inst_roll_smpl_tim3 = (cache_miss_next == `IDST_SYAD)&(cache_miss_current == `IDST_SYWB);

assign inst_collision_smpl1 = (cache_miss_next == `IDST_ISWD)&(cache_miss_current == `IDST_ISAF);

assign inst_masked_in_icdc_sync_start = (cache_miss_current == `IDST_SYWB);

// FPGA (2026-09-15, ILA diagnostic, see project memory
// project_slub_debug_u_axi_hang): a live real-hardware read during the
// current hang showed dc_stall=0 and cpu_run_state=1 - i.e. neither the
// D$ (lsu_stage.v) nor the top-level run/quit gate (cpu_status.v) is what
// is actually holding the pipeline. pc_hang_probe's own PC-window freeze
// detection had already located this same hang inside a 5-instruction
// D$-test compare loop (0x457314-0x45733c) - if PC is genuinely replaying
// only a couple of those instructions forever without ever reaching the
// loop-increment/branch further down, that points at this module's own
// cache_miss_current (IDST_*) FSM - specifically the ISWD self-loop
// previously investigated and judged "a safety mechanism, not a bug" in
// 2026-08-09 (project_ic_dc_overlap_monitor) for a DIFFERENT scenario;
// this extreme-thrashing DWIDTH=4 condition may be exactly the case that
// judgment did not cover. dbg_pc_stuck_cntr watches pc_id directly (the
// most upstream, hardest-to-fake indicator of real forward progress) and
// counts consecutive cycles it hasn't changed, independent of dc_stall/
// cpu_run_state/ic_stall entirely - if the CPU is genuinely wedged this
// will climb without bound; if it's just legitimately slow (still making
// occasional real progress) it will keep resetting to 0. Pure
// observational tap, no functional feedback.
//
// FIXED 2026-09-15: this board's reset sequence is reset -> DRAM
// calibration (which scrambles DRAM contents) -> monitor loads the
// kernel image -> monitor issues cpu_start - a necessarily manual,
// human-paced gap exists between reset and cpu_start during which pc_id
// is legitimately static (nothing has started running yet). The counter
// as originally written couldn't tell that apart from a real hang, so it
// always saturated/triggered during this harmless wait, before the real
// test (post cpu_start) ever began. Gated on pc_start (cpu_status.v's
// one-cycle pulse marking the actual start of execution, already wired
// into this module) via a sticky "seen_pc_start" latch - the counter now
// stays at 0 and cannot trigger until the CPU has genuinely started.
reg seen_pc_start;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		seen_pc_start <= 1'b0;
	else if (pc_start)
		seen_pc_start <= 1'b1;
end
reg [31:2] dbg_pc_id_dly;
reg [15:0] dbg_pc_stuck_cntr;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		dbg_pc_id_dly     <= 30'd0;
		dbg_pc_stuck_cntr <= 16'd0;
	end else if (~seen_pc_start) begin
		dbg_pc_id_dly     <= pc_id;
		dbg_pc_stuck_cntr <= 16'd0;
	end else begin
		dbg_pc_id_dly <= pc_id;
		if (pc_id != dbg_pc_id_dly)
			dbg_pc_stuck_cntr <= 16'd0;
		else if (dbg_pc_stuck_cntr != 16'hffff)
			dbg_pc_stuck_cntr <= dbg_pc_stuck_cntr + 16'd1;
	end
end
(* mark_debug = "true" *) wire [15:0] dbg_pc_stuck_cntr_ila = dbg_pc_stuck_cntr;
(* mark_debug = "true" *) wire dbg_seen_pc_start_ila = seen_pc_start;
(* mark_debug = "true" *) wire [31:2] dbg_pc_id_ila = pc_id;
(* mark_debug = "true" *) wire [3:0] dbg_cache_miss_current_ila = cache_miss_current;
(* mark_debug = "true" *) wire dbg_ic_stall_ila = ic_stall;
(* mark_debug = "true" *) wire dbg_use_collision_ila = use_collision;
(* mark_debug = "true" *) wire dbg_jump_under_ic_stall_ila = jump_under_ic_stall;
// FPGA (2026-09-15): real-hardware capture (post cpu_start, genuine hang)
// showed cache_miss_current pinned at IDST_IDLE (0) - the I$/D$ overlap
// FSM is not cycling, ruling out an ISWD-style livelock. pc_id_pre's own
// hold condition is `ic_stall | stall | stall_ld` (see the always block
// a few hundred lines up) - stall(=~cpu_run_state|dc_stall) is already
// confirmed 0, so whichever of ic_stall/stall_ld is stuck at 1 is the
// direct, immediate cause of PC not advancing. ic_stall is already
// tapped above; stall_ld (forwarding.v's load-use hazard stall, an
// input to this module, never tapped before) is the one remaining
// untested candidate in this exact equation.
(* mark_debug = "true" *) wire dbg_stall_ld_ila = stall_ld;
(* mark_debug = "true" *) wire dbg_stall_top_ila = stall;

//wire inst_mask_condition_with_jmp = ((cache_miss_current == `IDST_SYWB)|(cache_miss_current == `IDST_DSWI)) & jmp_condition_ex;

//always @ (posedge clk or negedge rst_n) begin
    //if (~rst_n)
        //inst_mask_condition_with_jmp_lat <= 1'b0;
    //else if (cache_miss_current == `IDST_IDLE)
        //inst_mask_condition_with_jmp_lat <= 1'b0;
    //else if (inst_mask_condition_with_jmp)
        //inst_mask_condition_with_jmp_lat <= 1'b1;
//end

// status latch for jump under ic_stall state
//
// FIX (2026-07-16): also arm this mask for INTERRUPTS taken during
// ic_stall, not only for jump/ecall/mret/fencei (jump_cmd_cond).
// interrupt_condition_ex/timer_condition_ex are gated only by ~stall
// (= ~dc_stall) in ex_stage, so an interrupt CAN be taken in the middle
// of an I$ miss / AMO / DIV stall (all of which are ic_stall here).
// When that happened, the fetch PC was correctly redirected to mtvec
// (see the pc_if_pre priority mux above), but nothing masked the
// in-flight refill's instruction delivery paths (inst_roll /
// dc_fin_after_ic / ic_fin_after_dc), and ex_stage's jmp_purge_ma
// latch is only updated on ~stall & ~ic_stall so the one-cycle
// jmp_purge_ex pulse from the interrupt was lost.  The stale
// instruction at the interrupted PC could then be delivered into ID
// after the refill finished and execute once on the way into the ISR -
// and, since mepc also points at it, execute AGAIN after mret (double
// execution / ghost execution: stores, register increments etc. applied
// twice).  This is the same hazard class as the 2026-07-13
// "purge-target mid-I$-miss" fix, just for the interrupt flavor of the
// redirect instead of the jump flavor.  The mask is cleared by
// ic_stall_fin2 exactly like the jump case, after which fetch resumes
// from the already-redirected pc_if (mtvec).
// FIX (2026-07-19): the fin2 that clears this mask is the COMPOSITE
// ic_stall_fin2_add_div (I$ LDRD | fencei | amo | div/mul fin2 - see
// ilu_stage/cpu_top wiring).  When TWO stall components overlap - e.g.
// a MUL/DIV in EX (its own 2..35-cycle "ic" stall, whose internal
// pipeline advances on ~stall only, i.e. it keeps running through an
// I$ miss) while an I$ refill is in flight on a later fetch - the
// FIRST component to finish pulses the composite fin2 and used to
// clear this mask while the OTHER stall was still running.  If an
// interrupt had been taken during the overlap, the still-pending
// stale-delivery legs (inst_roll / inst_collision, armed when a D$
// stall or load-use replay is also in the mix) were then unmasked at
// the real refill end and delivered a pre-redirect instruction: it
// executed once on the way into the ISR and again after mret (mepc)
// = double execution.  Qualify the clear with ~ic_stall (composite)
// so the mask holds until the WHOLE stall complex is over; in the
// single-component case ic_stall is already low at the fin2 cycle so
// the timing is unchanged.
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        jump_under_ic_stall <= 1'b0;
    else if (ic_stall_fin2 & ~ic_stall)
        jump_under_ic_stall <= 1'b0;
    else if (ic_stall & (jump_cmd_cond | intr_ecall_exception))
        jump_under_ic_stall <= 1'b1;
end

// pc_hang_probe taps - pure taps of already-registered collision latches
assign dbg_use_collision               = use_collision;
assign dbg_jump_under_ic_stall         = jump_under_ic_stall;
assign dbg_use_collision_clear_pending = use_collision_clear_pending;

endmodule

