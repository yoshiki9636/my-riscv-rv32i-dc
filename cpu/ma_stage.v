/*
 * My RISC-V RV32I CPU
 *   CPU Memory Access Stage Module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

`define SUPPORT_A

module ma_stage
	#(parameter DWIDTH = 12,
	  parameter SWIDTH = 13)
	(
	input clk,
	input rst_n,
	
	// from EX
    input cmd_ld_ma,
    input cmd_st_ma,
	input [4:0] rd_adr_ma,
	input [31:0] rd_data_ma,
	input wbk_rd_reg_ma,
	input [31:0] st_data_ma,
	input [2:0] ldst_code_ma,
	// to WB
    output reg cmd_ld_wb,
	output reg [2:0] ld_code_wb,
	output reg [4:0] rd_adr_wb,
	output reg [31:0] rd_data_wb,
	output reg wbk_rd_reg_wb,
	output [31:0] ld_data_wb,
	// to LSU
	input [DWIDTH-3:0] ram_radr_all,
	output [127:0] ram_rdata_all,
	input ram_ren_all,
	input [DWIDTH-3:0] ram_wadr_all,
	input [127:0] ram_wdata_all,
	input ram_wen_all,
	input dc_stall_fin2,
	input dc_st_ok,
	input dc_wb_mask,
	// dc controls
    input dc_tag_hit_ma,
    input dc_st_wt_ma,
    output dc_cache_wr_ma,
    //output dc_cache_clr_bits,
	// to UART monitor
	input [SWIDTH+1:2] scr_ram_radr,
	output [31:0] scr_ram_rdata,
	input [SWIDTH+1:2] scr_ram_wadr,
	input [31:0] scr_ram_wdata,
	input scr_ram_wen,
	input scr_read_sel,
	// from/to IO
	output dma_io_we,
	output [15:2] dma_io_wadr,
	output [31:0] dma_io_wdata,
    output [15:2] dma_io_radr,
	output dma_io_radr_en,
    input [31:0] dma_io_rdata,
	// from/to dma memory access interface
	input [SWIDTH-3:0] scr_ram_radr_all,
	output [127:0] scr_ram_rdata_all,
	input scr_ram_ren_all,
	input [SWIDTH-3:0] scr_ram_wadr_all,
	input [127:0] scr_ram_wdata_all,
	input scr_ram_wen_all,

    //input dma_we_ma,
    //input [31:4] dataram_wadr_ma,
    //input [127:0] dataram_wdata_ma,
    //input dma_re_ma,
    //input [31:4] dataram_radr_ma,
    //output [127:0] dataram_rdata_wb,

`ifdef SUPPORT_A
	input success_scw_ma,
	input cmd_scw_purge_ma,
	output reg success_scw_wb,
	output reg cmd_scw_purge_wb,
`endif // SUPPORT_A

	// stall
	input stall,
	input stall_1shot,
	input stall_1shot_dly, // not used
	input stall_dly,
	input stall_dly2, // not used
	input cpu_stopping,
	input rst_pipe_ma

	);

// store
// byte aligner
function [31:0] byte_aligner;
input [1:0] adr_ofs;
input [7:0] data_byte;
begin
	case(adr_ofs)
		2'd0: byte_aligner = { 24'd0, data_byte };
		2'd1: byte_aligner = { 16'd0, data_byte, 8'd0 };
		2'd2: byte_aligner = { 8'd0, data_byte, 16'd0 };
		2'd3: byte_aligner = { data_byte, 24'd0 };
		default: byte_aligner = 32'd0;
	endcase
end
endfunction

wire [31:0] st_data_byte = byte_aligner( rd_data_ma[1:0], st_data_ma[7:0] );

function [31:0] half_aligner;
input adr_ofs;
input [15:0] data_byte;
begin
	case(adr_ofs)
		1'b0: half_aligner = { 16'd0, data_byte };
		1'b1: half_aligner = { data_byte, 16'd0 };
		default: half_aligner = 32'd0;
	endcase
end
endfunction

wire [31:0] st_data_half = half_aligner( rd_data_ma[1], st_data_ma[15:0] );

wire [31:0] st_wdata = (ldst_code_ma == 3'b000) ? st_data_byte :
                       (ldst_code_ma == 3'b001) ? st_data_half :
					   (ldst_code_ma == 3'b010) ? st_data_ma : 32'd0;

// byte enable

function [3:0] be_byte_aligner;
input [1:0] adr_ofs;
input cmd_st_ma;
begin
	case(adr_ofs)
		2'd0: be_byte_aligner = { 3'd0, cmd_st_ma };
		2'd1: be_byte_aligner = { 2'd0, cmd_st_ma, 1'd0 };
		2'd2: be_byte_aligner = { 1'd0, cmd_st_ma, 2'd0 };
		2'd3: be_byte_aligner = { cmd_st_ma, 3'd0 };
		default: be_byte_aligner = 4'd0;
	endcase
end
endfunction

wire [3:0] be_byte = be_byte_aligner( rd_data_ma[1:0], cmd_st_ma );

wire [3:0] be_half = rd_data_ma[1] ? { cmd_st_ma, cmd_st_ma, 2'd0 } : { 2'd0, cmd_st_ma, cmd_st_ma };

wire [3:0] st_we = (ldst_code_ma == 3'b000) ? be_byte :
                   (ldst_code_ma == 3'b001) ? be_half :
				   (ldst_code_ma == 3'b010) ? { cmd_st_ma, cmd_st_ma, cmd_st_ma, cmd_st_ma } : 4'd0;

//wire [3:0] st_we_mem = st_we & { 4{ (rd_data_ma[31:30] != 2'b11) }};
wire [3:0] st_we_mem = st_we & { 4{ (rd_data_ma[31] == 1'b0) }};
wire [3:0] st_we_scr_mem = st_we & { 4{ (rd_data_ma[31:30] == 2'b10) }};
assign dma_io_we = (&st_we) & (rd_data_ma[31:30] == 2'b11);
assign dma_io_wadr = rd_data_ma[15:2];
assign dma_io_wdata = st_wdata;
assign dma_io_radr = rd_data_ma[15:2];
assign dma_io_radr_en = (rd_data_ma[31:30] == 2'b11) & cmd_ld_ma;

// load / next stage

// data memory
reg  [31:0] ld_data_roll;
//wire sel_data_rd_ma;
wire [DWIDTH+1:2] data_radr_ma;
wire [31:0] data_rdata_wb_mem;
wire [31:0] data_rdata_wb;
wire [DWIDTH+1:2] data_wadr_ma;
wire [31:0] data_wdata_ma;
wire [3:0] data_we_ma;

// for D$
//wire d_ram_wen = 1'b0;
//wire d_read_sel = 1'b0;


//assign data_radr_ma = d_read_sel ? scr_ram_radr : rd_data_ma[DWIDTH+1:2]; // new
assign data_radr_ma = rd_data_ma[DWIDTH+1:2];
//assign data_wadr_ma = d_ram_wen ? scr_ram_wadr : rd_data_ma[DWIDTH+1:2]; // new
assign data_wadr_ma = rd_data_ma[DWIDTH+1:2];


/*
generate
if (DWIDTH < 15) begin
assign data_radr_ma = d_read_sel ? scr_ram_radr :
                      dma_re_ma ? dataram_radr_ma[DWIDTH+1:2] : rd_data_ma[DWIDTH+1:2];
assign data_wadr_ma = d_ram_wen ? scr_ram_wadr :
                      dma_we_ma ? dataram_wadr_ma[DWIDTH+1:2] : rd_data_ma[DWIDTH+1:2];
end
else if (DWIDTH >= 15) begin
assign data_radr_ma = d_read_sel ? scr_ram_radr :
                      dma_re_ma ? { { (DWIDTH-14){ 1'b0 }}, dataram_radr_ma[15:2] } : rd_data_ma[DWIDTH+1:2];
assign data_wadr_ma = d_ram_wen ? scr_ram_wadr :
                      dma_we_ma ? { { (DWIDTH-14){ 1'b0 }}, dataram_wadr_ma[15:2] } : rd_data_ma[DWIDTH+1:2];
end
endgenerate
*/

