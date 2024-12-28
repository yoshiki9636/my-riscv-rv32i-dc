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
reg [31:0] wadr_keeper;
reg collision_selw;
wire wqfull;

wire collision = wcmd_wen & rcmd_wen;

always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n)
		collision_selw  <= 1'b0;
	else if (collision)
		collision_selw  <= ~collision_selw;
	else if (rcmd_wen)
		collision_selw  <= 1'b0;
	else if (wcmd_wen)
		collision_selw  <= 1'b1;
	else
		collision_selw  <= 1'b0;
end

assign selr = (collision ? ~collision_selw : rcmd_wen) & ~wqfull;
assign selw = (collision ?  collision_selw : wcmd_wen) & ~wqfull;

assign qw_rd_bwt_addr = selr ? { 1'b1, raddr } :
                        selw ? { 1'b0, waddr } : 33'd0;

wire qwen = (rcmd_wen | wcmd_wen) & ~wqfull;

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

assign rqempty_pre = (ppcntr == 4'd0);
assign rqempty = rqempty_pre | rwait;

// wait cycle
always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n)
		rwait  <= 1'b0;
	else
		rwait  <=  ~rqempty_pre & rnext;
end

endmodule
