/*
 * My RISC-V RV32I CPU
 *   Control and Status Register Module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

`define SUPPORT_M

module csr_array(
	input clk,
	input rst_n,

	// from ID
    input cmd_csr_ex,
    input [11:0] csr_ofs_ex,
	input [4:0] csr_uimm_ex,
	input [2:0] csr_op2_ex,
	input [31:0] rs1_sel,
	output [31:0] csr_rd_data,
	output [31:2] csr_mtvec_ex,
	input g_interrupt,
	input interrupt_condition_ex,
	input frc_cntr_val_leq,
	input timer_condition_ex,
	input post_jump_cmd_cond, // old?
	input illegal_ops_ex,
    input [31:0] illegal_ops_inst, // new
	input g_exception,
	input [1:0] g_interrupt_priv,
	input [1:0] g_current_priv,
	output [31:2] csr_mepc_ex,
	output [31:2] csr_sepc_ex,
	input cmd_mret_ex,
	input cmd_sret_ex,
	input cmd_uret_ex,
    output reg csr_rmie, // new
	output csr_meie,
	output csr_mtie,
	output csr_msie,
    input ecall_condition_ex,
	input cmd_ebreak_ex,
	input [31:2] pc_id,
	input [31:2] pc_ex,
	input [31:2] jmp_adr_if,
	input jmp_condition_ex,
	input fencei_condition_ex,
	input mret_condition_ex,
`ifdef SUPPORT_M
	input div_stall_start,
	input div_stall_dly,
`endif // SUPPORT_M
	input stall,
    input csr_radr_en_mon, // new
    input [11:0] csr_radr_mon, // new
    input [11:0] csr_wadr_mon, // new
    input csr_we_mon, // new
    input [31:0] csr_wdata_mon, // new
    output [31:0] csr_rdata_mon // new
	);

// csr address definition

`define CSR_MSTATUS_ADR 12'h300
`define CSR_MISA_ADR 12'h301
`define CSR_MTVEC_ADR 12'h305
`define CSR_MSCRACH_ADR 12'h340
`define CSR_MEPC_ADR 12'h341
`define CSR_MCAUSE_ADR 12'h342
`define CSR_MTVAL_ADR 12'h343
`define CSR_MSTATUSH_ADR 12'h310
`define CSR_SSCRACH_ADR 12'h140
`define CSR_SEPC_ADR 12'h141
`define CSR_MIE_ADR 12'h304
`define CSR_MIP_ADR 12'h344

`define M_MODE 2'b11
`define S_MODE 2'b01
`define U_MODE 2'b00

// MISA resigister value
// MXL[31:30] : 01 : 32bit
// Extentions[25:0] : only I
`define CSR_MISA_DATA 32'h4000_0100

// op2 decode
wire immidiate = csr_op2_ex[2];
wire cmd_rw = (csr_op2_ex[1:0] == 2'b01);
wire cmd_rs = (csr_op2_ex[1:0] == 2'b10);
wire cmd_rc = (csr_op2_ex[1:0] == 2'b11);

// address decode

wire [11:0] csr_ofs_ex_pm = (csr_radr_en_mon) ? csr_radr_mon :
                            (csr_we_mon) ? csr_wadr_mon : csr_ofs_ex;

wire adr_mstatus = (csr_ofs_ex_pm == `CSR_MSTATUS_ADR);
wire adr_misa = (csr_ofs_ex_pm == `CSR_MISA_ADR);
wire adr_mtvec = (csr_ofs_ex_pm == `CSR_MTVEC_ADR);
wire adr_mscrach = (csr_ofs_ex_pm == `CSR_MSCRACH_ADR);
wire adr_sscrach = (csr_ofs_ex_pm == `CSR_SSCRACH_ADR);
wire adr_mepc = (csr_ofs_ex_pm == `CSR_MEPC_ADR);
wire adr_sepc = (csr_ofs_ex_pm == `CSR_SEPC_ADR);
wire adr_mcause = (csr_ofs_ex_pm == `CSR_MCAUSE_ADR);
wire adr_mtval = (csr_ofs_ex_pm == `CSR_MTVAL_ADR);
wire adr_mstatush = (csr_ofs_ex_pm == `CSR_MSTATUSH_ADR);
wire adr_mip = (csr_ofs_ex_pm == `CSR_MIP_ADR);
wire adr_mie = (csr_ofs_ex_pm == `CSR_MIE_ADR);

// read data selector
wire [31:0] csr_mstatus;
reg [31:0] csr_mstatush;
wire [31:0] csr_misa = `CSR_MISA_DATA;
reg [31:0] csr_mtvec;
reg [31:2] csr_mepc;
reg [6:0] csr_mcause;
reg [31:0] csr_mtval;
//wire [31:2] csr_sepc_i = 30'd0;
assign csr_sepc_ex = 30'd0;
wire [31:0] csr_mip;
wire [31:0] csr_mie;
reg [31:0] csr_mscrach;
reg [31:0] csr_sscrach;

wire [31:0] csr_rsel = adr_mstatus ? csr_mstatus :
                       adr_misa ? csr_misa :
                       adr_mtvec ? csr_mtvec :
                       adr_mepc ? { csr_mepc, 2'b00 } :
                       adr_sepc ? { csr_sepc_ex, 2'b00 } :
                       adr_mcause ?  { csr_mcause[6], 25'd0, csr_mcause[5:0] } :
                       adr_mtval ? csr_mtval :
                       adr_mstatush ? csr_mstatush :
                       adr_mip ? csr_mip :
                       adr_mie ? csr_mie :
                       adr_mscrach ? csr_mscrach :
                       adr_sscrach ? csr_sscrach :
                       32'd0;

assign csr_rd_data = csr_rsel;
assign csr_rdata_mon = csr_rsel;

//reg [31:0] csrrw_swap_value;

//always @ ( posedge clk or negedge rst_n) begin
    //if (~rst_n)
        //csrrw_swap_value <= 32'd0;
    //else if ( cmd_csr_ex )
        //csrrw_swap_value <= csr_rsel;
//end

//assign csr_rd_data = csrrw_swap_value;

// wirte data selector 
wire [31:0] wdata_rw = immidiate ? { 27'd0, csr_uimm_ex } : rs1_sel;
wire [31:0] wdata_rs = wdata_rw | csr_rsel ;
wire [31:0] wdata_rc = (~wdata_rw) & csr_rsel ;
wire [31:0] wdata_all = cmd_rw ? wdata_rw :
                        cmd_rs ? wdata_rs :
						cmd_rc ? wdata_rc : 32'd0;

// csr registers
// mstatus
wire mstatus_wr =(~stall)&(cmd_csr_ex)&(adr_mstatus);

//reg csr_rmie;
reg csr_sie;
reg csr_mpie;
reg csr_spie;
reg [1:0] csr_mpp;
reg csr_spp;

// MIE[3] : Machine mode Global Interrupt enable
//wire m_interrupt = g_interrupt & (g_interrupt_priv == `M_MODE);
//wire m_interrupt =  (interrupts_in_pc_state & (g_interrupt_priv == `M_MODE) | ecall_condition_ex | cmd_ebreak_ex ) & cpu_stat_pc & csr_rmie | g_exception;
//wire m_interrupt =  (g_interrupt & (g_interrupt_priv == `M_MODE) | ecall_condition_ex) & csr_rmie | g_exception;
wire m_interrupt =  ((interrupt_condition_ex | timer_condition_ex) & (g_interrupt_priv == `M_MODE)) & csr_rmie | ecall_condition_ex | g_exception;
//wire rmie_wr = m_interrupt | cmd_mret_ex;
wire rmie_wr = m_interrupt | mret_condition_ex;
//wire rmie_value = m_interrupt ? 1'b0 :
                 //cmd_mret_ex ? csr_mpie : csr_rmie;
wire pc_int_ecall_syn_end = 1'b0; // temp fixed
wire rmie_value = pc_int_ecall_syn_end ? 1'b0 :
                  cmd_mret_ex ? csr_mpie :
                  m_interrupt ? 1'b0 : csr_rmie;

always @ ( posedge clk or negedge rst_n) begin 
	if (~rst_n) begin
		csr_rmie <= 1'b0;
	end
	else if (rmie_wr) begin
		csr_rmie <= rmie_value;
	end
	else if (mstatus_wr) begin
		csr_rmie <= wdata_all[3];
	end
    else if (csr_we_mon & adr_mstatus) begin
        csr_rmie <= csr_wdata_mon[3];
    end
end

// MPIE[7] : Machine mode Previouse Interrupt Enable
wire mpie_wr = m_interrupt | mret_condition_ex;
wire mpie_value = m_interrupt ? csr_rmie :
                  cmd_mret_ex ? 1'b1 : csr_mpie;

always @ ( posedge clk or negedge rst_n) begin 
	if (~rst_n) begin
		csr_mpie <= 1'b0;
	end
	else if (mpie_wr) begin
		csr_mpie <= mpie_value;
	end
	else if (mstatus_wr) begin
		csr_mpie <= wdata_all[7];
	end
    else if (csr_we_mon & adr_mstatus) begin
        csr_mpie <= csr_wdata_mon[7];
    end
end

// MPP[12:11] : Machine mode Previouse Privilege
wire mpp_wr = m_interrupt | mret_condition_ex;
//wire [1:0] mpp_value = m_interrupt ? g_current_priv :
                       //cmd_mret_ex ? `M_MODE : // currently only M_MODE support
                       //csr_mpp;
wire [1:0] mpp_value = pc_int_ecall_syn_end ? csr_mpp :
                       m_interrupt ? g_current_priv :
                       cmd_mret_ex ? `M_MODE : // currently only M_MODE support
                       csr_mpp;

always @ ( posedge clk or negedge rst_n) begin 
	if (~rst_n) begin
		csr_mpp <= 2'b00;
	end
	else if (mpp_wr) begin
		csr_mpp <= mpp_value;
	end
	else if (mstatus_wr) begin
		csr_mpp <= wdata_all[12:11];
	end
    else if (csr_we_mon & adr_mstatus) begin
        csr_mpp <= csr_wdata_mon[12:11];
    end
end

// SIE[1] : Supervisor mode Global Interrupt enable : currently not used
//wire s_interrupt = g_interrupt & (g_interrupt_priv == `S_MODE);
//wire s_interrupt = g_interrupt & (g_interrupt_priv == `S_MODE) & csr_sie;
wire s_interrupt = (interrupt_condition_ex | timer_condition_ex) & (g_interrupt_priv == `S_MODE) & csr_sie;
wire sie_wr = s_interrupt | cmd_sret_ex;
wire sie_value = s_interrupt ? 1'b0 :
                 cmd_sret_ex ? csr_spie : csr_sie;

always @ ( posedge clk or negedge rst_n) begin 
	if (~rst_n) begin
		csr_sie <= 1'b0;
	end
	else if (sie_wr) begin
		csr_sie <= sie_value;
	end
	else if (mstatus_wr) begin
		csr_sie <= wdata_all[1];
	end
    else if (csr_we_mon & adr_mstatus) begin
        csr_sie <= csr_wdata_mon[1];
    end
end

// SPIE[5] : Supervisor mode Previouse Interrupt Enable
wire spie_wr = s_interrupt | cmd_sret_ex;
wire spie_value = s_interrupt ? csr_sie :
                  cmd_sret_ex ? 1'b1 : csr_spie;

always @ ( posedge clk or negedge rst_n) begin 
	if (~rst_n) begin
		csr_spie <= 1'b0;
	end
	else if (spie_wr) begin
		csr_spie <= spie_value;
	end
	else if (mstatus_wr) begin
		csr_spie <= wdata_all[5];
	end
    else if (csr_we_mon & adr_mstatus) begin
        csr_spie <= csr_wdata_mon[5];
    end
end


// SPP[8] : Supervisor mode Previouse Privilege
// cueerntly fixed 0 because it dows not support S-mode
wire spp_wr = s_interrupt | cmd_sret_ex;
//wire [1:0] spp_value = s_interrupt ? g_current_priv :
                 //cmd_sret_ex ? `U_MODE : // need to check when use the value
                 //csr_spp;

always @ ( posedge clk or negedge rst_n) begin 
	if (~rst_n) begin
		csr_spp <= 1'b0;
	end
	else if (spp_wr) begin
		//csr_spp <= spp_value;
		csr_spp <= 1'b0;
	end
	else if (mstatus_wr) begin
		csr_spp <= wdata_all[8];
		//csr_spp <= 1'b0;
	end
    else if (csr_we_mon & adr_mstatus) begin
        csr_spp <= csr_wdata_mon[8];
    end
end

assign csr_mstatus = { 19'd0, csr_mpp, 2'b00, csr_spp, csr_mpie,
                       1'b0, csr_spie, 1'b0, csr_rmie, 1'b0, csr_sie, 1'b0 };
// MPRV, MXR : is not implemented becase no U-MODE now
// SUM : is not implemented becase no S-MODE and virturalzation now
// FS,VS,XS, SD is not implemented because none of extentions are implemented
// TVM is not implemented because no virtualization implemented
// TW  is not implemented because ecurrently WFI instruction is not implemented
// TSR is not implemented because S-mode is not implemented.

// MISA : currently implimented as read-only

wire [5:0] mcause_code;

// mtvec
always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
		csr_mtvec <= 32'd0;
	end
	else if ((~stall)&(cmd_csr_ex)&(adr_mtvec)) begin
		csr_mtvec <= wdata_all;
	end
    else if (csr_we_mon & adr_mtvec) begin
        csr_mtvec <= csr_wdata_mon;
    end
end

//assign csr_mtvec_ex = csr_mtvec[31:2];
assign csr_mtvec_ex = (csr_mtvec[1:0] == 2'd0) ? csr_mtvec[31:2] : csr_mtvec[31:2] + { 24'd0, mcause_code[5:0] };

//assign pc_csr_mtvec = csr_mtvec[31:2];

// mscrach
// scrach register for m-mode
always @ ( posedge clk or negedge rst_n) begin
    if (~rst_n)
        csr_mscrach <= 32'd0;
    else if ((cmd_csr_ex)&(adr_mscrach))
        csr_mscrach <= wdata_all;
    else if (csr_we_mon & adr_mscrach)
        csr_mscrach <= csr_wdata_mon;
end

// sscrach
// scrach register for s-mode
always @ ( posedge clk or negedge rst_n) begin
    if (~rst_n)
        csr_sscrach <= 32'd0;
    else if ((cmd_csr_ex)&(adr_sscrach))
        csr_sscrach <= wdata_all;
    else if (csr_we_mon & adr_sscrach)
        csr_sscrach <= csr_wdata_mon;
end


// mepc
// capture PC when ecall occured
wire [31:2] sel_pc_ex;
wire [31:2] sel_pc_ex_2;
wire [31:2] sel_pc_id;

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
		csr_mepc <= 30'd0;
	end
	//else if ( ecall_condition_ex | g_exception ) begin
		//csr_mepc <= sel_pc_ex_2;
	//end
	else if ( m_interrupt ) begin
		csr_mepc <= sel_pc_ex;
	end
	else if ((~stall)&(cmd_csr_ex)&(adr_mepc)) begin
		csr_mepc <= wdata_all[31:2];
	end
    else if (csr_we_mon & adr_mepc) begin
        csr_mepc <= csr_wdata_mon[31:2];
    end
end

assign csr_mepc_ex = csr_mepc[31:2];

// mcause
// conditions
//
// FIX (2026-07-16): mcause/mtval must be selected by the condition that
// actually FIRED this trap, not by the raw pending LEVELS of the
// interrupt sources.  The old code used g_interrupt/frc_cntr_val_leq
// (level signals that stay asserted from compare-match until the ISR
// clears the FRC status bit) as both the code selector and the
// interrupt bit.  Consequence: while mstatus.MIE=0 (inside the timer
// ISR itself, or any irq-off region) with a timer compare already
// pending, an illegal-instruction trap (e.g. a wild jump into garbage)
// or an ecall was reported as mcause=0x8000_0007 - i.e. disguised as a
// normal timer interrupt.  The kernel then serviced a "timer
// interrupt", mret'ed straight back to the faulting PC and trapped
// again forever, and mtval was 0 instead of the faulting instruction.
// This masked real crashes as spurious timer interrupts and destroyed
// the diagnostics.
//
// interrupt_condition_ex / timer_condition_ex are the actual 1-shot
// "this trap is being taken now" strobes from ex_stage (already gated
// by ~stall & csr_rmie), so they are the correct selectors and are
// timing-consistent with mcause_write below.  illegal_ops_ex is
// checked before ecall_condition_ex because ex_stage's
// ecall_condition_ex includes illegal_ops_ex in its OR (in practice
// g_exception suppresses ecall_condition_ex for illegal ops, but the
// explicit priority keeps this correct even if that coupling changes).
//wire interrupt_bit = interrupt_condition_ex;
wire interrupt_bit = interrupt_condition_ex | timer_condition_ex;

// EBREAK (2026-07-23): cmd_ebreak_ex is decoded/purge-tracked in id_stage
// exactly like illegal_ops_ex (same reset/purge conditions) and folded into
// ex_stage's ecall_condition_ex OR, so by the time this trap fires it is
// checked ahead of the generic ecall_condition_ex fallback below - giving
// ebreak its own mcause=3 (breakpoint) instead of being reported as an
// ecall (mcause=11).
assign mcause_code = interrupt_condition_ex ? 6'd11 :
                     timer_condition_ex ? 6'd7 :
                     illegal_ops_ex ? 6'd2 :
                     cmd_ebreak_ex ? 6'd3 :
                     ecall_condition_ex ?  6'd11 :
                     6'h3f;

// FIX (2026-07-16): same level-vs-condition fix as mcause_code above -
// an illegal-instruction trap taken while a timer compare was pending
// used to lose its mtval (reported 0 instead of the faulting
// instruction bits).
// EBREAK (2026-07-23): mtval for a breakpoint trap carries the ebreak
// instruction's own PC (spec-permitted; either 0 or the faulting address
// is valid, and Linux's do_trap_break() doesn't inspect it either way).
wire [31:0] sel_tval = (interrupt_condition_ex | timer_condition_ex) ? 32'd0 :
                       illegal_ops_ex ? illegal_ops_inst :
                       cmd_ebreak_ex ? { pc_ex, 2'd0 } : 32'd0;


//wire mcause_write = ecall_condition_ex | g_interrupt | g_exception;
//wire mcause_write = (ecall_condition_ex | cmd_ebreak_ex | g_interrupt) & csr_rmie | g_exception;
//wire mcause_write = (ecall_condition_ex | g_interrupt) & csr_rmie | g_exception;
wire mcause_write = (interrupt_condition_ex | timer_condition_ex) & csr_rmie | ecall_condition_ex | g_exception;

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
		csr_mcause <= 7'd0;
	end
	else if (mcause_write) begin
		csr_mcause <= { interrupt_bit, mcause_code };
	end
	else if ((~stall)&(cmd_csr_ex)&(adr_mcause)) begin
		csr_mcause <= { wdata_all[31], wdata_all[5:0] };
	end
    else if (csr_we_mon & adr_mcause) begin
        csr_mcause <= { csr_wdata_mon[31], csr_wdata_mon[5:0] };
    end
end

// mtval
always @ ( posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        csr_mtval <= 32'd0;
    end
    //else if (cmd_mret_ex) begin  // for debugging
        //csr_mtval <= 32'hdeadbeef;  // for debugging
    //end  // for debugging
    else if (mcause_write) begin
        csr_mtval <= sel_tval;
    end
    else if ((cmd_csr_ex)&(adr_mtval)) begin
        csr_mtval <= wdata_all;
    end
    else if (csr_we_mon & adr_mtval) begin
        csr_mtval <= csr_wdata_mon;
    end
end

// mstatush
// [5] MBE machine level big endian -> little endian: fixed 0
// [4] SBE superviser level big endian -> little endian: fixed 0
always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
		csr_mstatush <= 32'd0;
	end
	else if ((~stall)&(cmd_csr_ex)&(adr_mstatush)) begin
		csr_mstatush <= { wdata_all[31:6], 2'b00, wdata_all[3:0] };
	end
    else if (csr_we_mon & adr_mstatush) begin
        csr_mstatush <= { csr_wdata_mon[31:6], 2'b00, csr_wdata_mon[3:0] };
    end
end

// currently unuesd the privileges

// medelg, mideleg  is not need when the CPU dows not support S-MODE

// mip resister : currently read only register because of only M-mode is supported
//assign csr_mip = { 20'd0, g_interrupt, 3'd0, frc_cntr_val_leq, 3'd0, g_exception, 3'd0 };
//assign csr_mip = { 20'd0, g_interrupt, 3'd0, 1'b0, 3'd0, g_exception, 3'd0 };
assign csr_mip = { 20'd0, g_interrupt, 3'd0, frc_cntr_val_leq, 3'd0, g_exception, 3'd0 };

// mie register
reg [2:0] csr_mie_bits;

always @ ( posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        csr_mie_bits <= 3'd0;
    end
    else if ((cmd_csr_ex)&(adr_mie)) begin
        csr_mie_bits <= { wdata_all[11], wdata_all[7], wdata_all[3] };
    end
    else if (csr_we_mon & adr_mie) begin
        csr_mie_bits <= { csr_wdata_mon[11], csr_wdata_mon[7], csr_wdata_mon[3] };
    end
end

assign csr_mie = { 20'd0, csr_mie_bits[2], 3'd0, csr_mie_bits[1], 3'd0, csr_mie_bits[0], 3'd0 };

assign csr_meie = csr_mie_bits[2];
assign csr_mtie = csr_mie_bits[1];
assign csr_msie = csr_mie_bits[0];


// pc control for mepc
reg [31:2] post_pc_ex;

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n)
		post_pc_ex <= 30'd0;
	else if ( jmp_condition_ex | mret_condition_ex | fencei_condition_ex )
		post_pc_ex <= jmp_adr_if;
		//post_pc_ex <= jmp_condition_ex ? jmp_adr_ex : pc_ex;
`ifdef SUPPORT_M
	else if ( div_stall_start )
		post_pc_ex <= pc_ex;
		//post_pc_ex <= jmp_condition_ex ? jmp_adr_ex : pc_ex;
`endif // SUPPORT_M
end

// post_jump_cmd_cond : 1 empty slot after jump command 
	//input cmd_mret_ex,
//assign sel_pc_ex = post_jump_cmd_cond ? jmp_adr_ex : pc_ex; // ayashii
//assign sel_pc_ex = post_jump_cmd_cond ? post_pc_ex : pc_ex + 30'd1; // ayashii
`ifdef SUPPORT_M
assign sel_pc_ex = (post_jump_cmd_cond | div_stall_dly) ? post_pc_ex : pc_ex; // ayashii
`else // SUPPORT_M
assign sel_pc_ex = post_jump_cmd_cond ? post_pc_ex : pc_ex; // ayashii
`endif // SUPPORT_M

assign sel_pc_ex_2 = pc_ex;
//assign sel_pc_ex = post_jump_cmd_cond ? post_pc_ex :
                   //jmp_condition_ex ? jmp_adr_ex : pc_ex; // zantei
//assign sel_pc_id = cmd_mret_ex ? csr_mepc_ex :
                   //pc_ex; // zantei
                   //jmp_condition_ex ? jmp_adr_ex : pc_ex + 32'd1; // zantei
                   //jmp_condition_ex ? jmp_adr_ex : pc_ex; // zantei
//assign sel_pc_id = jmp_condition_ex ? jmp_adr_ex : pc_id;


endmodule
