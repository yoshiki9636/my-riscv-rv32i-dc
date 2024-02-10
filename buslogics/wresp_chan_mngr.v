/*
 * My RISC-V RV32I CPU
 *  response channel manager
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module wresp_chan_mngr (
	input clk,
	input rst_n,

	// bus signals
	input bvalid,
	output  bready,
	input [3:0] bid,
	input bcomp,
	// signals other side
	input finish_wd,
	input [3:0] finish_id,
	output finish_wresp

	);

`define RESP_MIDLE 2'b00
`define RESP_MBINP 2'b01
`define RESP_MDEFO 2'b11

// write data channel manager state machine
reg [1:0] resp_m_current;
wire check_ok;

function [1:0] resp_m_decode;
input [1:0] resp_m_current;
input finish_wd;
input bvalid;
input check_ok;
begin
    case(resp_m_current)
		`RESP_MIDLE: begin
    		case(finish_wd)
				1'b1: resp_m_decode = `RESP_MBINP;
				1'b0: resp_m_decode = `RESP_MIDLE;
				default: resp_m_decode = `RESP_MDEFO;
    		endcase
		end
		`RESP_MBINP: begin
    		casex({bvalid, check_ok, finish_wd})
				3'b0xx: resp_m_decode = `RESP_MBINP;
				3'b10x: resp_m_decode = `RESP_MDEFO;
				3'b110: resp_m_decode = `RESP_MIDLE;
				3'b111: resp_m_decode = `RESP_MBINP;
				default: resp_m_decode = `RESP_MDEFO;
    		endcase
		end
		`RESP_MDEFO: resp_m_decode = `RESP_MDEFO;
		default:     resp_m_decode = `RESP_MDEFO;
   	endcase
end
endfunction

wire [1:0] resp_m_next = resp_m_decode( resp_m_current, finish_wd, bvalid, check_ok );

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        resp_m_current <= `RESP_MIDLE;
    else
        resp_m_current <= resp_m_next;
end

// controls
assign bready = (resp_m_current == `RESP_MBINP);

// check ok
reg [3:0] finish_id_lat;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        finish_id_lat <= 3'd0;
    else if ( finish_wd )
        finish_id_lat <= finish_id;
end

assign check_ok = bready & bcomp & (bid == finish_id_lat);

assign finish_wresp = check_ok & bvalid;

endmodule
