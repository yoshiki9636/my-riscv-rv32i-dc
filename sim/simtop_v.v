/*
 * My RISC-V RV32I CPU
 *   Verilog Simulation Top Module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */
`timescale 1ns / 1ps

module simtop;

reg clkin;
reg rst_n;
wire rx = 1'b0;
wire tx;
reg interrupt_0;
wire [2:0] rgb_led;
wire [2:0] rgb_led1;
wire [2:0] rgb_led2;
wire [2:0] rgb_led3;

wire ck; // input
wire ck_n; // input
wire cke; // input
wire cs_n; // input
wire ras_n; // input
wire cas_n; // input
wire we_n; // input
wire [1:0] dm_tdqs; // inout
wire [2:0] ba; // input
wire [13:0] addr; // input
wire [15:0] dq; // inout
wire [1:0] dqs; // inout
wire [1:0] dqs_n; // inout
wire [1:0] tdqs_n; // output
wire odt; // input
wire ddr3_reset_n; // output

//wire [0:0] ddr3_odt; // output
fpga_top fpga_top (
	.clkin(clkin),
	.rst_n(rst_n),
	.rx(rx),
	.tx(tx),
	.interrupt_0(interrupt_0),
	.rgb_led(rgb_led),
	.rgb_led1(rgb_led1),
	.rgb_led2(rgb_led2),
	.rgb_led3(rgb_led3),

	.ddr3_dq(dq),
	.ddr3_dqs_n(dqs_n),
	.ddr3_dqs_p(dqs),
	.ddr3_addr(addr),
	.ddr3_ba(ba),
	.ddr3_ras_n(ras_n),
	.ddr3_cas_n(cas_n),
	.ddr3_we_n(we_n),
	.ddr3_reset_n(ddr3_reset_n),
	.ddr3_ck_p(ck),
	.ddr3_ck_n(ck_n),
	.ddr3_cke(cke),
	.ddr3_cs_n(cs_n),
	.ddr3_dm(dm_tdqs),
	.ddr3_odt(odt)
	);

ddr3_model ddr3_model (
	.rst_n(ddr3_reset_n),
	.ck(ck),
	.ck_n(ck_n),
	.cke(cke),
	.cs_n(cs_n),
	.ras_n(ras_n),
	.cas_n(cas_n),
	.we_n(we_n),
	.dm_tdqs(dm_tdqs),
	.ba(ba),
	.addr(addr),
	.dq(dq),
	.dqs(dqs),
	.dqs_n(dqs_n),
	.tdqs_n(tdqs_n),
	.odt(odt)
	);

//initial $readmemh("./test.txt", fpga_top.cpu_top.if_stage.inst_1r1w.ram);
//initial $readmemh("./test0.txt", fpga_top.cpu_top.ma_stage.data_1r1w.ram0);
//initial $readmemh("./test1.txt", fpga_top.cpu_top.ma_stage.data_1r1w.ram1);
//initial $readmemh("./test2.txt", fpga_top.cpu_top.ma_stage.data_1r1w.ram2);
//initial $readmemh("./test3.txt", fpga_top.cpu_top.ma_stage.data_1r1w.ram3);

initial clkin = 0;

always #5.0 clkin <= ~clkin;

integer file_out;

initial file_out = $fopen("./instfilelog.txt", "w");

always @ ( posedge fpga_top.cpu_top.clk ) begin
    if (~(fpga_top.cpu_top.if_stage.ic_stall) & ~(fpga_top.cpu_top.if_stage.ic_stall_dly) & ~(fpga_top.cpu_top.if_stage.stall) & ~(fpga_top.cpu_top.if_stage.stall_ld) & ~(fpga_top.cpu_top.if_stage.jmp_cond) & ~(fpga_top.cpu_top.if_stage.post_jump_cmd_c) ) begin
        $display("instlog: %h",fpga_top.cpu_top.if_stage.pc_id * 4," , %h",fpga_top.cpu_top.if_stage.inst_id);
        $fdisplay(file_out,"instlog: %h",fpga_top.cpu_top.if_stage.pc_id * 4," , %h",fpga_top.cpu_top.if_stage.inst_id);
    end
end


initial begin
	force fpga_top.cpu_start = 1'b0;
	rst_n = 1'b1;
	interrupt_0 = 1'b0;
#10
	rst_n = 1'b0;
#500
	rst_n = 1'b1;
#15000
#10
	force fpga_top.cpu_start = 1'b1;
    force fpga_top.start_adr = 30'h00000400; // 0x1000 for C
    //force fpga_top.start_adr = 30'h00000040; // 0x100 for asm
#50
	force fpga_top.cpu_start = 1'b0;
//#500000
	//$stop;
end



endmodule
