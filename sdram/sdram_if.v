/*
 * My RISC-V RV32I CPU
 *   SDR SDRAM interface (replacement of mig_if / MIG for Tang Primer 25K)
 *    single clock (mclk) version, derived from sdram_sample/sdram_ctrl.sv
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2026 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

// Line side interface is the same as mig_if / qspi_line_if :
//   req : 128bit line request (byte address, rd_bwt = 1 : read / 0 : write)
//   wdq : { mask[15:0], data[127:0] } mask bit 1 : byte NOT written (same as MIG)
//   rdq : 128bit read line (no back pressure, same as mig_if)
//
// SDRAM : 16bit SDR SDRAM x 2 chips (Tang Primer 25K SDRAM module)
//   sdram_cs selects the chip in the same way as sdram_sample (0 : chip0, 1 : chip1)
//   byte address mapping (64MB) :
//     [25] cs, [24:12] row(13bit), [11:10] bank, [9:1] column, [0] byte
//   one 128bit line = 8 x 16bit = one BL8 burst (column [2:0] = 0)
//
// Access policy : closed page. ACT -> READA / WRITEA (BL8, auto precharge).
//   Bank state is always "idle" in S_IDLE, so refresh can be issued at once.
//
// Single clock, no phase adjustment (for LSI implementation) :
//   every SDRAM output is a register of mclk, the SDRAM chip clock pin is mclk
//   itself (0deg, sdram_clk = mclk in fpga_top), and the read data is captured
//   by mclk (sdram_dq_i -> dq_in_r) RD_LAT clocks after the READ command edge.
//   Low frequency (50MHz) makes the timing window wide enough without the 2nd
//   clock (aux_clk) of sdram_sample or any clock phase shift.
//     cmd launched at mclk edge E0 -> SDRAM samples it at E0 + 1T (+ dclk)
//     read data valid : E0 + (CAS_LAT)T + dclk + tAC + din
//                    .. E0 + (CAS_LAT+1)T + dclk + tOH + din
//     dq_in_r samples at E0 + RD_LAT  -> RD_LAT = CAS_LAT + 1
//   e.g. 50MHz (T = 20ns), CL2, RD_LAT 3, dclk + din = 2ns :
//        valid 47.4ns .. 64.5ns, sampled at 60ns (setup 12.6ns, hold 4.5ns)
//   dclk : mclk -> sdram_clk pin delay, din : dq pin -> dq_in_r delay
//
// OUT_NEGEDGE = 1 (default) : the SDRAM output pins (cmd / adr / dqm / write dq)
//   are re-registered at the falling edge of mclk. The pins change at the middle
//   of the SDRAM clock cycle, so setup / hold to the SDRAM is about T/2 each and
//   does not depend on the sdram_clk pin delay (dclk) vs output delay (tco).
//   With OUT_NEGEDGE = 0 and sdram_clk = mclk (0deg), the SDRAM samples a command
//   at the next edge only when tco > dclk + tIH. If dclk is larger, the command is
//   taken at the same edge (1 cycle early, RD_LAT mismatch) or hold is violated.
//   Latency from E0 (posedge where the state machine issues a command) is the same
//   in both modes : the SDRAM samples it at E0 + 1T + dclk, RD_LAT = CAS_LAT + 1.
//   50MHz, CL2, RD_LAT 3, OUT_NEGEDGE 1 : read OK for -2.5ns < dclk + din < 14.6ns
//   (minus tIS / tIH margins)

module sdram_if
	#(parameter MCLK_MHZ = 50,  // mclk frequency (MHz, integer) : timing calc only
	  parameter CAS_LAT = 2,    // 2 or 3
	  parameter RD_LAT = 3,     // READ cmd edge -> 1st beat sampled in dq_in_r (CAS_LAT + 1)
	  parameter OUT_NEGEDGE = 1 // 1 : SDRAM output pins change at negedge mclk
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

	// SDRAM pins (tri-state buffer of dq is in fpga_top)
	output sdram_cs,
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

// ---- timing (clock cycles, rounded up) ----
//   W9825G6KH-6 class : tRP/tRCD 18ns, tRC 60ns, tWR 2clk, tMRD 2clk
//   refresh 8192 / 64ms = 7.8us -> issue every 6.0us (margin for the access in progress)
localparam integer T_RP_C   = (20 * MCLK_MHZ + 999) / 1000;
localparam integer T_RCD_C  = (20 * MCLK_MHZ + 999) / 1000;
localparam integer T_RFC_C  = (70 * MCLK_MHZ + 999) / 1000;
localparam integer T_WR_C   = (15 * MCLK_MHZ + 999) / 1000;
localparam integer T_RP     = (T_RP_C  < 2) ? 2 : T_RP_C;
localparam integer T_RCD    = (T_RCD_C < 2) ? 2 : T_RCD_C;
localparam integer T_RFC    = (T_RFC_C < 2) ? 2 : T_RFC_C;
localparam integer T_WR     = (T_WR_C  < 2) ? 2 : T_WR_C;
localparam integer T_MRD    = 3;
localparam integer T_INIT   = 200 * MCLK_MHZ;         // 200us power up wait
localparam integer T_REFI   = (6000 * MCLK_MHZ) / 1000;
localparam integer BL       = 8;
// READA : auto precharge starts BL clocks after READ, and the last beat is
//         captured at E0 + RD_LAT + BL. wait both before the next ACT.
localparam integer T_RD_END_A = RD_LAT + BL + 1;
localparam integer T_RD_END_B = BL + T_RP;
localparam integer T_RD_END   = (T_RD_END_A > T_RD_END_B) ? T_RD_END_A : T_RD_END_B;
// WRITEA : last data -> tWR -> auto precharge -> tRP (+1 margin)
localparam integer T_WR_END   = T_WR + T_RP + 1;

// wait counter load values (command at E -> next command at E + T)
localparam integer W_RP     = T_RP - 1;
localparam integer W_RCD    = T_RCD - 1;
localparam integer W_RFC    = T_RFC - 1;
localparam integer W_MRD    = T_MRD - 1;
localparam integer W_RD_END = T_RD_END - 1;
localparam integer W_WR_END = T_WR_END - 1;
localparam integer W_INIT   = T_INIT;
localparam integer W_REFI   = T_REFI;
localparam integer W_BL     = BL - 1;
localparam integer CL_BITS  = CAS_LAT;

// mode register : burst write, CL, sequential, BL8
wire [12:0] mode_reg = { 3'b000, 1'b0, 2'b00, CL_BITS[2:0], 1'b0, 3'b011 };

// ---- state ----
localparam [3:0] S_INIT_WAIT = 4'd0,
                 S_INIT_PALL = 4'd1,
                 S_INIT_REF1 = 4'd2,
                 S_INIT_REF2 = 4'd3,
                 S_INIT_MRS  = 4'd4,
                 S_INIT_NEXT = 4'd5,
                 S_IDLE      = 4'd6,
                 S_ACT_WAIT  = 4'd7,
                 S_RD_WAIT   = 4'd8,
                 S_WR_BURST  = 4'd9,
                 S_WR_WAIT   = 4'd10,
                 S_REF2      = 4'd11,
                 S_REF_WAIT  = 4'd12;

reg [3:0] state;
reg [15:0] wcnt;       // wait counter : command at E -> next command at E + (wcnt+1)
reg init_chip;         // chip under initialization
reg init_done_r;

// refresh request
reg [11:0] ref_cnt;
reg ref_req;

// latched request
reg l_rd;
reg l_cs;
reg [1:0] l_bank;
reg [5:0] l_col;       // column [8:3]
reg [127:0] l_wdata;   // shifted 16bit / beat
reg [15:0] l_wmask;    // shifted 2bit / beat
reg [2:0] wbeat;

// SDRAM output registers (OUT_NEGEDGE = 0 : should be packed into IOB)
reg o_cs;
reg o_ras;
reg o_cas;
reg o_we;
reg [1:0] o_ba;
reg [12:0] o_adr;
reg [1:0] o_dqm;
reg [15:0] o_dq;
reg o_dq_en;

// read window : 1 for BL clocks from the READ command edge
reg rd_win;
reg [2:0] rd_win_cnt;

// request accept (same style as qspi_line_if)
wire in_idle = (state == S_IDLE);
wire start_read  = in_idle & ~ref_req & ~req_rqempty & req_rd_bwt;
wire start_write = in_idle & ~ref_req & ~req_rqempty & ~req_rd_bwt & ~wdq_rqempty;

assign req_rnext = start_read | start_write;
assign wdq_rnext = start_write;

// byte address -> SDRAM address
wire        a_cs   = req_qraddr[25];
wire [12:0] a_row  = req_qraddr[24:12];
wire [1:0]  a_bank = req_qraddr[11:10];
wire [5:0]  a_col  = req_qraddr[9:4];

// column address with A10 = 1 (auto precharge)
wire [12:0] col_adr_ap = { 2'b00, 1'b1, 1'b0, l_col, 3'b000 };

// refresh timer
always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n) begin
		ref_cnt <= 12'd0;
		ref_req <= 1'b0;
	end
	else if (~init_done_r) begin
		ref_cnt <= W_REFI[11:0];
		ref_req <= 1'b0;
	end
	else begin
		if (ref_cnt == 12'd0)
			ref_cnt <= W_REFI[11:0];
		else
			ref_cnt <= ref_cnt - 12'd1;

		if (ref_cnt == 12'd0)
			ref_req <= 1'b1;
		else if (in_idle)
			ref_req <= 1'b0; // refresh is issued in S_IDLE when ref_req == 1
	end
end

// main state machine
always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n) begin
		state <= S_INIT_WAIT;
		wcnt <= W_INIT[15:0];
		init_chip <= 1'b0;
		init_done_r <= 1'b0;
		l_rd <= 1'b0;
		l_cs <= 1'b0;
		l_bank <= 2'd0;
		l_col <= 6'd0;
		l_wdata <= 128'd0;
		l_wmask <= 16'hffff;
		wbeat <= 3'd0;
		o_cs <= 1'b0;
		o_ras <= 1'b1;
		o_cas <= 1'b1;
		o_we <= 1'b1;
		o_ba <= 2'd0;
		o_adr <= 13'd0;
		o_dqm <= 2'b11;
		o_dq <= 16'd0;
		o_dq_en <= 1'b0;
		rd_win <= 1'b0;
		rd_win_cnt <= 3'd0;
	end
	else begin
		// default : NOP (cs keeps the last value)
		o_ras <= 1'b1;
		o_cas <= 1'b1;
		o_we <= 1'b1;
		o_dq_en <= 1'b0;
		o_dqm <= init_done_r ? 2'b00 : 2'b11;

		if (wcnt != 16'd0)
			wcnt <= wcnt - 16'd1;

		// read window
		if (rd_win) begin
			if (rd_win_cnt == 3'd0)
				rd_win <= 1'b0;
			else
				rd_win_cnt <= rd_win_cnt - 3'd1;
		end

		case (state)
		// ---- initialization (chip0 -> chip1, same as sdram_sample) ----
		S_INIT_WAIT : if (wcnt == 16'd0) state <= S_INIT_PALL;
		S_INIT_PALL : if (wcnt == 16'd0) begin // precharge all
			o_cs <= init_chip;
			o_ras <= 1'b0;
			o_we <= 1'b0;
			o_adr <= 13'h0400; // A10 = 1
			wcnt <= W_RP[15:0];
			state <= S_INIT_REF1;
		end
		S_INIT_REF1 : if (wcnt == 16'd0) begin // auto refresh
			o_cs <= init_chip;
			o_ras <= 1'b0;
			o_cas <= 1'b0;
			wcnt <= W_RFC[15:0];
			state <= S_INIT_REF2;
		end
		S_INIT_REF2 : if (wcnt == 16'd0) begin // auto refresh
			o_cs <= init_chip;
			o_ras <= 1'b0;
			o_cas <= 1'b0;
			wcnt <= W_RFC[15:0];
			state <= S_INIT_MRS;
		end
		S_INIT_MRS : if (wcnt == 16'd0) begin // load mode register
			o_cs <= init_chip;
			o_ras <= 1'b0;
			o_cas <= 1'b0;
			o_we <= 1'b0;
			o_ba <= 2'b00;
			o_adr <= mode_reg;
			wcnt <= W_MRD[15:0];
			state <= S_INIT_NEXT;
		end
		S_INIT_NEXT : if (wcnt == 16'd0) begin
			if (~init_chip) begin
				init_chip <= 1'b1;
				state <= S_INIT_PALL;
			end
			else begin
				init_done_r <= 1'b1;
				state <= S_IDLE;
			end
		end
		// ---- normal operation ----
		S_IDLE : begin
			if (ref_req) begin // refresh chip0 (all banks are idle here)
				o_cs <= 1'b0;
				o_ras <= 1'b0;
				o_cas <= 1'b0;
				state <= S_REF2;
			end
			else if (start_read | start_write) begin // activate
				o_cs <= a_cs;
				o_ras <= 1'b0;
				o_ba <= a_bank;
				o_adr <= a_row;
				l_rd <= start_read;
				l_cs <= a_cs;
				l_bank <= a_bank;
				l_col <= a_col;
				if (start_write) begin
					l_wdata <= wdq_mask_rdata[127:0];
					l_wmask <= wdq_mask_rdata[143:128];
				end
				wcnt <= W_RCD[15:0];
				state <= S_ACT_WAIT;
			end
		end
		S_ACT_WAIT : if (wcnt == 16'd0) begin
			o_cs <= l_cs;
			o_cas <= 1'b0;
			o_ba <= l_bank;
			o_adr <= col_adr_ap;
			if (l_rd) begin // READA
				rd_win <= 1'b1;
				rd_win_cnt <= W_BL[2:0];
				wcnt <= W_RD_END[15:0];
				state <= S_RD_WAIT;
			end
			else begin // WRITEA with beat 0
				o_we <= 1'b0;
				o_dq_en <= 1'b1;
				o_dq <= l_wdata[15:0];
				o_dqm <= l_wmask[1:0];
				l_wdata <= { 16'd0, l_wdata[127:16] };
				l_wmask <= { 2'b11, l_wmask[15:2] };
				wbeat <= 3'd1;
				state <= S_WR_BURST;
			end
		end
		S_RD_WAIT : if (wcnt == 16'd0) state <= S_IDLE;
		S_WR_BURST : begin // beat 1 - 7
			o_dq_en <= 1'b1;
			o_dq <= l_wdata[15:0];
			o_dqm <= l_wmask[1:0];
			l_wdata <= { 16'd0, l_wdata[127:16] };
			l_wmask <= { 2'b11, l_wmask[15:2] };
			wbeat <= wbeat + 3'd1;
			if (wbeat == 3'd7) begin
				wcnt <= W_WR_END[15:0];
				state <= S_WR_WAIT;
			end
		end
		S_WR_WAIT : if (wcnt == 16'd0) state <= S_IDLE;
		S_REF2 : begin // refresh chip1
			o_cs <= 1'b1;
			o_ras <= 1'b0;
			o_cas <= 1'b0;
			wcnt <= W_RFC[15:0];
			state <= S_REF_WAIT;
		end
		S_REF_WAIT : if (wcnt == 16'd0) state <= S_IDLE;
		default : state <= S_IDLE;
		endcase
	end
end

// ---- read data capture (mclk) ----
reg [15:0] dq_in_r; // should be packed into IOB
always @ (posedge mclk) begin
	dq_in_r <= sdram_dq_i;
end

reg [RD_LAT-1:0] rd_dly;
always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n)
		rd_dly <= { RD_LAT{ 1'b0 }};
	else
		rd_dly <= (rd_dly << 1) | { { (RD_LAT-1){ 1'b0 }}, rd_win };
end

// rd_dly[RD_LAT-1] == 1 : dq_in_r holds a beat (beat 0 - 7)
wire rd_capture = rd_dly[RD_LAT-1];

reg [127:0] rd_line;
reg [2:0] rd_beat;
reg rdq_wen_r;

always @ (posedge mclk or negedge mrst_n) begin
	if (~mrst_n) begin
		rd_line <= 128'd0;
		rd_beat <= 3'd0;
		rdq_wen_r <= 1'b0;
	end
	else begin
		rdq_wen_r <= rd_capture & (rd_beat == 3'd7);
		if (rd_capture) begin
			rd_line <= { dq_in_r, rd_line[127:16] }; // beat 0 ends up in [15:0]
			rd_beat <= rd_beat + 3'd1;
		end
	end
end

assign rdq_wen = rdq_wen_r;
assign rdq_wdata = rd_line;

assign init_done = init_done_r;

// ---- SDRAM output stage ----
//   { cs, ras, cas, we, ba[1:0], adr[12:0], dqm[1:0], dq[15:0], dq_en } = 38bit
wire [37:0] out_pos = { o_cs, o_ras, o_cas, o_we, o_ba, o_adr, o_dqm, o_dq, o_dq_en };
wire [37:0] out_pin;

generate
if (OUT_NEGEDGE != 0) begin : g_out_neg
	// falling edge output registers (should be packed into IOB)
	reg [37:0] out_neg;
	always @ (negedge mclk or negedge mrst_n) begin
		if (~mrst_n) // NOP, cs 0, dqm 11, dq_en 0 (same as o_* reset values)
			out_neg <= { 1'b0, 1'b1, 1'b1, 1'b1, 2'd0, 13'd0, 2'b11, 16'd0, 1'b0 };
		else
			out_neg <= out_pos;
	end
	assign out_pin = out_neg;
end
else begin : g_out_pos
	assign out_pin = out_pos;
end
endgenerate

assign { sdram_cs, sdram_ras, sdram_cas, sdram_we, sdram_ba, sdram_adr,
         sdram_dqm, sdram_dq_o, sdram_dq_en } = out_pin;

endmodule
