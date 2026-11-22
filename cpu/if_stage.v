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

// ID-stage static jump prediction (2026-11-12)
//   JAL                       : always taken, target = pc + imm
//   conditional branch (B)    : backward taken / forward not taken (BTFN)
//   JALR                      : not predicted (resolved in EX as before)
// comment out to get the original (EX-resolved only) behavior
//`define ID_JUMP_PRED

// IF-stage dynamic prediction (BTB + 2-bit counter) (2026-11-12)
//   jal / conditional branches : predicted at fetch, taken penalty 0
//   JALR                       : not predicted
// takes priority over ID_JUMP_PRED.  Comment out both for the original.
`define IF_BTB_PRED
// BTB entries = 2**BTB_IDX_W
`define BTB_IDX_W 6

`ifdef IF_BTB_PRED
  `undef ID_JUMP_PRED
`endif

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
	// ID-stage jump prediction
	input pred_hit_ex,
	input pred_block_ex,
	input jmp_regs_flush,
	output reg pred_ex,
	output pred_a_mode,
	input btb_upd_valid,
	input btb_upd_taken,
	input btb_upd_jal,
	input [31:2] btb_upd_pc,
	input [31:2] btb_upd_target,
	input btb_flush,
	output reg btb_spec_fetch, // to ilu_stage : don't start an I$ miss for this fetch
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
	output [31:0] pc_data
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
                    // fencei_cond: retry target (fence.i PC + 4) now comes on jmp_adr_ex
                    // from ex_stage (FIX 2026-10-28) - was pc_id - 30'd1
                    cmd_sret_ex ? csr_sepc_ex : jmp_adr_ex;

// ID-stage jump prediction (defined at the bottom)
wire pred_fire;
wire [31:2] pred_adr;
wire pred_kill_id;
// IF-stage BTB prediction (defined at the bottom)
wire btb_take;          // pc_if is a jal/branch predicted taken
wire [31:2] btb_tgt;    // its target

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

// FIX (2026-10-28): exception traps (g_exception: illegal instruction,
// misaligned load/store) redirect with the same priority as interrupts.
// A misaligned load whose rd is used by the next instruction raises
// stall_ld in the trap cycle, and the stall/stall_ld hold below used to
// win over jmp_cond: the trap updated mepc/mcause but the jump to mtvec
// was lost and execution fell through.  g_exception is only acted on in
// ~stall cycles, as in ex_stage's jmp_purge_ex.
wire exc_redirect = ~stall & g_exception;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		pc_if_pre <= 30'd0;
	else if (pc_start)
		pc_if_pre <= start_adr_lat;
	//else if (interrupt_condition_ex | timer_condition_ex)
	else if (interrupt_condition_ex | timer_condition_ex | exc_redirect)
		pc_if_pre <= jmp_adr;
	else if (keep_jmp_between)
		pc_if_pre <= pc_if_between;
	else if (stall | stall_ld)
		pc_if_pre <= pc_if_pre;	
	else if (jmp_cond)
		pc_if_pre <= jmp_adr;
	else if (pred_fire)
		pc_if_pre <= pred_adr;
	else if (ic_stall)
		pc_if_pre <= pc_if_pre;	
	else
		// next fetch PC : BTB-predicted target or sequential
		pc_if_pre <= btb_take ? btb_tgt : pc_if + 30'd1;
end

reg [31:2] pc_if_roll;

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        pc_if_roll <= 30'd0;
	else if (pc_start)
		pc_if_roll <= start_adr_lat;
	else if (interrupt_condition_ex | timer_condition_ex | exc_redirect)
        pc_if_roll <= jmp_adr;
	else if (keep_jmp_between)
		pc_if_roll <= pc_if_between;
	else if (jmp_cond)
        pc_if_roll <= jmp_adr;
	else if (pred_fire)
        pc_if_roll <= pred_adr;
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

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
        pred_collision <= 1'b0;
	else if (rst_pipe)
        pred_collision <= 1'b0;
	else if ((stall_1shot & stall_ld_ex)|inst_collision_smpl1)
        pred_collision <= pred_id;
end

assign pc_id = use_collision ?  pc_collision : pc_id_pre;

// BTB prediction bit of the ID instruction.  It follows pc_id exactly
// (same enables as pc_id_pre / pc_collision): pc_if_pre takes the
// predicted target in exactly the cycles where pc_id_pre <= pc_if, so
// "pred bit = 1" always means "the instruction after this one in the fetch
// stream is the BTB target".
reg pred_id_pre;
reg pred_collision;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		pred_id_pre <= 1'b0;
	else if (rst_pipe)
		pred_id_pre <= 1'b0;
	else if (ic_stall | stall | stall_ld)
		pred_id_pre <= pred_id_pre;
	else
		pred_id_pre <= btb_take;
end
wire pred_id = use_collision ? pred_collision : pred_id_pre;
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
// FIX (2026-11-22): a D$ flush (fence.i) that starts while the I$ is
// missing sets use_collision (inst_collision_smpl1 on the flush's
// stall_1shot), but the flush ends FLSH -> IDLE without dc_stall_fin2, so
// use_collision was never cleared: after the fence.i retry jump, ID kept
// delivering the stale pc_collision / inst_collision and EX executed it
// every cycle while IF prefetched forever.  Seen with a D$ miss on the
// instruction right before fence.i while the I$ is cold after an earlier
// fence.i (sim_mmu/tests/t05_fencei_dmiss.S, NOFS=2/3).  The retry jump
// (fencei_cond) discards the ID instruction, so the collision state is
// cleared there.
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
        use_collision <= 1'b0;
	else if (rst_pipe)
        use_collision <= 1'b0;
	else if (fencei_cond)
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
	else if (fencei_cond)
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
                 // ID-stage jump prediction: the fall-through instruction
                 // after a predicted jump is replaced by NOP
                 pred_kill_id ? 32'h0000_0013 :
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
// pred_hit_ex : a jump predicted in ID is confirmed in EX.  The next EX slot
// is the killed fall-through NOP, so mepc must be the target (post_pc_ex)
// for an interrupt taken there, same as after a taken jump.
// S/U-mode (2026-11-22) : cmd_sret_ex is ex_stage's sret_jump (qualified sret)
wire jump_only = jmp_condition_ex | mret_condition_ex | cmd_sret_ex | fencei_cond | pred_hit_ex;

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
	// FIX (2026-10-28): record the jump even when it lands on the cycle right
	// after an ic_stall (ic_stall_dly = 1).  The shift below is frozen on
	// that cycle, so such a jump was never seen and an interrupt taken while
	// the jump target was still being fetched (I$ miss) saved the stale
	// pc_ex as mepc instead of post_pc_ex (the target) - the target and the
	// instructions after it were skipped after mret.  fence.i's retry jump
	// (fencei_cond) always lands there, because fencei_stall is part of
	// ic_stall on the cycle before.  Reproduced by
	// rtl_atomic_test/fencei_align_test.S (FENCE_OFS=4, IRQ=1, DWIDTH=12).
	else if (jump_only) begin
        jump_only_c1 <= 1'b1;
        jump_only_c2 <= jump_only_c1;
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


assign dc_fin_after_ic = (cache_miss_current == `IDST_DSAF) & ic_stall_fin2;
assign ic_fin_after_dc = (cache_miss_current == `IDST_ISAF) & ic_stall_fin2;
assign syn_fin         = (cache_miss_current == `IDST_SYAI) & ic_stall_fin2;

