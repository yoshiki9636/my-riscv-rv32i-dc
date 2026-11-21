/*
 * My RISC-V RV32I CPU
 *   behavioral model of sdram_if (simulation only)
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2026 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 *
 * Same module name / ports / parameters as ../sdram_if.v.  Compile this file
 * INSTEAD of ../sdram_if.v : the req / wdq / rdq protocol is the same, the
 * SDRAM chips are replaced by a 1MB line array (mem[], 128bit / line).
 *   - one request at a time (like the real sdram_if), random latency
 *   - write : wdq_mask_rdata[143:128] bit = 1 -> the byte is NOT written
 *   - the testbench loads the program with mem[] directly
 */

module sdram_if
	#(parameter MCLK_MHZ = 50,
	  parameter CAS_LAT = 2,
	  parameter RD_LAT = 3,
	  parameter OUT_NEGEDGE = 1
	) (
	input mclk,
	input mrst_n,

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

	// status
	output init_done,

	// SDRAM pins (not used)
	output [1:0] sdram_cs,
	output sdram_ras,
	output sdram_cas,
	output sdram_we,
	output [1:0] sdram_ba,
	output [12:0] sdram_adr,
	output [1:0] sdram_dqm,
	input [15:0] sdram_dq_i,
	output [15:0] sdram_dq_o,
	output sdram_dq_en
	);

assign sdram_cs = 2'b11;
assign sdram_ras = 1'b1;
assign sdram_cas = 1'b1;
assign sdram_we = 1'b1;
assign sdram_ba = 2'b00;
assign sdram_adr = 13'd0;
assign sdram_dqm = 2'b11;
assign sdram_dq_o = 16'd0;
assign sdram_dq_en = 1'b0;

// 1MB : line index = address[19:4]
reg [127:0] mem [0:65535];

// init done after a few cycles
reg [3:0] init_cnt;
always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n)
		init_cnt <= 4'd0;
	else if (init_cnt != 4'hf)
		init_cnt <= init_cnt + 4'd1;
end
assign init_done = (init_cnt == 4'hf);

reg busy;
reg [5:0] wait_cnt;
reg rd_op;
reg [15:0] l_idx;
reg [127:0] l_wdata;
reg [15:0] l_wmask;
reg rdq_wen_r;
reg [127:0] rdq_wdata_r;

wire in_idle = init_done & ~busy;
wire start_read  = in_idle & ~req_rqempty & req_rd_bwt;
wire start_write = in_idle & ~req_rqempty & ~req_rd_bwt & ~wdq_rqempty;

assign req_rnext = start_read | start_write;
assign wdq_rnext = start_write;

integer bi;

always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n) begin
		busy <= 1'b0;
		wait_cnt <= 6'd0;
		rd_op <= 1'b0;
		l_idx <= 16'd0;
		l_wdata <= 128'd0;
		l_wmask <= 16'd0;
		rdq_wen_r <= 1'b0;
		rdq_wdata_r <= 128'd0;
	end
	else begin
		rdq_wen_r <= 1'b0;
		if (start_read | start_write) begin
			busy <= 1'b1;
			rd_op <= start_read;
			l_idx <= req_qraddr[19:4];
			l_wdata <= wdq_mask_rdata[127:0];
			l_wmask <= wdq_mask_rdata[143:128];
			wait_cnt <= 6'd4 + ($random & 6'h7);
		end
		else if (busy) begin
			if (wait_cnt != 6'd0)
				wait_cnt <= wait_cnt - 6'd1;
			else begin
				busy <= 1'b0;
				if (rd_op) begin
					rdq_wen_r <= 1'b1;
					rdq_wdata_r <= mem[l_idx];
				end
				else begin
					for (bi = 0; bi < 16; bi = bi + 1)
						if (~l_wmask[bi])
							mem[l_idx][bi*8 +: 8] <= l_wdata[bi*8 +: 8];
				end
			end
		end
	end
end

assign rdq_wen = rdq_wen_r;
assign rdq_wdata = rdq_wdata_r;

endmodule
