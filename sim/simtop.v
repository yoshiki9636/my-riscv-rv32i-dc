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
wire [7:0] gpio;
wire spi_sck;
wire [1:0] spi_csn; 
wire spi_mosi;
wire spi_miso = spi_mosi; // loopback test

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
	.gpio(gpio),
	.spi_sck(spi_sck),
	.spi_csn(spi_csn),
	.spi_mosi(spi_mosi),
	.spi_miso(spi_miso)
	);

integer i;
integer j;

initial begin
	for(j = 0; j < 32; j = j + 1)
		fpga_top.cpu_top.id_stage.rf_2r1w.ram[j] = 0;
end

//initial $readmemh("./test.txt", fpga_top.cpu_top.if_stage.inst_1r1w.ram);
initial begin
	for(i = 0; i < 32768; i = i + 1)
		fpga_top.dummy_mig.sfifo_1r1w.ram[i] = 0;
    $readmemh("./test_dummy.txt", fpga_top.dummy_mig.sfifo_1r1w.ram);
end

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

integer file_out;

initial file_out = $fopen("./instfilelog.txt", "w");

always @ ( posedge fpga_top.cpu_top.clk ) begin
    if (~(fpga_top.cpu_top.if_stage.ic_stall) & (fpga_top.cpu_top.if_stage.ic_stall_dly) & ~(fpga_top.cpu_top.if_stage.stall) & ~(fpga_top.cpu_top.if_stage.stall_ld) & ~(fpga_top.cpu_top.if_stage.jmp_cond) & ~(fpga_top.cpu_top.if_stage.post_jump_cmd_c) & (fpga_top.cpu_top.if_stage.jump_under_ic_stall) ) begin
		// nothing to do
    end

    else if (~(fpga_top.cpu_top.if_stage.ic_stall) & (fpga_top.cpu_top.if_stage.ic_stall_dly) & ~(fpga_top.cpu_top.if_stage.stall) & ~(fpga_top.cpu_top.if_stage.stall_ld) & ~(fpga_top.cpu_top.if_stage.jmp_cond) & ~(fpga_top.cpu_top.if_stage.post_jump_cmd_c) & (fpga_top.cpu_top.if_stage.use_collision) ) begin
        $display("instlog: %h",fpga_top.cpu_top.if_stage.pc_id * 4," , %h",fpga_top.cpu_top.if_stage.inst_id);
        $fdisplay(file_out,"instlog: %h",fpga_top.cpu_top.if_stage.pc_id * 4," , %h",fpga_top.cpu_top.if_stage.inst_id);
    end

    else if (~(fpga_top.cpu_top.if_stage.ic_stall) & (fpga_top.cpu_top.if_stage.ic_stall_dly) & ~(fpga_top.cpu_top.if_stage.stall) & ~(fpga_top.cpu_top.if_stage.stall_ld) & ~(fpga_top.cpu_top.if_stage.jmp_cond) & ~(fpga_top.cpu_top.if_stage.post_jump_cmd_c) & (fpga_top.cpu_top.if_stage.dc_fin_after_ic) ) begin
        $display("instlog: %h",fpga_top.cpu_top.if_stage.pc_id * 4," , %h",fpga_top.cpu_top.if_stage.inst_id);
        $fdisplay(file_out,"instlog: %h",fpga_top.cpu_top.if_stage.pc_id * 4," , %h",fpga_top.cpu_top.if_stage.inst_id);
    end
    else if (~(fpga_top.cpu_top.if_stage.ic_stall) & (fpga_top.cpu_top.if_stage.ic_stall_dly) & ~(fpga_top.cpu_top.if_stage.stall) & ~(fpga_top.cpu_top.if_stage.stall_ld) & ~(fpga_top.cpu_top.if_stage.jmp_cond) & ~(fpga_top.cpu_top.if_stage.post_jump_cmd_c) & (fpga_top.cpu_top.if_stage.ic_fin_after_dc) ) begin
        $display("instlog: %h",fpga_top.cpu_top.if_stage.pc_id * 4," , %h",fpga_top.cpu_top.if_stage.inst_id);
        $fdisplay(file_out,"instlog: %h",fpga_top.cpu_top.if_stage.pc_id * 4," , %h",fpga_top.cpu_top.if_stage.inst_id);
    end
    else if (~(fpga_top.cpu_top.if_stage.ic_stall) & (fpga_top.cpu_top.if_stage.ic_stall_dly) & ~(fpga_top.cpu_top.if_stage.stall) & ~(fpga_top.cpu_top.if_stage.stall_ld) & ~(fpga_top.cpu_top.if_stage.jmp_cond) & ~(fpga_top.cpu_top.if_stage.post_jump_cmd_c) &(fpga_top.cpu_top.if_stage.stall_ld_ex_smpl) & (fpga_top.cpu_top.if_stage.ic_stall_fin2) ) begin
        $display("instlog: %h",fpga_top.cpu_top.if_stage.pc_id * 4," , %h",fpga_top.cpu_top.if_stage.inst_id);
        $fdisplay(file_out,"instlog: %h",fpga_top.cpu_top.if_stage.pc_id * 4," , %h",fpga_top.cpu_top.if_stage.inst_id);
    end

    else if (~(fpga_top.cpu_top.if_stage.ic_stall) & (fpga_top.cpu_top.if_stage.ic_stall_dly) & ~(fpga_top.cpu_top.if_stage.stall) & ~(fpga_top.cpu_top.if_stage.stall_ld) & ~(fpga_top.cpu_top.if_stage.jmp_cond) & ~(fpga_top.cpu_top.if_stage.post_jump_cmd_c) & (fpga_top.cpu_top.if_stage.syn_fin) ) begin
		// nothing to do
    end



    else if (~(fpga_top.cpu_top.if_stage.ic_stall) & ~(fpga_top.cpu_top.if_stage.ic_stall_dly) & ~(fpga_top.cpu_top.if_stage.stall) & ~(fpga_top.cpu_top.if_stage.stall_ld) & ~(fpga_top.cpu_top.if_stage.jmp_cond) & ~(fpga_top.cpu_top.if_stage.post_jump_cmd_c) ) begin
        $display("instlog: %h",fpga_top.cpu_top.if_stage.pc_id * 4," , %h",fpga_top.cpu_top.if_stage.inst_id);
        $fdisplay(file_out,"instlog: %h",fpga_top.cpu_top.if_stage.pc_id * 4," , %h",fpga_top.cpu_top.if_stage.inst_id);
    end




end


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
