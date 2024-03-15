/*
 * My RISC-V RV32I CPU
 *   AXI bus Top Module for Tang Premier
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module axi_bus_top (
	input clk,
	input rst_n,

// uart axi bus interface
// uart axi write bus manager
	input uart_wstart_rq,
	input [31:0] uart_win_addr,
	input [127:0] uart_in_wdata,
	input [15:0] uart_in_mask,
	output uart_finish_wresp,
// uart axi read bus manager
	input uart_rstart_rq,
	input [31:0] uart_rin_addr,
	output [127:0] uart_rdat_m_data,
	output [15:0] uart_rdat_m_mask,
	output uart_rdat_m_valid,
	output uart_finish_mrd,
// dcache axi bus interface
// dcache axi write bus manager
	input dc_wstart_rq,
	input [31:0] dc_win_addr,
	input [127:0] dc_in_wdata,
	input [15:0] dc_in_mask,
	output dc_finish_wresp,
// dcache axi read bus manager
	input dc_rstart_rq,
	input [31:0] dc_rin_addr,
	output [127:0] dc_rdat_m_data,
	output [15:0] dc_rdat_m_mask,
	output dc_rdat_m_valid,
	output dc_finish_mrd,

    // write request
    output awvalid,
    input  awready,
    output [3:0] awid,
    output [31:0] awaddr,
    output [5:0] awatop,
    // write data
    output wvalid,
    input  wready,
    output [31:0] wdata,
    output [3:0] wstrb,
    output wlast,
    // write response
    input bvalid,
    output  bready,
    input [3:0] bid,
    input bcomp,
    // read request
    output arvalid,
    input  arready,
    output [3:0] arid,
    output [31:0] araddr,
    // read data
    input rvalid,
    output  rready,
    input [3:0] rid,
    input [31:0] rdata,
    input rlast

	);

// fixed unused signal
assign dc_rdat_m_mask = 16'd0;
wire [3:0] uart_rnext_id;
wire [3:0] dc_rnext_id;

// arbiter signals
wire uart_req_wt;
wire dc_req_wt;
wire uart_gnt_wt;
wire dc_gnt_wt;
wire [2:0] sel_wt;
wire uart_req_rd;
wire dc_req_rd;
wire uart_gnt_rd;
wire dc_gnt_rd;
wire [2:0] sel_rd;

wire gnt2_wt;
wire gnt2_rd;

// dc axi bus signals
wire dc_awvalid;
wire dc_awready;
wire [3:0] dc_awid;
wire [31:0] dc_awaddr;
wire [5:0] dc_awatop;
wire dc_wvalid;
wire dc_wready;
wire [31:0] dc_wdata;
wire [3:0] dc_wstrb;
wire dc_wlast;
wire dc_bvalid;
wire dc_bready;
wire [3:0] dc_bid;
wire dc_bcomp;
wire dc_arvalid;
wire dc_arready;
wire [3:0] dc_arid;
wire [31:0] dc_araddr;
wire dc_rvalid;
wire dc_rready;
wire [3:0] dc_rid;
wire [31:0] dc_rdata;
wire dc_rlast;

// uart axi bus signals
wire uart_awvalid;
wire uart_awready;
wire [3:0] uart_awid;
wire [31:0] uart_awaddr;
wire [5:0] uart_awatop;
wire uart_wvalid;
wire uart_wready;
wire [31:0] uart_wdata;
wire [3:0] uart_wstrb;
wire uart_wlast;
wire uart_bvalid;
wire uart_bready;
wire [3:0] uart_bid;
wire uart_bcomp;
wire uart_arvalid;
wire uart_arready;
wire [3:0] uart_arid;
wire [31:0] uart_araddr;
wire uart_rvalid;
wire uart_rready;
wire [3:0] uart_rid;
wire [31:0] uart_rdata;
wire uart_rlast;

// data cache bus

write_channels_mngr #(.REQC_M_ID(2'b00)) dc_write_channels_mngr (
	.clk(clk),
	.rst_n(rst_n),
	.req_rq(dc_req_wt),
	.gnt_rq(dc_gnt_wt),
	.awvalid(dc_awvalid),
	.awready(dc_awready),
	.awid(dc_awid),
	.awaddr(dc_awaddr),
	.awatop(dc_awatop),
	.wvalid(dc_wvalid),
	.wready(dc_wready),
	.wdata(dc_wdata),
	.wstrb(dc_wstrb),
	.wlast(dc_wlast),
	.bvalid(dc_bvalid),
	.bready(dc_bready),
	.bid(dc_bid),
	.bcomp(dc_bcomp),
	.wstart_rq(dc_wstart_rq),
	.win_addr(dc_win_addr),
	.in_wdata(dc_in_wdata),
	.in_mask(dc_in_mask),
	.finish_wresp(dc_finish_wresp)
	);

read_channels_mngr #(.REQC_M_ID(2'b01)) dc_read_channels_mngr (
	.clk(clk),
	.rst_n(rst_n),
	.req_rq(dc_req_rd),
	.gnt_rq(dc_gnt_rd),
	.arvalid(dc_arvalid),
	.arready(dc_arready),
	.arid(dc_arid),
	.araddr(dc_araddr),
	.rvalid(dc_rvalid),
	.rready(dc_rready),
	.rid(dc_rid),
	.rdata(dc_rdata),
	.rlast(dc_rlast),
	.rstart_rq(dc_rstart_rq),
	.rin_addr(dc_rin_addr),
	.rnext_rq(),
	.next_rid(dc_rnext_id),
	.rnext_id(dc_rnext_id),
	.rqfull_1(1'b0),
	.rdat_m_data(dc_rdat_m_data),
	.rdat_m_valid(dc_rdat_m_valid),
	.finish_mrd(dc_finish_mrd)
	);

// uart bus
write_channels_mngr #(.REQC_M_ID(2'b10)) uart_write_channels_mngr (
	.clk(clk),
	.rst_n(rst_n),
	.req_rq(uart_req_wt),
	.gnt_rq(uart_gnt_wt),
	.awvalid(uart_awvalid),
	.awready(uart_awready),
	.awid(uart_awid),
	.awaddr(uart_awaddr),
	.awatop(uart_awatop),
	.wvalid(uart_wvalid),
	.wready(uart_wready),
	.wdata(uart_wdata),
	.wstrb(uart_wstrb),
	.wlast(uart_wlast),
	.bvalid(uart_bvalid),
	.bready(uart_bready),
	.bid(uart_bid),
	.bcomp(uart_bcomp),
	.wstart_rq(uart_wstart_rq),
	.win_addr(uart_win_addr),
	.in_wdata(uart_in_wdata),
	.in_mask(uart_in_mask),
	.finish_wresp(uart_finish_wresp)
	);

read_channels_mngr #(.REQC_M_ID(2'b11)) uart_read_channels_mngr (
	.clk(clk),
	.rst_n(rst_n),
	.req_rq(uart_req_rd),
	.gnt_rq(uart_gnt_rd),
	.arvalid(uart_arvalid),
	.arready(uart_arready),
	.arid(uart_arid),
	.araddr(uart_araddr),
	.rvalid(uart_rvalid),
	.rready(uart_rready),
	.rid(uart_rid),
	.rdata(uart_rdata),
	.rlast(uart_rlast),
	.rstart_rq(uart_rstart_rq),
	.rin_addr(uart_rin_addr),
	.rnext_rq(),
	.next_rid(uart_rnext_id),
	.rnext_id(uart_rnext_id),
	.rqfull_1(1'b0),
	.rdat_m_data(uart_rdat_m_data),
	.rdat_m_valid(uart_rdat_m_valid),
	.finish_mrd(uart_finish_mrd)
	);

// bus logics
// write request
assign awvalid = sel_wt[0] ? dc_awvalid : sel_wt[1] ? uart_awvalid :  sel_wt[1] ? 1'b0 : 1'b0;
assign dc_awready = awready;
assign uart_awready = awready;
assign awid = sel_wt[0] ? dc_awid : sel_wt[1] ? uart_awid : sel_wt[2] ? 4'd0 : 4'd0;
assign awaddr = sel_wt[0] ? dc_awaddr : sel_wt[1] ? uart_awaddr : sel_wt[2] ? 32'd0 : 32'd0;
assign awatop =  sel_wt[0] ? dc_awatop : sel_wt[1] ? uart_awatop : sel_wt[2] ? 6'd0 : 6'd0;
// write data
assign wvalid =  sel_wt[0] ? dc_wvalid : sel_wt[1] ? uart_wvalid : sel_wt[2] ? 1'b0 : 1'b0;
assign dc_wready = wready;
assign uart_wready = wready;
assign wdata = sel_wt[0] ? dc_wdata : sel_wt[1] ? uart_wdata : sel_wt[2] ? 32'd0 : 32'd0;
assign wstrb = sel_wt[0] ? dc_wstrb : sel_wt[1] ? uart_wstrb : sel_wt[2] ? 4'd0 : 4'd0;
assign wlast = sel_wt[0] ? dc_wlast : sel_wt[1] ? uart_wlast : sel_wt[2] ? 1'b0 : 1'b0;
// write response
assign dc_bvalid = bvalid;
assign uart_bvalid = bvalid;
assign bready = sel_wt[0] ? dc_bready : sel_wt[1] ? uart_bready : sel_wt[2] ? 1'b0 : 1'b0;
assign dc_bid = bid;
assign uart_bid = bid;
assign dc_bcomp = bcomp;
assign uart_bcomp = bcomp;
// read request
assign arvalid =  sel_rd[0] ? dc_arvalid : sel_rd[1] ? uart_arvalid :  sel_rd[2] ? 1'b0 : 1'b0;
assign dc_arready = arready;
assign uart_arready = arready;
assign arid = sel_rd[0] ? dc_arid : sel_rd[1] ? uart_arid : sel_rd[2] ? 4'd0 : 4'd0;
assign araddr = sel_rd[0] ? dc_araddr : sel_rd[1] ? uart_araddr : sel_rd[2] ? 1'b0 : 1'b0;
    // read data
assign dc_rvalid = rvalid;
assign uart_rvalid = rvalid;
assign rready = sel_rd[0] ? dc_rready : sel_rd[1] ? uart_rready : sel_rd[2] ? 1'b0 : 1'b0;
assign dc_rid = rid;
assign uart_rid = rid;
assign dc_rdata = rdata;
assign uart_rdata = rdata;
assign dc_rlast = rlast;
assign uart_rlast = rlast;

// arbitors
arbitor3 write_arb (
	.clk(clk),
	.rst_n(rst_n),
	.req0(dc_req_wt),
	.req1(uart_req_wt),
	.req2(1'b0),
	.gnt0(dc_gnt_wt),
	.gnt1(uart_gnt_wt),
	.gnt2(gnt2_wt),
	.sel(sel_wt),
	.finish0(dc_finish_wresp),
	.finish1(uart_finish_wresp),
	.finish2(1'b0)
	);

arbitor3 read_arb (
	.clk(clk),
	.rst_n(rst_n),
	.req0(dc_req_rd),
	.req1(uart_req_rd),
	.req2(1'b0),
	.gnt0(dc_gnt_rd),
	.gnt1(uart_gnt_rd),
	.gnt2(gnt2_rd),
	.sel(sel_rd),
	.finish0(dc_finish_mrd),
	.finish1(uart_finish_mrd),
	.finish2(1'b0)
	);

endmodule