assign inst_roll_smpl_tim1 = (cache_miss_next == `IDST_DSNI)&(cache_miss_current == `IDST_IDLE);
assign inst_roll_smpl_tim2 = (cache_miss_next == `IDST_DSAF)&(cache_miss_current == `IDST_ISWD);
assign inst_roll_smpl_tim3 = (cache_miss_next == `IDST_SYAD)&(cache_miss_current == `IDST_SYWB);

assign inst_collision_smpl1 = (cache_miss_next == `IDST_ISWD)&(cache_miss_current == `IDST_ISAF);

assign inst_masked_in_icdc_sync_start = (cache_miss_current == `IDST_SYWB);


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


// ---------------------------------------------------------------------------
// ID-stage static jump prediction (2026-11-12)
//
// Without prediction every taken jal/jalr/branch is resolved in EX and
// costs 2 cycles (jmp_purge_ma / jmp_purge_ma2 cancel the 2 fall-through
// instructions).  Here jal and backward branches are redirected while they
// are in ID:
//
//   cycle t   : J in ID, IF fetches pc+4.  pred_fire -> pc_if_pre/roll <= target
//   cycle t+1 : J in EX (pred_ex=1), pc+4 in ID -> killed (inst_id = NOP)
//   cycle t+2 : NOP in EX, target in ID
//
//   -> taken penalty 2 -> 1 cycle.  A mispredicted branch (predicted taken,
//      not taken) is redirected in EX to pc+4 by the normal jmp_condition_ex
//      path, which purges the 2 younger slots as before (penalty 2).
//
// The fall-through instruction is killed by PC (pred_kill_pc), not by
// timing, so it is also dropped when it is held / replayed by the stall
// machinery (inst_roll / inst_collision) or dropped by an I$ miss.  The kill
// is disarmed when the first instruction with another PC (= the target)
// advances from ID to EX, or by any EX redirect (which purges the younger
// slots itself).
//
// Prediction is only made when the pipeline is quiet (no D$/I$/ld-use
// stall now or in the last 2 cycles, no collision replay, no pending
// redirect window).  In every other case the jump is simply not predicted
// and EX resolves it exactly as before, so the stall corner cases keep their
// original behavior.
// ---------------------------------------------------------------------------
wire [6:0] pd_opc = inst_id[6:0];
wire [2:0] pd_f3  = inst_id[14:12];
wire pd_jal = (pd_opc == 7'b1101111);
wire pd_br  = (pd_opc == 7'b1100011) & (pd_f3[2:1] != 2'b01); // beq/bne/blt/bge/bltu/bgeu
// word offsets ( imm[1] is dropped : same as EX's (pc+imm)[31:2] since pc[1:0]=0 )
wire [31:2] pd_jal_ofs = {{11{inst_id[31]}}, inst_id[31], inst_id[19:12], inst_id[20], inst_id[30:22]};
wire [31:2] pd_br_ofs  = {{19{inst_id[31]}}, inst_id[31], inst_id[7], inst_id[30:25], inst_id[11:9]};
wire pd_br_back = inst_id[31]; // negative offset = backward branch
wire [31:2] pd_ofs = pd_jal ? pd_jal_ofs : pd_br_ofs;
assign pred_adr = pc_id + pd_ofs;
// target == pc+4 would make the target itself the killed instruction
wire pd_ofs_is_1 = (pd_ofs == 30'd1);

// pipeline busy conditions (now / history)
wire pred_busy_now = stall | stall_dly | stall_ld | stall_ld_ex | stall_ld_add |
                     ic_stall | ic_stall_dly | use_collision | use_collision_clear_pending |
                     jump_under_ic_stall | (cache_miss_current != `IDST_IDLE) |
                     dc_stall_fin | dc_stall_fin2 | ic_stall_fin | ic_stall_fin2 |
                     pc_start | jmp_regs_flush | rst_pipe;
