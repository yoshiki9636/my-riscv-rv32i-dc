/*
 * My RISC-V RV32I CPU
 *   FPGA LED output Module for Tang Premier
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module ilu_stage
	#(parameter IWIDTH = 14)
	(
	input clk,
	input rst_n,

	// FORM TO IF
	input [31:2] pc_if,
	input [31:2] pc_id_pre,
	input pc_valid_id,
    output [IWIDTH-3:0] ic_ram_wadr_all,
    //output [127:0] ic_ram_wdata_all,
    //output ic_ram_wen_all,
    output ic_stall_fin2,
    output ic_stall_fin,
	output ic_stall,
	output reg ic_stall_dly,
    //output ic_st_ok,
	// IC controls
	output ic_tag_hit_id,
	//output ic_st_wt_id,
	// tiny AXI read bus i/f
	output icr_start_rq,
	output [31:0] ic_rin_addr,
	//input [127:0] rdat_m_data,
	input ic_rdat_m_valid,
	input ic_finish_mrd, // not used
	// IC flush
	input start_icflush,
	//output icflush_running,
	// reset pipeline
	input rst_pipe

	);
//
// flush counter
//reg [IWIDTH+1:4] icflush_cntr;
//reg ic_stall_dly;
reg [31:0] ic_curric_ent_radr_keeper;
// tag ram
wire ic_sel_tag;
reg [27:IWIDTH+2] ic_tag_adr_id;
wire [27:IWIDTH+2] ic_tag_adr_if = ic_sel_tag ? ic_curric_ent_radr_keeper[27:IWIDTH+2] : pc_if[27:IWIDTH+2];
wire [IWIDTH+1:4]  ic_index_adr = ic_sel_tag ? ic_curric_ent_radr_keeper[IWIDTH+1:4] : pc_if[IWIDTH+1:4];
wire [27:IWIDTH+2] ic_tag_wadr;
wire [IWIDTH+1:4] ic_index_wadr;
wire [27:IWIDTH+2] ic_tag_radr;
wire ic_cache_valid_id;
wire ic_tag_wen;

ic_tag_1r1w #(.IRWIDTH(IWIDTH-2)) ic_tag_1r1w (
	.clk(clk),
	.ram_radr(ic_index_adr),
	.ram_rdata(ic_tag_radr),
	.ram_wadr(ic_index_wadr),
	.ram_wdata(ic_tag_wadr),
	.ram_wen(ic_tag_wen)
	);

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ic_tag_adr_id <= { (27-IWIDTH-1){ 1'b0 }} ;
	else if (rst_pipe)
        ic_tag_adr_id <= { (27-IWIDTH-1){ 1'b0 }} ;
	else if (~ic_stall & ~ic_stall_fin )
		ic_tag_adr_id <= ic_tag_adr_if;
end


//wire cmd_ldst_id = (cmd_ld_id | cmd_st_id) & (pc_if[31:30] != 2'b11) ;

wire ic_tag_equal = (ic_tag_adr_id == ic_tag_radr);
assign ic_tag_hit_id = ic_tag_equal & ic_cache_valid_id & pc_valid_id;
wire ic_tag_empty_id = ~ic_cache_valid_id & pc_valid_id;
wire ic_tag_miss_id = ~ic_tag_equal & ic_cache_valid_id & pc_valid_id;

// dirty / valid bits
//reg [(2**(IWIDTH-2))-1:0] ic_ent_dirty_bit_id;
reg [(2**(IWIDTH-2))-1:0] ic_ent_valid_bit_id;

//wire [IWIDTH+1:4] ic_cache_dirty_adr = pc_if[IWIDTH+1:4];

/*
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ic_ent_dirty_bit_id <= { (2**(IWIDTH-2)){ 1'b0 }};
    else if (dc_cache_clr_bits | rst_pipe)
        ic_ent_dirty_bit_id <= { (2**(IWIDTH-2)){ 1'b0 }};
    else if (dc_cache_wr_id)
        ic_ent_dirty_bit_id[dc_cache_dirty_adr] <= 1'b1;
    else if (ic_tag_wen)
        ic_ent_dirty_bit_id[dc_index_wadr] <= 1'b0;
end
*/

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ic_ent_valid_bit_id <= { (2**(IWIDTH-2)){ 1'b0 }};
    else if (start_icflush | rst_pipe)
        ic_ent_valid_bit_id <= { (2**(IWIDTH-2)){ 1'b0 }};
    else if (ic_tag_wen)
        ic_ent_valid_bit_id[ic_index_wadr] <= 1'b1;
end

reg [IWIDTH+1:4] ic_index_adr_dly;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ic_index_adr_dly <= { (IWIDTH-2){ 1'b0 }};
	//else if (~ic_stall & ~ic_stall_fin )
	else
        ic_index_adr_dly <= ic_index_adr;
end

//assign ic_cache_valid_id = ic_ent_valid_bit_id[dc_cache_dirty_adr];
//wire ic_cache_dirty_id = ic_ent_dirty_bit_id[dc_cache_dirty_adr] & ic_tag_miss_id;
assign ic_cache_valid_id = ic_ent_valid_bit_id[ic_index_adr_dly];
//wire ic_cache_dirty_id = ic_ent_dirty_bit_id[dc_index_adr_dly] & ic_tag_miss_id;

// ic state machine

`define ICMS_IDLE 3'b000
`define ICMS_MEMR 3'b001
`define ICMS_ICWT 3'b010
`define ICMS_ICW2 3'b011
`define ICMS_ICW3 3'b100
//`define ICMS_ICW4 3'b101
`define ICMS_LDRD 3'b110
`define ICMS_DEFO 3'b111

// Request channel manager state machine
reg [2:0] ic_miss_current;

function [2:0] ic_miss_decode;
input [2:0] ic_miss_current;
input ic_tag_empty_id;
input ic_tag_miss_id;
//input ic_cache_dirty_id;
//input icw_finish_wresp;
input ic_rdat_m_valid;
begin
    case(ic_miss_current)
		`ICMS_IDLE: begin
    		casex({ic_tag_empty_id, ic_tag_miss_id})
				2'b1x: ic_miss_decode = `ICMS_MEMR;
				2'b01: ic_miss_decode = `ICMS_MEMR;
				2'b00: ic_miss_decode = `ICMS_IDLE;
				default: ic_miss_decode = `ICMS_DEFO;
    		endcase
		end
		`ICMS_MEMR: begin
    		case(ic_rdat_m_valid)
				1'b1: ic_miss_decode = `ICMS_ICWT;
				1'b0: ic_miss_decode = `ICMS_MEMR;
				default: ic_miss_decode = `ICMS_DEFO;
    		endcase
		end
		`ICMS_ICWT: ic_miss_decode = `ICMS_ICW2;
		`ICMS_ICW2: ic_miss_decode = `ICMS_ICW3;
		//`ICMS_ICW3: ic_miss_decode = `ICMS_ICW4;
		`ICMS_ICW3: ic_miss_decode = `ICMS_LDRD;
		`ICMS_LDRD: ic_miss_decode = `ICMS_IDLE;
		`ICMS_DEFO: ic_miss_decode = `ICMS_DEFO;
		default:     ic_miss_decode = `ICMS_DEFO;
   	endcase
end
endfunction

wire [2:0] ic_miss_next = ic_miss_decode( ic_miss_current, ic_tag_empty_id, ic_tag_miss_id, ic_rdat_m_valid );

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ic_miss_current <= `ICMS_IDLE;
	else if (rst_pipe)
        ic_miss_current <= `ICMS_IDLE;
    else
        ic_miss_current <= ic_miss_next;
end

// for timing
reg [31:2] pc_if_dly;
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        pc_if_dly <= 30'd0;
	else
        pc_if_dly <= pc_if;
end

// current read address keeper
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ic_curric_ent_radr_keeper <= 32'd0;
	else if (rst_pipe)
        ic_curric_ent_radr_keeper <= 32'd0;
	else if ((ic_miss_current == `ICMS_IDLE) & (ic_tag_miss_id | ic_tag_empty_id))
		//ic_curric_ent_radr_keeper <= {pc_if, 2'd0};
		ic_curric_ent_radr_keeper <= {pc_if_dly, 2'd0};
end

// core stall singal
assign ic_stall = ((ic_miss_current != `ICMS_LDRD)&(ic_miss_current != `ICMS_IDLE)) | ((ic_tag_miss_id | ic_tag_empty_id)&(ic_miss_current != `ICMS_LDRD));
//assign ic_stall = (ic_miss_current != `ICMS_IDLE);
assign ic_sel_tag = ((ic_miss_current != `ICMS_LDRD)&(ic_miss_current != `ICMS_IDLE)) ;
//assign ic_st_ok = (dc_miss_current != `ICMS_MEMR);

// store data write timing
//assign ic_st_wt_id = (ic_miss_current != `ICMS_ICWT);

// load issue timing
assign ic_stall_fin = (ic_miss_current == `ICMS_ICW3);
assign ic_stall_fin2 = (ic_miss_current == `ICMS_LDRD);

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        ic_stall_dly <= 1'b0;
	else
        ic_stall_dly <= ic_stall;
end

// memory write bus i/f signals
//reg icw_start_rq_dc;
//reg icflush_wreq;
//wire [31:0] icw_in_addr_dcflush;

/*
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        icw_start_rq_dc <= 1'b0;
	else
        icw_start_rq_dc <= //ic_ram_ren_all;
end
//wire icw_start_rq_dc = ic_ram_ren_all;

reg [31:0] icw_in_addr_dly;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        icw_in_addr_dly <= 32'd0;
	else
        icw_in_addr_dly <= { pc_if[31:28], ic_tag_radr[27:IWIDTH+2],  pc_if[IWIDTH+1:0] };
end
*/

//assign icw_start_rq = icw_start_rq_dc | icflush_wreq;

//assign icw_in_idsk = 16'd0;

//assign icw_in_addr = icflush_running ? icw_in_addr_dcflush : { pc_if[31:28], ic_tag_radr[27:IWIDTH+2],  pc_if[IWIDTH+1:0] };
//assign icw_in_addr = icflush_running ? icw_in_addr_dcflush : icw_in_addr_dly;

//assign icw_in_data = ic_ram_rdata_all;

// memory read bus i/f signals

wire ic_memr_stat = (ic_miss_current == `ICMS_MEMR);
reg ic_memr_stat_dly;
reg ic_memr_stat_dly2;
reg ic_memr_stat_dly3; // just debug test

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        ic_memr_stat_dly <= 1'b0;
        ic_memr_stat_dly2 <= 1'b0;
        ic_memr_stat_dly3 <= 1'b0;
	end
	else begin
        ic_memr_stat_dly <= ic_memr_stat;
        ic_memr_stat_dly2 <= ic_memr_stat_dly;
        ic_memr_stat_dly3 <= ic_memr_stat_dly2;
	end
end

//assign icr_start_rq = ic_memr_stat & ~ic_memr_stat_dly;
assign icr_start_rq = ic_memr_stat_dly2 & ~ic_memr_stat_dly3;

//assign ic_rin_addr = { pc_if, 2'd0 } ;
assign ic_rin_addr = ic_curric_ent_radr_keeper;

// to MA
//assign ic_ram_wdata_all = rdat_m_data;
//assign ic_ram_radr_all = icflush_running ? icflush_cntr : pc_if[IWIDTH+1:4];
assign ic_ram_wadr_all = ic_curric_ent_radr_keeper[IWIDTH+1:4];
//assign ic_ram_wen_all = rdat_m_valid;
//assign ic_ram_ren_all = ((dc_miss_current == `ICMS_IDLE) & (dc_miss_next == `ICMS_MEMW)) | icflush_running;

//tag write address
assign ic_tag_wadr = ic_curric_ent_radr_keeper[27:IWIDTH+2];
assign ic_index_wadr = ic_curric_ent_radr_keeper[IWIDTH+1:4];
assign ic_tag_wen =  ic_rdat_m_valid;

/*
// IC flush
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        //dcflush_cntr <= 9'd0;
        icflush_cntr <= { (IWIDTH-3){ 1'b0 }};
	else if ( start_dcflush )
        icflush_cntr <= {9{1'b1}};
	else if ((icflush_cntr >  {(IWIDTH-3){ 1'b0 }}) & icw_finish_wresp)
        icflush_cntr <= icflush_cntr -  {{ (IWIDTH-4){ 1'b0 }}, 1'b1};
end

reg [IWIDTH+1:4] icflush_cntr_dly;
always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        icflush_cntr_dly <= { (IWIDTH-3){ 1'b0 }};
	else
        icflush_cntr_dly <= icflush_cntr;
end

wire icflush_cntr_not0 = (dcflush_cntr != { (IWIDTH-3){ 1'b0 }});
reg icflush_cntr_not0_dly;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
		dcflush_cntr_not0_dly <= 1'b0;
	else
		dcflush_cntr_not0_dly <= icflush_cntr_not0;
end

assign icflush_running = icflush_cntr_not0 | icflush_cntr_not0_dly;

wire icflush_wreq_pre = icflush_running & (dcflush_cntr_dly != icflush_cntr_not0_dly);

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
		dcflush_wreq <= 1'b0;
	else
		dcflush_wreq <= icflush_wreq_pre;
end

assign icw_in_addr_dcflush = { 4'd0, ic_tag_radr[27:IWIDTH+2],  icflush_cntr_dly, 4'd0 };
*/

endmodule
