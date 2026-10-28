/*
 * My RISC-V RV32I CPU
 *   CPU Execution Stage Module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

`define SUPPORT_M
`define SUPPORT_A

module ex_stage(
	input clk,
	input rst_n,

	// from ID
	input [31:0] rs1_data_ex,
	input [31:0] rs2_data_ex,
	input [31:2] pc_id,
	input [31:2] pc_ex,
    // microcode
    input cmd_lui_ex,
    input cmd_auipc_ex,
    input [31:12] lui_auipc_imm_ex,
    input cmd_ld_ex,
    //input [2:0] ld_bw_ex,
    input [11:0] ld_alui_ofs_ex,
    input cmd_alui_ex,
    input cmd_alui_shamt_ex,
    input cmd_alu_ex,
    input cmd_alu_add_ex, // ?
    input cmd_alu_sub_ex,
    input [2:0] alu_code_ex,
    //input [11:0] alui_imm_ex,
    input [4:0] alui_shamt_ex,
    input cmd_st_ex,
    input [11:0] st_ofs_ex,
    input cmd_jal_ex,
    input [20:1] jal_ofs_ex,
    input cmd_jalr_ex,
    input [11:0] jalr_ofs_ex,
    input cmd_br_ex,
    input [12:1] br_ofs_ex,
    input cmd_fence_ex,
    input cmd_fencei_ex,
    input [3:0] fence_succ_ex,
    input [3:0] fence_pred_ex,
    input cmd_sfence_ex,
    input cmd_csr_ex,
    input [11:0] csr_ofs_ex,
	input [4:0] csr_uimm_ex,
	input [2:0] csr_op2_ex,
    input cmd_ecall_ex,
    input cmd_ebreak_ex,
    input cmd_uret_ex,
    input cmd_sret_ex,
    input cmd_mret_ex,
    input cmd_wfi_ex,
    input illegal_ops_ex,
	input [4:0] rd_adr_ex,
	input wbk_rd_reg_ex,
	// from forwarding
	input hit_rs1_idex_ex,
	input hit_rs1_idma_ex,
	input hit_rs1_idwb_ex,
	input nohit_rs1_ex,
	input hit_rs2_idex_ex,
	input hit_rs2_idma_ex,
	input hit_rs2_idwb_ex,
	input nohit_rs2_ex,
	input [31:0] wbk_data_wb,
	input [31:0] wbk_data_wb2,

	// to MA
	input dc_stall,
	input dc_stall_fin,
	//input dc_stall_early,
    output reg cmd_ld_ma,
`ifdef SUPPORT_A
    output cmd_st_ma,
`else // SUPPORT_A
    output reg cmd_st_ma,
`endif // SUPPORT_A
	output reg [4:0] rd_adr_ma,
	output reg [31:0] rd_data_ma,
	output [31:0] rd_data_ex,
	output reg wbk_rd_reg_ma,
	output reg [31:0] st_data_ma,
	output reg [2:0] ldst_code_ma,
	// pc_jump_trace_logger WB-commit tap (2026-07-29): PC of the
	// instruction now entering MA, latched in lockstep with rd_adr_ma so
	// it stays paired with the same instruction all the way to WB - see
	// ma_stage.v's pc_wb and cpu_top.v's trc_pc_wb.
	output reg [31:2] pc_ma,
    // to IF
	output [31:2] jmp_adr_ex,
	input [31:2] jmp_adr_if,
	output jmp_condition_ex,
	output fencei_condition_ex,
	input fencei_cond,
	output [31:2] csr_mtvec_ex,
    output ecall_condition_ex,
    output mret_condition_ex,
    output interrupt_condition_ex,
    output timer_condition_ex,
	output jump_between_stall,
	output [31:2] csr_mepc_ex,
	output [31:2] csr_sepc_ex,
	// from somewhere...
	input frc_cntr_val_leq,
	input frc_cntr_val_leq_1shot,
	input g_interrupt,
	input g_interrupt_1shot,
	input [1:0] g_interrupt_priv,
	input [1:0] g_current_priv,
    input post_jump_cmd_cond,
	output g_exception,
    output csr_meie,
    output csr_mtie,
    output csr_msie,
	// new signals
	input [31:0] illegal_ops_inst, // new
	output csr_rmie, // new
    input csr_radr_en_mon, // new
    input [11:0] csr_radr_mon, // new
    input [11:0] csr_wadr_mon, // new
    input csr_we_mon, // new
    input [31:0] csr_wdata_mon, // new
    output [31:0] csr_rdata_mon, // new

`ifdef SUPPORT_M
	output [31:0] rs1_sel,
	output [31:0] rs2_sel,
	input [31:0] m_result_ex,
	input m_cmd_finished,
	input div_result_valid,
	input [4:0] div_rd_adr_ex,
	input div_stall_start,
	input div_stall_dly,
`endif // SUPPORT_M
`ifdef SUPPORT_A
	input cmd_lrw_ex,
	input cmd_scw_ex,
	input cmd_amoswapw_ex,
	input cmd_amoaddw_ex,
	input cmd_amoxorw_ex,
	input cmd_amoandw_ex,
	input cmd_amoorw_ex,
	input cmd_amominw_ex,
	input cmd_amomaxw_ex,
	input cmd_amominuw_ex,
	input cmd_amomaxuw_ex,
	output amo_stall,
	output amo_stall_dly,
	output amo_stall_fin,
	output reg amo_stall_fin2,
	output success_scw_ma,
	output reg cmd_scw_purge_ma,
`endif // SUPPORT_A

	// to ID
	output reg jmp_purge_ma,
	output jmp_purge_ex,
	// FPGA FIX (2026-07-19): fence.i window purge - see fencei_wb_purge
	// block below.  Exported so cpu_top can also cancel an in-flight
	// mul/div started by the shadowed instruction (mex_stage
	// intexp_cancel_mex).
	output reg fencei_wb_purge,
	// stall
	//input dc_stall_1shot_re,
	input ic_stall,
	input stall,
	input stall_1shot,
	input stall_dly,
	input stall_dly2,
	input rst_pipe

	);

`ifndef SUPPORT_M
wire [31:0] rs1_sel;
wire [31:0] rs2_sel;
`else // SUPPORT_M
`ifndef SUPPORT_A
wire [31:0] rs1_sel;
wire [31:0] rs2_sel;
`endif // SUPPORT_A
`endif // SUPPORT_M

// for A instructions
//assign jmp_purge_ex = jmp_condition_ex | ecall_condition_ex | mret_condition_ex | interrupt_condition_ex | timer_condition_ex | fencei_cond;

wire intexp_purge_ex = interrupt_condition_ex | timer_condition_ex | g_exception;

// FPGA FIX (2026-07-19): fence.i executes as: EX(fence.i) -> full D$ flush
// (dc_stall for its whole duration) -> fencei_dcflush_end -> 2 cycles ->
// fencei_cond = "retry jump" to pc_id-1 (the instruction AFTER fence.i),
// whose whole point is that the shadowed next instruction re-executes with
// the freshly synced caches.  BUT: that next instruction entered EX one
// cycle after the fence.i and sat there FROZEN through the flush; on the
// FIRST ~stall cycle after the flush (one or two cycles BEFORE fencei_cond
// fires) it committed via the roll path - stores/writebacks/CSR ops/jumps
// all landed - and then the retry jump executed it AGAIN.  Idempotent
// instructions hide this; `addi sp,sp,N` / csr RMW / `mul a,a,b` forms get
// silently double-applied (this is almost certainly why the 2026-07-05-era
// kernel saw wild jumps / stack-protector panics around jump_label
// patching whenever fence.i was executed, which led to fence.i being
// removed from the kernel on 2026-07-07 - trading the bug for a total loss
// of I$/D$ coherence).  Fix: latch a purge from the fence.i's own EX cycle
// (fencei_condition_ex) until the retry jump (fencei_cond) and mask every
// commit path with it, so the shadowed instruction's ONLY execution is the
// post-retry one.  An interrupt taken in the commit window is fine: the
// existing post_intr_ecall_exception guard swallows the retry jump and
// mepc (= pc_ex = the shadowed instruction, never executed) re-runs it
// after mret.
always @ ( posedge clk or negedge rst_n) begin
	if (~rst_n)
		fencei_wb_purge <= 1'b0;
	else if (fencei_cond)
		fencei_wb_purge <= 1'b0;
	else if (fencei_condition_ex)
		fencei_wb_purge <= 1'b1;
end

reg jmp_purge_ma2;

`ifdef SUPPORT_A
// lr.w cmd
wire cmd_lrw_purge = cmd_lrw_ex  & ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2; 

// lr.w / sc.w
// FIX (2026-10-28): drop the reservation on every trap entry and on mret,
// so an sc.w can never succeed on a reservation taken in another context
// (e.g. an lr.w left behind by an ISR or another task).
wire resv_clr_trap = interrupt_condition_ex | timer_condition_ex | ecall_condition_ex | g_exception | mret_condition_ex;
reg resv_flg;
reg [31:0] resv_adr;
wire reset_flg_cond;
wire cmd_ld_pur;
wire cmd_st_pur;

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n)
		resv_flg <= 1'b0;
	else if (resv_clr_trap)
		resv_flg <= 1'b0;
	else if (reset_flg_cond & ~stall)
		resv_flg <= 1'b0;
	//else if (cmd_lrw_ex)
	else if (cmd_lrw_purge)
		resv_flg <= 1'b1;
end

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n)
		resv_adr <= 32'd0;
	else if (cmd_lrw_purge)
		resv_adr <= rs1_sel;
end

// lr.w conditions
wire [31:0] rd_data_ex_pre;

assign reset_flg_cond = (cmd_scw_ex | (cmd_st_ex & (resv_adr[29:2] == rd_data_ex_pre[29:2]))) & ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2;

// sc.w conditions
wire success_scw = cmd_scw_ex & resv_flg & ~intexp_purge_ex & ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2;
//wire cmd_scw_hit = success_scw & (resv_adr[31:2] == rs1_sel[31:2]);
wire cmd_scw_hit = success_scw & (resv_adr[29:2] == rd_data_ex_pre[29:2]);

// sc.w write back to register
wire cmd_scw_purge = cmd_scw_ex & ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2; 

// amo instructions

wire cmd_amoswapw_pur = ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2 & cmd_amoswapw_ex;
wire cmd_amoaddw_pur = ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2 & cmd_amoaddw_ex;
wire cmd_amoxorw_pur = ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2 & cmd_amoxorw_ex;
wire cmd_amoandw_pur = ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2 & cmd_amoandw_ex;
wire cmd_amoorw_pur = ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2 & cmd_amoorw_ex;
wire cmd_amominw_pur = ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2 & cmd_amominw_ex;
wire cmd_amomaxw_pur = ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2 & cmd_amomaxw_ex;
wire cmd_amominuw_pur = ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2 & cmd_amominuw_ex;
wire cmd_amomaxuw_pur = ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2 & cmd_amomaxuw_ex;

wire amo_cmds = cmd_amoswapw_pur | cmd_amoaddw_pur | cmd_amoxorw_pur | cmd_amoandw_pur | cmd_amoorw_pur | cmd_amominw_pur | cmd_amomaxw_pur | cmd_amominuw_pur | cmd_amomaxuw_pur;

// critical path 
// state machine for amo instructions

`define AMO_IDLE 3'b000
`define AMO_LOAD 3'b001
`define AMO_LDWB 3'b011
`define AMO_EXEC 3'b101
`define AMO_STOR 3'b110
`define AMO_STWT 3'b100

reg [2:0] amo_current;

function [2:0] amo_decode;
input [2:0] amo_current;
input amo_cmds;
input stall;
input dc_stall_fin;
begin
    case(amo_current)
		`AMO_IDLE: begin
			// FIX (2026-10-28): start only when the AMO's own load is
			// issued (~stall).  An AMO right behind a load that misses the
			// D$ sits in EX during that miss; it used to enter AMO_LOAD at
			// once, took the older load's dc_stall_fin as its own, and
			// computed/stored from the wrong data (the AMO's store was lost).
			if (amo_cmds & ~stall) amo_decode = `AMO_LOAD;
			else amo_decode = `AMO_IDLE;
		end
		`AMO_LOAD: begin
			if (~stall) amo_decode = `AMO_LDWB;
			else if (dc_stall_fin)  amo_decode = `AMO_LDWB;
			else amo_decode = `AMO_LOAD;
		end
		`AMO_LDWB: amo_decode = `AMO_EXEC;
		`AMO_EXEC: amo_decode = `AMO_STOR;
		`AMO_STOR: begin
			if (dc_stall_fin | ~stall) amo_decode = `AMO_STWT;
			else amo_decode = `AMO_STOR;
		end
		`AMO_STWT: amo_decode = `AMO_IDLE;
		default: amo_decode = `AMO_IDLE;
	endcase
end
endfunction

wire [2:0] amo_next = amo_decode( amo_current, amo_cmds, stall, dc_stall_fin );

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		amo_current <= `AMO_IDLE;
	else
		amo_current <= amo_next;
end

wire amo_term = (amo_current != `AMO_IDLE);
wire amo_wb_term = (amo_current == `AMO_LDWB);
wire amo_ex_term = (amo_current == `AMO_EXEC);
wire amo_st_term = (amo_current == `AMO_STOR);
wire amo_ld_cmd = amo_cmds;
wire amo_st_cmd = (amo_current == `AMO_EXEC);

// amo stall signals
assign amo_stall = amo_cmds | ((amo_current != `AMO_IDLE)&(amo_current != `AMO_STWT));
assign amo_stall_dly = amo_term;
assign amo_stall_fin =  (amo_current == `AMO_STWT);

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		amo_stall_fin2 <= 1'b0;
	else
		amo_stall_fin2 <= amo_stall_fin;
end

// keep selected values
reg [31:0] amo_rs1_addr;
reg [31:0] amo_rs2_oper;
wire [31:0] rs2_fwd;

wire [31:0] rs2_sel_for_oper = ~nohit_rs2_ex ? rs2_fwd : rs2_data_ex;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		amo_rs1_addr <= 32'd0;
		amo_rs2_oper <= 32'd0;
	end
	else if (amo_cmds & ~stall) begin
		amo_rs1_addr <= rs1_sel;
		amo_rs2_oper <= rs2_sel_for_oper;
	end
end

// load inst : same timing as amo_cmds
// store inst : same timing as exec of amo
reg cmd_amoswapw_lat;
reg cmd_amoaddw_lat;
reg cmd_amoxorw_lat;
reg cmd_amoandw_lat;
reg cmd_amoorw_lat;
reg cmd_amominw_lat;
reg cmd_amomaxw_lat;
reg cmd_amominuw_lat;
reg cmd_amomaxuw_lat;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		cmd_amoswapw_lat <= 1'b0;
		cmd_amoaddw_lat <= 1'b0;
		cmd_amoxorw_lat <= 1'b0;
		cmd_amoandw_lat <= 1'b0;
		cmd_amoorw_lat <= 1'b0;
		cmd_amominw_lat <= 1'b0;
		cmd_amomaxw_lat <= 1'b0;
		cmd_amominuw_lat <= 1'b0;
		cmd_amomaxuw_lat <= 1'b0;
	end
	else if (amo_stall_fin) begin
		cmd_amoswapw_lat <= 1'b0;
		cmd_amoaddw_lat <= 1'b0;
		cmd_amoxorw_lat <= 1'b0;
		cmd_amoandw_lat <= 1'b0;
		cmd_amoorw_lat <= 1'b0;
		cmd_amominw_lat <= 1'b0;
		cmd_amomaxw_lat <= 1'b0;
		cmd_amominuw_lat <= 1'b0;
		cmd_amomaxuw_lat <= 1'b0;
	end
	else if (amo_cmds) begin
		cmd_amoswapw_lat <= cmd_amoswapw_ex;
		cmd_amoaddw_lat <= cmd_amoaddw_ex;
		cmd_amoxorw_lat <= cmd_amoxorw_ex;
		cmd_amoandw_lat <= cmd_amoandw_ex;
		cmd_amoorw_lat <= cmd_amoorw_ex;
		cmd_amominw_lat <= cmd_amominw_ex;
		cmd_amomaxw_lat <= cmd_amomaxw_ex;
		cmd_amominuw_lat <= cmd_amominuw_ex;
		cmd_amomaxuw_lat <= cmd_amomaxuw_ex;
	end
end

// wbk_data_wb : wbk_data_wb2;
reg [31:0] wbk_data_lat;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		wbk_data_lat <= 32'd0;
	else if (amo_wb_term)
		wbk_data_lat <= wbk_data_wb;
end

// amo alu
wire [31:0] amo_swp_data = amo_rs2_oper;
wire [31:0] amo_add_data = wbk_data_lat + amo_rs2_oper;
wire [31:0] amo_xor_data = wbk_data_lat ^ amo_rs2_oper;
wire [31:0] amo_and_data = wbk_data_lat & amo_rs2_oper;
wire [31:0] amo_or_data  = wbk_data_lat | amo_rs2_oper;
wire [31:0] amo_min_data = ($signed( wbk_data_lat ) > $signed( amo_rs2_oper)) ? amo_rs2_oper : wbk_data_lat;
wire [31:0] amo_max_data = ($signed( wbk_data_lat ) > $signed( amo_rs2_oper)) ? wbk_data_lat : amo_rs2_oper;
wire [31:0] amo_minu_data = (wbk_data_lat > amo_rs2_oper) ? amo_rs2_oper : wbk_data_lat;
wire [31:0] amo_maxu_data = (wbk_data_lat > amo_rs2_oper) ? wbk_data_lat : amo_rs2_oper;

wire [31:0] amo_sel_data = cmd_amoswapw_lat ? amo_swp_data :
                           cmd_amoaddw_lat ? amo_add_data : 
                           cmd_amoxorw_lat ? amo_xor_data : 
                           cmd_amoandw_lat ? amo_and_data : 
                           cmd_amoorw_lat ? amo_or_data : 
                           cmd_amominw_lat ? amo_min_data : 
                           cmd_amomaxw_lat ? amo_max_data : 
                           cmd_amominuw_lat ? amo_minu_data : 
                           cmd_amomaxuw_lat ? amo_maxu_data : 32'd0;


`endif // SUPPORT_A

// Pre-selector

// cmd_auipc_ex rs1:pc rs2:auipc_data
wire [31:0] auipc_data = { lui_auipc_imm_ex, 12'd0 };
wire [31:0] pc_data = { pc_ex, 2'd0 };

// cmd_ld_ex rs1  rs2:ofs
wire [31:0] ld_alui_ofs = { { 20{ ld_alui_ofs_ex[11] }}, ld_alui_ofs_ex };

// cmd_alui_ex rs1, rs2:ofs

// cmd_alui_shamt_ex rs1, rs2:shamt
wire [31:0] shamt = { 27'd0, alui_shamt_ex };

// cmd_alu_ex rs1, rs2

// cmd_st_ex rs1, rs2:ofs
wire [31:0] st_ofs = {{  20{ st_ofs_ex[11] }}, st_ofs_ex };

// cmd_jal_ex rs1:pc rs2:ofs20
wire [31:0] jal_ofs = {{ 11{ jal_ofs_ex[20] }}, jal_ofs_ex, 1'b0 };

// cmd_jalr_ex rs1:pc rs2:ofs
wire [31:0] jalr_ofs = {{ 20{ jalr_ofs_ex[11] }}, jalr_ofs_ex };

// cmd_br_ex rs1:pc rs2:ofs
wire [31:0] br_ofs = {{ 19{ br_ofs_ex[12] }}, br_ofs_ex, 1'b0 };

`ifdef SUPPORT_A
assign cmd_ld_pur = (cmd_ld_ex | cmd_lrw_ex | amo_ld_cmd) & ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2;
assign cmd_st_pur = (cmd_st_ex | amo_st_cmd) & ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2;
`else // SUPPORT_A
wire cmd_ld_pur = cmd_ld_ex & ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2;
wire cmd_st_pur = cmd_st_ex & ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2;
`endif // SUPPORT_A

// csr cmd need to purge
wire cmd_csr_pur = cmd_csr_ex & ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2 & ~fencei_wb_purge;

// forwarding selector

`ifdef SUPPORT_A
reg cmd_scw_hit_ma;
wire [31:0] rd_data_ma_scw = cmd_scw_purge_ma ? { 31'd0, ~cmd_scw_hit_ma } : rd_data_ma;
//wire [31:0] rd_data_ma_scw = rd_data_ma;

wire [31:0] rs1_fwd_raw = hit_rs1_idex_ex ? rd_data_ma_scw :
                          hit_rs1_idma_ex ? wbk_data_wb : wbk_data_wb2;

wire [31:0] rs2_fwd_raw = hit_rs2_idex_ex ? rd_data_ma_scw :
                          hit_rs2_idma_ex ? wbk_data_wb : wbk_data_wb2;
`else // SUPPORT_A
wire [31:0] rs1_fwd_raw = hit_rs1_idex_ex ? rd_data_ma :
                          hit_rs1_idma_ex ? wbk_data_wb : wbk_data_wb2;

wire [31:0] rs2_fwd_raw = hit_rs2_idex_ex ? rd_data_ma :
                          hit_rs2_idma_ex ? wbk_data_wb : wbk_data_wb2;
`endif // SUPPORT_A

// keep forwarded operands during stall:
// the forwarding sources (wbk_data_wb2, wbk_data_wb) keep moving while EX
// is frozen by a stall, so capture the values at the 1st stall cycle and
// use them until the stall is released.
reg [31:0] rs1_fwd_keep;
reg [31:0] rs2_fwd_keep;

always @ ( posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		rs1_fwd_keep <= 32'd0;
		rs2_fwd_keep <= 32'd0;
	end
	else if (stall & ~stall_dly) begin
		rs1_fwd_keep <= rs1_fwd_raw;
		rs2_fwd_keep <= rs2_fwd_raw;
	end
end

wire [31:0] rs1_fwd = stall_dly ? rs1_fwd_keep : rs1_fwd_raw;
assign rs2_fwd = stall_dly ? rs2_fwd_keep : rs2_fwd_raw;

// ALU selector
assign rs1_sel = ~nohit_rs1_ex ? rs1_fwd : rs1_data_ex;

assign rs2_sel = (cmd_ld_pur | cmd_alui_ex) ? ld_alui_ofs :
					  cmd_st_pur ? st_ofs :
					  //cmd_st_ex ? st_ofs :
					  cmd_alui_shamt_ex ? shamt :
					   ~nohit_rs2_ex ? rs2_fwd : rs2_data_ex;

wire [31:0] st_data_ex_pre = ~nohit_rs2_ex ? rs2_fwd : rs2_data_ex;

// jump / branch / auipc

wire [31:0] adr_s1 = cmd_jalr_ex ? rs1_sel : pc_data;
wire [31:0] adr_s2 = cmd_auipc_ex ? auipc_data :
                     cmd_jal_ex ? jal_ofs :
					 cmd_jalr_ex ? jalr_ofs : br_ofs;


// currently not implemented
// fence, sfence, eret
// ebreak: implemented 2026-07-23 via ecall_condition_ex_pre (mcause=3, see csr_array.v)

// ALU

// Adder
wire alu_adder_comp = cmd_alu_sub_ex & cmd_alu_ex;
wire [31:0] rs2_xor = rs2_sel ^ { 32{ alu_adder_comp }};

//wire [32:0] alu_add_tmp = { rs1_sel, 1'b1 } + { rs2_xor, alu_adder_comp };
wire [32:0] alu_add_r = { rs1_sel, 1'b1 };
wire [32:0] alu_add_l = { rs2_xor, alu_adder_comp };
wire [32:0] alu_add_tmp = alu_add_r + alu_add_l;
wire [31:0] alu_add = alu_add_tmp[32:1];

// Left shift

wire [31:0] alu_sll = rs1_sel << rs2_sel[4:0];

// Right shift

wire [31:0] alu_srl = rs1_sel >> rs2_sel[4:0];

wire signed [31:0] alu_sra = $signed( rs1_sel ) >>> $signed( rs2_sel[4:0] ) ;

wire [31:0] alu_srl_sra = cmd_alu_sub_ex ? alu_sra : alu_srl;

// Compare
wire slt = ($signed( rs1_sel ) < $signed( rs2_sel ));
wire sge = ~slt;
wire sltu = ( rs1_sel < rs2_sel );
wire sbgu = ~sltu;
wire seq = ( rs1_sel == rs2_sel );
wire sne = ~seq;

wire [31:0] alu_slt = { 31'd0, slt };
wire [31:0] alu_sltu = { 31'd0, sltu };

// Logics
wire [31:0] alu_xor = rs1_sel ^ rs2_sel;
wire [31:0] alu_and = rs1_sel & rs2_sel;
wire [31:0] alu_or  = rs1_sel | rs2_sel;

// jal,jalr pcp4

wire [31:0] pcp4_ex = { pc_ex, 2'd0 } + 32'd4;

// adder pc for jump/branch

wire [31:0] jump_adr = adr_s1 + adr_s2;

// csrs , ecall
wire [31:0] csr_rd_data;

// misaligned load/store (2026-10-28)
// lw/sw need addr[1:0] == 0, lh/lhu/sh need addr[0] == 0 (funct3[1:0] is
// the access size; byte accesses never trap).  The core used to ignore the
// low address bits silently, so a misaligned lw read the aligned word.  Now
// it traps like an illegal instruction (g_exception): mcause 4 (load) or
// 6 (store), mtval = the address, mepc = the load/store, which is purged
// (no D$ access, no write-back).  Evaluated only on ~stall cycles, and not
// for an instruction that is being purged (jump shadow, fence.i shadow) or
// is losing to an interrupt in the same cycle (the interrupt wins, mepc =
// the load/store, which re-executes and traps after mret).
// lr.w/sc.w/AMO are not checked here.
// The address is recomputed from rs1_sel + offset instead of using the ALU
// result: the ALU only adds the offset while cmd_ld_pur/cmd_st_pur are set,
// and those are cleared by g_exception itself (combinational loop).  Only
// the low 2 bits feed the trap condition; the full sum is just for mtval.
wire [31:0] misal_ofs = cmd_st_ex ? st_ofs : ld_alui_ofs;
wire [1:0] misal_lo = rs1_sel[1:0] + misal_ofs[1:0];
wire [31:0] misal_va = rs1_sel + misal_ofs;
wire misal_adr_ex = (alu_code_ex[1:0] == 2'b10) ? (misal_lo != 2'b00) :
                    (alu_code_ex[1:0] == 2'b01) ? misal_lo[0] : 1'b0;
wire misal_ok_ex = ~stall & ~interrupt_condition_ex & ~timer_condition_ex &
                   ~jmp_purge_ma & ~jmp_purge_ma2 & ~fencei_wb_purge & misal_adr_ex;
wire misal_ld_ex = misal_ok_ex & cmd_ld_ex;
wire misal_st_ex = misal_ok_ex & cmd_st_ex;

csr_array csr_array(
	.clk(clk),
	.rst_n(rst_n),
	.cmd_csr_ex(cmd_csr_pur),
	.csr_ofs_ex(csr_ofs_ex),
	.csr_uimm_ex(csr_uimm_ex),
	.csr_op2_ex(csr_op2_ex),
	.rs1_sel(rs1_sel),
	.csr_rd_data(csr_rd_data),
	.csr_mtvec_ex(csr_mtvec_ex),
	.g_interrupt(g_interrupt),
	.frc_cntr_val_leq(frc_cntr_val_leq),
	//.g_interrupt_1shot(g_interrupt_1shot),
	.interrupt_condition_ex(interrupt_condition_ex),
	.timer_condition_ex(timer_condition_ex),
	.post_jump_cmd_cond(post_jump_cmd_cond),
	.illegal_ops_ex(illegal_ops_ex),
	.illegal_ops_inst(illegal_ops_inst), // new
	.misal_ld_ex(misal_ld_ex),
	.misal_st_ex(misal_st_ex),
	.misal_adr(misal_va),
	.g_exception(g_exception),
	.g_interrupt_priv(g_interrupt_priv),
	.g_current_priv(g_current_priv),
	.csr_mepc_ex(csr_mepc_ex),
	.csr_sepc_ex(csr_sepc_ex),
	//.cmd_mret_ex(cmd_mret_ex),
	.cmd_mret_ex(mret_condition_ex),
	.cmd_sret_ex(cmd_sret_ex),
	.cmd_uret_ex(cmd_uret_ex),
	.csr_rmie(csr_rmie), // new
	.csr_meie(csr_meie),
	.csr_mtie(csr_mtie),
	.csr_msie(csr_msie),
	//.cmd_ecall_ex(cmd_ecall_ex),
	.ecall_condition_ex(ecall_condition_ex),
	.cmd_ebreak_ex(cmd_ebreak_ex),
	.pc_id(pc_id),
	.pc_ex(pc_ex),
	.jmp_adr_if(jmp_adr_if),
	.jmp_condition_ex(jmp_condition_ex),
	.fencei_condition_ex(fencei_cond),
	.mret_condition_ex(mret_condition_ex),
`ifdef SUPPORT_M
	.div_stall_start(div_stall_start),
	.div_stall_dly(div_stall_dly),
`endif // SUPPORT_M
	.stall(stall),
	.csr_radr_en_mon(csr_radr_en_mon), // new
	.csr_radr_mon(csr_radr_mon), // new
	.csr_wadr_mon(csr_wadr_mon), // new
	.csr_we_mon(csr_we_mon), // new
	.csr_wdata_mon(csr_wdata_mon), // new
	.csr_rdata_mon(csr_rdata_mon) // new
	);

// exception block

exception exception (
	.clk(clk),
	.rst_n(rst_n),
	.illegal_ops_ex(illegal_ops_ex),
	.misal_ld_ex(misal_ld_ex),
	.misal_st_ex(misal_st_ex),
	.g_exception(g_exception)
	);

// Post-selector
// ALU

wire [2:0] alu_code = alu_code_ex & { 3{ ~(cmd_alu_ex & cmd_alui_ex & cmd_alui_shamt_ex) }};
wire cmd_stld = cmd_st_pur | cmd_ld_pur;
//wire cmd_stld = cmd_st_ex | cmd_ld_pur;

function [31:0] alu_selector;
input [2:0] alu_code;
input cmd_stld;
input [31:0] alu_add;
input [31:0] alu_sll;
input [31:0] alu_slt;
input [31:0] alu_sltu;
input [31:0] alu_xor;
input [31:0] alu_srl_sra;
input [31:0] alu_or;
input [31:0] alu_and;
begin
	casez({cmd_stld,alu_code})
		4'b1???: alu_selector = alu_add;
		4'b0000: alu_selector = alu_add;
		4'b0001: alu_selector = alu_sll;
		4'b0010: alu_selector = alu_slt;
		4'b0011: alu_selector = alu_sltu;
		4'b0100: alu_selector = alu_xor;
		4'b0101: alu_selector = alu_srl_sra;
		4'b0110: alu_selector = alu_or;
		4'b0111: alu_selector = alu_and;
		default: alu_selector = alu_add;
	endcase
end
endfunction

wire [31:0] alu_sel = alu_selector( alu_code,
                                    cmd_stld,
                                    alu_add,
                                    alu_sll,
                                    alu_slt,
                                    alu_sltu,
                                    alu_xor,
                                    alu_srl_sra,
                                    alu_or,
                                    alu_and);

// Lui
wire [31:0] lui_data = { lui_auipc_imm_ex, 12'd0 };

`ifdef SUPPORT_A
`ifdef SUPPORT_M
assign rd_data_ex_pre = cmd_lui_ex ? lui_data :
                        (cmd_jal_ex | cmd_jalr_ex) ? pcp4_ex :
						cmd_auipc_ex ? jump_adr :
                        cmd_csr_pur ? csr_rd_data :
                        m_cmd_finished ? m_result_ex :
                        (cmd_lrw_purge | cmd_scw_purge) ? rs1_sel :
                        alu_sel;
`else // SUPPORT_M
assign rd_data_ex_pre = cmd_lui_ex ? lui_data :
                        (cmd_jal_ex | cmd_jalr_ex) ? pcp4_ex :
						cmd_auipc_ex ? jump_adr :
                        cmd_csr_pur ? csr_rd_data :
                        (cmd_lrw_purge | cmd_scw_purge) ? rs1_sel :
                        alu_sel;
`endif // SUPPORT_M
`else // SUPPORT_A
`ifdef SUPPORT_M
assign rd_data_ex_pre = cmd_lui_ex ? lui_data :
                        (cmd_jal_ex | cmd_jalr_ex) ? pcp4_ex :
						cmd_auipc_ex ? jump_adr :
                        cmd_csr_pur ? csr_rd_data :
                        m_cmd_finished ? m_result_ex :
                        alu_sel;
`else // SUPPORT_M
assign rd_data_ex_pre = cmd_lui_ex ? lui_data :
                        (cmd_jal_ex | cmd_jalr_ex) ? pcp4_ex :
					    cmd_auipc_ex ? jump_adr :
                        cmd_csr_pur ? csr_rd_data :
                              alu_sel;
`endif // SUPPORT_M
`endif // SUPPORT_A

/*
reg cmd_ld_ma_keeper;

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n)
        cmd_ld_ma_keeper <= 1'b0;
	else if (stall)
        cmd_ld_ma_keeper <= cmd_ld_ma;
end
*/

