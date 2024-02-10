/*
 * My RISC-V RV32I CPU
 *   dummy mig memory module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module dummy_mig (
	// mig ingerface
	input mclk, // not used
	input mrst_n, // not used
	// address/command
	input [27:0] app_addr,
	input [2:0] app_cmd,
	input app_en,
	output app_rdy,
	// write data
	input [127:0] app_wdf_data,
	input [15:0] app_wdf_mask,
	input app_wdf_wren,
	input app_wdf_end,
	output app_wdf_rdy,
	// read data
	output [127:0] app_rd_data,
	output app_rd_data_end,
	output app_rd_data_valid

	);

`define DMIG_IDLE 2'b00
`define DMIG_WWIT 2'b01
`define DMIG_RWIT 2'b10
`define DMIG_DEFO 2'b10
`define READ_LATENCY 4'd15

// mask is not used
// signal / sampler
wire read_flg = app_cmd[0];
wire read_end;

reg [9:0] rwadr;

always @ (posedge mclk or negedge mrst_n) begin
    if (~mrst_n)
        rwadr <= 10'd0;
    else if ( app_en & app_rdy )
        rwadr <=  app_addr[13:4];
end

// write data channel manager state machine
reg [1:0] dmig_current;

function [1:0] dmig_decode;
input [1:0] dmig_current;
input app_en;
input read_flg;
input app_wdf_wren;
input read_end;
begin
    case(dmig_current)
        `DMIG_IDLE: begin
            casez({app_en, read_flg})
                2'b0?: dmig_decode = `DMIG_IDLE;
                2'b10: dmig_decode = `DMIG_WWIT;
                2'b11: dmig_decode = `DMIG_RWIT;
                default: dmig_decode = `DMIG_DEFO;
            endcase
        end
        `DMIG_WWIT: begin
            case(app_wdf_wren)
                1'b0: dmig_decode = `DMIG_WWIT;
                1'b1: dmig_decode = `DMIG_IDLE;
                default: dmig_decode = `DMIG_DEFO;
            endcase
        end
        `DMIG_RWIT: begin
            case(read_end)
                1'b0: dmig_decode = `DMIG_RWIT;
                1'b1: dmig_decode = `DMIG_IDLE;
                default: dmig_decode = `DMIG_DEFO;
            endcase
        end

        `DMIG_DEFO: dmig_decode = `DMIG_DEFO;
        default:     dmig_decode = `DMIG_DEFO;
    endcase
end
endfunction

wire [1:0] dmig_next = dmig_decode( dmig_current, app_en, read_flg, app_wdf_wren, read_end );

always @ (posedge mclk or negedge mrst_n) begin
    if (~mrst_n)
        dmig_current <= `DMIG_IDLE;
    else
        dmig_current <= dmig_next;
end

// controls

wire rstart = (dmig_current == `DMIG_IDLE)&(dmig_next == `DMIG_RWIT);

// burst counter just spport 4
reg [3:0] burst_cntr;

always @ (posedge mclk or negedge mrst_n) begin
    if (~mrst_n)
        burst_cntr <= 4'd0;
    else if (rstart)
        burst_cntr <= `READ_LATENCY;
    else if (burst_cntr > 4'd0)
        burst_cntr <= burst_cntr - 4'd1;
end

assign read_end = (burst_cntr == 4'd1);

// interface out signals

assign app_rdy = (dmig_current == `DMIG_IDLE);
assign app_wdf_rdy = (dmig_current == `DMIG_WWIT);
assign app_rd_data_end = read_end;
assign app_rd_data_valid = read_end;

// dummy memory : 128bit x 1024 word
sfifo_1r1w
    #(.SFIFODW(128),
      .SFIFOAW(10),
      .SFIFODP(1024)
    ) sfifo_1r1w (
    .clk(mclk),
    .ram_radr(rwadr),
    .ram_rdata(app_rd_data),
    .ram_wadr(rwadr),
    .ram_wdata(app_wdf_data),
    .ram_wen(app_wdf_wren)
    );

endmodule