reg [1:0] pred_busy_hist;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		pred_busy_hist <= 2'b11;
	else
		pred_busy_hist <= { pred_busy_hist[0], pred_busy_now };
end

wire pred_quiet = ~pred_busy_now & ~(|pred_busy_hist) &
                  ~pred_block_ex & ~(|post_intr_ecall_exception) &
                  ~keep_jmp_between & ~jump_between_stall & ~exc_redirect;

`ifdef ID_JUMP_PRED
// note: an EX redirect in the same cycle (jmp_cond) has priority in the PC
// muxes and disarms the kill, and the predicted jump itself is purged in EX
// by jmp_purge_ma, so jmp_cond is not needed in this (timing critical) term.
assign pred_fire = pred_quiet & (pd_jal | pd_br & pd_br_back) & ~pd_ofs_is_1;
`else
assign pred_fire = 1'b0;
`endif

// to EX : the jump/branch entering EX was predicted taken
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		pred_ex <= 1'b0;
	else if (rst_pipe)
		pred_ex <= 1'b0;
	else if (~stall)
		pred_ex <= pred_fire | pred_id;
end

// kill the fall-through instruction of a predicted jump
reg pred_kill_armed;
reg [31:2] pred_kill_pc;
wire id_advance = ~stall & ~stall_ld;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		pred_kill_armed <= 1'b0;
	else if (rst_pipe | pc_start | jmp_cond | exc_redirect)
		pred_kill_armed <= 1'b0;
	else if (pred_fire)
		pred_kill_armed <= 1'b1;
	else if (id_advance & (pc_id != pred_kill_pc))
		pred_kill_armed <= 1'b0;
end

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		pred_kill_pc <= 30'd0;
	else if (pred_fire)
		pred_kill_pc <= pc_id + 30'd1;
end

assign pred_kill_id = pred_kill_armed & (pc_id == pred_kill_pc);

// ---------------------------------------------------------------------------
// IF-stage BTB (2026-11-12)
//
// Looked up with pc_if in the fetch cycle.  On a hit with counter[1] = 1 the
// next fetch PC is the stored target (pc_if_pre mux), so a correctly
// predicted taken jal/branch has no penalty.  The prediction bit travels
// with the instruction (pred_id -> pred_ex) and EX checks it:
//   predicted, branch not taken  -> redirect to pc+4 (penalty 2)
//   not predicted, taken         -> redirect to target as before
// Entries are only written for jal/branches that executed in EX, with full
// tags, and the BTB is flushed on fence.i / pc_start / rst_pipe, so a hit is
// always a jal/branch at that PC whose target (pc-relative) is the stored
// one: the target never has to be compared in EX.
// Training is registered once (btb_u_*) to keep EX's branch compare off the
// BTB write path.
// ---------------------------------------------------------------------------
`ifdef IF_BTB_PRED
localparam BTB_W = `BTB_IDX_W;
localparam BTB_N = 1 << BTB_W;

reg [31:BTB_W+2] btb_tag [0:BTB_N-1];
reg [31:2]       btb_tgt_ram [0:BTB_N-1];
reg [1:0]        btb_cnt [0:BTB_N-1];
reg [BTB_N-1:0]  btb_vld;

// lookup (fetch)
wire [BTB_W-1:0] btb_ridx = pc_if[BTB_W+1:2];
wire btb_rhit = btb_vld[btb_ridx] & (btb_tag[btb_ridx] == pc_if[31:BTB_W+2]);
assign btb_take = btb_rhit & btb_cnt[btb_ridx][1];
assign btb_tgt = btb_tgt_ram[btb_ridx];

// training (one cycle after EX)
reg btb_u_v;
reg btb_u_taken;
reg btb_u_jal;
reg [31:2] btb_u_pc;
reg [31:2] btb_u_tgt;
wire btb_clr = btb_flush | pc_start | rst_pipe;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		btb_u_v <= 1'b0;
		btb_u_taken <= 1'b0;
		btb_u_jal <= 1'b0;
		btb_u_pc <= 30'd0;
		btb_u_tgt <= 30'd0;
	end
	else begin
		btb_u_v <= btb_upd_valid & ~btb_clr;
		btb_u_taken <= btb_upd_taken;
		btb_u_jal <= btb_upd_jal;
		btb_u_pc <= btb_upd_pc;
		btb_u_tgt <= btb_upd_target;
	end
end

wire [BTB_W-1:0] btb_widx = btb_u_pc[BTB_W+1:2];
wire btb_whit = btb_vld[btb_widx] & (btb_tag[btb_widx] == btb_u_pc[31:BTB_W+2]);
wire [1:0] btb_wcnt = btb_cnt[btb_widx];
wire [1:0] btb_ncnt = btb_u_jal ? 2'b11 :
                      ~btb_whit ? 2'b10 : // new entry : weakly taken
                      btb_u_taken ? ((btb_wcnt == 2'b11) ? 2'b11 : btb_wcnt + 2'd1) :
                                    ((btb_wcnt == 2'b00) ? 2'b00 : btb_wcnt - 2'd1);
// allocate only on taken, update counters of existing entries
wire btb_we = btb_u_v & (btb_whit | btb_u_taken);

always @ (posedge clk) begin
	if (btb_we) begin
		btb_tag[btb_widx] <= btb_u_pc[31:BTB_W+2];
		btb_tgt_ram[btb_widx] <= btb_u_tgt;
		btb_cnt[btb_widx] <= btb_ncnt;
	end
end

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		btb_vld <= {BTB_N{1'b0}};
	else if (btb_clr)
		btb_vld <= {BTB_N{1'b0}};
	else if (btb_we)
		btb_vld[btb_widx] <= 1'b1;
end
assign pred_a_mode = 1'b0;

// (1) The fetch made while a predicted jump/branch is held in ID (pc_if = the
// predicted target, its result is discarded because pc_id does not
// advance) must not start an I$ refill.  The original design only ever
// fetches pc+4 there, i.e. the same or the adjacent line; a refill of the
// target (any line) could evict the held instruction's own line before it
// is refetched, or start a second miss in a state the icdc state machine
// does not expect (IDST_SYAD).  The target is fetched again in the cycle
// the jump leaves ID and an I$ miss is handled normally from there.
// (registered : qualifies ilu_stage's tag check one cycle later)
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		btb_spec_fetch <= 1'b0;
	else
		btb_spec_fetch <= pred_id & ~ic_stall_dly & (ic_stall | stall | stall_ld) |
		                  // IDST_SYAD : the I$ refill that started together with a
		                  // D$ stall is over, the D$ stall still runs, ID holds the
		                  // refilled instruction.  The original design never misses
		                  // here (no jump can land on an uncached line exactly when
		                  // an older load starts a D$ stall; the sequential next
		                  // fetch is in the refilled line) and the state machine
		                  // has no path for it (SYAD -> ISWD "not occured" loses the
		                  // ID instruction).  With the BTB the target of a branch in
		                  // ID can be such a line (target = its last word, the next
		                  // fetch crosses).  The fetch is redone when ID advances.
		                  (cache_miss_next == `IDST_SYAD);
end
`else
always @ (posedge clk) btb_spec_fetch <= 1'b0;
assign btb_take = 1'b0;
assign btb_tgt = 30'd0;
assign pred_a_mode = 1'b1;
`endif

endmodule

