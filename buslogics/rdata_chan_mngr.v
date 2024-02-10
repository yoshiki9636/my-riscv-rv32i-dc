/*
 * My RISC-V RV32I CPU
 *  read data channel manager
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module rdata_chan_mngr (
	input clk,
	input rst_n,

	// bus signals
	input rvalid,
	output  rready,
	input [3:0] rid,
	input [31:0] rdata,
	input rlast,
	// signals other side
	input next_rrq,
	input [3:0] next_rid,
	input rqfull_1,
	output [127:0] rdat_m_data,
	output reg rdat_m_valid,
	output finish_mrd

	);

`define RDAT_MIDLE 3'b000
`define RDAT_MBINP 3'b001
`define RDAT_MLST1 3'b010
`define RDAT_MBUSY 3'b011
`define RDAT_MDEFO 3'b111

// write data channel manager state machine
reg [2:0] rdat_m_current;
wire check_ok;

function [2:0] rdat_m_decode;
input [2:0] rdat_m_current;
input next_rrq;
input rvalid;
input rlast;
input rqfull_1;
input check_ok;
begin
    case(rdat_m_current)
		`RDAT_MIDLE: begin
    		case(next_rrq)
				1'b1: rdat_m_decode = `RDAT_MBINP;
				1'b0: rdat_m_decode = `RDAT_MIDLE;
				default: rdat_m_decode = `RDAT_MDEFO;
    		endcase
		end
		`RDAT_MBINP: begin
    		casex({rvalid, check_ok, rlast, rqfull_1, next_rrq})
				5'b0xxxx: rdat_m_decode = `RDAT_MBINP;
				5'b00xxx: rdat_m_decode = `RDAT_MBINP;
				5'b110xx: rdat_m_decode = `RDAT_MBINP;
				5'b11100: rdat_m_decode = `RDAT_MIDLE;
				5'b11101: rdat_m_decode = `RDAT_MBINP;
				5'b11110: rdat_m_decode = `RDAT_MBUSY;
				5'b11111: rdat_m_decode = `RDAT_MLST1;
				default: rdat_m_decode = `RDAT_MDEFO;
    		endcase
		end
		`RDAT_MLST1: begin
    		casex({rvalid, rlast, rqfull_1, next_rrq})
				4'b0xxx: rdat_m_decode = `RDAT_MLST1;
				4'b10xx: rdat_m_decode = `RDAT_MLST1;
				4'b111x: rdat_m_decode = `RDAT_MBUSY;
				4'b1101: rdat_m_decode = `RDAT_MBINP;
				4'b1100: rdat_m_decode = `RDAT_MIDLE;
				default: rdat_m_decode = `RDAT_MDEFO;
    		endcase
		end
		`RDAT_MBUSY: begin
    		casex({rqfull_1,next_rrq})
				2'b1x: rdat_m_decode = `RDAT_MBUSY;
				2'b01: rdat_m_decode = `RDAT_MBINP;
				2'b00: rdat_m_decode = `RDAT_MIDLE;
				default: rdat_m_decode = `RDAT_MDEFO;
    		endcase
		end
		`RDAT_MDEFO: rdat_m_decode = `RDAT_MDEFO;
		default:     rdat_m_decode = `RDAT_MDEFO;
   	endcase
end
endfunction

wire [2:0] rdat_m_next = rdat_m_decode( rdat_m_current, next_rrq, rvalid, rlast, rqfull_1, check_ok );

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        rdat_m_current <= `RDAT_MIDLE;
    else
        rdat_m_current <= rdat_m_next;
end

assign rready = (rdat_m_current == `RDAT_MBINP)|(rdat_m_current == `RDAT_MLST1);

// burst counter just spport 4
reg [1:0] burst_cntr;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        burst_cntr <= 2'd0;
    else if (rlast & rready & check_ok)
        burst_cntr <= 2'd0;
    else if (rready & rvalid & check_ok)
        burst_cntr <= burst_cntr + 2'd1;
end

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        rdat_m_valid <= 1'b0;
    else
        rdat_m_valid <= rlast & rready & check_ok;
end

assign finish_mrd = rdat_m_valid;

// data buffer
reg [31:0] rdata_ofs0;
reg [31:0] rdata_ofs1;
reg [31:0] rdata_ofs2;
reg [31:0] rdata_ofs3;

// write enables
wire rdata_ofs0_wen = rready & rvalid & check_ok & (burst_cntr == 2'd0);
wire rdata_ofs1_wen = rready & rvalid & check_ok & (burst_cntr == 2'd1);
wire rdata_ofs2_wen = rready & rvalid & check_ok & (burst_cntr == 2'd2);
wire rdata_ofs3_wen = rready & rvalid & check_ok & (burst_cntr == 2'd3);

// data ofs 0
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
       rdata_ofs0  <= 32'd0;
    else if (rdata_ofs0_wen)
       rdata_ofs0  <= rdata;
end

// data ofs 1
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
       rdata_ofs1  <= 32'd0;
    else if (rdata_ofs0_wen & rlast)
       rdata_ofs1  <= 32'd0;
    else if (rdata_ofs1_wen)
       rdata_ofs1  <= rdata;
end

// data ofs 2
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
       rdata_ofs2  <= 32'd0;
    else if ((rdata_ofs0_wen | rdata_ofs1_wen) & rlast)
       rdata_ofs2  <= 32'd0;
    else if (rdata_ofs2_wen)
       rdata_ofs2  <= rdata;
end

// data ofs 3
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
       rdata_ofs3  <= 32'd0;
    else if ((rdata_ofs0_wen | rdata_ofs1_wen | rdata_ofs2_wen) & rlast)
       rdata_ofs3  <= 32'd0;
    else if (rdata_ofs3_wen)
       rdata_ofs3  <= rdata;
end

assign rdat_m_data = { rdata_ofs3, rdata_ofs2, rdata_ofs1, rdata_ofs0 };


// check ok
reg [3:0] next_rid_lat;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        next_rid_lat <= 3'd0;
    else if ( next_rrq )
        next_rid_lat <= next_rid;
end

assign check_ok = rready & (rid == next_rid_lat);

endmodule
