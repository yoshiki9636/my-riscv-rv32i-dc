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
	#(parameter DWIDTH = 14)
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
    output dc_stall_fin2,
    output dc_stall_fin,
    output dc_st_ok,
	output dc_wb_mask,
	// DC controls
	output dc_tag_hit_ma,
	output dc_st_wt_ma,
	input dc_cache_wr_ma,
	input dc_cache_clr_bits,
	output dc_stall,
	// tiny AXI wirte bus i/f
	output dcw_start_rq,
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
	input finish_mrd,
	// DC flush
	input start_dcflush,
	output dcflush_running,
	// to IF
	output dc_wbback_state,
	// reset pipeline
	input rst_pipe

	);
//
// flush counter
reg [DWIDTH+1:4] dcflush_cntr;
reg dc_stall_dly;
reg [31:0] current_radr_keeper;
// tag ram
wire dc_sel_tag; //=((dc_miss_current != `DCMS_LDRD)&(dc_miss_current != `DCMS_IDLE)&(dc_miss_current != `DCMS_MEMW)) ;
reg [27:DWIDTH+2] dc_tag_adr_ma;
//wire [27:DWIDTH+2] dc_tag_adr_ex = dc_stall_dly ? current_radr_keeper[27:DWIDTH+2] : rd_data_ex[27:DWIDTH+2];
//wire [27:DWIDTH+2] dc_tag_adr_ex = dc_sel_tag ? current_radr_keeper[27:DWIDTH+2] : rd_data_ex[27:DWIDTH+2];
wire [27:DWIDTH+2] dc_tag_adr_ex = dc_sel_tag ? rd_data_ma[27:DWIDTH+2] : rd_data_ex[27:DWIDTH+2];
wire [DWIDTH+1:4] dc_index_adr = dcflush_running ? dcflush_cntr :
                                 dc_sel_tag ? rd_data_ma[DWIDTH+1:4] : rd_data_ex[DWIDTH+1:4];
                                 //dc_sel_tag ? current_radr_keeper[DWIDTH+1:4] : rd_data_ex[DWIDTH+1:4];
                                 //dc_stall_dly ? current_radr_keeper[DWIDTH+1:4] : rd_data_ex[DWIDTH+1:4];
