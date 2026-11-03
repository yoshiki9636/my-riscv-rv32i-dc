/*
 * My RISC-V RV32I CPU
 *   128bit line request -> qspi_if word/halfword/byte access converter
 *   (replacement of mig_if for QSPI main memory)
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2026 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

// read  : 1 line (16B) = 4 x 32bit qspi read, then 1 rdq write
// write : 1 line (16B) with 16bit byte mask (1 : not written, MIG style)
//         per word  mask 4'b0000 : 32bit write
//                   mask 4'b1111 : skipped
//                   others       : 16bit / 8bit writes for unmasked bytes
// qspi address : [25:24] chip select (cs0-cs2), [23:0] address in chip
// qspi_if request is a 1-cycle pulse; the next request is issued
// at least 1 cycle after read_valid / write_finish

module qspi_line_if (
	input clk,
	input rst_n,

	// req
	output req_rnext,
	input req_rqempty,
	input [31:0] req_qraddr,
	input req_rd_bwt,
	// wdq
	output wdq_rnext,
	input wdq_rqempty,
	input [143:0] wdq_mask_rdata,
	// rdq
	output rdq_wen,
	output [127:0] rdq_wdata,

	// qspi_if interface
	output read_req,
	output read_w,
	output read_hw,
	input read_valid,
	output [31:0] read_adr,
	input [31:0] read_data,
	output write_req,
	output write_w,
	output write_hw,
	input write_finish,
	output [31:0] write_adr,
	output [31:0] write_data
	);

`define QL_IDLE  3'd0
`define QL_RREQ  3'd1
`define QL_RWAIT 3'd2
`define QL_RDONE 3'd3
`define QL_WSEL  3'd4
`define QL_WWAIT 3'd5

reg [2:0] ql_state;
reg [25:4] line_adr;
reg [1:0] widx;    // word index in line
reg [2:0] bidx;    // byte index in word (4 : word done)
reg [127:0] line_data;
reg [15:0] line_mask;

// request start
wire start_read  = (ql_state == `QL_IDLE) & ~req_rqempty & req_rd_bwt;
wire start_write = (ql_state == `QL_IDLE) & ~req_rqempty & ~req_rd_bwt & ~wdq_rqempty;

assign req_rnext = start_read | start_write;
assign wdq_rnext = start_write;

// current word / mask
wire [31:0] cur_word = (widx == 2'd0) ? line_data[31:0] :
                       (widx == 2'd1) ? line_data[63:32] :
                       (widx == 2'd2) ? line_data[95:64] : line_data[127:96];
wire [3:0] cur_mask  = (widx == 2'd0) ? line_mask[3:0] :
                       (widx == 2'd1) ? line_mask[7:4] :
                       (widx == 2'd2) ? line_mask[11:8] : line_mask[15:12];

// write access selection in QL_WSEL
wire word_done = bidx[2];
wire [1:0] boff = bidx[1:0];
wire cur_bmask  = cur_mask[boff];
wire next_bmask = (boff == 2'd0) ? cur_mask[1] :
                  (boff == 2'd2) ? cur_mask[3] : 1'b1;
wire wsel_word = ~word_done & (boff == 2'd0) & (cur_mask == 4'b0000);
wire wsel_hw   = ~word_done & ~wsel_word & ~boff[0] & ~cur_bmask & ~next_bmask;
wire wsel_byte = ~word_done & ~wsel_word & ~wsel_hw & ~cur_bmask;
wire wsel_skip = ~word_done & ~wsel_word & ~wsel_hw & ~wsel_byte;
wire wsel_any  = wsel_word | wsel_hw | wsel_byte;
wire in_wsel   = (ql_state == `QL_WSEL);
wire last_word = (widx == 2'd3);

// state machine
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		ql_state <= `QL_IDLE;
	else case (ql_state)
		`QL_IDLE  : if (start_read) ql_state <= `QL_RREQ;
		            else if (start_write) ql_state <= `QL_WSEL;
		`QL_RREQ  : ql_state <= `QL_RWAIT;
		`QL_RWAIT : if (read_valid) ql_state <= last_word ? `QL_RDONE : `QL_RREQ;
		`QL_RDONE : ql_state <= `QL_IDLE;
		`QL_WSEL  : if (word_done & last_word) ql_state <= `QL_IDLE;
		            else if (wsel_any) ql_state <= `QL_WWAIT;
		`QL_WWAIT : if (write_finish) ql_state <= `QL_WSEL;
		default   : ql_state <= `QL_IDLE;
	endcase
end

// line address
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		line_adr <= 22'd0;
	else if (start_read | start_write)
		line_adr <= req_qraddr[25:4];
end

// word index
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		widx <= 2'd0;
	else if (start_read | start_write)
		widx <= 2'd0;
	else if ((ql_state == `QL_RWAIT) & read_valid)
		widx <= widx + 2'd1;
	else if (in_wsel & word_done & ~last_word)
		widx <= widx + 2'd1;
end

// byte index
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		bidx <= 3'd0;
	else if (start_write)
		bidx <= 3'd0;
	else if (in_wsel) begin
		if (word_done)
			bidx <= 3'd0;
		else if (wsel_word)
			bidx <= 3'd4;
		else if (wsel_hw)
			bidx <= bidx + 3'd2;
		else // byte or skip
			bidx <= bidx + 3'd1;
	end
end

// line data : write data latch / read data assembly
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		line_data <= 128'd0;
		line_mask <= 16'hffff;
	end
	else if (start_write) begin
		line_data <= wdq_mask_rdata[127:0];
		line_mask <= wdq_mask_rdata[143:128];
	end
	else if ((ql_state == `QL_RWAIT) & read_valid) begin
		case (widx)
			2'd0 : line_data[31:0]   <= read_data;
			2'd1 : line_data[63:32]  <= read_data;
			2'd2 : line_data[95:64]  <= read_data;
			2'd3 : line_data[127:96] <= read_data;
		endcase
	end
end

assign rdq_wen = (ql_state == `QL_RDONE);
assign rdq_wdata = line_data;

// qspi_if read request
assign read_req = (ql_state == `QL_RREQ);
assign read_w = 1'b1;
assign read_hw = 1'b0;
assign read_adr = { 6'd0, line_adr, widx, 2'b00 };

// qspi_if write request
assign write_req = in_wsel & wsel_any;
assign write_w = wsel_word;
assign write_hw = wsel_hw;
assign write_adr = { 6'd0, line_adr, widx, boff };
assign write_data = (boff == 2'd0) ? cur_word :
                    (boff == 2'd1) ? { 8'd0, cur_word[31:8] } :
                    (boff == 2'd2) ? { 16'd0, cur_word[31:16] } : { 24'd0, cur_word[31:24] };

endmodule
