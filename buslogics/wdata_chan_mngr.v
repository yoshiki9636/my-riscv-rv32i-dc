/*
 * My RISC-V RV32I CPU
 *  write data channel manager
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module wdata_chan_mngr (
	input clk,
	input rst_n,

	// bus signals
	output wvalid,
	input  wready,
	output [31:0] wdata,
	output [3:0] wstrb,
	output wlast,
	// signals other side
	input next_rq,
	input [3:0] next_id,
	input [127:0] next_wdata,
	input [15:0] next_mask,
	output finish_wd,
	output [3:0] finish_id
	//output reg [3:0] finish_id

	);

`define WDAT_MIDLE 2'b00
`define WDAT_MBOUT 2'b01
`define WDAT_MBFIN 2'b10
`define WDAT_MDEFO 2'b11

// write data channel manager state machine
reg [1:0] wdat_m_current;
wire wcntr_2;

function [1:0] wdat_m_decode;
input [1:0] wdat_m_current;
input next_rq;
input wready;
input wcntr_2;
begin
    case(wdat_m_current)
		`WDAT_MIDLE: begin
    		case(next_rq)
				1'b1: wdat_m_decode = `WDAT_MBOUT;
				1'b0: wdat_m_decode = `WDAT_MIDLE;
				default: wdat_m_decode = `WDAT_MDEFO;
    		endcase
		end
		`WDAT_MBOUT: begin
    		casex({wready, wcntr_2})
				2'b0x: wdat_m_decode = `WDAT_MBOUT;
				2'b10: wdat_m_decode = `WDAT_MBOUT;
				2'b11: wdat_m_decode = `WDAT_MBFIN;
				default: wdat_m_decode = `WDAT_MDEFO;
    		endcase
		end
		`WDAT_MBFIN: begin
    		casex({wready,next_rq})
				2'b0x: wdat_m_decode = `WDAT_MBFIN;
				2'b10: wdat_m_decode = `WDAT_MIDLE;
				2'b11: wdat_m_decode = `WDAT_MBOUT;
				default: wdat_m_decode = `WDAT_MDEFO;
    		endcase
		end
		`WDAT_MDEFO: wdat_m_decode = `WDAT_MDEFO;
		default:     wdat_m_decode = `WDAT_MDEFO;
   	endcase
end
endfunction

wire [1:0] wdat_m_next = wdat_m_decode( wdat_m_current, next_rq, wready, wcntr_2 );

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        wdat_m_current <= `WDAT_MIDLE;
    else
        wdat_m_current <= wdat_m_next;
end

assign wvalid = (wdat_m_current == `WDAT_MBOUT)|(wdat_m_current == `WDAT_MBFIN);
assign wlast = (wdat_m_current == `WDAT_MBFIN);
assign finish_wd = wlast & wready;

// burst counter just spport 4
reg [1:0] burst_cntr;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        burst_cntr <= 2'd0;
    else if (next_rq)
        burst_cntr <= 2'd3;
    else if ((burst_cntr > 2'd0)&wready)
        burst_cntr <= burst_cntr - 2'd1;
end

assign wcntr_2 = (burst_cntr == 2'd1);

// wdata selecter

assign  wdata = (burst_cntr == 2'd3) ? next_wdata[31:0] :
                (burst_cntr == 2'd2) ? next_wdata[63:32] :
                (burst_cntr == 2'd1) ? next_wdata[95:64] : next_wdata[127:96];

assign  wstrb = (burst_cntr == 2'd3) ? ~next_mask[3:0] :
                (burst_cntr == 2'd2) ? ~next_mask[7:4] :
                (burst_cntr == 2'd1) ? ~next_mask[11:8] : ~next_mask[15:12];

// id address keeper

assign finish_id = next_id;

//always @ (posedge clk or negedge rst_n) begin
    //if (~rst_n)
       //finish_id  <= 4'd0;
    //else if (finish_wd)
       //finish_id  <= next_id;
//end

endmodule
