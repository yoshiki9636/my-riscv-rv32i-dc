/*
 * My RISC-V RV32I CPU
 *  read data channel subordinamte
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module rdata_chan_subo (
	input clk,
	input rst_n,

	// bus signals
	output rvalid,
	input  rready,
	output reg [3:0] rid,
	output [31:0] rdata,
	output rlast,
	// signals other side
	input rdata_s_valid, //level
	input [3:0] rdata_s_id,
	input [127:0] rdata_s_data,
	output finish_rdata_s

	);

`define RDAT_SIDLE 2'b00
`define RDAT_SBOUT 2'b01
`define RDAT_SBFIN 2'b10
`define RDAT_SDEFO 2'b11

// write data channel manager state machine
reg [1:0] rdat_s_current;
wire rcntr_2;

function [1:0] rdat_s_decode;
input [1:0] rdat_s_current;
input rdata_s_valid;
input rready;
input rcntr_2;
begin
    case(rdat_s_current)
		`RDAT_SIDLE: begin
    		case(rdata_s_valid)
				1'b1: rdat_s_decode = `RDAT_SBOUT;
				1'b0: rdat_s_decode = `RDAT_SIDLE;
				default: rdat_s_decode = `RDAT_SDEFO;
    		endcase
		end
		`RDAT_SBOUT: begin
    		casex({rready, rcntr_2})
				2'b0x: rdat_s_decode = `RDAT_SBOUT;
				2'b10: rdat_s_decode = `RDAT_SBOUT;
				2'b11: rdat_s_decode = `RDAT_SBFIN;
				default: rdat_s_decode = `RDAT_SDEFO;
    		endcase
		end
		`RDAT_SBFIN: begin
    		casex(rready)
				1'b0: rdat_s_decode = `RDAT_SBFIN;
				1'b1: rdat_s_decode = `RDAT_SIDLE;
				default: rdat_s_decode = `RDAT_SDEFO;
    		endcase
		end
		`RDAT_SDEFO: rdat_s_decode = `RDAT_SDEFO;
		default:     rdat_s_decode = `RDAT_SDEFO;
   	endcase
end
endfunction

wire [1:0] rdat_s_next = rdat_s_decode( rdat_s_current, rdata_s_valid, rready, rcntr_2 );

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        rdat_s_current <= `RDAT_SIDLE;
    else
        rdat_s_current <= rdat_s_next;
end

assign rvalid = (rdat_s_current == `RDAT_SBOUT)|(rdat_s_current == `RDAT_SBFIN);
wire next_ok = (rdat_s_current == `RDAT_SIDLE);

// burst counter just spport 4
reg [1:0] burst_cntr;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        burst_cntr <= 2'd0;
    else if (rdata_s_valid & next_ok)
        burst_cntr <= 2'd3;
    else if (burst_cntr > 2'd0)
        burst_cntr <= burst_cntr - 2'd1;
end

assign rcntr_2 = (burst_cntr == 2'd1);

// read data buffer
reg [127:0] rdata_lat;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
       rdata_lat  <= 128'd0;
    else if (rdata_s_valid)
       rdata_lat  <= rdata_s_data;
end

assign  rdata = (burst_cntr == 2'd3) ? rdata_lat[31:0] :
                (burst_cntr == 2'd2) ? rdata_lat[63:32] :
                (burst_cntr == 2'd1) ? rdata_lat[95:64] : rdata_lat[127:96];

assign rlast = (rdat_s_current == `RDAT_SBFIN);

assign finish_rdata_s = rlast & rready;

// id latch
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        rid <= 4'd0;
    else if (rdata_s_valid)
        rid <= rdata_s_id;
end

endmodule
