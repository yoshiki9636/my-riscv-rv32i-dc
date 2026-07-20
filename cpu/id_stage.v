/*
 * My RISC-V RV32I CPU
 *   CPU Instruction Decode Stage Module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 * @version		0.2 add part of csr instructions
 * @version		0.3 add part of M instructions
 * @version		0.4 add part of A instructions
 */

`define SUPPORT_M
`define SUPPORT_A

module id_stage(
	input clk,
	input rst_n,
	// from IF stage
	input [31:0] inst_id,
	input [31:2] pc_id,
	// to EX stage
	output [31:0] rs1_data_ex,
	output [31:0] rs2_data_ex,
	output [31:2] pc_ex,

    // control signals
    output reg cmd_lui_ex,
    output reg cmd_auipc_ex,
    output reg [31:12] lui_auipc_imm_ex,
    output reg cmd_ld_ex,
    output reg [11:0] ld_alui_ofs_ex,
    output reg cmd_alui_ex,
    output reg cmd_alui_shamt_ex,
    output reg cmd_alu_ex,
    output reg cmd_alu_add_ex,
    output reg cmd_alu_sub_ex,
    output reg [2:0] alu_code_ex,
    output reg [4:0] alui_shamt_ex,
    output reg cmd_st_ex,
    output reg [11:0] st_ofs_ex,
    output reg cmd_jal_ex,
    output reg [20:1] jal_ofs_ex,
    output reg cmd_jalr_ex,
    output reg [11:0] jalr_ofs_ex,
    output reg cmd_br_ex,
    output reg [12:1] br_ofs_ex,
    output reg cmd_fence_ex,
    output reg cmd_fencei_ex,
    output reg [3:0] fence_succ_ex,
    output reg [3:0] fence_pred_ex,
    output reg cmd_sfence_ex,
    output reg cmd_csr_ex,
    output reg [11:0] csr_ofs_ex,
	output reg [4:0] csr_uimm_ex,
	output reg [2:0] csr_op2_ex,
    output reg cmd_ecall_ex,
    output reg cmd_ebreak_ex,
    output reg cmd_uret_ex,
    output reg cmd_sret_ex,
    output reg cmd_mret_ex,
    output reg cmd_wfi_ex,
	output reg [4:0] rd_adr_ex,
	output reg wbk_rd_reg_ex,
    output reg illegal_ops_ex,
    output reg [31:0] inst_ex,
`ifdef SUPPORT_M
	output reg cmd_mul_ex,
	output reg cmd_mulh_ex,
	output reg cmd_mulhsu_ex,
	output reg cmd_mulhu_ex,
	output reg cmd_div_ex,
	output reg cmd_divu_ex,
	output reg cmd_rem_ex,
	output reg cmd_remu_ex,
	output reg cmd_mul_decode_ex,
	output reg cmd_div_decode_ex,
	output reg cmd_rem_decode_ex,
`endif // SUPPORT_M
`ifdef SUPPORT_A
	output reg cmd_lrw_ex,
	output reg cmd_scw_ex,
	output reg cmd_amoswapw_ex,
	output reg cmd_amoaddw_ex,
	output reg cmd_amoxorw_ex,
	output reg cmd_amoandw_ex,
	output reg cmd_amoorw_ex,
	output reg cmd_amominw_ex,
	output reg cmd_amomaxw_ex,
	output reg cmd_amominuw_ex,
	output reg cmd_amomaxuw_ex,
`endif // SUPPORT_A
	// from EX
	input jmp_purge_ma,
	input jmp_purge_ex,
	// from WB
	input [4:0] rd_adr_wb,
	input wbk_rd_reg_wb,
	input [31:0] wbk_data_wb,
	// to Forwarding
	output [4:0] inst_rs1_id,
	output [4:0] inst_rs2_id,
	output inst_rs1_valid,
	output inst_rs2_valid,
	// to monitor
    input rf_radr_en_mon,
    input [4:0] rf_radr_mon,
    input [4:0] rf_wadr_mon,
    input rf_we_mon,
    input [31:0] rf_wdata_mon,
    output [31:0] rf_rdata_mon,
	// stall
	input stall,
	input stall_1shot,
	input stall_dly,
	input stall_ld,
	input stall_ld_ex,
	input stall_ld_ma,
	input rst_pipe

	);

// decoder
// bit slice

wire [1:0]   inst_set = inst_id[1:0];
wire [6:2]   inst_op1 = inst_id[6:2];
wire [11:7]  inst_rd  = inst_id[11:7];
wire [14:12] inst_op2 = inst_id[14:12];
wire [19:15] inst_rs1 = inst_id[19:15];
wire [19:15] inst_uimm = inst_id[19:15];
wire [24:20] inst_rs2 = inst_id[24:20];
wire [26:25] inst_op5 = inst_id[26:25];
wire [31:27] inst_op3 = inst_id[31:27];
wire [31:12] inst_imm_31_12 = inst_id[31:12];
wire [20:1]  inst_ofs_20_1 = { inst_id[31], inst_id[19:12], inst_id[20], inst_id[30:21] };
wire [11:0]  inst_imm_11_0 = inst_id[31:20];
wire [11:0]  inst_ofs_11_0_l = inst_id[31:20];
wire [24:20] inst_shamt = inst_id[24:20];
wire         inst_zero_26 = inst_id[26];
wire [26:25] inst_zero_26_25 = inst_id[26:25];
wire [23:20] inst_succ = inst_id[23:20];
wire [27:24] inst_pred = inst_id[27:24];
wire [31:28] inst_zero_31_28 = inst_id[31:28];
wire [19:15] inst_zero_19_15 = inst_id[19:15];
wire [11:7]  inst_zero_11_7  = inst_id[11:7];
wire [24:20] inst_op4 = inst_id[24:20];
wire [11:0]  inst_ofs_11_0_s = { inst_id[31:25], inst_id[11:7] };
wire [12:1]  inst_ofs_12_1 = { inst_id[31], inst_id[7], inst_id[30:25], inst_id[11:8]};

