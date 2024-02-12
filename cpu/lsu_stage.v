/*
 * My RISC-V RV32I CPU
 *   FPGA LED output Module for Tang Premier
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module lsu_stage
	#(parameter DWIDTH = 11)
	(
	input clk,
	input rst_n,

	input [31:0] rd_data_ex,
	input [31:0] rd_data_ma,
	input cmd_ld_ma,
	input cmd_st_ma,
	input jmp_purge_ma,

    // to MA
    output [DWIDTH-3:0] ram_radr_all,
    input [127:0] ram_rdata_all,
    output ram_ren_all,
    output [DWIDTH-3:0] ram_wadr_all,
    output [127:0] ram_wdata_all,
    output ram_wen_all,
    output dc_ld_issue_ma,
	// DC controls
	output dc_tag_hit_ma,
	output dc_st_wt_ma,
	input dc_cache_wr_ma,
	input dc_cache_clr_bits,
	output dc_stall,
	// tiny AXI wirte bus i/f
	output reg dcw_start_rq,
	output [31:0] dcw_in_addr,
	output [15:0] dcw_in_mask,
	output [127:0] dcw_in_data,
	input dcw_finish_wresp,
	// tiny AXI read bus i/f
	output dcr_start_rq,
	output [31:0] dcr_rin_addr,
	output rqfull_1,
	input [127:0] rdat_m_data,
	input rdat_m_valid,
	input finish_mrd

	);

// tag ram
reg [27:13] dc_tag_adr_ma;
wire [27:13] dc_tag_adr_ex = rd_data_ex[27:13];
wire [12:4] dc_index_adr = rd_data_ex[12:4];
wire [27:13] dc_tag_wadr;
wire [12:4] dc_index_wadr;
wire [27:13] dc_tag_radr;
wire dc_cache_valid_ma;

tag_1r1w #(.DRWIDTH(DWIDTH-2)) tag_1r1w (
	.clk(clk),
	.ram_radr(dc_index_adr),
	.ram_rdata(dc_tag_radr),
	.ram_wadr(dc_index_wadr),
	.ram_wdata(dc_tag_wadr),
	.ram_wen(tag_wen)
	);

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dc_tag_adr_ma <= 15'd0 ;
	else
		dc_tag_adr_ma <= dc_tag_adr_ex;
end

wire cmd_ldst_ma = (cmd_ld_ma | cmd_st_ma) & (rd_data_ma[31:30] != 2'b11) ;
wire dc_tag_equal = (dc_tag_adr_ma == dc_tag_radr);
assign dc_tag_hit_ma = dc_tag_equal & dc_cache_valid_ma & cmd_ldst_ma;
wire dc_tag_empty_ma = ~dc_cache_valid_ma & cmd_ldst_ma;
wire dc_tag_misshit_ma = ~dc_tag_equal & dc_cache_valid_ma & cmd_ldst_ma;

// dirty / valid bits
reg [(2**(DWIDTH-2))-1:0] ent_dirty_bit_ma;
reg [(2**(DWIDTH-2))-1:0] ent_valid_bit_ma;

wire [27:13] dc_cache_dirty_adr = rd_data_ma[12:4];

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ent_dirty_bit_ma <= { (2**(DWIDTH-2)){ 1'b0 }};
    else if (dc_cache_clr_bits)
        ent_dirty_bit_ma <= { (2**(DWIDTH-2)){ 1'b0 }};
    else if (dc_cache_wr_ma)
        ent_dirty_bit_ma[dc_cache_dirty_adr] <= 1'b1;
    else if (tag_wen)
        ent_dirty_bit_ma[dc_index_wadr] <= 1'b0;
end

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ent_valid_bit_ma <= { (2**(DWIDTH-2)){ 1'b0 }};
    else if (dc_cache_clr_bits)
        ent_valid_bit_ma <= { (2**(DWIDTH-2)){ 1'b0 }};
    else if (tag_wen)
        ent_valid_bit_ma[dc_index_wadr] <= 1'b1;
end

assign dc_cache_valid_ma = ent_valid_bit_ma[dc_cache_dirty_adr];
wire dc_cache_dirty_ma = ent_dirty_bit_ma[dc_cache_dirty_adr] & dc_tag_misshit_ma;

// dc state machine

`define DCMS_IDLE 3'b000
`define DCMS_MEMW 3'b001
`define DCMS_MEMR 3'b010
`define DCMS_DCWT 3'b011
`define DCMS_DCW2 3'b100
`define DCMS_DCW3 3'b101
`define DCMS_LDRD 3'b110
`define DCMS_DEFO 3'b111

// Request channel manager state machine
reg [2:0] dc_miss_current;

function [2:0] dc_miss_decode;
input [2:0] dc_miss_current;
input dc_tag_empty_ma;
input dc_tag_misshit_ma;
input dc_cache_dirty_ma;
input dcw_finish_wresp;
input rdat_m_valid;
begin
    case(dc_miss_current)
		`DCMS_IDLE: begin
    		casex({dc_tag_empty_ma, dc_tag_misshit_ma, dc_cache_dirty_ma})
				3'b1xx: dc_miss_decode = `DCMS_MEMR;
				3'b00x: dc_miss_decode = `DCMS_IDLE;
				3'b011: dc_miss_decode = `DCMS_MEMW;
				3'b010: dc_miss_decode = `DCMS_MEMR;
				default: dc_miss_decode = `DCMS_DEFO;
    		endcase
		end
		`DCMS_MEMW: begin
    		case(dcw_finish_wresp)
				1'b1: dc_miss_decode = `DCMS_MEMR;
				1'b0: dc_miss_decode = `DCMS_MEMW;
				default: dc_miss_decode = `DCMS_DEFO;
    		endcase
		end
		`DCMS_MEMR: begin
    		case(rdat_m_valid)
				1'b1: dc_miss_decode = `DCMS_DCWT;
				1'b0: dc_miss_decode = `DCMS_MEMR;
				default: dc_miss_decode = `DCMS_DEFO;
    		endcase
		end
		`DCMS_DCWT: dc_miss_decode = `DCMS_DCW2;
		`DCMS_DCW2: dc_miss_decode = `DCMS_DCW3;
		`DCMS_DCW3: dc_miss_decode = `DCMS_LDRD;
		`DCMS_LDRD: dc_miss_decode = `DCMS_IDLE;
		`DCMS_DEFO: dc_miss_decode = `DCMS_DEFO;
		default:     dc_miss_decode = `DCMS_DEFO;
   	endcase
end
endfunction

wire [2:0] dc_miss_next = dc_miss_decode( dc_miss_current, dc_tag_empty_ma, dc_tag_misshit_ma, dc_cache_dirty_ma, dcw_finish_wresp, rdat_m_valid );

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dc_miss_current <= `DCMS_IDLE;
    else
        dc_miss_current <= dc_miss_next;
end

// current read address keeper
reg [31:0] current_radr_keeper;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        current_radr_keeper <= 32'd0;
	else if ((dc_miss_current == `DCMS_IDLE) & (dc_tag_misshit_ma | dc_tag_empty_ma))
		current_radr_keeper <= rd_data_ma;
end

// core stall singal
assign dc_stall = (dc_miss_current != `DCMS_IDLE) | (dc_tag_misshit_ma | dc_tag_empty_ma);

// store data write timing
assign dc_st_wt_ma = (dc_miss_current != `DCMS_DCWT);

// load issue timing
assign dc_ld_issue_ma = (dc_miss_current == `DCMS_LDRD);

// memory write bus i/f signals
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dcw_start_rq <= 1'b0;
	else
        dcw_start_rq <= ram_ren_all;
end

assign dcw_in_mask = 16'd0;

assign dcw_in_addr = { rd_data_ma[31:28], dc_tag_radr[27:13],  rd_data_ma[12:0] };

assign dcw_in_data = ram_rdata_all;

// memory read bus i/f signals

assign dcr_start_rq = ((dc_miss_current == `DCMS_MEMW)|(dc_miss_current == `DCMS_IDLE)) & (dc_miss_next == `DCMS_MEMR);
assign dcr_rin_addr = rd_data_ma;
assign rqfull_1 = 1'b0;

// to MA
assign ram_wadr_all = current_radr_keeper[12:4];
assign ram_wdata_all = rdat_m_data;
//assign ram_radr_all = current_radr_keeper[12:4];
assign ram_radr_all = rd_data_ma[12:4];
assign ram_wadr_all = current_radr_keeper[12:4];
assign ram_wen_all = rdat_m_valid;
assign ram_ren_all = (dc_miss_current == `DCMS_IDLE) & (dc_miss_next == `DCMS_MEMW);

//tag write address
assign dc_tag_wadr = current_radr_keeper[27:13];
assign dc_index_wadr = current_radr_keeper[12:4];
assign tag_wen =  rdat_m_valid;


endmodule
