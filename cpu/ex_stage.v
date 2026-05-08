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
    output reg cmd_st_ma,
	output reg [4:0] rd_adr_ma,
	output reg [31:0] rd_data_ma,
	output [31:0] rd_data_ex,
	output reg wbk_rd_reg_ma,
	output reg [31:0] st_data_ma,
	output reg [2:0] ldst_code_ma,
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
`endif // SUPPORT_A

	// to ID
	output reg jmp_purge_ma,
	output jmp_purge_ex,
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

`ifdef SUPPORT_A
// for A instructions

// lr.w / sc.w
reg resv_flg;
reg [31:0] resv_adr;
wire reset_flg_cond;
wire cmd_ld_pur;
wire cmd_st_pur;

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n)
		resv_flg <= 1'b0;
	else if (reset_flg_cond)
		resv_flg <= 1'b0;
	else if (cmd_lrw_ex)
		resv_flg <= 1'b1;
end

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n)
		resv_adr <= 32'd0;
	else if (cmd_lrw_ex)
		resv_adr <= rs1_sel;
end

// lr.w conditions
assign reset_flg_cond = (cmd_scw_ex | (cmd_st_ex & (resv_adr[31:2] == rs1_sel[31:2]))) & ~jmp_purge_ma;

// sc.w conditions
wire success_scw = (cmd_scw_ex & (resv_adr[31:2] == rs1_sel[31:2]) & resv_flg) & ~jmp_purge_ma;

// amo instructions

wire amo_cmds = cmd_amoswapw_ex | cmd_amoaddw_ex | cmd_amoxorw_ex | cmd_amoandw_ex |
                cmd_amoorw_ex | cmd_amominw_ex | cmd_amomaxw_ex | cmd_amominuw_ex | cmd_amomaxuw_ex;

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
			if (amo_cmds) amo_decode = `AMO_LOAD;
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
	else if (amo_cmds) begin
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
assign cmd_ld_pur = (cmd_ld_ex | cmd_lrw_ex | amo_ld_cmd) & ~jmp_purge_ma;
assign cmd_st_pur = (cmd_st_ex | success_scw | amo_st_cmd) & ~jmp_purge_ma;
`else // SUPPORT_A
wire cmd_ld_pur = cmd_ld_ex & ~jmp_purge_ma;
wire cmd_st_pur = cmd_st_ex & ~jmp_purge_ma;
`endif // SUPPORT_A

// forwarding selector

wire [31:0] rs1_fwd = hit_rs1_idex_ex ? rd_data_ma :
                      hit_rs1_idma_ex ? wbk_data_wb : wbk_data_wb2;

`ifdef SUPPORT_A
assign rs2_fwd = hit_rs2_idex_ex ? rd_data_ma :
                 hit_rs2_idma_ex ? wbk_data_wb : wbk_data_wb2;
`else // SUPPORT_A
wire [31:0] rs2_fwd = hit_rs2_idex_ex ? rd_data_ma :
                      hit_rs2_idma_ex ? wbk_data_wb : wbk_data_wb2;
`endif // SUPPORT_A

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
// fence, sfence
// ebreak, eret

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

