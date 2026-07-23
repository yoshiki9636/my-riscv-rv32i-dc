/*
 * My RISC-V RV32I CPU
 *   DRAM write/read hazard watchdog
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2026 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 *
 * Purpose (2026-07-21, software-side investigation): the long-documented
 * "DRAM write loss" corruption (see project memory
 * project_dram_write_loss_async_queue_theory / feedback_isr_required_for_write_loss)
 * has resisted every attempt to reproduce it on demand in an isolated
 * rtl_atomic_test - it only shows up reliably during real, long-running
 * Linux boots, at a different, unpredictable spot each time. Rather than
 * trying yet again to force a synthetic repro, this module watches the REAL
 * write path continuously and latches forensic evidence the moment a
 * suspicious condition occurs, so ANY real boot (regardless of where/how it
 * eventually crashes) becomes a data point: a READ accepted into req_queue
 * whose address matches a WRITE that was accepted into req_queue but has
 * NOT YET been committed to the DRAM controller (app_wdf_wren/app_wdf_rdy
 * handshake completed) is a hazard - the read *might* race ahead and return
 * stale data if the write's completion isn't actually ordered ahead of it
 * inside the (opaque, vendor) MIG core. This does not prove data was lost
 * on any single hit (this may be a benign, correctly-ordered case as far as
 * the MIG is concerned) - it just records every time the *precondition* for
 * that whole bug class occurs, with an address + timestamp, for later
 * correlation against whatever corruption software eventually observes.
 *
 * Lives in the mclk domain (instantiated alongside req_queue/mig_if in
 * dram_top.v), taps their existing internal signals directly - no changes
 * to req_queue.v or mig_if.v themselves. Exposes results to the CPU-side
 * MMIO bus (clk domain) via the same afifo async-FIFO IP already used
 * elsewhere in this design for cross-domain data (not a hand-rolled
 * synchronizer), one event record per hazard, so software can drain a
 * short history rather than just the single most recent hit.
 *
 * MMIO map (word addresses, `SYS_*` convention matching io_led.v/io_frc.v;
 * byte addresses = 0xC0000000 + (word_addr << 2), i.e. 0xC000C000 base):
 *   SYS_DWD_STATUS (3000 / 0xC000C000) [R]  bit0=event(s) queued, bit1=fifo-overflow sticky
 *   SYS_DWD_ADDR   (3001 / 0xC000C004) [R]  raddr of the oldest queued event (not popped by this read)
 *   SYS_DWD_TIME   (3002 / 0xC000C008) [R]  mclk-domain free-running cycle count at that event
 *   SYS_DWD_COUNT  (3003 / 0xC000C00C) [R]  total hazard events ever seen (free-running, coarse-synced)
 *   SYS_DWD_POP    (3004 / 0xC000C010) [W]  any write pops the oldest queued event (advance to next);
 *                                           write with bit31 set additionally clears the overflow sticky flag
 */

module dram_write_hazard_watchdog (
	// mclk domain - tapped directly from dram_top's existing internal wires
	input mclk,
	input mrst_n,
	input wcmd_ack,			// write request accepted into req_queue this cycle
	input [31:0] waddr,
	input rcmd_ack,			// read request accepted into req_queue this cycle
	input [31:0] raddr,
	input wdq_rnext,		// a write is being committed (data phase) to the DRAM controller this cycle
	input [31:0] req_qraddr,	// address of the write being committed this cycle (valid when wdq_rnext=1)

	// clk domain - CPU-side MMIO bus (same convention as io_led.v etc)
	input clk,
	input rst_n,
	input dma_io_we,
	input [15:2] dma_io_wadr,
	input [31:0] dma_io_wdata,
	input [15:2] dma_io_radr,
	input dma_io_radr_en,
	input [31:0] dma_io_rdata_in,
	output [31:0] dma_io_rdata
	);