// roll back for dc_stall
//wire cmd_st_tmp;
reg [4:0] rd_adr_roll;
reg [31:0] st_data_roll;
reg [31:0] rd_data_roll;
reg [2:0] ldst_code_roll;
reg  cmd_ld_roll;
reg  cmd_st_roll;
reg  wbk_rd_reg_roll;
reg  jmp_purge_roll;
wire wbk_rd_reg_tmp;
//wire stall_ldst_pre = (cmd_ld_pur | cmd_st_tmp) ? stall : stall_dly;
//wire stall_ldst_pre = (cmd_ld_pur|cmd_st_tmp) ? stall : stall_dly;
//wire stall_ldst_pre = (stall & cmd_st_tmp) |  (stall_dly & cmd_ld_pur);
//wire stall_ldst_pre = (stall & cmd_st_tmp) |  (stall & cmd_ld_pur);

//wire stall_ldst_pre = (stall & cmd_st_pur) |  (stall & cmd_ld_pur);

`ifdef SUPPORT_M
wire [4:0] rd_adr_ex_with_div = div_result_valid ? div_rd_adr_ex : rd_adr_ex;
`else // SUPPORT_M
wire [4:0] rd_adr_ex_with_div = rd_adr_ex;
`endif // SUPPORT_M

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
		rd_adr_roll <= 5'd0;
        st_data_roll <= 32'd0;
        rd_data_roll <= 32'd0;
        ldst_code_roll <= 3'd0;
        cmd_ld_roll <= 1'b0;
        cmd_st_roll <= 1'b0;
		wbk_rd_reg_roll <= 1'b0;
		jmp_purge_roll <= 1'b0;
	end
	//else if (rst_pipe) begin
        //st_data_roll <= 32'd0;
        //rd_data_roll <= 32'd0;
	//end
	//else if (~dc_stall | dc_stall_fin)
	//else if (~stall | dc_stall_fin)
	//else if (~stall & ~dc_stall_fin)
	//else if (~stall & ~stall_dly)
	else if (stall_1shot) begin
	//else if (stall_1shot | dc_stall_1shot_re) begin
		rd_adr_roll <= rd_adr_ex_with_div;
        st_data_roll <= st_data_ex_pre;
        rd_data_roll <= rd_data_ex_pre;
        ldst_code_roll <= alu_code_ex;
        cmd_ld_roll <= cmd_ld_pur;
        //cmd_st_roll <= cmd_st_tmp;
        cmd_st_roll <= cmd_st_pur;
		wbk_rd_reg_roll <= wbk_rd_reg_tmp;
		jmp_purge_roll <= jmp_purge_ex;
	end
end

//assign rd_data_ex = (dc_stall & ~dc_stall_fin) ? rd_data_roll : rd_data_ex_pre;
//assign rd_data_ex = (stall | dc_stall_fin) ? rd_data_roll : rd_data_ex_pre;

//wire stall_ldst = (cmd_ld_pur | cmd_st_tmp) ? stall_dly :  stall_dly2;
//wire stall_ldst = (cmd_ld_pur) ? stall_dly :  stall_dly2;
//wire stall_ldst = (stall_dly |  stall_dly2) & ~(cmd_ld_ma|cmd_st_ma);

//wire stall_ldst = (stall_dly & cmd_st_ma) |  (stall_dly2 & cmd_ld_ma);
//wire stall_ldst = (stall_dly & cmd_st_ma) |  (stall_dly & cmd_ld_ma); // for debug test
wire stall_ldst = stall_dly; // for debug test
wire stall_ldst_0 = 1'b0;
//wire stall_ldst = 1'b0; // for debug test
//wire stall_ldst = stall & stall_dly; // for debug test
//assign rd_data_ex = stall_ldst ? rd_data_roll : rd_data_ex_pre;

//assign rd_data_ex = (stall | stall_dly2) ? rd_data_roll : rd_data_ex_pre;
//assign rd_data_ex = (stall | stall_dly) ? rd_data_roll : rd_data_ex_pre;
//assign rd_data_ex = rd_data_ex_pre;

wire [4:0] rd_adr_ex_post = (stall_ldst_0) ? rd_adr_roll : rd_adr_ex_with_div;

`ifdef SUPPORT_A
// FIX (2026-10-28): the AMO load address must be the forwarded rs1_sel, the
// same value amo_rs1_addr latches for the store.  rs1_data_ex is the raw
// register-file read, which is stale when rs1 is produced by one of the
// previous instructions (mv a0,..; amoadd.w t0,t1,(a0)): the load then read
// the wrong address while the store wrote the right one.
assign rd_data_ex = amo_cmds? rs1_sel :
                    amo_ex_term ? amo_rs1_addr :
                    (stall_ldst) ? rd_data_roll : rd_data_ex_pre;