csr_array csr_array(
	.clk(clk),
	.rst_n(rst_n),
	.cmd_csr_ex(cmd_csr_ex),
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
	.pc_id(pc_id),
	.pc_ex(pc_ex),
	.jmp_adr_if(jmp_adr_if),
	.jmp_condition_ex(jmp_condition_ex),
	.fencei_condition_ex(fencei_cond),
	.mret_condition_ex(mret_condition_ex),
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

`ifdef SUPPORT_M
wire [31:0] rd_data_ex_pre = cmd_lui_ex ? lui_data :
                             (cmd_jal_ex | cmd_jalr_ex) ? pcp4_ex :
						      cmd_auipc_ex ? jump_adr :
                              cmd_csr_ex ? csr_rd_data :
                              m_cmd_finished ? m_result_ex :
                              alu_sel;
`else // SUPPORT_M
wire [31:0] rd_data_ex_pre = cmd_lui_ex ? lui_data :
                             (cmd_jal_ex | cmd_jalr_ex) ? pcp4_ex :
						      cmd_auipc_ex ? jump_adr :
                              cmd_csr_ex ? csr_rd_data :
                              alu_sel;
`endif // SUPPORT_M

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
assign rd_data_ex = amo_cmds? rs1_data_ex :
                    amo_ex_term ? amo_rs1_addr :
                    (stall_ldst) ? rd_data_roll : rd_data_ex_pre;
//wire [31:0] st_data_ex = amo_st_term ? amo_sel_data :
wire [31:0] st_data_ex = amo_ex_term ? amo_sel_data :
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
reg jmp_purge_ma2;

wire fencei_condition_ex_pre = ~jmp_purge_ma & ~jmp_purge_ma2 & cmd_fencei_ex;
assign fencei_condition_ex = ~stall & fencei_condition_ex_pre;

// jamp/br

assign jmp_adr_ex = jump_adr[31:2];

//wire jmp_condition_ex_pre = ~jmp_purge_ma & (
wire jmp_condition_ex_pre = ~jmp_purge_ma & ~jmp_purge_ma2 & (
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
wire ecall_condition_ex_pre = ~jmp_purge_ma & ~jmp_purge_ma2 & (cmd_ecall_ex | illegal_ops_ex);
assign ecall_condition_ex = ~stall & ecall_condition_ex_pre;
// mret
wire mret_condition_ex_pre = ~jmp_purge_ma & ~jmp_purge_ma2 & cmd_mret_ex;
assign mret_condition_ex = ~stall & mret_condition_ex_pre;
// interrupt
assign interrupt_condition_ex = ~stall & g_interrupt_1shot & csr_rmie;
// timer interrupt
assign timer_condition_ex = ~stall & frc_cntr_val_leq_1shot & csr_rmie;

// purge signal
assign jmp_purge_ex = jmp_condition_ex | ecall_condition_ex | mret_condition_ex | interrupt_condition_ex | timer_condition_ex | fencei_cond;

assign wbk_rd_reg_tmp = wbk_rd_reg_ex & ~jmp_purge_ma & ~illegal_ops_ex;
//assign cmd_st_tmp = cmd_st_ex & ~jmp_purge_ma;

wire wb_mask_with_exception_interrupt = interrupt_condition_ex | timer_condition_ex | g_exception;

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
	else if (~stall & ~ic_stall) begin
	//else if (~(stall_dly|stall)) begin
		jmp_purge_ma <= jmp_purge_ex_post;
		jmp_purge_ma2 <= jmp_purge_ma;
	end
end

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
		rd_adr_ma <= 5'd0;
		rd_data_ma <= 32'd0;
		st_data_ma <= 32'd0;
		ldst_code_ma <= 3'd0;
        cmd_ld_ma <= 1'b0;
        cmd_st_ma <= 1'b0;
		wbk_rd_reg_ma <= 1'b0;
	end
	//else if (~dc_stall_early) begin
	else if (~stall) begin
		rd_adr_ma <= rd_adr_ex_post;
		rd_data_ma <= rd_data_ex; // for debug test
		st_data_ma <= st_data_ex; // for debug test
		//rd_data_ma <= rd_data_ex_pre; // for debug test
		//st_data_ma <= st_data_ex_pre; // for debug test
		ldst_code_ma <= ldst_code_ex;
	    cmd_ld_ma <= cmd_ld_ex_post & ~wb_mask_with_exception_interrupt;
        cmd_st_ma <= cmd_st_ex_post & ~wb_mask_with_exception_interrupt;
		wbk_rd_reg_ma <= wbk_rd_reg_ex_post & ~wb_mask_with_exception_interrupt;
	end
end

endmodule
