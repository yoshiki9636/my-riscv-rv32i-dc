/*
 * My RISC-V RV32I CPU
 *   WB-stage forwarding hazard statistics monitor
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2026 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 *
 * Purpose (2026-07-23): forwarding.v's hit_rs1_idwb_ex/hit_rs2_idwb_ex
 * (WB-stage forward-hit detection) are plain unconditional registers, unlike
 * hit_rs1_idex_ex/hit_rs1_idma_ex (EX/MA-stage forward-hit detection), which
 * both carry a _pre/_post + stall_dly mux specifically to stay correct
 * across a multi-cycle D$-miss stall (if_stage.v freezes inst_id via
 * inst_roll starting the stall's 2nd cycle, so the comparison operand seen
 * by this logic is frozen well before the WB stage itself freezes via
 * stall_wb = stall_dly3 & stall_dly, i.e. not until the stall's 4th cycle).
 * hit_rs1_idwb_ex/hit_rs2_idwb_ex never got that same protection - during
 * cycles 2-3 of a multi-cycle stall, a frozen inst_rs1_id/inst_rs2_id can
 * coincidentally equal an unrelated, still-advancing rd_adr_wb and produce a
 * false-positive WB forward, feeding a stale wbk_data_wb2 value into rs1_sel
 * (see ex_stage.v). This was the leading suspect (found 2026-07-20, see
 * project memory project_rtl_lab3_dram_review.md / project_nommu_clean_restart.md)
 * for the recurring execve wild-jump crash class (epc/ra corrupted to small
 * values like 0/1, landing in do_mmap/vm_mmap_pgoff epilogue) - it survives
 * even inside fully IRQ-off code, ruling out ISR-timing theories, and the
 * DRAM write-hazard watchdog (dram_write_hazard_watchdog.v) already cleared
 * the DRAM-commit-ordering theory for the exact same crash (all counters 0).
 *
 * A one-shot functional fix (adding the missing _pre/_post + stall_dly mux
 * to hit_rs1_idwb_ex/hit_rs2_idwb_ex, matching hit_rs1_idex_ex) was tried on
 * real hardware once: the wild jump did not recur, but a new, unrelated-
 * looking silent hang appeared at ~5s (tty_register_ldisc(27)), and the
 * change was reverted without ever being able to tell whether it was the
 * fix exposing a second, independent bug or the fix itself being wrong.
 *
 * Rather than guess again, this module is monitor-only (touches no
 * functional signal) - same investigative strategy as
 * dram_write_hazard_watchdog.v: latch forensic evidence of the *suspected
 * precondition* (hit_rs1_idwb_ex/hit_rs2_idwb_ex firing during the
 * unprotected window: stall asserted, stall_wb not yet asserted) on every
 * real boot, so the very next hardware run either confirms or clears this
 * hypothesis before any further functional RTL change is risked again.
 *
 * All inputs live in the CPU's single `clk` domain (forwarding.v has no
 * mclk-domain signals at all) - no CDC/async-FIFO needed here, unlike
 * dram_write_hazard_watchdog.v.
 *
 * 2026-07-23 (same day, extension): the raw suspect counters above only test
 * half the 2026-07-20 hypothesis - that a WB forward fires during the
 * unprotected window. On the first real-hardware read they turned out NOT
 * to be rare (109,286 rs1 / 26,767 rs2 events in one boot, ~0.2-0.3% of all
 * WB forwards), which by itself doesn't distinguish "legitimate hit that
 * happens to land in that window" from "false-positive hit caused by a
 * frozen inst_rs1_id/inst_rs2_id coincidentally matching an unrelated,
 * still-advancing rd_adr_wb" - the actual mechanism in the hypothesis.
 * Added a second, stronger signal: track whether inst_rs1_id/inst_rs2_id
 * have remained bit-identical, cycle over cycle, for the entire stall
 * episode up to and including the cycle of the hit (a direct test of the
 * "already frozen via inst_roll" half of the hypothesis, not just "a hit
 * occurred at a suspicious time"). A suspect hit that also carries a
 * confirmed frozen streak is much stronger evidence of the exact aliasing
 * mechanism than a raw suspect hit alone.
 *
 * MMIO map (word addresses, `SYS_*` convention matching io_led.v/io_frc.v/
 * dram_write_hazard_watchdog.v; byte addresses = 0xC0000000 + (word_addr<<2)):
 *   SYS_FHM_STATUS      (3010 / 0xC000C040) [R] bit0=rs1 suspect ever seen, bit1=rs2 ditto,
 *                                               bit2=rs1 frozen-confirmed suspect ever seen, bit3=rs2 ditto
 *   SYS_FHM_RS1_SUSP    (3011 / 0xC000C044) [R] total suspect hit_rs1_idwb_ex events (free-running)
 *   SYS_FHM_RS2_SUSP    (3012 / 0xC000C048) [R] total suspect hit_rs2_idwb_ex events (free-running)
 *   SYS_FHM_RS1_TOTAL   (3013 / 0xC000C04C) [R] total hit_rs1_idwb_ex events regardless of window (baseline)
 *   SYS_FHM_RS2_TOTAL   (3014 / 0xC000C050) [R] total hit_rs2_idwb_ex events regardless of window (baseline)
 *   SYS_FHM_LAST_PC     (3015 / 0xC000C054) [R] pc_ex (byte address) of the most recent suspect event (any)
 *   SYS_FHM_LAST_RD     (3016 / 0xC000C058) [R] rd_adr_wb (zero-extended) that coincidentally matched (any)
 *   SYS_FHM_LAST_TIME   (3017 / 0xC000C05C) [R] free-running clk cycle count at that event (any)
 *   SYS_FHM_RS1_SUSPFRZ (3018 / 0xC000C060) [R] suspect hit_rs1_idwb_ex events with inst_rs1_id confirmed
 *                                               frozen for the whole stall episode (the strong signal)
 *   SYS_FHM_RS2_SUSPFRZ (3019 / 0xC000C064) [R] ditto for rs2
 *   SYS_FHM_LAST_PC_FRZ (301A / 0xC000C068) [R] pc_ex of the most recent FROZEN-confirmed suspect event
 *   SYS_FHM_LAST_RD_FRZ (301B / 0xC000C06C) [R] rd_adr_wb of the most recent FROZEN-confirmed suspect event
 */