//assign data_wdata_ma = d_ram_wen ? scr_ram_wdata : st_wdata; // new
assign data_wdata_ma = st_wdata; // new

//assign data_we_ma = ((d_ram_wen | dma_we_ma) ? 4'b1111 : st_we_mem) & { 4{ dc_tag_hit_ma | dc_st_wt_ma }};
//assign data_we_ma = (d_ram_wen ? 4'b1111 : st_we_mem & { 4{ dc_st_ok}}) & { 4{ dc_tag_hit_ma }};
assign data_we_ma = st_we_mem & { 4{ dc_st_ok}} & { 4{ dc_tag_hit_ma }};

assign dc_cache_wr_ma = |data_we_ma;

//assign sel_data_rd_ma = cmd_ld_ma; 
assign dataram_rdata_wb = data_rdata_wb_mem[15:0];

data_ram #(.DWIDTH(DWIDTH)) data_ram (
	.clk(clk),
	.rst_n(rst_n),
	.ram_radr_part(data_radr_ma),
	.ram_rdata(data_rdata_wb_mem),
	.ram_wadr_part(data_wadr_ma),
	.ram_wdata(data_wdata_ma),
	.ram_wen(data_we_ma),

	.ram_radr_all(ram_radr_all),
	.ram_rdata_all(ram_rdata_all),
	.ram_ren_all(ram_ren_all),
	.ram_wadr_all(ram_wadr_all),
	.ram_wdata_all(ram_wdata_all),
	.ram_wen_all(ram_wen_all)
	);

// scrach memory
wire [SWIDTH+1:2] scr_data_radr_ma;  // read adr
wire [31:0] scr_data_rdata_wb_mem; // read data to wb
wire [SWIDTH+1:2] scr_data_wadr_ma; // write adr
wire [31:0] scr_data_wdata_ma; // write data
wire [3:0] scr_data_we_ma; // write enabe