`define SYS_DWD_STATUS 14'h3000
`define SYS_DWD_ADDR   14'h3001
`define SYS_DWD_TIME   14'h3002
`define SYS_DWD_COUNT  14'h3003
`define SYS_DWD_POP    14'h3004

// ---------------------------------------------------------------------
// mclk domain: shadow-track outstanding (accepted but not yet committed)
// write addresses, depth-matched to req_queue's own sfifo (SFIFODP=8).
// ---------------------------------------------------------------------
localparam PEND_DEPTH = 8;

reg [31:0] pend_addr [0:PEND_DEPTH-1];
reg [PEND_DEPTH-1:0] pend_valid;
reg [2:0] pend_head;
reg [2:0] pend_tail;

integer pi;

always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n) begin
		pend_valid <= {PEND_DEPTH{1'b0}};
		pend_head  <= 3'd0;
		pend_tail  <= 3'd0;
	end else begin
		if (wcmd_ack) begin
			pend_addr[pend_tail]  <= waddr;
			pend_valid[pend_tail] <= 1'b1;
			pend_tail <= pend_tail + 3'd1;
		end
		if (wdq_rnext) begin
			pend_valid[pend_head] <= 1'b0;
			pend_head <= pend_head + 3'd1;
		end
	end
end

// hazard check: does an accepted READ hit a still-pending (uncommitted)
// WRITE address? Compare at 16-byte (128-bit DRAM burst) granularity,
// matching the [27:4] alignment mig_if.v itself uses for app_addr.
reg hazard_hit;
integer hj;
always @ (*) begin
	hazard_hit = 1'b0;
	for (hj = 0; hj < PEND_DEPTH; hj = hj + 1) begin
		if (pend_valid[hj] && (pend_addr[hj][31:4] == raddr[31:4]))
			hazard_hit = 1'b1;
	end
end

wire hazard_event = rcmd_ack & hazard_hit;

// free-running cycle counter, mclk domain, for coarse relative timestamps
reg [31:0] mclk_cyclecnt;
always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n)
		mclk_cyclecnt <= 32'd0;
	else
		mclk_cyclecnt <= mclk_cyclecnt + 32'd1;
end

// total hazard event counter, mclk domain (free-running, never cleared -
// only the queued-event fifo/overflow flag are software-clearable)
reg [31:0] hazard_total;
always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n)
		hazard_total <= 32'd0;
	else if (hazard_event)
		hazard_total <= hazard_total + 32'd1;
end

// ---------------------------------------------------------------------
// CDC: mclk -> clk, one {cyclecnt,raddr} record per hazard event, via the
// same async-FIFO IP already used elsewhere in this design (afifo.v).
// ---------------------------------------------------------------------
wire [63:0] evt_wdata = { mclk_cyclecnt, raddr };
wire evt_wqfull;
wire evt_rqempty;
wire [63:0] evt_rdata;
wire evt_rnext;

afifo #(.AFIFODW(64)) hazard_evt_fifo (
	.wclk(mclk),
	.wrst_n(mrst_n),
	.rclk(clk),
	.rrst_n(rst_n),
	.wen(hazard_event),
	.wqfull(evt_wqfull),
	.wdata(evt_wdata),
	.rnext(evt_rnext),
	.rqempty(evt_rqempty),
	.rdata(evt_rdata)
	);

// coarse mclk->clk sync of the free-running total-event counter: value
// changes slowly relative to clk and is read post-mortem, not real-time,
// so a plain double-flop synchronizer per bit is adequate here (occasional
// one-count staleness from a read racing an increment is harmless for a
// "how many total, roughly" readout).
reg [31:0] hazard_total_s1, hazard_total_s2;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		hazard_total_s1 <= 32'd0;
		hazard_total_s2 <= 32'd0;
	end else begin
		hazard_total_s1 <= hazard_total;
		hazard_total_s2 <= hazard_total_s1;
	end
end

// overflow condition (a hazard fired while the event fifo had no room):
// pulse-synchronize into clk domain and latch as a sticky flag there.
wire mclk_overflow_pulse = hazard_event & evt_wqfull;
reg ovf_s1, ovf_s2, ovf_s3;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		ovf_s1 <= 1'b0;
		ovf_s2 <= 1'b0;
		ovf_s3 <= 1'b0;
	end else begin
		ovf_s1 <= mclk_overflow_pulse;
		ovf_s2 <= ovf_s1;
		ovf_s3 <= ovf_s2;
	end
end
wire ovf_edge_clk = ovf_s2 & ~ovf_s3;

// ---------------------------------------------------------------------
// clk domain: MMIO register decode (same shape as io_led.v)
// ---------------------------------------------------------------------
wire re_dwd_status = dma_io_radr_en & (dma_io_radr == `SYS_DWD_STATUS);
wire re_dwd_addr   = dma_io_radr_en & (dma_io_radr == `SYS_DWD_ADDR);
wire re_dwd_time   = dma_io_radr_en & (dma_io_radr == `SYS_DWD_TIME);
wire re_dwd_count  = dma_io_radr_en & (dma_io_radr == `SYS_DWD_COUNT);
wire we_dwd_pop    = dma_io_we      & (dma_io_wadr == `SYS_DWD_POP);

assign evt_rnext = we_dwd_pop & ~evt_rqempty;

reg fifo_overflow_sticky;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		fifo_overflow_sticky <= 1'b0;
	else if (we_dwd_pop & dma_io_wdata[31])
		fifo_overflow_sticky <= 1'b0;
	else if (ovf_edge_clk)
		fifo_overflow_sticky <= 1'b1;
end

reg re_dwd_dly;
reg [1:0] re_dwd_sel_dly;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		re_dwd_dly <= 1'b0;
		re_dwd_sel_dly <= 2'd0;
	end else begin
		re_dwd_dly <= re_dwd_status | re_dwd_addr | re_dwd_time | re_dwd_count;
		re_dwd_sel_dly <= re_dwd_status ? 2'd0 :
				  re_dwd_addr   ? 2'd1 :
				  re_dwd_time   ? 2'd2 :
				  2'd3;
	end
end

assign dma_io_rdata = ~re_dwd_dly ? dma_io_rdata_in :
			(re_dwd_sel_dly == 2'd0) ? { 30'd0, fifo_overflow_sticky, ~evt_rqempty } :
			(re_dwd_sel_dly == 2'd1) ? evt_rdata[31:0] :
			(re_dwd_sel_dly == 2'd2) ? evt_rdata[63:32] :
			hazard_total_s2;

endmodule