// decode opecode and zero

wire dc_notc = (inst_set == 2'b11);
wire dc_zero_26 = (inst_zero_26 == 1'b0);
wire dc_zero_26_25 = (inst_zero_26_25 == 2'd0);
wire dc_zero_31_28 = (inst_zero_31_28 == 4'd0);
wire dc_zero_19_15 = (inst_zero_19_15 == 5'd0);
wire dc_zero_11_7  = (inst_zero_11_7  == 5'd0);

wire dc_pred = (inst_pred == 4'd0);
wire dc_succ = (inst_succ == 4'd0);

//op1

function [10:0] op1_decoder;
input [4:0] inst_op1;
begin
	case(inst_op1)
		5'b01101: op1_decoder = 11'b000_0000_0001;
		5'b00101: op1_decoder = 11'b000_0000_0010;
		5'b11011: op1_decoder = 11'b000_0000_0100;
		5'b00100: op1_decoder = 11'b000_0000_1000;
		5'b11100: op1_decoder = 11'b000_0001_0000;
		5'b00000: op1_decoder = 11'b000_0010_0000;
		5'b01100: op1_decoder = 11'b000_0100_0000;
		5'b00011: op1_decoder = 11'b000_1000_0000;
		5'b11000: op1_decoder = 11'b001_0000_0000;
		5'b01000: op1_decoder = 11'b010_0000_0000;
		5'b11001: op1_decoder = 11'b100_0000_0000;
		default : op1_decoder = 11'b00_0000_0000;
	endcase
end
endfunction

wire [10:0] dc_op1 = op1_decoder( inst_op1 );

wire dc_op1_01101 = dc_op1[0];
wire dc_op1_00101 = dc_op1[1];
wire dc_op1_11011 = dc_op1[2];
wire dc_op1_00100 = dc_op1[3];
wire dc_op1_11100 = dc_op1[4];
wire dc_op1_00000 = dc_op1[5];
wire dc_op1_01100 = dc_op1[6];
wire dc_op1_00011 = dc_op1[7];
wire dc_op1_11000 = dc_op1[8];
wire dc_op1_01000 = dc_op1[9];
wire dc_op1_11001 = dc_op1[10];

// op2

function [7:0] op2_decoder;
input [2:0] inst_op2;
begin
	case(inst_op2)
		3'b000: op2_decoder = 8'b0000_0001;
		3'b001: op2_decoder = 8'b0000_0010;
		3'b010: op2_decoder = 8'b0000_0100;
		3'b011: op2_decoder = 8'b0000_1000;
		3'b100: op2_decoder = 8'b0001_0000;
		3'b101: op2_decoder = 8'b0010_0000;
		3'b110: op2_decoder = 8'b0100_0000;
		3'b111: op2_decoder = 8'b1000_0000;
		default: op2_decoder = 8'b0000_0000;
	endcase
end
endfunction

wire [7:0] dc_op2 = op2_decoder( inst_op2 );

wire dc_op2_000 = dc_op2[0];
wire dc_op2_001 = dc_op2[1];
wire dc_op2_010 = dc_op2[2];
wire dc_op2_011 = dc_op2[3];
wire dc_op2_100 = dc_op2[4];
wire dc_op2_101 = dc_op2[5];
wire dc_op2_110 = dc_op2[6];
wire dc_op2_111 = dc_op2[7];

// op3

function [3:0] op3_decoder;
input [4:0] inst_op3;
begin
	case(inst_op3)
		5'b00000: op3_decoder = 4'b0001;
		5'b01000: op3_decoder = 4'b0010;
		5'b00010: op3_decoder = 4'b0100;
		5'b00110: op3_decoder = 4'b1000;
		default : op3_decoder = 4'b0000;
	endcase
end
endfunction

wire [3:0] dc_op3 = op3_decoder( inst_op3 );

wire dc_op3_00000 = dc_op3[0];
wire dc_op3_01000 = dc_op3[1];
wire dc_op3_00010 = dc_op3[2];
wire dc_op3_00110 = dc_op3[3];

// op4
function [3:0] op4_decoder;
input [4:0] inst_op4;
begin
	case(inst_op4)
		5'b00000: op4_decoder = 4'b0001;
		5'b00001: op4_decoder = 4'b0010;
		5'b00010: op4_decoder = 4'b0100;
		5'b00101: op4_decoder = 4'b1000;
		default : op4_decoder = 4'b0000;
	endcase
end
endfunction

wire [3:0] dc_op4 = op4_decoder( inst_op4 );

wire dc_op4_00000 = dc_op4[0];
wire dc_op4_00001 = dc_op4[1];
wire dc_op4_00010 = dc_op4[2];
wire dc_op4_00101 = dc_op4[3];

// op5

wire dc_op5_01 = (inst_op5 == 2'b01);

`ifdef SUPPORT_M
// decode opecode and zero for M

//wire dc_notc = (inst_set == 2'b11);
wire dc_op5_m = (inst_op5 == 2'b01);
wire dc_op3_m = (inst_op3 == 5'd0);
wire dc_op1_m = (inst_op1 == 5'b01100);

wire mcmd_decode = dc_notc & dc_op5_m & dc_op3_m & dc_op1_m;

// microcode signals

wire cmd_mul_id    = dc_op2_000 & mcmd_decode;
wire cmd_mulh_id   = dc_op2_001 & mcmd_decode;
wire cmd_mulhsu_id = dc_op2_010 & mcmd_decode;
wire cmd_mulhu_id  = dc_op2_011 & mcmd_decode;
wire cmd_div_id    = dc_op2_100 & mcmd_decode;
wire cmd_divu_id   = dc_op2_101 & mcmd_decode;
wire cmd_rem_id    = dc_op2_110 & mcmd_decode;
wire cmd_remu_id   = dc_op2_111 & mcmd_decode;

wire cmd_mul_decode_id = cmd_mul_id | cmd_mulh_id | cmd_mulhsu_id | cmd_mulhu_id;
wire cmd_div_decode_id = cmd_div_id | cmd_divu_id;
wire cmd_rem_decode_id = cmd_rem_id | cmd_remu_id;

`endif // SUPPORT_M

`ifdef SUPPORT_A
//wire [11:7]  inst_rd  = inst_id[11:7];
//wire [19:15] inst_rs1 = inst_id[19:15];
//wire [24:20] inst_rs2 = inst_id[24:20];
//wire [26:25] inst_op5 = inst_id[26:25]; aq, rl -> ignore because just 1 core like fence inst

//wire dc_notc = (inst_set == 2'b11); // bit 1-9
wire dc_op1_01011 = (inst_op1 == 5'b01011);
//wire dc_op2_010
wire dc_uimm_00000 = (inst_uimm == 5'b00000);

// FIX (2026-07-16): A-extension DISABLED at decode - lr.w/sc.w/amo*.w now
// raise illegal-instruction traps and are emulated by the kernel
// (arch/riscv/kernel/traps.c rv32a_emulate(), which has proper
// reservation tracking and covers both kernel and user mode as of
// 2026-07-16).  Rationale, from the 2026-07-16 RTL review
// (RTL_REVIEW_2026-07-16.md 2-2..2-4): the hardware A implementation has
// three known-unresolved hazards - (1) the AMO load address uses the
// unforwarded rs1_data_ex while the store uses the forwarded rs1_sel
// (ex_stage.v rd_data_ex mux), so an AMO whose address register is
// produced by the immediately preceding instruction loads from a stale
// address and writes a wrong value to the right one; (2) the lr/sc
// reservation (resv_flg) is not invalidated by traps/mret, so sc.w can
// succeed across a context switch; (3) an interrupt taken during
// amo_stall has no mepc special-casing (csr_array post_pc_ex has a
// div_stall term but no AMO term), risking double-executed AMOs.  The
// kernel itself contains zero A instructions (verified by objdump), but
// busybox's static glibc has ~677 of them; trapping to the emulator is
// the safe path.  misa already advertises RV32I only, so no
// discoverability change.  To re-enable hardware A after fixing
// (1)-(3), set a_ext_disable back to 1'b0 - everything downstream
// (cmd_*_id wires, cmd_all_except_nop terms, the ex_stage AMO FSM) is
// left intact and simply sees zeros while disabled.
wire a_ext_disable = 1'b1;

wire a_cmds_decode = dc_op1_01011 & dc_op2_010 & ~a_ext_disable;

// op3 decode for A insts
function [10:0] op3_decoder_a;
input [4:0] inst_op3;
begin
	case(inst_op3)
		5'b00010: op3_decoder_a = 11'b000_0000_0001; // lr.w
		5'b00011: op3_decoder_a = 11'b000_0000_0010; // sc.w
		5'b00001: op3_decoder_a = 11'b000_0000_0100; // amoswap.w
		5'b00000: op3_decoder_a = 11'b000_0000_1000; // amoadd.w
		5'b00100: op3_decoder_a = 11'b000_0001_0000; // amoxor.w
		5'b01100: op3_decoder_a = 11'b000_0010_0000; // amoand.w
		5'b01000: op3_decoder_a = 11'b000_0100_0000; // amoor.w
		5'b10000: op3_decoder_a = 11'b000_1000_0000; // amomin.w
		5'b10100: op3_decoder_a = 11'b001_0000_0000; // amomax.w
		5'b11000: op3_decoder_a = 11'b010_0000_0000; // amominu.w
		5'b11100: op3_decoder_a = 11'b100_0000_0000; // amomaxu.w
		default : op3_decoder_a = 11'b000_0000_0000;
	endcase
end
endfunction

wire [10:0] dc_op3_a = op3_decoder_a( inst_op3 );

wire cmd_lrw_id = a_cmds_decode & dc_op3_a[0];
wire cmd_scw_id = a_cmds_decode & dc_op3_a[1];
wire cmd_amoswapw_id = a_cmds_decode & dc_op3_a[2];
wire cmd_amoaddw_id = a_cmds_decode & dc_op3_a[3];
wire cmd_amoxorw_id = a_cmds_decode & dc_op3_a[4];
wire cmd_amoandw_id = a_cmds_decode & dc_op3_a[5];
wire cmd_amoorw_id = a_cmds_decode & dc_op3_a[6];
wire cmd_amominw_id = a_cmds_decode & dc_op3_a[7];
wire cmd_amomaxw_id = a_cmds_decode & dc_op3_a[8];
wire cmd_amominuw_id = a_cmds_decode & dc_op3_a[9];
wire cmd_amomaxuw_id = a_cmds_decode & dc_op3_a[10];
`endif // SUPPORT_A

// microcode signals

// load, auipc
wire cmd_lui_id = dc_op1_01101 & dc_notc;
wire cmd_auipc_id = dc_op1_00101 & dc_notc;
wire [31:12] lui_auipc_imm_id = inst_imm_31_12;

wire cmd_ld_id = dc_op1_00000 & dc_notc & ~jmp_purge_ma;
//wire [2:0] ld_bw_id = inst_op2;
wire [11:0] ld_ofs_id = inst_ofs_11_0_l;

// ALU immediate, rs2
wire cmd_alui_id = dc_op1_00100 & dc_notc & ~( dc_op2_001 | dc_op2_101 );
wire cmd_alui_shamt_id = dc_op1_00100 & dc_notc & dc_zero_26 & ( dc_op2_001 | dc_op2_101 );
wire cmd_alu_id = dc_op1_01100 & dc_notc & dc_zero_26_25;
wire cmd_alu_add_id = dc_op3_00000;
wire cmd_alu_sub_id = dc_op3_01000;

wire [2:0] alu_code_id = inst_op2;

wire [11:0] alui_imm_id = inst_imm_11_0;
wire [4:0] alui_shamt_id = inst_shamt;

// store
wire cmd_st_id = dc_op1_01000 & dc_notc & ~jmp_purge_ma;
wire [11:0] st_ofs_id = inst_ofs_11_0_s;

// jump jal jalr branch
wire cmd_jal_id = dc_op1_11011 & dc_notc & ~jmp_purge_ma;
wire [20:1] jal_ofs_id = inst_ofs_20_1;

wire cmd_jalr_id = dc_op1_11001 & dc_op2_000 & dc_notc & ~jmp_purge_ma;
wire [11:0] jalr_ofs_id = inst_ofs_11_0_l;

wire cmd_br_id = dc_op1_11000 & dc_notc & ~jmp_purge_ma;
wire [12:1] br_ofs_id = inst_ofs_12_1;

// fence
wire cmd_fence_id = dc_op1_00011 & dc_op2_000 & dc_notc & dc_zero_31_28 & dc_zero_19_15 & dc_zero_11_7;
wire cmd_fencei_id = dc_op1_00011 & dc_op2_001 & dc_notc & dc_zero_31_28 & dc_pred & dc_succ & dc_zero_19_15 & dc_zero_11_7;
wire [3:0] fence_succ_id = inst_succ;
wire [3:0] fence_pred_id = inst_pred;

// sfence
wire cmd_sfence_id = dc_op1_11100 & dc_op2_000 & dc_notc & dc_op3_00010 & dc_op5_01;

// csr
wire cmd_csr_id = dc_op1_11100 & ~dc_op2_000 & dc_notc;
wire [11:0] csr_ofs_id = inst_ofs_11_0_l;
wire [4:0] csr_uimm_id = inst_uimm;
// need to see dc_op2_001 - dc_op2_111
wire [2:0] csr_op2_id = inst_op2;

// ecall
wire cmd_ec_id  = dc_op1_11100 &  dc_op2_000 & dc_notc & dc_zero_26_25 & dc_zero_19_15 & dc_zero_11_7;
wire cmd_ecall_id  = cmd_ec_id & dc_op3_00000 & dc_op4_00000;
wire cmd_ebreak_id = cmd_ec_id & dc_op3_00000 & dc_op4_00001;
wire cmd_uret_id   = cmd_ec_id & dc_op3_00000 & dc_op4_00010;
wire cmd_sret_id   = cmd_ec_id & dc_op3_00010 & dc_op4_00010;
wire cmd_mret_id   = cmd_ec_id & dc_op3_00110 & dc_op4_00010;
wire cmd_wfi_id    = cmd_ec_id & dc_op3_00010 & dc_op4_00101;

// nop command
wire cmd_nop = (inst_id == 32'h0000_0013);
// all command except nop
//
// FIX (2026-07-16): cmd_alu_add_id / cmd_alu_sub_id REMOVED from every
// cmd_all_except_nop variant below.  They are bare funct5 matches with
// no opcode qualification at all (cmd_alu_add_id = dc_op3_00000,
// cmd_alu_sub_id = dc_op3_01000), kept that way deliberately because
// cmd_alu_sub_ex doubles as the SRA/SRAI selector in ex_stage
// (alu_srl_sra) for BOTH the OP and OP-IMM opcodes - so their VALUES
// must not change.  But as standalone terms in the valid-instruction
// list they declared every word with inst[31:27]==5'b00000 (the whole
// 0x00000000-0x07FFFFFF pattern space - all-zero words, small
// integers, most pointers on this 128MB board...) or 5'b01000
// (0x40000000-0x47FFFFFF) to be a "valid" instruction, defeating
// illegal-instruction detection for the most common garbage/data
// patterns: a wild jump into zeroed or small-value data executed it
// silently as quasi-NOPs and kept walking instead of trapping at the
// first word.  It also made amoadd.w (funct5=00000) decode as "valid"
// even with the A extension disabled above.  Every real RV32IM
// instruction remains covered: OP-opcode add/sub/sra by cmd_alu_id,
// OP-IMM addi/srai by cmd_alui_id/cmd_alui_shamt_id.

`ifdef SUPPORT_A
`ifdef SUPPORT_M
wire cmd_all_except_nop = mcmd_decode |
	cmd_lui_id | cmd_auipc_id | cmd_ld_id | cmd_alui_id | cmd_alui_shamt_id
	| cmd_alu_id | cmd_st_id | cmd_jal_id
	| cmd_jalr_id | cmd_br_id | cmd_fence_id | cmd_fencei_id | cmd_sfence_id
	| cmd_csr_id | cmd_ec_id | cmd_ecall_id | cmd_ebreak_id | cmd_uret_id  
	| cmd_sret_id | cmd_mret_id | cmd_wfi_id
	| cmd_lrw_id | cmd_scw_id | cmd_amoswapw_id | cmd_amoaddw_id | cmd_amoxorw_id
	| cmd_amoandw_id | cmd_amoorw_id | cmd_amominw_id | cmd_amomaxw_id
	| cmd_amominuw_id | cmd_amomaxuw_id;
`else // SUPPORT_M
wire cmd_all_except_nop =
	cmd_lui_id | cmd_auipc_id | cmd_ld_id | cmd_alui_id | cmd_alui_shamt_id
	| cmd_alu_id | cmd_st_id | cmd_jal_id
	| cmd_jalr_id | cmd_br_id | cmd_fence_id | cmd_fencei_id | cmd_sfence_id
	| cmd_csr_id | cmd_ec_id | cmd_ecall_id | cmd_ebreak_id | cmd_uret_id  
	| cmd_sret_id | cmd_mret_id | cmd_wfi_id
	| cmd_lrw_id | cmd_scw_id | cmd_amoswapw_id | cmd_amoaddw_id | cmd_amoxorw_id
	| cmd_amoandw_id | cmd_amoorw_id | cmd_amominw_id | cmd_amomaxw_id
	| cmd_amominuw_id | cmd_amomaxuw_id;
`endif // SUPPORT_M
`else // SUPPORT_A
`ifdef SUPPORT_M
wire cmd_all_except_nop = mcmd_decode |
	cmd_lui_id | cmd_auipc_id | cmd_ld_id | cmd_alui_id | cmd_alui_shamt_id
	| cmd_alu_id | cmd_st_id | cmd_jal_id
	| cmd_jalr_id | cmd_br_id | cmd_fence_id | cmd_fencei_id | cmd_sfence_id
	| cmd_csr_id | cmd_ec_id | cmd_ecall_id | cmd_ebreak_id | cmd_uret_id  
	| cmd_sret_id | cmd_mret_id | cmd_wfi_id;
`else // SUPPORT_M
wire cmd_all_except_nop =
	cmd_lui_id | cmd_auipc_id | cmd_ld_id | cmd_alui_id | cmd_alui_shamt_id
	| cmd_alu_id | cmd_st_id | cmd_jal_id
	| cmd_jalr_id | cmd_br_id | cmd_fence_id | cmd_fencei_id | cmd_sfence_id
	| cmd_csr_id | cmd_ec_id | cmd_ecall_id | cmd_ebreak_id | cmd_uret_id  
	| cmd_sret_id | cmd_mret_id | cmd_wfi_id;
`endif // SUPPORT_M
`endif // SUPPORT_A

wire illegal_ops_id = ~(cmd_nop | cmd_all_except_nop) & ~jmp_purge_ma & ~jmp_purge_ex & ~stall;

// destination register number
wire [4:0] rd_adr_id = inst_rd;

// destination register write back signal

//wire wbk_rd_reg_id = ~(cmd_st_id | cmd_br_id) & dc_notc & ~jmp_purge_ma;
wire wbk_rd_reg_id = ~(cmd_st_id | cmd_br_id) & dc_notc & ~jmp_purge_ma & ~stall_ld;

// for forwarding

assign inst_rs1_id = inst_rs1;
assign inst_rs2_id = inst_rs2;

`ifdef SUPPORT_A
`ifdef SUPPORT_M
assign inst_rs1_valid = cmd_alui_id | cmd_alui_shamt_id | cmd_alu_id | cmd_csr_id
                      | cmd_sfence_id | cmd_ld_id | cmd_st_id | cmd_jalr_id | cmd_br_id | mcmd_decode
	                  | cmd_lrw_id | cmd_scw_id | cmd_amoswapw_id | cmd_amoaddw_id | cmd_amoxorw_id
	                  | cmd_amoandw_id | cmd_amoorw_id | cmd_amominw_id | cmd_amomaxw_id
	                  | cmd_amominuw_id | cmd_amomaxuw_id;

assign inst_rs2_valid = cmd_alu_id | cmd_st_id | cmd_br_id | mcmd_decode
	                  | cmd_lrw_id | cmd_scw_id | cmd_amoswapw_id | cmd_amoaddw_id | cmd_amoxorw_id
	                  | cmd_amoandw_id | cmd_amoorw_id | cmd_amominw_id | cmd_amomaxw_id
	                  | cmd_amominuw_id | cmd_amomaxuw_id;
`else // SUPPORT_M
assign inst_rs1_valid = cmd_alui_id | cmd_alui_shamt_id | cmd_alu_id | cmd_csr_id
                      | cmd_sfence_id | cmd_ld_id | cmd_st_id | cmd_jalr_id | cmd_br_id
	                  | cmd_lrw_id | cmd_scw_id | cmd_amoswapw_id | cmd_amoaddw_id | cmd_amoxorw_id
	                  | cmd_amoandw_id | cmd_amoorw_id | cmd_amominw_id | cmd_amomaxw_id
	                  | cmd_amominuw_id | cmd_amomaxuw_id;

assign inst_rs2_valid = cmd_alu_id | cmd_st_id | cmd_br_id
	                  | cmd_lrw_id | cmd_scw_id | cmd_amoswapw_id | cmd_amoaddw_id | cmd_amoxorw_id
	                  | cmd_amoandw_id | cmd_amoorw_id | cmd_amominw_id | cmd_amomaxw_id
	                  | cmd_amominuw_id | cmd_amomaxuw_id;
`endif // SUPPORT_M
`else // SUPPORT_A
`ifdef SUPPORT_M
assign inst_rs1_valid = cmd_alui_id | cmd_alui_shamt_id | cmd_alu_id | cmd_csr_id |
                        cmd_sfence_id | cmd_ld_id | cmd_st_id | cmd_jalr_id | cmd_br_id | mcmd_decode;

assign inst_rs2_valid = cmd_alu_id | cmd_st_id | cmd_br_id | mcmd_decode;
`else // SUPPORT_M
assign inst_rs1_valid = cmd_alui_id | cmd_alui_shamt_id | cmd_alu_id | cmd_csr_id |
                        cmd_sfence_id | cmd_ld_id | cmd_st_id | cmd_jalr_id | cmd_br_id;

assign inst_rs2_valid = cmd_alu_id | cmd_st_id | cmd_br_id;
`endif // SUPPORT_M
`endif // SUPPORT_A

wire [4:0] inst_rs1_mon = rf_radr_en_mon ? rf_radr_mon : inst_rs1;

// zero register

wire rs1_zero = ( inst_rs1 == 5'd0);
wire rs2_zero = ( inst_rs2 == 5'd0);
reg rs1_zero_ex;
reg rs2_zero_ex;

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
        rs1_zero_ex <= 1'b1;
        rs2_zero_ex <= 1'b1;
	end
	else if (rst_pipe) begin
        rs1_zero_ex <= 1'b1;
        rs2_zero_ex <= 1'b1;
	end
	else if (~stall) begin
		rs1_zero_ex <= rs1_zero;
		rs2_zero_ex <= rs2_zero;
	end
end

wire [31:0] ram_data1;
wire [31:0] ram_data2;

// selrctor for monitor

wire wbk_rd_reg_wb_mon = wbk_rd_reg_wb | rf_we_mon;
wire [4:0] rd_adr_wb_mon = wbk_rd_reg_wb ? rd_adr_wb : rf_wadr_mon;
wire [31:0] wbk_data_wb_mon = wbk_rd_reg_wb ? wbk_data_wb : rf_wdata_mon;

// register file

rf_2r1w rf_2r1w (
	.clk(clk),
	.ram_radr1(inst_rs1_mon),
	.ram_rdata1(ram_data1),
	.ram_radr2(inst_rs2),
	.ram_rdata2(ram_data2),
	.ram_wadr(rd_adr_wb_mon),
	.ram_wdata(wbk_data_wb_mon),
	.ram_wen(wbk_rd_reg_wb_mon)
	);

assign rf_rdata_mon = ram_data1;

// roll back
wire [31:0] rs1_data_st = ram_data1 & { 32{ ~rs1_zero_ex }};
wire [31:0] rs2_data_st = ram_data2 & { 32{ ~rs2_zero_ex }};

reg [31:0] rs1_data_roll;
reg [31:0] rs2_data_roll;

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
        rs1_data_roll <= 32'd0;
        rs2_data_roll <= 32'd0;
	end
	else if (rst_pipe) begin
        rs1_data_roll <= 32'd0;
        rs2_data_roll <= 32'd0;
	end
	else if (stall_1shot | stall_ld) begin
        rs1_data_roll <= rs1_data_st;
        rs2_data_roll <= rs2_data_st;
	end
end

assign rs1_data_ex = (stall_dly | stall_ld_ex) ? rs1_data_roll : rs1_data_st;
assign rs2_data_ex = (stall_dly | stall_ld_ex) ? rs2_data_roll : rs2_data_st;

// pc_ex stops when stall_ld_ex

reg [31:2] pc_ex_pre;
reg [31:2] pc_ex_roll;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        pc_ex_roll <= 30'd0;
    end
    else if (rst_pipe) begin
        pc_ex_roll <= 30'd0;
    end
    else if ( stall_ld_ex) begin
        pc_ex_roll <= pc_ex_pre;
    end
end

assign pc_ex = stall_ld_ma ? pc_ex_roll : pc_ex_pre;

// FF to EX stage

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
        cmd_lui_ex <= 1'b0;
        cmd_auipc_ex <= 1'b0;
        lui_auipc_imm_ex <= 20'd0;
        cmd_ld_ex <= 1'b0;
        //ld_bw_ex <= 3'd0;
        ld_alui_ofs_ex <= 12'd0;
        cmd_alui_ex <= 1'b0;
        cmd_alui_shamt_ex <= 1'b0;
        cmd_alu_ex <= 1'b0;
        cmd_alu_add_ex <= 1'b0;
        cmd_alu_sub_ex <= 1'b0;
        alu_code_ex <= 3'd0;
        //alui_imm_ex <= 12'd0;
        alui_shamt_ex <= 5'd0;
        cmd_st_ex <= 1'b0;
        st_ofs_ex <= 12'd0;
        cmd_jal_ex <= 1'b0;
        jal_ofs_ex <= 20'b0;
        cmd_jalr_ex <= 1'b0;
        jalr_ofs_ex <= 12'd0;
        cmd_br_ex <= 1'b0;
        br_ofs_ex <= 12'd0;
        cmd_fence_ex <= 1'b0;
        cmd_fencei_ex <= 1'b0;
        fence_succ_ex <= 4'd0;
        fence_pred_ex <= 4'd0;
        cmd_sfence_ex <= 1'b0;
        cmd_csr_ex <= 1'b0;
        csr_ofs_ex <= 12'd0;
		csr_uimm_ex <= 5'd0;
		csr_op2_ex <= 3'd0;
        cmd_ecall_ex <= 1'b0;
        cmd_ebreak_ex <= 1'b0;
        cmd_uret_ex <= 1'b0;
        cmd_sret_ex <= 1'b0;
        cmd_mret_ex <= 1'b0;
        cmd_wfi_ex <= 1'b0;
		illegal_ops_ex <= 1'b0;
		rd_adr_ex <= 5'd0;
		wbk_rd_reg_ex <= 1'b0;
		pc_ex_pre <= 30'd0;
		inst_ex <= 32'd0;
`ifdef SUPPORT_M
		cmd_mul_ex <= 1'b0;
		cmd_mulh_ex <= 1'b0;
		cmd_mulhsu_ex <= 1'b0;
		cmd_mulhu_ex <= 1'b0;
		cmd_div_ex <= 1'b0;
		cmd_divu_ex <= 1'b0;
		cmd_rem_ex <= 1'b0;
		cmd_remu_ex <= 1'b0;
		cmd_mul_decode_ex <= 1'b0;
		cmd_div_decode_ex <= 1'b0;
		cmd_rem_decode_ex <= 1'b0;
`endif // SUPPORT_M
`ifdef SUPPORT_A
		cmd_lrw_ex <= 1'b0;
		cmd_scw_ex <= 1'b0;
		cmd_amoswapw_ex <= 1'b0;
		cmd_amoaddw_ex <= 1'b0;
		cmd_amoxorw_ex <= 1'b0;
		cmd_amoandw_ex <= 1'b0;
		cmd_amoorw_ex <= 1'b0;
		cmd_amominw_ex <= 1'b0;
		cmd_amomaxw_ex <= 1'b0;
		cmd_amominuw_ex <= 1'b0;
		cmd_amomaxuw_ex <= 1'b0;
`endif // SUPPORT_A
     end
	else if (rst_pipe) begin
        cmd_lui_ex <= 1'b0;
        cmd_auipc_ex <= 1'b0;
        lui_auipc_imm_ex <= 20'd0;
        cmd_ld_ex <= 1'b0;
        //ld_bw_ex <= 3'd0;
        ld_alui_ofs_ex <= 12'd0;
        cmd_alui_ex <= 1'b0;
        cmd_alui_shamt_ex <= 1'b0;
        cmd_alu_ex <= 1'b0;
        cmd_alu_add_ex <= 1'b0;
        cmd_alu_sub_ex <= 1'b0;
        alu_code_ex <= 3'd0;
        //alui_imm_ex <= 12'd0;
        alui_shamt_ex <= 5'd0;
        cmd_st_ex <= 1'b0;
        st_ofs_ex <= 12'd0;
        cmd_jal_ex <= 1'b0;
        jal_ofs_ex <= 20'b0;
        cmd_jalr_ex <= 1'b0;
        jalr_ofs_ex <= 12'd0;
        cmd_br_ex <= 1'b0;
        br_ofs_ex <= 12'd0;
        cmd_fence_ex <= 1'b0;
        cmd_fencei_ex <= 1'b0;
        fence_succ_ex <= 4'd0;
        fence_pred_ex <= 4'd0;
        cmd_sfence_ex <= 1'b0;
        cmd_csr_ex <= 1'b0;
        csr_ofs_ex <= 12'd0;
		csr_uimm_ex <= 5'd0;
		csr_op2_ex <= 3'd0;
        cmd_ecall_ex <= 1'b0;
        cmd_ebreak_ex <= 1'b0;
        cmd_uret_ex <= 1'b0;
        cmd_sret_ex <= 1'b0;
        cmd_mret_ex <= 1'b0;
        cmd_wfi_ex <= 1'b0;
		illegal_ops_ex <= 1'b0;
		rd_adr_ex <= 5'd0;
		wbk_rd_reg_ex <= 1'b0;
		pc_ex_pre <= 30'd0;
`ifdef SUPPORT_M
		cmd_mul_ex <= 1'b0;
		cmd_mulh_ex <= 1'b0;
		cmd_mulhsu_ex <= 1'b0;
		cmd_mulhu_ex <= 1'b0;
		cmd_div_ex <= 1'b0;
		cmd_divu_ex <= 1'b0;
		cmd_rem_ex <= 1'b0;
		cmd_remu_ex <= 1'b0;
		cmd_mul_decode_ex <= 1'b0;
		cmd_div_decode_ex <= 1'b0;
		cmd_rem_decode_ex <= 1'b0;
`endif // SUPPORT_M
`ifdef SUPPORT_A
		cmd_lrw_ex <= 1'b0;
		cmd_scw_ex <= 1'b0;
		cmd_amoswapw_ex <= 1'b0;
		cmd_amoaddw_ex <= 1'b0;
		cmd_amoxorw_ex <= 1'b0;
		cmd_amoandw_ex <= 1'b0;
		cmd_amoorw_ex <= 1'b0;
		cmd_amominw_ex <= 1'b0;
		cmd_amomaxw_ex <= 1'b0;
		cmd_amominuw_ex <= 1'b0;
		cmd_amomaxuw_ex <= 1'b0;
`endif // SUPPORT_A
     end
     else if (~stall) begin
        cmd_lui_ex <= cmd_lui_id & ~stall_ld;
        cmd_auipc_ex <= cmd_auipc_id & ~stall_ld;
        lui_auipc_imm_ex <= lui_auipc_imm_id;
        cmd_ld_ex <= cmd_ld_id & ~stall_ld;
        //ld_bw_ex <= ld_bw_id;
        ld_alui_ofs_ex <= ld_ofs_id;
        cmd_alui_ex <= cmd_alui_id & ~stall_ld;
        cmd_alui_shamt_ex <= cmd_alui_shamt_id & ~stall_ld;
        cmd_alu_ex <= cmd_alu_id & ~stall_ld;
        cmd_alu_add_ex <= cmd_alu_add_id & ~stall_ld;
        cmd_alu_sub_ex <= cmd_alu_sub_id & ~stall_ld;
        alu_code_ex <= alu_code_id;
        //alui_imm_ex <= alui_imm_id;
        alui_shamt_ex <= alui_shamt_id;
        cmd_st_ex <= cmd_st_id & ~stall_ld;
        st_ofs_ex <= st_ofs_id;
        cmd_jal_ex <= cmd_jal_id & ~stall_ld;
        jal_ofs_ex <= jal_ofs_id;
        cmd_jalr_ex <= cmd_jalr_id & ~stall_ld;
        jalr_ofs_ex <= jalr_ofs_id;
        cmd_br_ex <= cmd_br_id & ~stall_ld;
        br_ofs_ex <= br_ofs_id;
        cmd_fence_ex <= cmd_fence_id & ~stall_ld;
        cmd_fencei_ex <= cmd_fencei_id & ~stall_ld;
        fence_succ_ex <= fence_succ_id;
        fence_pred_ex <= fence_pred_id;
        cmd_sfence_ex <= cmd_sfence_id & ~stall_ld;
        cmd_csr_ex <= cmd_csr_id & ~stall_ld;
        csr_ofs_ex <= csr_ofs_id;
		csr_uimm_ex <= csr_uimm_id;
		csr_op2_ex <= csr_op2_id;
        cmd_ecall_ex <= cmd_ecall_id & ~stall_ld;
        cmd_ebreak_ex <= cmd_ebreak_id & ~stall_ld;
        cmd_uret_ex <= cmd_uret_id & ~stall_ld;
        cmd_sret_ex <= cmd_sret_id & ~stall_ld;
        cmd_mret_ex <= cmd_mret_id & ~stall_ld;
        cmd_wfi_ex <= cmd_wfi_id & ~stall_ld;
		illegal_ops_ex <= illegal_ops_id & ~stall_ld;
		rd_adr_ex <= rd_adr_id;
		wbk_rd_reg_ex <= wbk_rd_reg_id;
		pc_ex_pre <= pc_id;
		inst_ex <= inst_id;
`ifdef SUPPORT_M
		cmd_mul_ex <= cmd_mul_id & ~stall_ld;
		cmd_mulh_ex <= cmd_mulh_id & ~stall_ld;
		cmd_mulhsu_ex <= cmd_mulhsu_id & ~stall_ld;
		cmd_mulhu_ex <= cmd_mulhu_id & ~stall_ld;
		cmd_div_ex <= cmd_div_id & ~stall_ld;
		cmd_divu_ex <= cmd_divu_id & ~stall_ld;
		cmd_rem_ex <= cmd_rem_id & ~stall_ld;
		cmd_remu_ex <= cmd_remu_id & ~stall_ld;
		cmd_mul_decode_ex <= cmd_mul_decode_id & ~stall_ld;
		cmd_div_decode_ex <= cmd_div_decode_id & ~stall_ld;
		cmd_rem_decode_ex <= cmd_rem_decode_id & ~stall_ld;
`endif // SUPPORT_M
`ifdef SUPPORT_A
		cmd_lrw_ex <= cmd_lrw_id & ~stall_ld;
		cmd_scw_ex <= cmd_scw_id & ~stall_ld;
		cmd_amoswapw_ex <= cmd_amoswapw_id & ~stall_ld;
		cmd_amoaddw_ex <= cmd_amoaddw_id & ~stall_ld;
		cmd_amoxorw_ex <= cmd_amoxorw_id & ~stall_ld;
		cmd_amoandw_ex <= cmd_amoandw_id & ~stall_ld;
		cmd_amoorw_ex <= cmd_amoorw_id & ~stall_ld;
		cmd_amominw_ex <= cmd_amominw_id & ~stall_ld;
		cmd_amomaxw_ex <= cmd_amomaxw_id & ~stall_ld;
		cmd_amominuw_ex <= cmd_amominuw_id & ~stall_ld;
		cmd_amomaxuw_ex <= cmd_amomaxuw_id & ~stall_ld;
`endif // SUPPORT_A
    end
end

endmodule
