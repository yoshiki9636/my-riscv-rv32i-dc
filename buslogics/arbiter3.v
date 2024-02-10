/*
 * My RISC-V RV32I CPU
 *   arbiter for tiny axi bus
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module arbitor3 (
	input clk,
	input rst_n,

	input req0,
	input req1,
	input req2,

	output gnt0,
	output gnt1,
	output gnt2,

	output [2:0] sel,
	input finish0,
	input finish1,
	input finish2

	);

`define ARB3_IDL012 3'b000
`define ARB3_SEL012 3'b100
`define ARB3_IDL120 3'b001
`define ARB3_SEL120 3'b101
`define ARB3_IDL201 3'b010
`define ARB3_SEL201 3'b110
`define ARB3_SELDEF 3'b111

// make finish signal

wire finish = finish0 | finish1 | finish2;

// round robin state machine
reg [2:0] arbit3_current;

function [10:0] arbit3_decode;
input [2:0] arbit3_current;
input req0;
input req1;
input req2;
input finish;
begin
    case(arbit3_current)
		`ARB3_IDL012: begin
    		casez({req0,req1,req2})
				3'b1??: arbit3_decode = `ARB3_SEL012;
				3'b01?: arbit3_decode = `ARB3_SEL120;
				3'b001: arbit3_decode = `ARB3_SEL201;
				3'b000: arbit3_decode = `ARB3_IDL012;
				default: arbit3_decode = `ARB3_SELDEF;
    		endcase
		end
		`ARB3_SEL012: begin
    		casez({finish,req1,req2,req0})
				4'b0???: arbit3_decode = `ARB3_SEL012;
				4'b11??: arbit3_decode = `ARB3_SEL120;
				4'b101?: arbit3_decode = `ARB3_SEL201;
				4'b1001: arbit3_decode = `ARB3_SEL012;
				4'b1000: arbit3_decode = `ARB3_IDL120;
				default: arbit3_decode = `ARB3_SELDEF;
    		endcase
		end
		`ARB3_IDL120: begin
    		casez({req1,req2,req0})
				3'b1??: arbit3_decode = `ARB3_SEL120;
				3'b01?: arbit3_decode = `ARB3_SEL201;
				3'b001: arbit3_decode = `ARB3_SEL012;
				3'b000: arbit3_decode = `ARB3_IDL120;
				default: arbit3_decode = `ARB3_SELDEF;
    		endcase
		end
		`ARB3_SEL120: begin
    		casez({finish,req2,req0,req1})
				4'b0???: arbit3_decode = `ARB3_SEL120;
				4'b11??: arbit3_decode = `ARB3_SEL201;
				4'b101?: arbit3_decode = `ARB3_SEL012;
				4'b1001: arbit3_decode = `ARB3_SEL120;
				4'b1000: arbit3_decode = `ARB3_IDL201;
				default: arbit3_decode = `ARB3_SELDEF;
    		endcase
		end
		`ARB3_IDL201: begin
    		casez({req2,req0,req1})
				3'b1??: arbit3_decode = `ARB3_SEL201;
				3'b01?: arbit3_decode = `ARB3_SEL012;
				3'b001: arbit3_decode = `ARB3_SEL120;
				3'b000: arbit3_decode = `ARB3_IDL201;
				default: arbit3_decode = `ARB3_SELDEF;
    		endcase
		end
		`ARB3_SEL201: begin
    		casez({finish,req0,req1,req2})
				4'b0???: arbit3_decode = `ARB3_SEL201;
				4'b11??: arbit3_decode = `ARB3_SEL012;
				4'b101?: arbit3_decode = `ARB3_SEL120;
				4'b1001: arbit3_decode = `ARB3_SEL201;
				4'b1000: arbit3_decode = `ARB3_IDL012;
				default: arbit3_decode = `ARB3_SELDEF;
    		endcase
		end
		`ARB3_SELDEF: arbit3_decode = `ARB3_SELDEF;
		default:      arbit3_decode = `ARB3_SELDEF;
   	endcase
end
endfunction

wire [2:0] arbit3_next = arbit3_decode( arbit3_current, req0, req1, req2, finish );

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        arbit3_current <= `ARB3_IDL012;
    else
        arbit3_current <= arbit3_next;
end


wire sel0_pre = (arbit3_next == `ARB3_SEL012);
wire sel1_pre = (arbit3_next == `ARB3_SEL120);
wire sel2_pre = (arbit3_next == `ARB3_SEL201);

reg sel0_post;
reg sel1_post;
reg sel2_post;
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        sel0_post <= 1'b0;
        sel1_post <= 1'b0;
        sel2_post <= 1'b0;
	end
    else begin
        sel0_post <= sel0_pre;
        sel1_post <= sel1_pre;
        sel2_post <= sel2_pre;
	end
end

assign gnt0 = (~arbit3_current[2]|finish)&(arbit3_next == `ARB3_SEL012);
assign gnt1 = (~arbit3_current[2]|finish)&(arbit3_next == `ARB3_SEL120);
assign gnt2 = (~arbit3_current[2]|finish)&(arbit3_next == `ARB3_SEL201);

assign sel = { sel2_post, sel1_post, sel0_post };

endmodule
