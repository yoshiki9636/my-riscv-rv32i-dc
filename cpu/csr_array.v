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

module csr_array
	#(parameter MMU_EN = 1,  // 0 : satp.MODE is fixed to 0 (Bare, no MMU) (2026-11-22)
	  parameter SMODE = 0)   // 1 : S-mode / U-mode, trap delegation (2026-11-22)
	(
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
	input ipf_ex,             // instruction page fault (with illegal_ops_ex, 2026-11-22)
    input [31:0] illegal_ops_inst, // new
	input misal_ld_ex,
	input misal_st_ex,
	input [31:0] misal_adr,
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
	// ID-stage jump prediction (2026-11-12): predicted jump/branch confirmed
	// in EX (no EX redirect) and its target
	input pred_hit_ex,
	input [31:2] pred_adr_ex,
`ifdef SUPPORT_M
	input div_stall_start,
	input div_stall_dly,
`endif // SUPPORT_M
	input stall,
	// MMU (2026-11-22)
	input pf_exc,             // page fault of the MA access (part of g_exception)
	input pf_store,           // 1 : store/AMO page fault, 0 : load page fault
	input [31:0] pf_va,       // faulting virtual address (mtval)
	input [31:2] pc_ma,       // faulting instruction (mepc)
	output csr_satp_mode,     // satp.MODE (1 : Sv32)
	output [19:0] csr_satp_ppn,
	output csr_mprv,
	output csr_sum,
	output csr_mxr,
	output [1:0] csr_mpp_o,
	// S/U-mode (2026-11-22)
	input sret_condition_ex,  // sret is executed (purged / ~stall qualified)
	input sint_condition_ex,  // S-level interrupt (SSIP/STIP/SEIP) is taken
	output csr_sint_pend,     // an S-level interrupt is pending and enabled
	output csr_m_ie,          // M-level interrupts are enabled (MIE | priv < M)
	output [1:0] csr_priv,    // current privilege level
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
`define CSR_SATP_ADR 12'h180
// S-mode (2026-11-22)
`define CSR_SSTATUS_ADR 12'h100
`define CSR_SIE_ADR 12'h104
`define CSR_STVEC_ADR 12'h105
`define CSR_SCOUNTEREN_ADR 12'h106
`define CSR_SCAUSE_ADR 12'h142
`define CSR_STVAL_ADR 12'h143
`define CSR_SIP_ADR 12'h144
`define CSR_MEDELEG_ADR 12'h302
`define CSR_MIDELEG_ADR 12'h303
`define CSR_MCOUNTEREN_ADR 12'h306

`define M_MODE 2'b11
`define S_MODE 2'b01
`define U_MODE 2'b00

// MISA resigister value
// MXL[31:30] : 01 : 32bit
// Extentions[25:0] : only I
`define CSR_MISA_DATA 32'h4000_0100
// S-mode (2026-11-22) : I, M, A, S, U
`define CSR_MISA_DATA_SU 32'h4014_1101

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
wire adr_satp = (csr_ofs_ex_pm == `CSR_SATP_ADR);
// S-mode CSRs exist only when SMODE = 1 (read 0, writes ignored otherwise)
wire smode_en = (SMODE != 0);
wire adr_sstatus = smode_en & (csr_ofs_ex_pm == `CSR_SSTATUS_ADR);
wire adr_sie = smode_en & (csr_ofs_ex_pm == `CSR_SIE_ADR);
wire adr_stvec = smode_en & (csr_ofs_ex_pm == `CSR_STVEC_ADR);
wire adr_scause = smode_en & (csr_ofs_ex_pm == `CSR_SCAUSE_ADR);
wire adr_stval = smode_en & (csr_ofs_ex_pm == `CSR_STVAL_ADR);
wire adr_sip = smode_en & (csr_ofs_ex_pm == `CSR_SIP_ADR);
wire adr_medeleg = smode_en & (csr_ofs_ex_pm == `CSR_MEDELEG_ADR);
wire adr_mideleg = smode_en & (csr_ofs_ex_pm == `CSR_MIDELEG_ADR);
wire adr_sepc_s = smode_en & adr_sepc;

// read data selector
wire [31:0] csr_mstatus;
reg [31:0] csr_mstatush;
wire [31:0] csr_misa = smode_en ? `CSR_MISA_DATA_SU : `CSR_MISA_DATA;
reg [31:0] csr_mtvec;
reg [31:2] csr_mepc;
reg [6:0] csr_mcause;
reg [31:0] csr_mtval;
//wire [31:2] csr_sepc_i = 30'd0;
// S-mode registers (2026-11-22)
reg [1:0] priv_r;
wire [1:0] priv = smode_en ? priv_r : `M_MODE;
reg [31:2] csr_sepc;
reg [31:0] csr_stvec;
reg [6:0] csr_scause;
reg [31:0] csr_stval;
reg [15:0] csr_medeleg;
reg [2:0] csr_mideleg;     // { SEI(9), STI(5), SSI(1) }
reg [2:0] csr_mip_sw;      // { SEIP(9), STIP(5), SSIP(1) } : written by M-mode software
reg [2:0] csr_mie_s;       // { SEIE(9), STIE(5), SSIE(1) }
wire [31:0] csr_sstatus;
wire [31:0] csr_sie_r;
wire [31:0] csr_sip_r;
wire [31:0] csr_medeleg_r = { 16'd0, csr_medeleg };
wire [31:0] csr_mideleg_r = { 22'd0, csr_mideleg[2], 3'd0, csr_mideleg[1], 3'd0, csr_mideleg[0], 1'b0 };
assign csr_sepc_ex = smode_en ? csr_sepc : 30'd0;
assign csr_priv = priv;
wire [31:0] csr_mip;
wire [31:0] csr_mie;
reg [31:0] csr_mscrach;
reg [31:0] csr_sscrach;
// satp (2026-11-22) : MODE[31] / ASID[30:22] (not implemented : read 0) / PPN[21:0]
//   PA is 32bit : only PPN[19:0] is used for the page table walk
reg csr_satp_mode_r;
reg [21:0] csr_satp_ppn_r;
wire [31:0] csr_satp = { csr_satp_mode_r, 9'd0, csr_satp_ppn_r };

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
                       adr_satp ? csr_satp :
                       adr_sstatus ? csr_sstatus :
                       adr_sie ? csr_sie_r :
                       adr_stvec ? csr_stvec :
                       adr_scause ? { csr_scause[6], 25'd0, csr_scause[5:0] } :
                       adr_stval ? csr_stval :
                       adr_sip ? csr_sip_r :
                       adr_medeleg ? csr_medeleg_r :
                       adr_mideleg ? csr_mideleg_r :
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
// S/U-mode (2026-11-22) :
//   trap_any : a trap is taken in this cycle (interrupt / exception / ecall)
//   target_s : it goes to S-mode (delegated by medeleg / mideleg, priv < M)
//   m_interrupt is the M-mode trap (the name is kept from the M-only CPU)
wire trap_any = ((interrupt_condition_ex | timer_condition_ex) & (g_interrupt_priv == `M_MODE)) & csr_m_ie
              | sint_condition_ex | ecall_condition_ex | g_exception;
wire target_s;
wire m_interrupt = trap_any & ~target_s;
wire s_interrupt_t = trap_any & target_s;   // S-mode trap
//wire rmie_wr = m_interrupt | cmd_mret_ex;
wire rmie_wr = m_interrupt | mret_condition_ex;
//wire rmie_value = m_interrupt ? 1'b0 :
                 //cmd_mret_ex ? csr_mpie : csr_rmie;
wire pc_int_ecall_syn_end = 1'b0; // temp fixed
wire rmie_value = pc_int_ecall_syn_end ? 1'b0 :
                  cmd_mret_ex ? csr_mpie :
                  m_interrupt ? 1'b0 : csr_rmie;
// M-level interrupts are always enabled below M-mode
assign csr_m_ie = csr_rmie | (priv != `M_MODE);

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
                       m_interrupt ? priv :
                       cmd_mret_ex ? (smode_en ? `U_MODE : `M_MODE) : // mret : MPP <- least privileged mode
                       csr_mpp;
// MPP is WARL : 2'b10 (reserved) is written as U when S-mode is supported
wire [1:0] mpp_wdata = (smode_en & (wdata_all[12:11] == 2'b10)) ? `U_MODE : wdata_all[12:11];

always @ ( posedge clk or negedge rst_n) begin 
	if (~rst_n) begin
		csr_mpp <= 2'b00;
	end
	else if (mpp_wr) begin
		csr_mpp <= mpp_value;
	end
	else if (mstatus_wr) begin
		csr_mpp <= mpp_wdata;
	end
    else if (csr_we_mon & adr_mstatus) begin
        csr_mpp <= csr_wdata_mon[12:11];
    end
end

// SIE[1] : Supervisor mode Global Interrupt enable : currently not used
//wire s_interrupt = g_interrupt & (g_interrupt_priv == `S_MODE);
//wire s_interrupt = g_interrupt & (g_interrupt_priv == `S_MODE) & csr_sie;
// S/U-mode (2026-11-22) : S-mode trap (s_interrupt_t) / sret (sret_condition_ex)
wire sstatus_wr = (~stall)&(cmd_csr_ex)&(adr_sstatus);
wire s_interrupt = s_interrupt_t;
wire sie_wr = s_interrupt | sret_condition_ex;
wire sie_value = s_interrupt ? 1'b0 :
                 sret_condition_ex ? csr_spie : csr_sie;

always @ ( posedge clk or negedge rst_n) begin 
	if (~rst_n) begin
		csr_sie <= 1'b0;
	end
	else if (sie_wr) begin
		csr_sie <= sie_value;
	end
	else if (mstatus_wr | sstatus_wr) begin
		csr_sie <= wdata_all[1];
	end
    else if (csr_we_mon & adr_mstatus) begin
        csr_sie <= csr_wdata_mon[1];
    end
end

// SPIE[5] : Supervisor mode Previouse Interrupt Enable
wire spie_wr = s_interrupt | sret_condition_ex;
wire spie_value = s_interrupt ? csr_sie :
                  sret_condition_ex ? 1'b1 : csr_spie;

always @ ( posedge clk or negedge rst_n) begin 
	if (~rst_n) begin
		csr_spie <= 1'b0;
	end
	else if (spie_wr) begin
		csr_spie <= spie_value;
	end
	else if (mstatus_wr | sstatus_wr) begin
		csr_spie <= wdata_all[5];
	end
    else if (csr_we_mon & adr_mstatus) begin
        csr_spie <= csr_wdata_mon[5];
    end
end


// SPP[8] : Supervisor mode Previouse Privilege
// cueerntly fixed 0 because it dows not support S-mode
wire spp_wr = s_interrupt | sret_condition_ex;
// S-mode trap : SPP <- (priv == S), sret : SPP <- U
wire spp_value = s_interrupt ? (priv == `S_MODE) : 1'b0;
//wire [1:0] spp_value = s_interrupt ? g_current_priv :
                 //cmd_sret_ex ? `U_MODE : // need to check when use the value
                 //csr_spp;

always @ ( posedge clk or negedge rst_n) begin 
	if (~rst_n) begin
		csr_spp <= 1'b0;
	end
	else if (spp_wr) begin
		csr_spp <= spp_value;
	end
	else if (mstatus_wr | sstatus_wr) begin
		csr_spp <= wdata_all[8];
		//csr_spp <= 1'b0;
	end
    else if (csr_we_mon & adr_mstatus) begin
        csr_spp <= csr_wdata_mon[8];
    end
end

// MPRV[17] / SUM[18] / MXR[19] (2026-11-22, MMU)
//   MPRV = 1 : loads / stores are translated and checked with the privilege in
//              MPP (translation is active when MPP != M and satp.MODE = 1)
//   mret clears MPRV when it returns to a mode other than M (MPP != M)
reg csr_mprv_r;
reg csr_sum_r;
reg csr_mxr_r;

always @ ( posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		csr_mprv_r <= 1'b0;
		csr_sum_r <= 1'b0;
		csr_mxr_r <= 1'b0;
	end
	else if (mret_condition_ex) begin
		if (csr_mpp != `M_MODE)
			csr_mprv_r <= 1'b0;
	end
	else if (sret_condition_ex) begin
		csr_mprv_r <= 1'b0;      // sret returns to S or U
	end
	else if (mstatus_wr) begin
		csr_mprv_r <= wdata_all[17];
		csr_sum_r <= wdata_all[18];
		csr_mxr_r <= wdata_all[19];
	end
	else if (sstatus_wr) begin
		csr_sum_r <= wdata_all[18];
		csr_mxr_r <= wdata_all[19];
	end
    else if (csr_we_mon & adr_mstatus) begin
		csr_mprv_r <= csr_wdata_mon[17];
		csr_sum_r <= csr_wdata_mon[18];
		csr_mxr_r <= csr_wdata_mon[19];
    end
end

assign csr_mprv = csr_mprv_r;
assign csr_sum = csr_sum_r;
assign csr_mxr = csr_mxr_r;
assign csr_mpp_o = csr_mpp;

assign csr_mstatus = { 12'd0, csr_mxr_r, csr_sum_r, csr_mprv_r, 4'd0, csr_mpp, 2'b00, csr_spp, csr_mpie,
                       1'b0, csr_spie, 1'b0, csr_rmie, 1'b0, csr_sie, 1'b0 };
// sstatus : SIE / SPIE / SPP / SUM / MXR view of mstatus
assign csr_sstatus = { 12'd0, csr_mxr_r, csr_sum_r, 9'd0, csr_spp, 2'b00, csr_spie, 3'd0, csr_sie, 1'b0 };
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

// satp (2026-11-22)
//   writing satp does not flush the DTLB : sfence.vma is needed (as the spec)
always @ ( posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		csr_satp_mode_r <= 1'b0;
		csr_satp_ppn_r <= 22'd0;
	end
	else if ((~stall)&(cmd_csr_ex)&(adr_satp)) begin
		csr_satp_mode_r <= wdata_all[31] & (MMU_EN != 0);
		csr_satp_ppn_r <= wdata_all[21:0];
	end
    else if (csr_we_mon & adr_satp) begin
		csr_satp_mode_r <= csr_wdata_mon[31] & (MMU_EN != 0);
		csr_satp_ppn_r <= csr_wdata_mon[21:0];
    end
end

assign csr_satp_mode = csr_satp_mode_r;
assign csr_satp_ppn = csr_satp_ppn_r[19:0];

//assign csr_mtvec_ex = csr_mtvec[31:2];
wire [31:2] mtvec_vec = (csr_mtvec[1:0] == 2'd0) ? csr_mtvec[31:2] : csr_mtvec[31:2] + { 24'd0, mcause_code[5:0] };
// stvec : vectored mode only for interrupts (as the spec)
wire [31:2] stvec_vec = ((csr_stvec[1:0] == 2'd1) & interrupt_bit) ? csr_stvec[31:2] + { 24'd0, mcause_code[5:0] } : csr_stvec[31:2];
assign csr_mtvec_ex = target_s ? stvec_vec : mtvec_vec;

//assign pc_csr_mtvec = csr_mtvec[31:2];

// mscrach
// scrach register for m-mode
always @ ( posedge clk or negedge rst_n) begin
    if (~rst_n)
        csr_mscrach <= 32'd0;
    // MMU (2026-11-22): written only in the ~stall (commit) cycle like mtvec.
    // Before, the CSR in EX was written in every stalled cycle; with a page
    // fault of the older load/store in MA the CSR instruction is purged after
    // the stall, so the early write must not happen.
    else if ((~stall)&(cmd_csr_ex)&(adr_mscrach))
        csr_mscrach <= wdata_all;
    else if (csr_we_mon & adr_mscrach)
        csr_mscrach <= csr_wdata_mon;
end

// sscrach
// scrach register for s-mode
always @ ( posedge clk or negedge rst_n) begin
    if (~rst_n)
        csr_sscrach <= 32'd0;
    else if ((~stall)&(cmd_csr_ex)&(adr_sscrach))
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
	else if ( pf_exc & m_interrupt ) begin
		// page fault (2026-11-22) : the faulting load/store is in MA
		csr_mepc <= pc_ma;
	end
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
wire interrupt_bit = (interrupt_condition_ex | timer_condition_ex | sint_condition_ex) & ~pf_exc;

// EBREAK (2026-07-23): cmd_ebreak_ex is decoded/purge-tracked in id_stage
// exactly like illegal_ops_ex (same reset/purge conditions) and folded into
// ex_stage's ecall_condition_ex OR, so by the time this trap fires it is
// checked ahead of the generic ecall_condition_ex fallback below - giving
// ebreak its own mcause=3 (breakpoint) instead of being reported as an
// ecall (mcause=11).
// MMU (2026-11-22): a page fault belongs to the OLDER instruction (MA), so it
// has the highest priority (ex_stage holds interrupts in the pf_exc cycle).
wire [5:0] sint_code;
// ecall : 8 (from U) / 9 (from S) / 11 (from M)
wire [5:0] ecall_code = (priv == `M_MODE) ? 6'd11 : (priv == `S_MODE) ? 6'd9 : 6'd8;
assign mcause_code = pf_exc ? (pf_store ? 6'd15 : 6'd13) :
                     interrupt_condition_ex ? 6'd11 :
                     timer_condition_ex ? 6'd7 :
                     sint_condition_ex ? sint_code :
                     illegal_ops_ex ? (ipf_ex ? 6'd12 : 6'd2) :
                     cmd_ebreak_ex ? 6'd3 :
                     misal_ld_ex ? 6'd4 :
                     misal_st_ex ? 6'd6 :
                     ecall_condition_ex ?  ecall_code :
                     6'h3f;

// ---------------------------------------------------------------------------
// S/U-mode (2026-11-22)
// ---------------------------------------------------------------------------
// trap target : S-mode when priv < M and the cause is delegated
wire [15:0] medeleg_hit = csr_medeleg >> mcause_code[3:0];
wire deleg_int = ((mcause_code == 6'd9) & csr_mideleg[2]) |
                 ((mcause_code == 6'd5) & csr_mideleg[1]) |
                 ((mcause_code == 6'd1) & csr_mideleg[0]);
wire deleg_exc = (mcause_code[5:4] == 2'b00) & medeleg_hit[0];
assign target_s = smode_en & (priv != `M_MODE) & (interrupt_bit ? deleg_int : deleg_exc);

// S-level interrupts (level) : SSIP / STIP / SEIP are set by M-mode software
//   (SBI) in mip.  The hardware SEIP input is not connected yet.
wire [2:0] s_ip = csr_mip_sw;
wire [2:0] s_pend = s_ip & csr_mie_s;
wire s_enable = (priv == `U_MODE) | ((priv == `S_MODE) & csr_sie);
wire m_enable = (priv != `M_MODE) | csr_rmie;
wire [2:0] pend_to_s = s_pend & csr_mideleg & { 3{ s_enable }};
wire [2:0] pend_to_m = s_pend & ~csr_mideleg & { 3{ m_enable }};
assign csr_sint_pend = smode_en & (|(pend_to_s | pend_to_m));
// priority : not delegated (M) first, then SEI > SSI > STI
wire [2:0] pend_sel = (|pend_to_m) ? pend_to_m : pend_to_s;
assign sint_code = pend_sel[2] ? 6'd9 : pend_sel[0] ? 6'd1 : 6'd5;

// privilege level
always @ ( posedge clk or negedge rst_n) begin
	if (~rst_n)
		priv_r <= `M_MODE;
	else if (m_interrupt)
		priv_r <= `M_MODE;
	else if (s_interrupt_t)
		priv_r <= `S_MODE;
	else if (mret_condition_ex)
		priv_r <= csr_mpp;
	else if (sret_condition_ex)
		priv_r <= csr_spp ? `S_MODE : `U_MODE;
end

// sepc / scause / stval (S-mode trap) and stvec
always @ ( posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		csr_sepc <= 30'd0;
		csr_scause <= 7'd0;
		csr_stval <= 32'd0;
		csr_stvec <= 32'd0;
	end
	else if (s_interrupt_t) begin
		csr_sepc <= pf_exc ? pc_ma : sel_pc_ex;
		csr_scause <= { interrupt_bit, mcause_code };
		csr_stval <= sel_tval;
	end
	else if ((~stall)&(cmd_csr_ex)) begin
		if (adr_sepc_s)  csr_sepc <= wdata_all[31:2];
		if (adr_scause)  csr_scause <= { wdata_all[31], wdata_all[5:0] };
		if (adr_stval)   csr_stval <= wdata_all;
		if (adr_stvec)   csr_stvec <= { wdata_all[31:2], 1'b0, wdata_all[0] };
	end
end

// medeleg (exceptions 0-15 except 10, 11 : ecall from M, 14) / mideleg (SSI, STI, SEI)
always @ ( posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		csr_medeleg <= 16'd0;
		csr_mideleg <= 3'd0;
	end
	else if ((~stall)&(cmd_csr_ex)) begin
		if (adr_medeleg) csr_medeleg <= wdata_all[15:0] & 16'hb3ff;
		if (adr_mideleg) csr_mideleg <= { wdata_all[9], wdata_all[5], wdata_all[1] };
	end
end

// mip / mie S bits (sip / sie are views limited by mideleg)
//   mip : SSIP / STIP / SEIP writable by M-mode, sip : SSIP writable when delegated
wire mip_wr = smode_en & (~stall)&(cmd_csr_ex)&(adr_mip);
wire sip_wr = (~stall)&(cmd_csr_ex)&(adr_sip);
wire mie_wr_s = smode_en & (~stall)&(cmd_csr_ex)&(adr_mie);
wire sie_wr_s = (~stall)&(cmd_csr_ex)&(adr_sie);
always @ ( posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		csr_mip_sw <= 3'd0;
		csr_mie_s <= 3'd0;
	end
	else begin
		if (mip_wr)
			csr_mip_sw <= { wdata_all[9], wdata_all[5], wdata_all[1] };
		else if (sip_wr & csr_mideleg[0])
			csr_mip_sw[0] <= wdata_all[1];
		if (mie_wr_s)
			csr_mie_s <= { wdata_all[9], wdata_all[5], wdata_all[1] };
		else if (sie_wr_s)
			csr_mie_s <= (csr_mie_s & ~csr_mideleg) | ({ wdata_all[9], wdata_all[5], wdata_all[1] } & csr_mideleg);
	end
end

wire [2:0] sip_bits = csr_mip_sw & csr_mideleg;
wire [2:0] sie_bits = csr_mie_s & csr_mideleg;
assign csr_sip_r = { 22'd0, sip_bits[2], 3'd0, sip_bits[1], 3'd0, sip_bits[0], 1'b0 };
assign csr_sie_r = { 22'd0, sie_bits[2], 3'd0, sie_bits[1], 3'd0, sie_bits[0], 1'b0 };

// FIX (2026-07-16): same level-vs-condition fix as mcause_code above -
// an illegal-instruction trap taken while a timer compare was pending
// used to lose its mtval (reported 0 instead of the faulting
// instruction bits).
// EBREAK (2026-07-23): mtval for a breakpoint trap carries the ebreak
// instruction's own PC (spec-permitted; either 0 or the faulting address
// is valid, and Linux's do_trap_break() doesn't inspect it either way).
wire [31:0] sel_tval = pf_exc ? pf_va :
                       (interrupt_condition_ex | timer_condition_ex | sint_condition_ex) ? 32'd0 :
                       illegal_ops_ex ? (ipf_ex ? { pc_ex, 2'd0 } : illegal_ops_inst) :
                       (misal_ld_ex | misal_st_ex) ? misal_adr :
                       cmd_ebreak_ex ? { pc_ex, 2'd0 } : 32'd0;


//wire mcause_write = ecall_condition_ex | g_interrupt | g_exception;
//wire mcause_write = (ecall_condition_ex | cmd_ebreak_ex | g_interrupt) & csr_rmie | g_exception;
//wire mcause_write = (ecall_condition_ex | g_interrupt) & csr_rmie | g_exception;
wire mcause_write = m_interrupt;   // M-mode trap (S/U-mode, 2026-11-22)

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
    else if ((~stall)&(cmd_csr_ex)&(adr_mtval)) begin
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
assign csr_mip = { 20'd0, g_interrupt, 3'd0, frc_cntr_val_leq, 3'd0, g_exception, 3'd0 } |
                 (smode_en ? { 22'd0, csr_mip_sw[2], 3'd0, csr_mip_sw[1], 3'd0, csr_mip_sw[0], 1'b0 } : 32'd0);

// mie register
reg [2:0] csr_mie_bits;

always @ ( posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        csr_mie_bits <= 3'd0;
    end
    else if ((~stall)&(cmd_csr_ex)&(adr_mie)) begin
        csr_mie_bits <= { wdata_all[11], wdata_all[7], wdata_all[3] };
    end
    else if (csr_we_mon & adr_mie) begin
        csr_mie_bits <= { csr_wdata_mon[11], csr_wdata_mon[7], csr_wdata_mon[3] };
    end
end

assign csr_mie = { 20'd0, csr_mie_bits[2], 3'd0, csr_mie_bits[1], 3'd0, csr_mie_bits[0], 3'd0 } |
                 (smode_en ? { 22'd0, csr_mie_s[2], 3'd0, csr_mie_s[1], 3'd0, csr_mie_s[0], 1'b0 } : 32'd0);

assign csr_meie = csr_mie_bits[2];
assign csr_mtie = csr_mie_bits[1];
assign csr_msie = csr_mie_bits[0];


// pc control for mepc
reg [31:2] post_pc_ex;

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n)
		post_pc_ex <= 30'd0;
	else if ( jmp_condition_ex | mret_condition_ex | sret_condition_ex | fencei_condition_ex )
		post_pc_ex <= jmp_adr_if;
		//post_pc_ex <= jmp_condition_ex ? jmp_adr_ex : pc_ex;
	// ID-stage jump prediction (2026-11-12): the jump was already redirected
	// in ID, so the slot after it in EX is a killed NOP.  An interrupt taken
	// on that slot (post_jump_cmd_cond) must save the jump target as mepc.
	else if ( pred_hit_ex )
		post_pc_ex <= pred_adr_ex;
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