module forwarding_hazard_monitor (
	input clk,
	input rst_n,

	// tapped directly from cpu_top's existing internal wires - no changes
	// to forwarding.v/cpu_top.v functional logic, only new output ports
	// exposing already-existing signals.
	input stall,
	input stall_wb,
	input hit_rs1_idwb_ex,
	input hit_rs2_idwb_ex,
	input [4:0] rd_adr_wb,
	input [31:2] pc_ex,
	input [4:0] inst_rs1_id,
	input [4:0] inst_rs2_id,

	// CPU-side MMIO bus (same convention as io_led.v / dram_write_hazard_watchdog.v)
	input dma_io_we,
	input [15:2] dma_io_wadr,
	input [31:0] dma_io_wdata,
	input [15:2] dma_io_radr,
	input dma_io_radr_en,
	input [31:0] dma_io_rdata_in,
	output [31:0] dma_io_rdata
	);

`define SYS_FHM_STATUS      14'h3010
`define SYS_FHM_RS1_SUSP    14'h3011
`define SYS_FHM_RS2_SUSP    14'h3012
`define SYS_FHM_RS1_TOTAL   14'h3013
`define SYS_FHM_RS2_TOTAL   14'h3014
`define SYS_FHM_LAST_PC     14'h3015
`define SYS_FHM_LAST_RD     14'h3016
`define SYS_FHM_LAST_TIME   14'h3017
`define SYS_FHM_RS1_SUSPFRZ 14'h3018
`define SYS_FHM_RS2_SUSPFRZ 14'h3019
`define SYS_FHM_LAST_PC_FRZ 14'h301A
`define SYS_FHM_LAST_RD_FRZ 14'h301B