//wire [31:0] st_data_ex = amo_st_term ? amo_sel_data :
wire [31:0] st_data_ex = amo_ex_term ? amo_sel_data :
                        cmd_scw_purge ? rs2_sel :
                        (stall_ldst) ? st_data_roll : st_data_ex_pre;
wire [2:0] ldst_code_ex = (amo_ld_cmd | amo_st_cmd) ? 3'b010 : // select always word
                          (stall_ldst_0) ? ldst_code_roll : alu_code_ex;
`else // SUPPORT_A
assign rd_data_ex = (stall_ldst) ? rd_data_roll : rd_data_ex_pre;
wire [31:0] st_data_ex = (stall_ldst) ? st_data_roll : st_data_ex_pre;
wire [2:0] ldst_code_ex = (stall_ldst_0) ? ldst_code_roll : alu_code_ex;
`endif // SUPPORT_A

wire cmd_ld_ex_post = (stall_ldst_0) ? cmd_ld_roll : cmd_ld_pur;
wire cmd_st_ex_post = (stall_ldst_0) ? cmd_st_roll : cmd_st_pur;
//wire cmd_st_ex_post = (stall_ldst_0) ? cmd_st_roll : cmd_st_tmp;
wire wbk_rd_reg_ex_post = (stall_ldst_0) ? wbk_rd_reg_roll : wbk_rd_reg_tmp;
wire jmp_purge_ex_post =  (stall_ldst_0) ? jmp_purge_roll : jmp_purge_ex;

