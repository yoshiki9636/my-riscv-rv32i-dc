/*
 * My RISC-V RV32I CPU
 *   arbiter for tiny axi bus
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2026 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module arbitor4 (
	input clk,
	input rst_n,

	input req0,
	input req1,
	input req2,
	input req3,

	output gnt0,
	output gnt1,
	output gnt2,
	output gnt3,

	output [3:0] sel,
	input finish0,
	input finish1,
	input finish2,
	input finish3

	);

`define ARB4_IDL0123 4'b0000
`define ARB4_SEL0123 4'b0100
`define ARB4_IDL1230 4'b0001
`define ARB4_SEL1230 4'b0101
`define ARB4_IDL2301 4'b0010
`define ARB4_SEL2301 4'b0110
`define ARB4_IDL3012 4'b1000
`define ARB4_SEL3012 4'b1100
//`define ARB4_SELDEF  4'b1111

// make finish signal
//
// FPGA (2026-08-27): root-cause fix for the grant-race bug documented in
// project memory (project_arbiter4_finish_broadcast_bug). The blind OR below
// let ANY master's finish (fully async, decoupled from address-phase grant
// status) revoke a currently-granted-but-still-waiting master's grant before
// its own a_ready/w_ready ever arrived. The 2026-08-09 fix gated the
// downstream a_ready/ar_ready broadcast by sel_wt/sel_rd in axi_bus_top.v,
// which stops the revoked master from silently mistaking someone else's
// ready pulse for its own (the data-corruption symptom) - but did not stop
// the revocation itself, so a master can still be starved indefinitely if
// another master's finish keeps firing before it ever gets serviced (a
// hang, not corruption). Qualifying finish by which master arbit4_current
// actually holds closes this at the root: an unrelated master's finish can
// no longer interrupt a live grant at all.
wire cur_sel0 = (arbit4_current == `ARB4_SEL0123);
wire cur_sel1 = (arbit4_current == `ARB4_SEL1230);
wire cur_sel2 = (arbit4_current == `ARB4_SEL2301);
wire cur_sel3 = (arbit4_current == `ARB4_SEL3012);

wire finish = (finish0 & cur_sel0) | (finish1 & cur_sel1) | (finish2 & cur_sel2) | (finish3 & cur_sel3);

// round robin state machine
reg [3:0] arbit4_current;

function [3:0] arbit4_decode;
input [3:0] arbit4_current;
input req0;
input req1;
input req2;
input req3;
input finish;
begin
    case(arbit4_current)
		`ARB4_IDL0123: begin
    		casez({req0,req1,req2,req3})
				4'b1???: arbit4_decode = `ARB4_SEL0123;
				4'b01??: arbit4_decode = `ARB4_SEL1230;
				4'b001?: arbit4_decode = `ARB4_SEL2301;
				4'b0001: arbit4_decode = `ARB4_SEL3012;
				4'b0000: arbit4_decode = `ARB4_IDL0123;
				default: arbit4_decode = `ARB4_IDL0123;
    		endcase
		end
		`ARB4_SEL0123: begin
    		casez({finish,req1,req2,req3,req0})
				5'b0????: arbit4_decode = `ARB4_SEL0123;
				5'b11???: arbit4_decode = `ARB4_SEL1230;
				5'b101??: arbit4_decode = `ARB4_SEL2301;
				5'b1001?: arbit4_decode = `ARB4_SEL3012;
				5'b10001: arbit4_decode = `ARB4_SEL0123;
				5'b10000: arbit4_decode = `ARB4_IDL1230;
				default: arbit4_decode = `ARB4_IDL0123;
    		endcase
		end
		`ARB4_IDL1230: begin
    		casez({req1,req2,req3,req0})
				4'b1???: arbit4_decode = `ARB4_SEL1230;
				4'b01??: arbit4_decode = `ARB4_SEL2301;
				4'b001?: arbit4_decode = `ARB4_SEL3012;
				4'b0001: arbit4_decode = `ARB4_SEL0123;
				4'b0000: arbit4_decode = `ARB4_IDL1230;
				default: arbit4_decode = `ARB4_IDL0123;
    		endcase
		end
		`ARB4_SEL1230: begin
    		casez({finish,req2,req3,req0,req1})
				5'b0????: arbit4_decode = `ARB4_SEL1230;
				5'b11???: arbit4_decode = `ARB4_SEL2301;
				5'b101??: arbit4_decode = `ARB4_SEL3012;
				5'b1001?: arbit4_decode = `ARB4_SEL0123;
				5'b10001: arbit4_decode = `ARB4_SEL1230;
				5'b10000: arbit4_decode = `ARB4_IDL2301;
				default: arbit4_decode = `ARB4_IDL0123;
    		endcase
		end
		`ARB4_IDL2301: begin
    		casez({req2,req3,req0,req1})
				4'b1???: arbit4_decode = `ARB4_SEL2301;
				4'b01??: arbit4_decode = `ARB4_SEL3012;
				4'b001?: arbit4_decode = `ARB4_SEL0123;
				4'b0001: arbit4_decode = `ARB4_SEL1230;
				4'b0000: arbit4_decode = `ARB4_IDL2301;
				default: arbit4_decode = `ARB4_IDL0123;
    		endcase
		end
		`ARB4_SEL2301: begin
    		casez({finish,req3,req0,req1,req2})
				5'b0????: arbit4_decode = `ARB4_SEL2301;
				5'b11???: arbit4_decode = `ARB4_SEL3012;
				5'b101??: arbit4_decode = `ARB4_SEL0123;
				5'b1001?: arbit4_decode = `ARB4_SEL1230;
				5'b10001: arbit4_decode = `ARB4_SEL2301;
				5'b10000: arbit4_decode = `ARB4_IDL3012;
				default: arbit4_decode = `ARB4_IDL0123;
    		endcase
		end
		`ARB4_IDL3012: begin
    		casez({req3,req0,req1,req2})
				4'b1???: arbit4_decode = `ARB4_SEL3012;
				4'b01??: arbit4_decode = `ARB4_SEL0123;
				4'b001?: arbit4_decode = `ARB4_SEL1230;
				4'b0001: arbit4_decode = `ARB4_SEL2301;
				4'b0000: arbit4_decode = `ARB4_IDL3012;
				default: arbit4_decode = `ARB4_IDL0123;
    		endcase
		end
		`ARB4_SEL3012: begin
    		casez({finish,req0,req1,req2,req3})
				5'b0????: arbit4_decode = `ARB4_SEL3012;
				5'b11???: arbit4_decode = `ARB4_SEL0123;
				5'b101??: arbit4_decode = `ARB4_SEL1230;
				5'b1001?: arbit4_decode = `ARB4_SEL2301;
				5'b10001: arbit4_decode = `ARB4_SEL3012;
				5'b10000: arbit4_decode = `ARB4_IDL0123;
				default: arbit4_decode = `ARB4_IDL0123;
    		endcase
		end
		default:      arbit4_decode = `ARB4_IDL0123;
   	endcase
end
endfunction

wire [3:0] arbit4_next = arbit4_decode( arbit4_current, req0, req1, req2, req3, finish );

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        arbit4_current <= `ARB4_IDL0123;
    else
        arbit4_current <= arbit4_next;
end


wire sel0_pre = (arbit4_next == `ARB4_SEL0123);
wire sel1_pre = (arbit4_next == `ARB4_SEL1230);
wire sel2_pre = (arbit4_next == `ARB4_SEL2301);
wire sel3_pre = (arbit4_next == `ARB4_SEL3012);

reg sel0_post;
reg sel1_post;
reg sel2_post;
reg sel3_post;
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        sel0_post <= 1'b0;
        sel1_post <= 1'b0;
        sel2_post <= 1'b0;
        sel3_post <= 1'b0;
	end
    else begin
        sel0_post <= sel0_pre;
        sel1_post <= sel1_pre;
        sel2_post <= sel2_pre;
        sel3_post <= sel3_pre;
	end
end

assign gnt0 = (~arbit4_current[2]|finish)&(arbit4_next == `ARB4_SEL0123);
assign gnt1 = (~arbit4_current[2]|finish)&(arbit4_next == `ARB4_SEL1230);
assign gnt2 = (~arbit4_current[2]|finish)&(arbit4_next == `ARB4_SEL2301);
assign gnt3 = (~arbit4_current[2]|finish)&(arbit4_next == `ARB4_SEL3012);

assign sel = { sel3_post, sel2_post, sel1_post, sel0_post };

endmodule
