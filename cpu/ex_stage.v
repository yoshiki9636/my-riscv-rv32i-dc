/*
 * My RISC-V RV32I CPU
 *   CPU Execution Stage Module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module ex_stage(
	input clk,
	input rst_n,

	// from ID
	input [31:0] rs1_data_ex,
	input [31:0] rs2_data_ex,
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
	//input dc_stall,
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
	output jmp_condition_ex,
	output [31:2] csr_mtvec_ex,
    output ecall_condition_ex,
	output [31:2] csr_mepc_ex,
	output [31:2] csr_sepc_ex,
	// from somewhere...
	input g_interrupt,
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
	
	// to ID
	output reg jmp_purge_ma,
	output jmp_purge_ex,
	// stall
	//input dc_stall_1shot_re,
	input stall,
	input stall_1shot,
	input stall_dly,
	input stall_dly2,
	input rst_pipe

	);


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

wire cmd_ld_pur = cmd_ld_ex & ~jmp_purge_ma;
//wire cmd_ld_pur = cmd_ld_ex;

// forwarding selector

wire [31:0] rs1_fwd = hit_rs1_idex_ex ? rd_data_ma :
                      hit_rs1_idma_ex ? wbk_data_wb : wbk_data_wb2;

wire [31:0] rs2_fwd = hit_rs2_idex_ex ? rd_data_ma :
                      hit_rs2_idma_ex ? wbk_data_wb : wbk_data_wb2;

// ALU selector

wire [31:0] rs1_sel = ~nohit_rs1_ex ? rs1_fwd : rs1_data_ex;

wire [31:0] rs2_sel = (cmd_ld_pur | cmd_alui_ex) ? ld_alui_ofs :
					  cmd_st_ex ? st_ofs :
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

wire [32:0] alu_add_tmp = { rs1_sel, 1'b1 } + { rs2_xor, alu_adder_comp };
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
	.post_jump_cmd_cond(post_jump_cmd_cond),
	.illegal_ops_ex(illegal_ops_ex),
	.illegal_ops_inst(illegal_ops_inst), // new
	.g_exception(g_exception),
	.g_interrupt_priv(g_interrupt_priv),
	.g_current_priv(g_current_priv),
	.csr_mepc_ex(csr_mepc_ex),
	.csr_sepc_ex(csr_sepc_ex),
	.cmd_mret_ex(cmd_mret_ex),
	.cmd_sret_ex(cmd_sret_ex),
	.cmd_uret_ex(cmd_uret_ex),
	.csr_rmie(csr_rmie), // new
	.csr_meie(csr_meie),
	.csr_mtie(csr_mtie),
	.csr_msie(csr_msie),
	.cmd_ecall_ex(cmd_ecall_ex),
	.pc_ex(pc_ex),
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
wire cmd_stld = cmd_st_ex | cmd_ld_pur;

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

wire [31:0] rd_data_ex_pre = cmd_lui_ex ? lui_data :
                             (cmd_jal_ex | cmd_jalr_ex) ? pcp4_ex :
						      cmd_auipc_ex ? jump_adr :
                              cmd_csr_ex ? csr_rd_data :
                              alu_sel;

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
wire cmd_st_tmp;
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
wire stall_ldst_pre = (stall & cmd_st_tmp) |  (stall & cmd_ld_pur);

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
		rd_adr_roll <= rd_adr_ex;
        st_data_roll <= st_data_ex_pre;
        rd_data_roll <= rd_data_ex_pre;
        ldst_code_roll <= alu_code_ex;
        cmd_ld_roll <= cmd_ld_pur;
        cmd_st_roll <= cmd_st_tmp;
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
wire stall_ldst = (stall_dly & cmd_st_ma) |  (stall_dly & cmd_ld_ma); // for debug test
//wire stall_ldst = stall_dly; // for debug test
//wire stall_ldst = 1'b0; // for debug test
//wire stall_ldst = stall & stall_dly; // for debug test
//assign rd_data_ex = stall_ldst ? rd_data_roll : rd_data_ex_pre;

//assign rd_data_ex = (stall | stall_dly2) ? rd_data_roll : rd_data_ex_pre;
//assign rd_data_ex = (stall | stall_dly) ? rd_data_roll : rd_data_ex_pre;
//assign rd_data_ex = rd_data_ex_pre;
wire [4:0] rd_adr_ex_post = (stall_ldst) ? rd_adr_roll : rd_adr_ex;
assign rd_data_ex = (stall_ldst) ? rd_data_roll : rd_data_ex_pre;
wire [31:0] st_data_ex = (stall_ldst) ? st_data_roll : st_data_ex_pre;
wire [2:0] ldst_code_ex = (stall_ldst) ? ldst_code_roll : alu_code_ex;
wire cmd_ld_ex_post = (stall_ldst) ? cmd_ld_roll : cmd_ld_pur;
wire cmd_st_ex_post = (stall_ldst) ? cmd_st_roll : cmd_st_tmp;
wire wbk_rd_reg_ex_post = (stall_ldst) ? wbk_rd_reg_roll : wbk_rd_reg_tmp;
wire jmp_purge_ex_post =  (stall_ldst) ? jmp_purge_roll : jmp_purge_ex;

// jamp/br

assign jmp_adr_ex = jump_adr[31:2];

assign jmp_condition_ex = ~stall & ~jmp_purge_ma & (
                        cmd_jal_ex | cmd_jalr_ex | cmd_br_ex &
						( seq  & (alu_code_ex == 3'b000) |
					      sne  & (alu_code_ex == 3'b001) |
					      slt  & (alu_code_ex == 3'b100) |
					      sge  & (alu_code_ex == 3'b101) |
					      sltu & (alu_code_ex == 3'b110) |
					      sbgu & (alu_code_ex == 3'b111) ));

// ecall
assign ecall_condition_ex = ~stall & ~jmp_purge_ma & (cmd_ecall_ex | illegal_ops_ex);

// purge signal
assign jmp_purge_ex = jmp_condition_ex | ecall_condition_ex;

assign wbk_rd_reg_tmp = wbk_rd_reg_ex & ~jmp_purge_ma & ~illegal_ops_ex;
assign cmd_st_tmp = cmd_st_ex & ~jmp_purge_ma;

// FF to MA

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
		jmp_purge_ma <= 1'b0;
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
	else if (~stall) begin
	//else if (~(stall_dly|stall)) begin
		jmp_purge_ma <= jmp_purge_ex_post;
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
	    cmd_ld_ma <= cmd_ld_ex_post;
        cmd_st_ma <= cmd_st_ex_post;
		wbk_rd_reg_ma <= wbk_rd_reg_ex_post;
	end
end

endmodule