wire [27:DWIDTH+2] dc_tag_wadr;
wire [DWIDTH+1:4] dc_index_wadr;
wire [27:DWIDTH+2] dc_tag_radr;
wire dc_cache_valid_ma;
wire tag_wen;

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
        dc_tag_adr_ma <= { (27-DWIDTH-1){ 1'b0 }} ;
	else if (rst_pipe)
        dc_tag_adr_ma <= { (27-DWIDTH-1){ 1'b0 }} ;
	//else if (~dc_stall | dc_stall_fin )
	//else if (~dc_stall & ~dc_stall_fin )
	else
		dc_tag_adr_ma <= dc_tag_adr_ex;
end


wire cmd_ldst_ma = (cmd_ld_ma | cmd_st_ma) & (rd_data_ma[31:30] != 2'b11) ;
wire dc_tag_equal = (dc_tag_adr_ma == dc_tag_radr);
assign dc_tag_hit_ma = dc_tag_equal & dc_cache_valid_ma & cmd_ldst_ma;
wire dc_tag_empty_ma = ~dc_cache_valid_ma & cmd_ldst_ma;
wire dc_tag_miss_ma = ~dc_tag_equal & dc_cache_valid_ma & cmd_ldst_ma;

// dirty / valid bits
reg [(2**(DWIDTH-2))-1:0] ent_dirty_bit_ma;
reg [(2**(DWIDTH-2))-1:0] ent_valid_bit_ma;

//wire [27:13] dc_cache_dirty_adr = rd_data_ma[12:4];
//wire [DWIDTH+1:4] dc_cache_dirty_adr = rd_data_ma[DWIDTH+1:4];
//wire [DWIDTH+1:4] dc_cache_dirty_adr = current_radr_keeper[DWIDTH+1:4];
reg [DWIDTH+1:4] dc_index_adr_dly;

//wire [DWIDTH+1:4] dc_cache_dirty_adr = dc_index_adr;
wire [DWIDTH+1:4] dc_cache_dirty_adr = dc_index_adr_dly;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ent_dirty_bit_ma <= { (2**(DWIDTH-2)){ 1'b0 }};
    else if (dc_cache_clr_bits | rst_pipe)
        ent_dirty_bit_ma <= { (2**(DWIDTH-2)){ 1'b0 }};
    else if (dc_cache_wr_ma)
        ent_dirty_bit_ma[dc_cache_dirty_adr] <= 1'b1;
    else if (tag_wen)
        ent_dirty_bit_ma[dc_index_wadr] <= 1'b0;
end

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ent_valid_bit_ma <= { (2**(DWIDTH-2)){ 1'b0 }};
    //else if (dc_cache_clr_bits | rst_pipe)
    else if (dc_cache_clr_bits | start_dcflush | rst_pipe)
        ent_valid_bit_ma <= { (2**(DWIDTH-2)){ 1'b0 }};
    else if (tag_wen)
        //ent_valid_bit_ma[dc_index_wadr] <= 1'b1;
        ent_valid_bit_ma[dc_index_adr_dly] <= 1'b1;
end

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dc_index_adr_dly <= { (DWIDTH-2){ 1'b0 }};
	else if (~dc_stall & ~dc_stall_fin )
        dc_index_adr_dly <= dc_index_adr;
end

//assign dc_cache_valid_ma = ent_valid_bit_ma[dc_cache_dirty_adr];
//wire dc_cache_dirty_ma = ent_dirty_bit_ma[dc_cache_dirty_adr] & dc_tag_miss_ma;
assign dc_cache_valid_ma = ent_valid_bit_ma[dc_index_adr_dly];
wire dc_cache_dirty_ma = ent_dirty_bit_ma[dc_index_adr_dly] & dc_tag_miss_ma;

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
input dc_tag_miss_ma;
input dc_cache_dirty_ma;
input dcw_finish_wresp;
input rdat_m_valid;
begin
    case(dc_miss_current)
		`DCMS_IDLE: begin
    		casex({dc_tag_empty_ma, dc_tag_miss_ma, dc_cache_dirty_ma})
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

wire [2:0] dc_miss_next = dc_miss_decode( dc_miss_current, dc_tag_empty_ma, dc_tag_miss_ma, dc_cache_dirty_ma, dcw_finish_wresp, rdat_m_valid );

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dc_miss_current <= `DCMS_IDLE;
	else if (rst_pipe)
        dc_miss_current <= `DCMS_IDLE;
    else
        dc_miss_current <= dc_miss_next;
end

// current read address keeper

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        current_radr_keeper <= 32'd0;
	else if (rst_pipe)
        current_radr_keeper <= 32'd0;
	else if ((dc_miss_current == `DCMS_IDLE) & (dc_tag_miss_ma | dc_tag_empty_ma))
		current_radr_keeper <= rd_data_ma;
end

// core stall singal
assign dc_stall = ((dc_miss_current != `DCMS_LDRD)&(dc_miss_current != `DCMS_IDLE)) | ((dc_tag_miss_ma | dc_tag_empty_ma)&(dc_miss_current != `DCMS_LDRD));
assign dc_sel_tag = ((dc_miss_current != `DCMS_LDRD)&(dc_miss_current != `DCMS_IDLE)) ;
assign dc_st_ok = ((dc_miss_current != `DCMS_MEMW)&(dc_miss_current != `DCMS_MEMR));

// store data write timing
assign dc_st_wt_ma = (dc_miss_current != `DCMS_DCWT);

// load issue timing
assign dc_stall_fin = (dc_miss_current == `DCMS_DCW3);
assign dc_stall_fin2 = (dc_miss_current == `DCMS_LDRD);
//assign dc_wb_mask = dc_stall_fin2 & cmd_ld_ma & (dc_tag_miss_ma | dc_tag_empty_ma);
assign dc_wb_mask = 1'b0;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dc_stall_dly <= 1'b0;
	else
        dc_stall_dly <= dc_stall;
end

// memory write bus i/f signals
reg dcw_start_rq_dc;
reg dcflush_wreq;
wire [31:0] dcw_in_addr_dcflush;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dcw_start_rq_dc <= 1'b0;
	else
        dcw_start_rq_dc <= ram_ren_all;
end
//wire dcw_start_rq_dc = ram_ren_all;

reg [31:0] dcw_in_addr_dly;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dcw_in_addr_dly <= 32'd0;
	else
        dcw_in_addr_dly <= { rd_data_ma[31:28], dc_tag_radr[27:DWIDTH+2],  rd_data_ma[DWIDTH+1:0] };
end

assign dcw_start_rq = dcw_start_rq_dc | dcflush_wreq;

assign dcw_in_mask = 16'd0;

//assign dcw_in_addr = dcflush_running ? dcw_in_addr_dcflush : { rd_data_ma[31:28], dc_tag_radr[27:DWIDTH+2],  rd_data_ma[DWIDTH+1:0] };
assign dcw_in_addr = dcflush_running ? dcw_in_addr_dcflush : dcw_in_addr_dly;

assign dcw_in_data = ram_rdata_all;

// memory read bus i/f signals

assign dcr_start_rq = ((dc_miss_current == `DCMS_MEMW)|(dc_miss_current == `DCMS_IDLE)) & (dc_miss_next == `DCMS_MEMR);
assign dcr_rin_addr = rd_data_ma;
assign rqfull_1 = 1'b0;

// to MA
//assign ram_wadr_all = current_radr_keeper[12:4];
assign ram_wdata_all = rdat_m_data;
assign ram_radr_all = dcflush_running ? dcflush_cntr : rd_data_ma[DWIDTH+1:4];
assign ram_wadr_all = current_radr_keeper[DWIDTH+1:4];
assign ram_wen_all = rdat_m_valid;
assign ram_ren_all = ((dc_miss_current == `DCMS_IDLE) & (dc_miss_next == `DCMS_MEMW)) | dcflush_running;

//tag write address
assign dc_tag_wadr = current_radr_keeper[27:DWIDTH+2];
assign dc_index_wadr = current_radr_keeper[DWIDTH+1:4];
assign tag_wen =  rdat_m_valid;

// DC flush
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        //dcflush_cntr <= 9'd0;
        dcflush_cntr <= { (DWIDTH-2){ 1'b0 }};
	else if ( start_dcflush )
        //dcflush_cntr <= {9{1'b1}};
        dcflush_cntr <= { (DWIDTH-2){ 1'b1 }};
	else if ((dcflush_cntr >  {(DWIDTH-2){ 1'b0 }}) & dcw_finish_wresp)
        dcflush_cntr <= dcflush_cntr -  {{ (DWIDTH-3){ 1'b0 }}, 1'b1};
end

reg [DWIDTH+1:4] dcflush_cntr_dly;
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        dcflush_cntr_dly <= { (DWIDTH-2){ 1'b0 }};
	else
        dcflush_cntr_dly <= dcflush_cntr;
end

wire dcflush_cntr_not0 = (dcflush_cntr != { (DWIDTH-2){ 1'b0 }});
reg dcflush_cntr_not0_dly;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
		dcflush_cntr_not0_dly <= 1'b0;
	else
		dcflush_cntr_not0_dly <= dcflush_cntr_not0;
end

assign dcflush_running = dcflush_cntr_not0 | dcflush_cntr_not0_dly;

wire dcflush_wreq_pre = dcflush_running & dcflush_cntr_not0_dly;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
		dcflush_wreq <= 1'b0;
	else
		dcflush_wreq <= dcflush_wreq_pre;
end

assign dcw_in_addr_dcflush = { 4'd0, dc_tag_radr[27:DWIDTH+2],  dcflush_cntr_dly, 4'd0 };

// dc wirte back state signal to IF stage to cancel ic_after_dc

assign dc_wbback_state = (dc_miss_current == `DCMS_MEMW) ;

endmodule
