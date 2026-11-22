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
	  parameter SWIDTH = 13,
	  parameter DWAYS = 1)  // D$ ways : 1 / 2 / 4 / 8 (2026-11-22)
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
	// pc_jump_trace_logger WB-commit tap (2026-07-29): see ex_stage.v's
	// pc_ma for the rationale; just carried one more stage here.
	input [31:2] pc_ma,
	// to WB
    output reg cmd_ld_wb,
	output reg [2:0] ld_code_wb,
	output reg [4:0] rd_adr_wb,
	output reg [31:0] rd_data_wb,
	output reg wbk_rd_reg_wb,
	output [31:0] ld_data_wb,
	output reg [31:2] pc_wb,
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
    input [7:0] dc_way_hit_ma,   // D$ ways (2026-11-22) : store write enable per way
    input [7:0] dc_way_rd,       // way hit of the current access : load / PTE data select
    input [7:0] dc_fill_way,     // refill write way (one hot)
    input [2:0] dc_rdall_way,    // way of ram_rdata_all
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

	// MMU (2026-11-22)
	input [31:0] pa_ma,         // physical address of the MA access (= rd_data_ma when translation is off)
	input mmu_ok_ma,            // access is translated and allowed
	input io_ok_ma,             // I/O access may be issued in this cycle
	input pf_exc,               // page fault trap of the MA access : no write back
	input ptw_rd_sel,           // PTW reads a PTE from the data RAM
	input [31:0] ptw_pa,
	output [31:0] dc_rdata_raw, // data RAM read data (PTE)
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
// MMU (2026-11-22): the region is decoded from the physical address, and
// nothing is accessed until the DTLB allows it (mmu_ok_ma / io_ok_ma).
wire [3:0] st_we_mem = st_we & { 4{ (pa_ma[31] == 1'b0) & mmu_ok_ma }};
wire [3:0] st_we_scr_mem = st_we & { 4{ (pa_ma[31:30] == 2'b10) & mmu_ok_ma }};
assign dma_io_we = (&st_we) & (pa_ma[31:30] == 2'b11) & io_ok_ma;
assign dma_io_wadr = pa_ma[15:2];
assign dma_io_wdata = st_wdata;
assign dma_io_radr = pa_ma[15:2];
assign dma_io_radr_en = (pa_ma[31:30] == 2'b11) & cmd_ld_ma & io_ok_ma;

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
// MMU (2026-11-22): PTE read by the PTW (the MA access is stalled meanwhile)
assign data_radr_ma = ptw_rd_sel ? ptw_pa[DWIDTH+1:2] : rd_data_ma[DWIDTH+1:2];
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
// D$ ways (2026-11-22) : one data RAM per way (2^(DWIDTH+2) bytes each).
//   All ways are read in MA with the same index, the hit way is selected in
//   WB (rd_way_wb, way 0 when no way hits : DWAYS = 1 is the original D$).
//   Stores / refills write only their way.
wire [DWAYS*4-1:0] data_we_w;
wire [DWAYS*32-1:0] data_rdata_w;
wire [DWAYS*128-1:0] ram_rdata_all_w;
// timing (2026-11-22) : the load data is selected with one registered one-hot
// vector of { way, word } (flat AND-OR of the raw RAM words) instead of
// word select -> way select -> I/O / scratch select in series.
//   ld_sel_wb  : { way, word } one hot (way 0 when no way hits, like the
//                original direct mapped D$) : D$ data, PTE (dc_rdata_raw)
//   ld_selm_wb : the same, masked when the load is an I/O / scratch read
wire [3:0] word_oh = 4'd1 << data_radr_ma[3:2];   // data_radr_ma is [DWIDTH+1:2]
wire [7:0] way_oh = (|dc_way_rd[DWAYS-1:0]) ? dc_way_rd : 8'd1;
wire io_or_scr_ma;
reg [DWAYS*4-1:0] ld_sel_wb;
reg [DWAYS*4-1:0] ld_selm_wb;
integer si, sk;

always @ ( posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		ld_sel_wb <= { (DWAYS*4){ 1'b0 }};
		ld_selm_wb <= { (DWAYS*4){ 1'b0 }};
	end
	else begin
		for (si = 0; si < DWAYS; si = si + 1)
			for (sk = 0; sk < 4; sk = sk + 1) begin
				ld_sel_wb[si*4+sk] <= way_oh[si] & word_oh[sk];
				ld_selm_wb[si*4+sk] <= way_oh[si] & word_oh[sk] & ~io_or_scr_ma;
			end
	end
end

genvar gw;
generate
for (gw = 0; gw < DWAYS; gw = gw + 1) begin : dway
	assign data_we_w[gw*4 +: 4] = st_we_mem & { 4{ dc_st_ok & dc_way_hit_ma[gw] }};

	data_ram #(.DWIDTH(DWIDTH)) data_ram (
		.clk(clk),
		.rst_n(rst_n),
		.ram_radr_part(data_radr_ma),
		.ram_rdata(data_rdata_w[gw*32 +: 32]),
		.ram_wadr_part(data_wadr_ma),
		.ram_wdata(data_wdata_ma),
		.ram_wen(data_we_w[gw*4 +: 4]),
		.ram_radr_all(ram_radr_all),
		.ram_rdata_all(ram_rdata_all_w[gw*128 +: 128]),
		.ram_ren_all(ram_ren_all),
		.ram_wadr_all(ram_wadr_all),
		.ram_wdata_all(ram_wdata_all),
		.ram_wen_all(ram_wen_all & dc_fill_way[gw])
		);
end
endgenerate

function [3:0] or_we;
input [DWAYS*4-1:0] we;
integer k;
begin
	or_we = 4'd0;
	for (k = 0; k < DWAYS; k = k + 1)
		or_we = or_we | we[k*4 +: 4];
end
endfunction

function [31:0] sel_rdata;
input [DWAYS*4-1:0] sel;
input [DWAYS*128-1:0] d;
integer k;
begin
	sel_rdata = 32'd0;
	for (k = 0; k < DWAYS*4; k = k + 1)
		sel_rdata = sel_rdata | ({ 32{ sel[k] }} & d[k*32 +: 32]);
end
endfunction

function [127:0] sel_rdall;
input [2:0] w;
input [DWAYS*128-1:0] d;
integer k;
begin
	sel_rdall = d[127:0];
	for (k = 1; k < DWAYS; k = k + 1)
		if (w == k) sel_rdall = d[k*128 +: 128];
end
endfunction

assign data_we_ma = or_we(data_we_w);
assign dc_cache_wr_ma = |data_we_ma;
assign data_rdata_wb_mem = sel_rdata(ld_sel_wb, ram_rdata_all_w);
wire [31:0] data_rdata_wb_dc = sel_rdata(ld_selm_wb, ram_rdata_all_w);
assign ram_rdata_all = sel_rdall(dc_rdall_way, ram_rdata_all_w);

//assign sel_data_rd_ma = cmd_ld_ma; 
wire [15:0] dataram_rdata_wb = data_rdata_wb_mem[15:0];

// scrach memory
wire [SWIDTH+1:2] scr_data_radr_ma;  // read adr
wire [31:0] scr_data_rdata_wb_mem; // read data to wb
wire [SWIDTH+1:2] scr_data_wadr_ma; // write adr
wire [31:0] scr_data_wdata_ma; // write data
wire [3:0] scr_data_we_ma; // write enabe

assign scr_data_radr_ma = scr_read_sel ? scr_ram_radr : pa_ma[SWIDTH+1:2];
assign scr_data_wadr_ma = scr_ram_wen ? scr_ram_wadr : pa_ma[SWIDTH+1:2];

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
wire dma_io_ren_ma = cmd_ld_ma & (pa_ma[31:30] == 2'b11);
wire scr_ren_ma = cmd_ld_ma & (pa_ma[31:30] == 2'b10);

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

assign io_or_scr_ma = dma_io_ren_ma | scr_ren_ma;
// (flat : at most one of the three is selected)
wire [31:0] data_rdata_wb_flat = data_rdata_wb_dc |
                                 ({ 32{ dma_io_ren_wb }} & dma_io_rdata) |
                                 ({ 32{ scr_ren_wb }} & scr_data_rdata_wb_mem);
assign data_rdata_wb = data_rdata_wb_flat;

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
assign dc_rdata_raw = data_rdata_wb_mem;

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
		pc_wb <= 30'd0;
	end
	else begin
	//else if (~stall) begin
        cmd_ld_wb <= cmd_ld_ma;
		ld_code_wb <= ldst_code_ma;
		rd_adr_wb <= rd_adr_ma;
		pc_wb <= pc_ma;
`ifdef SUPPORT_A
		wbk_rd_reg_wb <= ~(stall & ~cpu_stopping) & wbk_rd_reg_with_scw & ~dc_wb_mask & ~pf_exc;
`else // SUPPORT_A
		wbk_rd_reg_wb <= ~(stall & ~cpu_stopping) & wbk_rd_reg_ma & ~dc_wb_mask & ~pf_exc;
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