// ---------------------------------------------------------------------
// free-running cycle counter, for timestamping suspect events
// ---------------------------------------------------------------------
reg [31:0] cycle_cnt;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		cycle_cnt <= 32'd0;
	else
		cycle_cnt <= cycle_cnt + 32'd1;
end

// ---------------------------------------------------------------------
// suspect window: stall & ~stall_wb, delayed 1 cycle to line up with
// hit_rs1_idwb_ex/hit_rs2_idwb_ex, which are themselves forwarding.v's
// registered (1-cycle-late) version of the raw hit_rs1_idwb/hit_rs2_idwb
// combinational compare against stall/stall_wb as they were the cycle
// before. Without this delay the window and the hit would be compared
// one cycle out of phase.
// ---------------------------------------------------------------------
reg stall_d1;
reg stall_wb_d1;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		stall_d1 <= 1'b0;
		stall_wb_d1 <= 1'b0;
	end else begin
		stall_d1 <= stall;
		stall_wb_d1 <= stall_wb;
	end
end

wire suspect_window = stall_d1 & ~stall_wb_d1;
wire suspect_hit_rs1 = suspect_window & hit_rs1_idwb_ex;
wire suspect_hit_rs2 = suspect_window & hit_rs2_idwb_ex;

// ---------------------------------------------------------------------
// frozen streak: track whether inst_rs1_id/inst_rs2_id have stayed
// bit-identical, cycle over cycle, for the whole current stall episode so
// far (reset to a fresh "true, nothing disproven yet" seed on the first
// cycle after a non-stalled cycle, then ANDed with cycle-to-cycle equality
// for as long as stall stays continuously asserted). This directly tests
// the "already frozen via inst_roll" half of the 2026-07-20 hypothesis,
// as opposed to suspect_window above, which only tests "a hit occurred
// during a suspicious cycle range" without checking whether the compared
// value actually stood still.
//
// stall_raw_prev is a plain 1-cycle delay of stall, kept separate from
// stall_d1 above (which serves suspect_window's own, different alignment
// need) to keep this streak's timing easy to reason about on its own.
// ---------------------------------------------------------------------
reg [4:0] inst_rs1_id_d1;
reg [4:0] inst_rs2_id_d1;
reg stall_raw_prev;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		inst_rs1_id_d1 <= 5'd0;
		inst_rs2_id_d1 <= 5'd0;
		stall_raw_prev <= 1'b0;
	end else begin
		inst_rs1_id_d1 <= inst_rs1_id;
		inst_rs2_id_d1 <= inst_rs2_id;
		stall_raw_prev <= stall;
	end
end

reg rs1_id_frozen_streak;
reg rs2_id_frozen_streak;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		rs1_id_frozen_streak <= 1'b0;
	else if (~stall_raw_prev)
		// previous cycle wasn't stalled: this is (at earliest) the first
		// cycle of a fresh stall episode - nothing to compare against
		// yet, seed true; a real change next cycle will clear it.
		rs1_id_frozen_streak <= 1'b1;
	else
		rs1_id_frozen_streak <= rs1_id_frozen_streak & (inst_rs1_id == inst_rs1_id_d1);
end

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		rs2_id_frozen_streak <= 1'b0;
	else if (~stall_raw_prev)
		rs2_id_frozen_streak <= 1'b1;
	else
		rs2_id_frozen_streak <= rs2_id_frozen_streak & (inst_rs2_id == inst_rs2_id_d1);
end

