/*
 * My RISC-V RV32I CPU
 *   dram mig interface
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module mig_if (
	// mig ingerface
	input mclk, // not used
	input mrst_n, // not used
	// address/command
	output [27:0] app_addr,
	output [2:0] app_cmd, //
	output app_en,
	input app_rdy,
	// write data
	output [127:0] app_wdf_data,
	output [15:0] app_wdf_mask,
	output app_wdf_wren,
	output app_wdf_end,
	input app_wdf_rdy,
	// read data
	input [127:0] app_rd_data,
	input app_rd_data_end,
	input app_rd_data_valid,

	// req
	output req_rnext,
	input req_rqempty,
	input [31:0] req_qraddr,
	input req_rd_bwt,
	// wdq
	output wdq_rnext,
	input wdq_rqempty,
	input [143:0] wdq_mask_rdata,
	// rdq
	output rdq_wen,
	output [127:0] rdq_wdata

	);

// MIG interface
//reg req_rd_bwt_lat;
//always @ (posedge mclk or negedge mrst_n) begin
    //if (~mrst_n)
        //req_rd_bwt_lat  <= 1'd0;
    //else if (req_rnext)
        //req_rd_bwt_lat  <= req_rd_bwt;
//end

// request
//assign app_addr = req_qraddr [27:0] ;
wire [27:0] r_app_addr = {1'b0, req_qraddr[27:4], 3'b000} ;
wire [2:0] r_app_cmd = { 2'b00, req_rd_bwt };
wire r_app_en = ~req_rqempty & req_rd_bwt;

reg app_wreq_stock;
always @ (posedge mclk or negedge mrst_n) begin
    if (~mrst_n)
        app_wreq_stock  <= 1'd0;
    else if (req_rnext)
        app_wreq_stock  <= 1'd0;
    else if (~req_rqempty & ~req_rd_bwt & ~app_wdf_wren) // write req coming before app_wdf_wren
        app_wreq_stock  <= 1'b1;
end

reg [27:4] waddr_lat;
always @ (posedge mclk or negedge mrst_n) begin
    if (~mrst_n)
        waddr_lat  <= 24'd0;
    else if (~req_rqempty & ~req_rd_bwt & ~app_wdf_wren) // write req coming before app_wdf_wren
        waddr_lat  <= req_qraddr[27:4];
end

//wire w_app_addr = app_wreq_stock ? {1'b0, waddr_lat, 3'b000} : {1'b0, req_qraddr[27:4], 3'b000} ;
wire [27:0] w_app_addr = {1'b0, req_qraddr[27:4], 3'b000} ;
//wire [27:0] w_app_addr = {waddr_lat, 3'b000};
wire [2:0] w_app_cmd = 3'b000; // app_wreq_stock ? 3'b000 : { 2'b00, req_rd_bwt };
//wire w_app_en_pre = ((~req_rqempty & ~req_rd_bwt) | app_wreq_stock);
wire w_app_en_pre = ~req_rqempty & ~req_rd_bwt;
wire w_app_en = w_app_en_pre & ~wdq_rqempty & app_wdf_rdy;

//assign app_addr = app_wreq_stock ? w_app_addr : r_app_addr;
assign app_addr = r_app_addr;
//assign app_cmd = app_wreq_stock ? w_app_cmd : r_app_cmd;
assign app_cmd = r_app_cmd;
assign app_en = w_app_en | r_app_en;

assign req_rnext = (r_app_en | (w_app_en & app_wdf_wren & app_wdf_rdy)) & app_rdy;

// write data
assign app_wdf_data = wdq_mask_rdata[127:0];
assign app_wdf_mask = wdq_mask_rdata[143:128];
assign app_wdf_wren = ~wdq_rqempty & w_app_en_pre & app_rdy; 
assign app_wdf_end = app_wdf_wren; // data 128bit only

assign wdq_rnext = app_wdf_wren & app_wdf_rdy & w_app_en & app_rdy;

// read data
assign rdq_wen = app_rd_data_valid;
assign rdq_wdata = app_rd_data;

endmodule