// fence.i
// (1) purge I$
// (2) jump to next instruction for reload new instructions

wire fencei_condition_ex_pre = ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2 & ~fencei_wb_purge & cmd_fencei_ex;
assign fencei_condition_ex = ~stall & fencei_condition_ex_pre;

// jamp/br

// FIX (2026-10-28): fence.i retry target.  if_stage used pc_id - 1, which
// assumes the pipeline advances exactly one slot between fence.i's EX
// cycle and the start of the D$-flush stall.  When fence.i enters EX on the
// cycle a previous load's D$ refill is finishing, lsu_stage only starts the
// flush once dc_miss is back in IDLE, the pipeline advances two slots, and
// the retry jump skips the instruction right after fence.i - it never
// executes (its shadow run is masked by fencei_wb_purge).  Seen on the real
// board as kernel#855/#859 hangs/panics (place_entity's fence.i), reproduced
// by rtl_atomic_test/fencei_align_test.S.  Latch fence.i's own PC + 4 and
// drive it on jmp_adr_ex while fencei_cond is high.
reg [31:2] fencei_ret_adr;

always @ ( posedge clk or negedge rst_n) begin
	if (~rst_n)
		fencei_ret_adr <= 30'd0;
	else if (fencei_condition_ex)
		fencei_ret_adr <= pc_ex + 30'd1;