// suspect_window/hit_rs*_idwb_ex are already 1-cycle-delayed relative to
// the raw stall/inst_rs*_id compare (see suspect_window's own comment
// above), so the frozen-streak flags - which reflect "as of the current
// cycle" - line up with them directly; no extra delay stage needed here.
wire suspect_hit_rs1_frozen = suspect_hit_rs1 & rs1_id_frozen_streak;
wire suspect_hit_rs2_frozen = suspect_hit_rs2 & rs2_id_frozen_streak;

// ---------------------------------------------------------------------
// free-running counters (saturating, not wrapping - forensic use only,
// wrapping back to a small count would look identical to "rare", which
// would be actively misleading)
// ---------------------------------------------------------------------
reg [31:0] rs1_susp_count;
reg [31:0] rs2_susp_count;
reg [31:0] rs1_total_count;
reg [31:0] rs2_total_count;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		rs1_susp_count <= 32'd0;
	else if (suspect_hit_rs1 & (rs1_susp_count != 32'hFFFFFFFF))
		rs1_susp_count <= rs1_susp_count + 32'd1;
end

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		rs2_susp_count <= 32'd0;
	else if (suspect_hit_rs2 & (rs2_susp_count != 32'hFFFFFFFF))
		rs2_susp_count <= rs2_susp_count + 32'd1;
end

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		rs1_total_count <= 32'd0;
	else if (hit_rs1_idwb_ex & (rs1_total_count != 32'hFFFFFFFF))
		rs1_total_count <= rs1_total_count + 32'd1;
end

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		rs2_total_count <= 32'd0;
	else if (hit_rs2_idwb_ex & (rs2_total_count != 32'hFFFFFFFF))
		rs2_total_count <= rs2_total_count + 32'd1;
end

reg [31:0] rs1_suspfrz_count;
reg [31:0] rs2_suspfrz_count;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		rs1_suspfrz_count <= 32'd0;
	else if (suspect_hit_rs1_frozen & (rs1_suspfrz_count != 32'hFFFFFFFF))
		rs1_suspfrz_count <= rs1_suspfrz_count + 32'd1;
end

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		rs2_suspfrz_count <= 32'd0;
	else if (suspect_hit_rs2_frozen & (rs2_suspfrz_count != 32'hFFFFFFFF))
		rs2_suspfrz_count <= rs2_suspfrz_count + 32'd1;
end

// ---------------------------------------------------------------------
// latch forensic evidence of the most recent suspect event (either rs1
// or rs2 - rs2 wins the latch if both fire the same cycle, arbitrarily;
// the per-source counters above already distinguish which happened), and
// separately the most recent FROZEN-confirmed suspect event (the strong
// signal).
// ---------------------------------------------------------------------
reg [31:0] last_pc;
reg [4:0]  last_rd;
reg [31:0] last_time;
reg [31:0] last_pc_frz;
reg [4:0]  last_rd_frz;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		last_pc <= 32'd0;
		last_rd <= 5'd0;
		last_time <= 32'd0;
	end else if (suspect_hit_rs1 | suspect_hit_rs2) begin
		last_pc <= { pc_ex, 2'd0 };
		last_rd <= rd_adr_wb;
		last_time <= cycle_cnt;
	end
end

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		last_pc_frz <= 32'd0;
		last_rd_frz <= 5'd0;
	end else if (suspect_hit_rs1_frozen | suspect_hit_rs2_frozen) begin
		last_pc_frz <= { pc_ex, 2'd0 };
		last_rd_frz <= rd_adr_wb;
	end
end

// ---------------------------------------------------------------------
// clk domain: MMIO register decode (same shape as dram_write_hazard_watchdog.v)
// ---------------------------------------------------------------------
wire re_fhm_status      = dma_io_radr_en & (dma_io_radr == `SYS_FHM_STATUS);
wire re_fhm_rs1_susp    = dma_io_radr_en & (dma_io_radr == `SYS_FHM_RS1_SUSP);
wire re_fhm_rs2_susp    = dma_io_radr_en & (dma_io_radr == `SYS_FHM_RS2_SUSP);
wire re_fhm_rs1_total   = dma_io_radr_en & (dma_io_radr == `SYS_FHM_RS1_TOTAL);
wire re_fhm_rs2_total   = dma_io_radr_en & (dma_io_radr == `SYS_FHM_RS2_TOTAL);
wire re_fhm_last_pc     = dma_io_radr_en & (dma_io_radr == `SYS_FHM_LAST_PC);
wire re_fhm_last_rd     = dma_io_radr_en & (dma_io_radr == `SYS_FHM_LAST_RD);
wire re_fhm_last_time   = dma_io_radr_en & (dma_io_radr == `SYS_FHM_LAST_TIME);
wire re_fhm_rs1_suspfrz = dma_io_radr_en & (dma_io_radr == `SYS_FHM_RS1_SUSPFRZ);
wire re_fhm_rs2_suspfrz = dma_io_radr_en & (dma_io_radr == `SYS_FHM_RS2_SUSPFRZ);
wire re_fhm_last_pc_frz = dma_io_radr_en & (dma_io_radr == `SYS_FHM_LAST_PC_FRZ);
wire re_fhm_last_rd_frz = dma_io_radr_en & (dma_io_radr == `SYS_FHM_LAST_RD_FRZ);

reg re_fhm_dly;
reg [3:0] re_fhm_sel_dly;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		re_fhm_dly <= 1'b0;
		re_fhm_sel_dly <= 4'd0;
	end else begin
		re_fhm_dly <= re_fhm_status | re_fhm_rs1_susp | re_fhm_rs2_susp |
			      re_fhm_rs1_total | re_fhm_rs2_total | re_fhm_last_pc |
			      re_fhm_last_rd | re_fhm_last_time | re_fhm_rs1_suspfrz |
			      re_fhm_rs2_suspfrz | re_fhm_last_pc_frz | re_fhm_last_rd_frz;
		re_fhm_sel_dly <= re_fhm_status      ? 4'd0 :
				   re_fhm_rs1_susp    ? 4'd1 :
				   re_fhm_rs2_susp    ? 4'd2 :
				   re_fhm_rs1_total   ? 4'd3 :
				   re_fhm_rs2_total   ? 4'd4 :
				   re_fhm_last_pc     ? 4'd5 :
				   re_fhm_last_rd     ? 4'd6 :
				   re_fhm_last_time   ? 4'd7 :
				   re_fhm_rs1_suspfrz ? 4'd8 :
				   re_fhm_rs2_suspfrz ? 4'd9 :
				   re_fhm_last_pc_frz ? 4'd10 :
				   4'd11;
	end
end

assign dma_io_rdata = ~re_fhm_dly ? dma_io_rdata_in :
			(re_fhm_sel_dly == 4'd0) ? { 28'd0,
						      (rs2_suspfrz_count != 32'd0), (rs1_suspfrz_count != 32'd0),
						      (rs2_susp_count != 32'd0), (rs1_susp_count != 32'd0) } :
			(re_fhm_sel_dly == 4'd1) ? rs1_susp_count :
			(re_fhm_sel_dly == 4'd2) ? rs2_susp_count :
			(re_fhm_sel_dly == 4'd3) ? rs1_total_count :
			(re_fhm_sel_dly == 4'd4) ? rs2_total_count :
			(re_fhm_sel_dly == 4'd5) ? last_pc :
			(re_fhm_sel_dly == 4'd6) ? { 27'd0, last_rd } :
			(re_fhm_sel_dly == 4'd7) ? last_time :
			(re_fhm_sel_dly == 4'd8) ? rs1_suspfrz_count :
			(re_fhm_sel_dly == 4'd9) ? rs2_suspfrz_count :
			(re_fhm_sel_dly == 4'd10) ? last_pc_frz :
			{ 27'd0, last_rd_frz };

endmodule