assign scr_data_radr_ma = scr_read_sel ? scr_ram_radr : rd_data_ma[SWIDTH+1:2];
assign scr_data_wadr_ma = scr_ram_wen ? scr_ram_wadr : rd_data_ma[SWIDTH+1:2];

assign scr_data_wdata_ma = scr_ram_wen ? scr_ram_wdata : st_wdata;

assign scr_data_we_ma = (scr_ram_wen) ? 4'b1111 : st_we_scr_mem;

data_ram #(.DWIDTH(SWIDTH)) scr_ram (
	.clk(clk),
	.rst_n(rst_n),
	.ram_radr_part(scr_data_radr_ma),
	.ram_rdata(scr_data_rdata_wb_mem),
	.ram_wadr_part(scr_data_wadr_ma),
	.ram_wdata(scr_data_wdata_ma),
	.ram_wen(scr_data_we_ma),

    // for DMA
	.ram_radr_all(scr_ram_radr_all),
	.ram_rdata_all(scr_ram_rdata_all),
	.ram_ren_all(scr_ram_ren_all),
	.ram_wadr_all(scr_ram_wadr_all),
	.ram_wdata_all(scr_ram_wdata_all),
	.ram_wen_all(scr_ram_wen_all)
	);


// io bus & scr memory
wire dma_io_ren_ma = cmd_ld_ma & (rd_data_ma[31:30] == 2'b11);
wire scr_ren_ma = cmd_ld_ma & (rd_data_ma[31:30] == 2'b10);

reg dma_io_ren_wb;
reg scr_ren_wb;
always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
		dma_io_ren_wb <= 1'b0;
		scr_ren_wb <= 1'b0;
	end
	else begin
		dma_io_ren_wb <= dma_io_ren_ma;
		scr_ren_wb <= scr_ren_ma;
	end
end

assign data_rdata_wb = dma_io_ren_wb ? dma_io_rdata :
                       scr_ren_wb ? scr_data_rdata_wb_mem : data_rdata_wb_mem;

always @ ( posedge clk or negedge rst_n) begin
    if (~rst_n)
        ld_data_roll <= 32'd0;
    else if (rst_pipe_ma)
        ld_data_roll <= 32'd0;
    else if (stall_1shot)
        ld_data_roll <= data_rdata_wb;
end

//assign ld_data_wb = data_rdata_wb;
//assign ld_data_wb = stall_dly2 ? ld_data_roll : data_rdata_wb;
//assign ld_data_wb = stall_dly ? ld_data_roll : data_rdata_wb;
//assign ld_data_wb = (stall_dly & ~cpu_stopping) ? ld_data_roll : data_rdata_wb; // for test
assign ld_data_wb = (1'b0) ? ld_data_roll : data_rdata_wb;
assign scr_ram_rdata = scr_data_rdata_wb_mem;

`ifdef SUPPORT_A
wire wbk_rd_reg_with_scw = wbk_rd_reg_ma | cmd_scw_purge_ma;
	
//wire [31:0] rd_data_with_scw = cmd_scw_purge_ma ? { 31'd0, ~success_scw_ma } : rd_data_ma;
wire [31:0] rd_data_with_scw = rd_data_ma;
`endif // SUPPORT_A

// FF to WB

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
        cmd_ld_wb <= 1'b0;
		ld_code_wb <= 3'd0;
		rd_adr_wb <= 5'd0;
		wbk_rd_reg_wb <= 1'b0;
	end
	else begin
	//else if (~stall) begin
        cmd_ld_wb <= cmd_ld_ma;
		ld_code_wb <= ldst_code_ma;
		rd_adr_wb <= rd_adr_ma;
`ifdef SUPPORT_A
		wbk_rd_reg_wb <= ~(stall & ~cpu_stopping) & wbk_rd_reg_with_scw & ~dc_wb_mask;
`else // SUPPORT_A
		wbk_rd_reg_wb <= ~(stall & ~cpu_stopping) & wbk_rd_reg_ma & ~dc_wb_mask;
`endif // SUPPORT_A
		//wbk_rd_reg_wb <= (stall & ~cpu_stopping) ? dc_stall_fin2 : wbk_rd_reg_ma;
		//wbk_rd_reg_wb <= ~stall & wbk_rd_reg_ma;
	end
end

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
		rd_data_wb <= 32'd0;
`ifdef SUPPORT_A
		success_scw_wb <= 1'b0;
		cmd_scw_purge_wb <= 1'b0;
`endif // SUPPORT_A
	end
	else if (~stall) begin
`ifdef SUPPORT_A
		rd_data_wb <= rd_data_with_scw;
		success_scw_wb <= success_scw_ma;
		cmd_scw_purge_wb <= cmd_scw_purge_ma;
`else // SUPPORT_A
		rd_data_wb <= rd_data_ma;
`endif // SUPPORT_A
	end
end


endmodule

