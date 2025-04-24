/*
 * My RISC-V RV32I CPU
 *   Verilog Simulation Top Module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

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

fpga_top fpga_top (
        .clkin(clkin),
        .rst_n(rst_n),
		.rx(rx),
        .tx(tx),
		.interrupt_0(interrupt_0),
        .rgb_led(rgb_led),
        .rgb_led1(rgb_led1),
        .rgb_led2(rgb_led2),
        .rgb_led3(rgb_led3)
	);

//initial $readmemh("./test.txt", fpga_top.cpu_top.if_stage.inst_1r1w.ram);
initial $readmemh("./test_dummy.txt", fpga_top.dummy_mig.sfifo_1r1w.ram);

//initial $readmemh("./test0.txt", fpga_top.cpu_top.ma_stage.data_ram.ram0.ram0);
//initial $readmemh("./test1.txt", fpga_top.cpu_top.ma_stage.data_ram.ram0.ram1);
//initial $readmemh("./test2.txt", fpga_top.cpu_top.ma_stage.data_ram.ram0.ram2);
//initial $readmemh("./test3.txt", fpga_top.cpu_top.ma_stage.data_ram.ram0.ram3);

//initial $readmemh("./test4.txt", fpga_top.cpu_top.ma_stage.data_ram.ram1.ram0);
//initial $readmemh("./test5.txt", fpga_top.cpu_top.ma_stage.data_ram.ram1.ram1);
//initial $readmemh("./test6.txt", fpga_top.cpu_top.ma_stage.data_ram.ram1.ram2);
//initial $readmemh("./test7.txt", fpga_top.cpu_top.ma_stage.data_ram.ram1.ram3);

//initial $readmemh("./test8.txt", fpga_top.cpu_top.ma_stage.data_ram.ram2.ram0);
//initial $readmemh("./test9.txt", fpga_top.cpu_top.ma_stage.data_ram.ram2.ram1);
//initial $readmemh("./testa.txt", fpga_top.cpu_top.ma_stage.data_ram.ram2.ram2);
//initial $readmemh("./testb.txt", fpga_top.cpu_top.ma_stage.data_ram.ram2.ram3);

//initial $readmemh("./testc.txt", fpga_top.cpu_top.ma_stage.data_ram.ram3.ram0);
//initial $readmemh("./testd.txt", fpga_top.cpu_top.ma_stage.data_ram.ram3.ram1);
//initial $readmemh("./teste.txt", fpga_top.cpu_top.ma_stage.data_ram.ram3.ram2);
//initial $readmemh("./testf.txt", fpga_top.cpu_top.ma_stage.data_ram.ram3.ram3);

always @ ( fpga_top.cpu_top.id_stage.rf_2r1w.ram_wdata or fpga_top.cpu_top.id_stage.rf_2r1w.ram_wen ) begin
	if ((fpga_top.cpu_top.id_stage.rf_2r1w.ram_wdata === 32'dx) & fpga_top.cpu_top.id_stage.rf_2r1w.ram_wen ) begin
	//if ((fpga_top.cpu_top.id_stage.rf_2r1w.ram_wdata === 32'dx) ) begin
	//if ((fpga_top.cpu_top.id_stage.rf_2r1w.ram_wdata === 32'd0) ) begin
		//$display("unknown data is written to rf");
		$warning("Unknown data is written to rf");
	end
end

always @ ( fpga_top.cpu_top.ilu_stage.ic_curric_ent_radr_keeper ) begin
	if (fpga_top.cpu_top.ilu_stage.ic_curric_ent_radr_keeper[3:0] === 4'dx) begin
		$warning("Unkown address written to ic_curric_ent_radr_keeper.");
	end
	else if (fpga_top.cpu_top.ilu_stage.ic_curric_ent_radr_keeper[3:0] !== 4'd0) begin
		$warning("Unalined address written to ic_curric_ent_radr_keeper.");
	end
end



initial clkin = 0;

always #5 clkin <= ~clkin;


initial begin
	force fpga_top.cpu_start = 1'b0;
	rst_n = 1'b1;
	interrupt_0 = 1'b0;
#10
	rst_n = 1'b0;
#20
	rst_n = 1'b1;
#10
	force fpga_top.cpu_start = 1'b1;
	//force fpga_top.start_adr = 30'h00000040;
#10
	force fpga_top.cpu_start = 1'b0;
#5000000
	$stop;
end



endmodule
