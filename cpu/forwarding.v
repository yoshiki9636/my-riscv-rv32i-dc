/*
 * My RISC-V RV32I CPU
 *   CPU Forwarding Module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module forwarding(
	input clk,
	input rst_n,
	// id and valid from stages
	input [4:0] inst_rs1_id,
	input inst_rs1_valid,
	input [4:0] inst_rs2_id,
	input inst_rs2_valid,
	input [4:0] rd_adr_ex,
	input wbk_rd_reg_ex,
    input cmd_ld_ex,
	input [4:0] rd_adr_ma,
	input wbk_rd_reg_ma,
	input [4:0] rd_adr_wb,
	input wbk_rd_reg_wb,
	
	output reg hit_rs1_idex_ex,
	output reg hit_rs1_idma_ex,
	output reg hit_rs1_idwb_ex,
	output reg nohit_rs1_ex,
	output reg hit_rs2_idex_ex,
	output reg hit_rs2_idma_ex,
	output reg hit_rs2_idwb_ex,
	output reg nohit_rs2_ex,
	output reg stall_ld_ex,
	output stall_ld,
	// stall
	input stall,
	input stall_dly,
	input stall_ex,
	input stall_ma,
	input stall_wb,
	input stall_fin2,
	input rst_pipe

	);

// comparetor
reg hit_rs1_ldidex_dly;
reg hit_rs2_ldidex_dly;

wire notstall_ex = ~stall_ex;
wire notstall_ma = ~stall_ma;
wire notstall_wb = ~stall_wb;


wire rd_adr_ex_not0 = |rd_adr_ex;
wire rd_adr_ma_not0 = |rd_adr_ma;
wire rd_adr_wb_not0 = |rd_adr_wb;
wire hit_rs1_ldidex = rd_adr_ex_not0 & (inst_rs1_id == rd_adr_ex) & notstall_ex & inst_rs1_valid & wbk_rd_reg_ex & cmd_ld_ex;
wire hit_rs1_idex = rd_adr_ex_not0 & (inst_rs1_id == rd_adr_ex) & notstall_ex & inst_rs1_valid & wbk_rd_reg_ex & ~cmd_ld_ex & ~hit_rs1_ldidex_dly;
wire hit_rs1_idma = rd_adr_ma_not0 & (inst_rs1_id == rd_adr_ma) & notstall_ma & inst_rs1_valid & wbk_rd_reg_ma;
wire hit_rs1_idwb = rd_adr_wb_not0 & (inst_rs1_id == rd_adr_wb) & notstall_wb & inst_rs1_valid & wbk_rd_reg_wb;
//wire hit_rs1_idma = (rd_adr_ma_not0 & (inst_rs1_id == rd_adr_ma) & notstall_ma & inst_rs1_valid & wbk_rd_reg_ma) | stall_fin2;
//wire hit_rs1_idwb = rd_adr_wb_not0 & (inst_rs1_id == rd_adr_wb) & notstall_wb & inst_rs1_valid & wbk_rd_reg_wb  & ~stall_fin2;
wire nohit_rs1 = ~( hit_rs1_idex | hit_rs1_idma | hit_rs1_idwb);

wire hit_rs2_ldidex = rd_adr_ex_not0 & (inst_rs2_id == rd_adr_ex) & notstall_ex & inst_rs2_valid & wbk_rd_reg_ex & cmd_ld_ex;
wire hit_rs2_idex = rd_adr_ex_not0 & (inst_rs2_id == rd_adr_ex) & notstall_ex & inst_rs2_valid & wbk_rd_reg_ex & ~cmd_ld_ex & ~hit_rs2_ldidex_dly;
//wire hit_rs2_idma = (rd_adr_ma_not0 & (inst_rs2_id == rd_adr_ma) & notstall_ma & inst_rs2_valid & wbk_rd_reg_ma) | stall_fin2;
//wire hit_rs2_idwb = rd_adr_wb_not0 & (inst_rs2_id == rd_adr_wb) & notstall_wb & inst_rs2_valid & wbk_rd_reg_wb & ~stall_fin2;
wire hit_rs2_idma = rd_adr_ma_not0 & (inst_rs2_id == rd_adr_ma) & notstall_ma & inst_rs2_valid & wbk_rd_reg_ma;
wire hit_rs2_idwb = rd_adr_wb_not0 & (inst_rs2_id == rd_adr_wb) & notstall_wb & inst_rs2_valid & wbk_rd_reg_wb;
wire nohit_rs2 = ~( hit_rs2_idex | hit_rs2_idma | hit_rs2_idwb);

// for stall 1 cycle
reg keep_stall_ld;

wire stall_ld_pre = hit_rs1_ldidex | hit_rs2_ldidex;
assign stall_ld = stall_dly ? keep_stall_ld : stall_ld_pre;

// keep stall_ld during stall
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		keep_stall_ld <= 1'b0;
	else if (rst_pipe)
		keep_stall_ld <= 1'b0;
	else if (~stall)
		keep_stall_ld <= stall_ld;
end

// pipeline FF
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		hit_rs1_idex_ex <= 1'b0;
		hit_rs1_idma_ex <= 1'b0;
		hit_rs1_idwb_ex <= 1'b0;
		nohit_rs1_ex <= 1'b0;
		hit_rs2_idex_ex <= 1'b0;
		hit_rs2_idma_ex <= 1'b0;
		hit_rs2_idwb_ex <= 1'b0;
		nohit_rs2_ex <= 1'b0;
		stall_ld_ex <= 1'b0;
		hit_rs1_ldidex_dly <= 1'b0;
		hit_rs2_ldidex_dly <= 1'b0;
	end
	else if (rst_pipe) begin
		hit_rs1_idex_ex <= 1'b0;
		hit_rs1_idma_ex <= 1'b0;
		hit_rs1_idwb_ex <= 1'b0;
		nohit_rs1_ex <= 1'b0;
		hit_rs2_idex_ex <= 1'b0;
		hit_rs2_idma_ex <= 1'b0;
		hit_rs2_idwb_ex <= 1'b0;
		nohit_rs2_ex <= 1'b0;
		stall_ld_ex <= 1'b0;
		hit_rs1_ldidex_dly <= 1'b0;
		hit_rs2_ldidex_dly <= 1'b0;
	end
	//else if (~stall) begin
	else begin
		hit_rs1_idex_ex <= hit_rs1_idex;
		hit_rs1_idma_ex <= hit_rs1_idma;
		hit_rs1_idwb_ex <= hit_rs1_idwb;
		nohit_rs1_ex <= nohit_rs1;
		hit_rs2_idex_ex <= hit_rs2_idex;
		hit_rs2_idma_ex <= hit_rs2_idma;
		hit_rs2_idwb_ex <= hit_rs2_idwb;
		nohit_rs2_ex <= nohit_rs2;
		stall_ld_ex <= stall_ld;
		hit_rs1_ldidex_dly <= hit_rs1_ldidex;
		hit_rs2_ldidex_dly <= hit_rs2_ldidex;
	end
end

endmodule
