/*
 * My RISC-V RV32I CPU
 * response channel subordinate
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module wresp_chan_subo (
	input clk,
	input rst_n,

	// bus signals
	output bvalid,
	input  bready,
	output reg [3:0] bid,
	output bcomp,
	// signals other side
	input reqc_s_valid,
	input [3:0] reqc_s_id,
	output finish_swd

	);

`define RESP_SIDLE 2'b00
`define RESP_SBOUT 2'b01
`define RESP_SDEFO 2'b11

// bcomp just fixed to 1 

assign bcomp = 1'b1;

// write data channel manager state machine
reg [1:0] resp_s_current;

function [1:0] resp_s_decode;
input [1:0] resp_s_current;
input finish_swd;
input bready;
begin
    case(resp_s_current)
		`RESP_SIDLE: begin
    		case(finish_swd)
				1'b1: resp_s_decode = `RESP_SBOUT;
				1'b0: resp_s_decode = `RESP_SIDLE;
				default: resp_s_decode = `RESP_SDEFO;
    		endcase
		end
		`RESP_SBOUT: begin
    		case(bready)
				1'b1: resp_s_decode = `RESP_SIDLE;
				1'b0: resp_s_decode = `RESP_SBOUT;
				default: resp_s_decode = `RESP_SDEFO;
    		endcase
		end
		`RESP_SDEFO: resp_s_decode = `RESP_SDEFO;
		default:     resp_s_decode = `RESP_SDEFO;
   	endcase
end
endfunction

wire [1:0] resp_s_next = resp_s_decode( resp_s_current, finish_swd, bready );

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        resp_s_current <= `RESP_SIDLE;
    else
        resp_s_current <= resp_s_next;
end

assign bvalid = (resp_s_current == `RESP_SBOUT);

// id latch
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        bid <= 4'd0;
    else if (reqc_s_valid)
        bid <= reqc_s_id;
end

endmodule
