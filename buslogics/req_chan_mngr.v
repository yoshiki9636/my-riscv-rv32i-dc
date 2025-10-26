/*
 * My RISC-V RV32I CPU
 *  request channel manager
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module req_chan_mngr
    #(parameter REQC_M_ID = 2'b00)
    (
	input clk,
	input rst_n,
	//bus controls
	output req_rq,
	input gnt_rq,
	// bus signals
	output a_valid,
	input  a_ready,
	output [3:0] a_id,
	output [31:0] a_addr,
	output [5:0] a_atop,
	// signals other side
	input start_rq,
	input [31:0] in_addr,
	input [15:0] in_mask,
	input [127:0] in_data,
	output next_rq,
	output [3:0] next_id,
	output [15:0] next_mask,
	output [127:0] next_data,
	input ren_id_data

	);

`define REQC_MIDLE 2'b00
`define REQC_MAREQ 2'b01
`define REQC_MBOUT 2'b10
`define REQC_MDEFO 2'b11

// fixed signal : for supporting in the future

assign a_atop = 6'b000000; // non-atomic

// Request channel manager state machine
reg [1:0] reqc_m_current;
wire inner_start;

function [1:0] reqc_m_decode;
input [1:0] reqc_m_current;
input inner_start;
input gnt_rq;
input a_ready;
begin
    case(reqc_m_current)
		`REQC_MIDLE: begin
    		case(inner_start)
				1'b1: reqc_m_decode = `REQC_MAREQ;
				1'b0: reqc_m_decode = `REQC_MIDLE;
				default: reqc_m_decode = `REQC_MDEFO;
    		endcase
		end
		`REQC_MAREQ: begin
    		case(gnt_rq)
				1'b1: reqc_m_decode = `REQC_MBOUT;
				1'b0: reqc_m_decode = `REQC_MAREQ;
				default: reqc_m_decode = `REQC_MDEFO;
    		endcase
		end
		`REQC_MBOUT: begin
    		case(a_ready)
				1'b0: reqc_m_decode = `REQC_MBOUT;
				1'b1: reqc_m_decode = `REQC_MIDLE;
				default: reqc_m_decode = `REQC_MDEFO;
    		endcase
		end
		`REQC_MDEFO: reqc_m_decode = `REQC_MDEFO;
		default:     reqc_m_decode = `REQC_MDEFO;
   	endcase
end
endfunction

wire [1:0] reqc_m_next = reqc_m_decode( reqc_m_current, inner_start, gnt_rq, a_ready );

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        reqc_m_current <= `REQC_MIDLE;
    else
        reqc_m_current <= reqc_m_next;
end

assign req_rq = (reqc_m_current == `REQC_MAREQ);
assign a_valid = (reqc_m_current == `REQC_MBOUT);
assign next_rq = a_valid & a_ready;

// id maker
reg [1:0] id_cntr;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        id_cntr <= 2'd0;
    else if (start_rq)
        id_cntr <= id_cntr + 2'd1;
end


// address data queue

wire [145:0] in_id_data = { id_cntr, in_mask, in_data };
wire [145:0] out_id_data;
wire empty_rq;
wire qfull_rq_dmy;
wire qfull_rq_dmy2;
wire empty_rq_dmy;
wire [31:0] out_addr;

sfifo
    #(.SFIFODW(32),
      .SFIFOAW(2),
      .SFIFODP(4)
    ) request_addr (
    .clk(clk),
    .rst_n(rst_n),
    .wen(start_rq),
    .wqfull(qfull_rq_dmy),
    .wdata(in_addr),
    .rnext(next_rq),
    .rqempty(empty_rq),
    .rdata(out_addr)
    );

assign inner_start = ~empty_rq;

sfifo
    #(.SFIFODW(146),
      .SFIFOAW(2),
      .SFIFODP(4)
    ) request_id_wdata (
    .clk(clk),
    .rst_n(rst_n),
    .wen(start_rq),
    .wqfull(qfull_rq_dmy2),
    .wdata(in_id_data),
    .rnext(ren_id_data),
    .rqempty(empty_rq_dmy),
    .rdata(out_id_data)
    );

assign a_addr = out_addr;
assign a_id = { REQC_M_ID, out_id_data[145:144] };
assign next_mask = out_id_data[143:128];
assign next_data = out_id_data[127:0];
assign next_id = a_id;

endmodule
