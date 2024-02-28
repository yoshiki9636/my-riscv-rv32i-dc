/*
 * My RISC-V RV32I CPU
 *   CPU Status Module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module cpu_status(
	input clk,
	input rst_n,

	// D$ stall
	input dc_stall,
	// from control
	input init_calib_complete,
	input cpu_start,
	input quit_cmd,
	// to CPU
	output stall,
	output stall_ex,
	output stall_ma,
	output stall_wb,
	output stall_1shot,
	output stall_fin,
	output stall_fin2,
	output reg stall_dly,
	output reg rst_pipe,
	output reg rst_pipe_id,
	output reg rst_pipe_ex,
	output reg rst_pipe_ma,
	output reg rst_pipe_wb
	);

reg cpu_run_state;
reg cpu_start_lat;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		cpu_run_state <= 1'b0;
	else if (quit_cmd)
		cpu_run_state <= 1'b0;	
	else if (~init_calib_complete)
		cpu_run_state <= 1'b0;	
	else if (cpu_start)
		cpu_run_state <= 1'b1;
	else if (cpu_start_lat)
		cpu_run_state <= 1'b1;
end

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		cpu_start_lat <= 1'b0;
	else if (quit_cmd)
		cpu_start_lat <= 1'b0;
	else if (cpu_run_state)
		cpu_start_lat <= 1'b0;
	else if (~init_calib_complete & cpu_start)
		cpu_start_lat <= 1'b1;
end

//wire cpu_running = cpu_run_state; 

// stall signal : currently controlled by outside
// add lsu stall
reg stall_dly2;
reg stall_dly3;
reg stall_dly4;

assign stall = ~cpu_run_state | dc_stall;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        stall_dly <= 1'b1 ;
        stall_dly2 <= 1'b1 ;
        stall_dly3 <= 1'b1 ;
        stall_dly4 <= 1'b1 ;
	end
	else begin
		stall_dly <= stall;
		stall_dly2 <= stall_dly;
		stall_dly3 <= stall_dly2;
		stall_dly4 <= stall_dly3;
	end
end

assign stall_ex = stall_dly;
assign stall_ma = stall_dly2;
assign stall_wb = stall_dly3;

assign stall_1shot = stall & ~stall_dly;

assign stall_fin = ~stall & stall_dly;
assign stall_fin2 = ~stall_dly & stall_dly2;

// pipeline reset signal

wire start_reset = cpu_start & ~cpu_run_state;
wire end_reset = quit_cmd & cpu_run_state;


always @ (posedge clk or negedge rst_n) begin
    if (~rst_n)
        rst_pipe <= 1'b0 ;
	else
		rst_pipe <= start_reset | end_reset;
end

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        rst_pipe_id <= 1'b0 ;
        rst_pipe_ex <= 1'b0 ;
        rst_pipe_ma <= 1'b0 ;
        rst_pipe_wb <= 1'b0 ;
	end
	else begin
        rst_pipe_id <= rst_pipe;
        rst_pipe_ex <= rst_pipe_id;
        rst_pipe_ma <= rst_pipe_ex;
        rst_pipe_wb <= rst_pipe_ma;
	end
end

endmodule
