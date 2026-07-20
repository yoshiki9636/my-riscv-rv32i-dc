/*
 * My RISC-V RV32I CPU
 *   request queue
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module req_queue (
	input mclk,
	input mrst_n,

    input wcmd_wen,
    input rcmd_wen,
	output wcmd_ack,
	output rcmd_ack,
    input [31:0] waddr,
    input [31:0] raddr,
    input rnext,
	output rqempty,
    output [31:0] qraddr,
    output rd_bwt
	);

reg [2:0] wadr;
reg [2:0] radr;
wire [32:0] qw_rd_bwt_addr;
wire [32:0] qr_rd_bwt_addr;

// assume no back-to-back request on write
//reg [31:0] wadr_keeper;
wire wqfull;

// WRITE PRIORITY RESTORED (2026-07-19) - the 2026-07-17 revert's
// rationale (2) ("a read and a same-address write are never
// simultaneously outstanding because the D$ stalls until the refill
// completes") is WRONG for the flush-then-reload pattern:
// wresp_chan_subo returns bcomp=1'b1 as soon as the data lands in the
// CPU-side CDC afifo, long before the DRAM commit, so a fence.i D$
// flush leaves up to afifo+queue-depth "completed" writes still
// draining here.  The flush also INVALIDATES every line it wrote back,
// so the CPU's very next access to any flushed address is a guaranteed
// miss whose read request arrives at this input while the OLDER write
// to the SAME address is still waiting at wcmd_wen - the round-robin
// then let the read overtake the write and the refill returned STALE
// DRAM data ("lost writeback" symptom without any write being lost).
// kernel#778 (fence.i restored) turned this from a rare eviction race
// into the common case and melted the initramfs unpack.  Writes must
// win: read starvation is bounded (the write stream is finite and
// drains into the MIG independently of reads - no deadlock), and a
// stalled read is just a longer D$/I$ miss.
wire selw = wcmd_wen & ~wqfull;
wire selr = rcmd_wen & ~wcmd_wen & ~wqfull;

assign qw_rd_bwt_addr = selr ? { 1'b1, raddr } :
                        selw ? { 1'b0, waddr } : 33'd0;

//wire qwen = (rcmd_wen | wcmd_wen) & ~wqfull;
wire qwen = selr | selw;

assign wcmd_ack = selw;
assign rcmd_ack = selr;

sfifo_1r1w
	#(.SFIFODW(33),
	  .SFIFOAW(3),
	  .SFIFODP(8)
	) sfifo_1r1w (
	.clk(mclk),
	.ram_radr(radr),
	.ram_rdata(qr_rd_bwt_addr),
	.ram_wadr(wadr),
	.ram_wdata(qw_rd_bwt_addr),
	.ram_wen(qwen)
	);

assign qraddr = qr_rd_bwt_addr[31:0];
assign rd_bwt = qr_rd_bwt_addr[32];

// fifo controls

always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n)
		wadr  <= 3'd0;
	else if (qwen)
		wadr  <= wadr + 3'd1;
end

always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n)
		radr  <= 3'd0;
	else if (rnext)
		radr  <= radr + 3'd1;
end

// for ppcntr
reg qwen_dly;
always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n)
		qwen_dly  <= 1'b0;
	else
		qwen_dly  <= qwen;
end
// push pull counter
reg [3:0] ppcntr;

always @ (posedge mclk or negedge mrst_n) begin
    if (~mrst_n)
        ppcntr  <= 4'd0;
    else if (qwen_dly & rnext)
        ppcntr  <= ppcntr;
    else if (qwen_dly)
        ppcntr  <= ppcntr + 4'd1;
    else if (rnext)
        ppcntr  <= ppcntr - 4'd1;
end

// qfull checker
reg rwait;
assign wqfull = (ppcntr >= 4'd8);

wire rqempty_pre = (ppcntr == 4'd0);
assign rqempty = rqempty_pre | rwait;

// wait cycle
always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n)
		rwait <= 1'b0;
	else
		//rwait  <=  ~rqempty_pre & rnext;
		rwait <= rnext;
end

endmodule