end

assign jmp_adr_ex = fencei_cond ? fencei_ret_adr : jump_adr[31:2];

//wire jmp_condition_ex_pre = ~jmp_purge_ma & (
//wire jmp_condition_ex_pre = ~jmp_purge_ma & ~jmp_purge_ma2 & (
wire jmp_condition_ex_pre = ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2 & ~fencei_cond & ~fencei_wb_purge & (
                        cmd_jal_ex | cmd_jalr_ex | cmd_br_ex &
						( seq  & (alu_code_ex == 3'b000) |
					      sne  & (alu_code_ex == 3'b001) |
					      slt  & (alu_code_ex == 3'b100) |
					      sge  & (alu_code_ex == 3'b101) |
					      sltu & (alu_code_ex == 3'b110) |
					      sbgu & (alu_code_ex == 3'b111) ));

assign jmp_condition_ex = ~stall & jmp_condition_ex_pre;

// ecall
//wire ecall_condition_ex_pre = ~jmp_purge_ma & ((cmd_ecall_ex & csr_rmie) | illegal_ops_ex);
// EBREAK (2026-07-23): cmd_ebreak_ex folded in here so ebreak drives the
// same trap-taking machinery (jmp_purge_ex redirect to mtvec, mepc/mstatus
// capture in csr_array's m_interrupt) as ecall/illegal already did. It was
// decoded all the way to this input (id_stage.v, purge-tracked identically
// to illegal_ops_ex) but never consumed anywhere, so ebreak was a silent
// NOP before this change - see RTL_REVIEW_2026-07-16.md item 10.
wire ecall_condition_ex_pre = ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2 & ~fencei_wb_purge & (cmd_ecall_ex | illegal_ops_ex | cmd_ebreak_ex);
assign ecall_condition_ex = ~stall & ecall_condition_ex_pre;
// mret
wire mret_condition_ex_pre = ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2 & ~fencei_wb_purge & cmd_mret_ex;
assign mret_condition_ex = ~stall & mret_condition_ex_pre;
// FIX (2026-10-28): do not take an interrupt while the AMO state machine
// is running (AMO_LOAD..AMO_STWT).  The AMO has already left EX, so an
// interrupt there set mepc to the wrong PC and the FSM still finished the
// store - the AMO could run twice after mret.  The interrupt is held in
// *_amo_pend (the io-side keepers only hold it across `stall`) and taken
// on the first cycle after the AMO completes.  An interrupt in the cycle
// the AMO itself is in EX (FSM still IDLE) already purges it cleanly.
`ifdef SUPPORT_A
wire amo_busy = amo_term;
`else // SUPPORT_A
wire amo_busy = 1'b0;
`endif // SUPPORT_A
// FIX (2026-10-28): also hold interrupts while a fence.i retry is pending
// (fencei_wb_purge: fence.i EX .. retry jump).  Since ilu_stage delays the
// retry jump (fencei_cond) past dc_stall, an interrupt could be taken in
// that window: either in the same cycle as fencei_cond (the interrupt wins,
// mepc = pc_ex = an instruction after the shadowed one, so the shadowed
// instruction is never executed) or a few stalled cycles before it (the
// 2-cycle post_intr_ecall_exception guard expires during the stall and the
// retry jump then hijacks the trap handler with MIE off).  Reproduced by
// rtl_atomic_test/fencei_pe_test.S (FENCE_OFS=8, IRQ=1, DWIDTH=12).  The
// interrupt is kept in *_amo_pend and taken right after the retry jump,
// where post_pc_ex (= retry target) gives the right mepc.
wire irq_hold = amo_busy | fencei_wb_purge;
reg g_int_amo_pend;
reg frc_amo_pend;

always @ ( posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		g_int_amo_pend <= 1'b0;
		frc_amo_pend <= 1'b0;
	end
	else begin
		if (interrupt_condition_ex)
			g_int_amo_pend <= 1'b0;
		else if (~stall & irq_hold & g_interrupt_1shot & csr_rmie)
			g_int_amo_pend <= 1'b1;
		if (timer_condition_ex)
			frc_amo_pend <= 1'b0;
		else if (~stall & irq_hold & frc_cntr_val_leq_1shot & csr_rmie)
			frc_amo_pend <= 1'b1;
	end
end

// interrupt
assign interrupt_condition_ex = ~stall & ~irq_hold & (g_interrupt_1shot | g_int_amo_pend) & csr_rmie;
// timer interrupt
assign timer_condition_ex = ~stall & ~irq_hold & (frc_cntr_val_leq_1shot | frc_amo_pend) & csr_rmie;

// purge signal
// FIX (2026-10-27): illegal-instruction exceptions (g_exception) must purge
// the younger instructions in ID/IF too. Without it the 2 following
// instructions kept executing after the trap, and a second illegal op among
// them (e.g. glibc's lr.w.aq; bnez; sc.w) trapped again and overwrote mepc.
// Reproduced in rtl_atomic_test/lrw_illegal_tb.v.
assign jmp_purge_ex = jmp_condition_ex | ecall_condition_ex | mret_condition_ex | interrupt_condition_ex | timer_condition_ex | fencei_cond | (~stall & g_exception);

wire no_wbk_cmds = cmd_st_ex | cmd_br_ex | ecall_condition_ex | mret_condition_ex | cmd_fencei_ex;

assign wbk_rd_reg_tmp = wbk_rd_reg_ex & ~no_wbk_cmds & ~intexp_purge_ex & ~jmp_purge_ma & ~jmp_purge_ma2 & ~illegal_ops_ex;
//assign wbk_rd_reg_tmp = wbk_rd_reg_ex & ~jmp_purge_ma & ~illegal_ops_ex;
//assign cmd_st_tmp = cmd_st_ex & ~jmp_purge_ma;

wire wb_mask_with_exception_interrupt = interrupt_condition_ex | timer_condition_ex | g_exception | fencei_wb_purge;

// workaround for jump between stall and stall
reg dc_stall_fin2;
reg dc_stall_fin3;

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
		dc_stall_fin2 <= 1'b0;
		dc_stall_fin3 <= 1'b0;
	end
	else begin
		dc_stall_fin2 <= dc_stall_fin;
		dc_stall_fin3 <= dc_stall_fin2;
	end
end

assign jump_between_stall = dc_stall_fin3 & (jmp_condition_ex_pre | ecall_condition_ex_pre | mret_condition_ex_pre | fencei_cond);


// FF to MA

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
		jmp_purge_ma <= 1'b0;
		jmp_purge_ma2 <= 1'b0;
	end
	//else if (rst_pipe) begin
        //cmd_st_ma <= 1'b0;
		//rd_adr_ma <= 5'd0;
		//rd_data_ma <= 32'd0;
		//st_data_ma <= 32'd0;
		//ldst_code_ma <= 3'd0;
		//jmp_purge_ma <= 1'b0;
        //cmd_ld_ma <= 1'b0;
		//wbk_rd_reg_ma <= 1'b0;
	//end
	//else if (~dc_stall_early) begin
	//else if (~(stall_dly|stall)) begin
	else if (~stall & fencei_cond) begin
		jmp_purge_ma <= 1'b1; // workaround
	end
	else if (~stall & ~ic_stall) begin
		jmp_purge_ma <= jmp_purge_ex_post;
		jmp_purge_ma2 <= jmp_purge_ma;
	end
end

`ifdef SUPPORT_A
//reg cmd_scw_hit_ma;
reg success_scw_ma_pre;
reg cmd_st_ma_pre;

//assign success_scw_ma = ~(success_scw_ma_pre & cmd_scw_hit_ma);
assign success_scw_ma = success_scw_ma_pre & cmd_scw_hit_ma;
assign cmd_st_ma = cmd_st_ma_pre | cmd_scw_hit_ma;
`endif // SUPPORT_A

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
		//rd_adr_ma <= 5'd0;
		//rd_data_ma <= 32'd0;
		//st_data_ma <= 32'd0;
		//ldst_code_ma <= 3'd0;
	end
	else begin
		//rd_adr_ma <= rd_adr_ex_post;
		//rd_data_ma <= rd_data_ex; // for debug test
		//st_data_ma <= st_data_ex; // for debug test
		//rd_data_ma <= rd_data_ex_pre; // for debug test
		//st_data_ma <= st_data_ex_pre; // for debug test
		//ldst_code_ma <= ldst_code_ex;
	end
end

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
		rd_adr_ma <= 5'd0;
		rd_data_ma <= 32'd0;
		st_data_ma <= 32'd0;
		ldst_code_ma <= 3'd0;
		pc_ma <= 30'd0;
        cmd_ld_ma <= 1'b0;
`ifdef SUPPORT_A
        cmd_st_ma_pre <= 1'b0;
`else // SUPPORT_A
        cmd_st_ma <= 1'b0;
`endif // SUPPORT_A
		wbk_rd_reg_ma <= 1'b0;
`ifdef SUPPORT_A
		// FPGA (2026-09-17): was 1'b1. With A-extension disabled at decode
		// (id_stage.v:347 a_ext_disable=1'b1), cmd_scw_hit is permanently 0,
		// so this register's ~stall-gated update (line ~1003 below) never
		// runs and the reset default sat here forever - and since
		// cmd_st_ma = cmd_st_ma_pre | cmd_scw_hit_ma (line ~946), a 1'b1
		// default made cmd_st_ma (and therefore cmd_ldst_ma, dc_tag_empty_ma,
		// dcr_start_rq) stuck permanently asserted from reset, independent
		// of cpu_start. Real hardware: confirmed dcr_start_rq stuck high via
		// ILA with cpu_start never asserted, traced to this exact register -
		// see project memory project_dram_write_loss_async_queue_theory.
		cmd_scw_hit_ma <= 1'b0;
		success_scw_ma_pre <= 1'b0;
		cmd_scw_purge_ma <= 1'b0;
`endif // SUPPORT_A
	end
	//else if (~dc_stall_early) begin
	else if (~stall) begin
		rd_adr_ma <= rd_adr_ex_post;
		rd_data_ma <= rd_data_ex; // for debug test
		st_data_ma <= st_data_ex; // for debug test
		////rd_data_ma <= rd_data_ex_pre; // for debug test
		////st_data_ma <= st_data_ex_pre; // for debug test
		ldst_code_ma <= ldst_code_ex;
		pc_ma <= pc_ex;
	    cmd_ld_ma <= cmd_ld_ex_post & ~wb_mask_with_exception_interrupt;
`ifdef SUPPORT_A
        cmd_st_ma_pre <= cmd_st_ex_post & ~wb_mask_with_exception_interrupt;
`else // SUPPORT_A
        cmd_st_ma <= cmd_st_ex_post & ~wb_mask_with_exception_interrupt;
`endif // SUPPORT_A
		wbk_rd_reg_ma <= wbk_rd_reg_ex_post & ~wb_mask_with_exception_interrupt;
`ifdef SUPPORT_A
		cmd_scw_hit_ma <= cmd_scw_hit & ~wb_mask_with_exception_interrupt;
		success_scw_ma_pre <= success_scw & ~wb_mask_with_exception_interrupt;
		cmd_scw_purge_ma <= cmd_scw_purge & ~wb_mask_with_exception_interrupt;
`endif // SUPPORT_A
	end
end

endmodule
