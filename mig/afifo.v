/*
 * My RISC-V RV32I CPU
 *   async fido
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2024 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module afifo
	#(parameter AFIFODW = 32)
	(
	input wclk,
	input wrst_n,
	input rclk,
	input rrst_n,

    input wen,
	output wqfull,
    input [AFIFODW-1:0] wdata,
    input rnext,
	output rqempty,
    output [AFIFODW-1:0] rdata
	);

reg [1:0] wadr;
reg [1:0] radr;

afifo_1r1w #(.AFIFODW(AFIFODW)) afifo_1r1w (
	.iclk(wclk),
	.oclk(rclk),
	.ram_radr(radr),
	.ram_rdata(rdata),
	.ram_wadr(wadr),
	.ram_wdata(wdata),
	.ram_wen(wen)
	);

always @ (posedge wclk or negedge wrst_n) begin
	if (~wrst_n)
		wadr  <= 2'd0;
	else if (wen)
		wadr  <= wadr + 2'd1;
end

wire [1:0] gwadr = { wadr[1], wadr[1] ^ wadr[0] };

reg [1:0] gwadr_l0;
reg [1:0] gwadr_l1;
reg [1:0] gwadr_l2;
reg [1:0] gwadr_l15;

always @ (posedge wclk or negedge wrst_n) begin
	if (~wrst_n)
		gwadr_l0  <= 2'd0;
	else
		gwadr_l0  <= gwadr;
end

// double latch for meta-stable
//  -> triple latch
always @ (posedge rclk or negedge rrst_n) begin
	if (~rrst_n) begin
		gwadr_l1  <= 2'd0;
		gwadr_l15  <= 2'd0;
		gwadr_l2  <= 2'd0;
	end
	else begin
		gwadr_l1  <= gwadr_l0;
		gwadr_l15  <= gwadr_l1;
		gwadr_l2  <= gwadr_l15;
	end
end

wire [1:0] bwadr = { gwadr_l2[1], gwadr_l2[1] ^ gwadr_l2[0] } ;

always @ (posedge rclk or negedge rrst_n) begin
	if (~rrst_n)
		radr  <= 2'd0;
	else if (rnext)
		radr  <= radr + 2'd1;
end

wire [1:0] gradr = { radr[1], radr[1] ^ radr[0] } ;

reg [1:0] gradr_l0;
reg [1:0] gradr_l1;
reg [1:0] gradr_l2;
reg [1:0] gradr_l15;

always @ (posedge rclk or negedge rrst_n) begin
	if (~rrst_n)
		gradr_l0  <= 2'd0;
	else
		gradr_l0  <= gradr;
end

// double latch for meta-stable
//  -> triple latch
always @ (posedge wclk or negedge wrst_n) begin
	if (~wrst_n) begin
		gradr_l1  <= 2'd0;
		gradr_l15  <= 2'd0;
		gradr_l2  <= 2'd0;
	end
	else begin
		gradr_l1  <= gradr_l0;
		gradr_l15  <= gradr_l1;
		gradr_l2  <= gradr_l15;
	end
end

wire [1:0] bradr = { gradr_l2[1], gradr_l2[1] ^ gradr_l2[0] } ;

// qfull checker
wire fwg = (wadr > bradr);
wire frg = (wadr < bradr);

//wire wqfull_0 = (wadr == bradr);
//wire wqfull_1 = (wg&(wadr - bradr == 2'd1))|(rg&(bradr - wadr <= 2'd3));
wire wqfull_2 = (fwg&(wadr - bradr == 2'd2))|(frg&(bradr - wadr <= 2'd2));
wire wqfull_3 = (fwg&(wadr - bradr == 2'd3))|(frg&(bradr - wadr <= 2'd1));
assign wqfull = wqfull_2 | wqfull_3 ;

// qempty checker
assign rqempty = (bwadr == radr);

endmodule
