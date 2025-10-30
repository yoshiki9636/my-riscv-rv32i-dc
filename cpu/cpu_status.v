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

	// I$ stall
	input ic_stall,
	// D$ stall
	input dc_stall,
	// from control
	input init_calib_complete,
	input cpu_start,
	input [31:2] start_adr,
	input quit_cmd,
	output reg cpu_run_state,
	// to CPU
	output pc_start,
	output reg [31:2] start_adr_lat,
	output pc_valid_id,
	output cpu_stopping,
	output stall,
	output stall_ex,
	output stall_ma,
	output stall_wb,
	output stall_1shot,
	output stall_1shot_dly,
	output reg stall_dly,
	output reg stall_dly2,
	output reg rst_pipe,
	output reg rst_pipe_id,
	output reg rst_pipe_ex,
	output reg rst_pipe_ma,
	output reg rst_pipe_wb
	);

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		start_adr_lat <= 30'd0;
	else if ( cpu_start )
		start_adr_lat <= start_adr;
end

// quit_cmd -> finish
reg [2:8] cpu_stopping_cntr;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		cpu_stopping_cntr <= 3'd0;
	else if (~init_calib_complete)
		cpu_stopping_cntr <= 3'd0;	
	else if (quit_cmd)
		cpu_stopping_cntr <= 3'd7;	
	else if (cpu_stopping_cntr == 3'd0)
		cpu_stopping_cntr <= 3'd0;	
	else if (~dc_stall)
		cpu_stopping_cntr <= cpu_stopping_cntr - 3'd1;
end

assign cpu_stopping = (cpu_stopping_cntr != 3'd0);


//reg cpu_run_state;
reg cpu_run_state_lat;
reg cpu_start_lat;

assign pc_valid_id = cpu_run_state_lat;

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
		cpu_run_state_lat <= 1'b0;
	else
		cpu_run_state_lat <= cpu_run_state;
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

//assign pc_start = init_calib_complete & ((cpu_run_state & ~cpu_run_state_lat) | cpu_start_lat);
assign pc_start = init_calib_complete & cpu_run_state & ~cpu_run_state_lat;


//wire cpu_running = cpu_run_state; 

// stall signal : currently controlled by outside
// add lsu stall
reg stall_dly3;

assign stall = ~cpu_run_state | dc_stall;
//assign stall = ~cpu_run_state | ic_stall | dc_stall;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        stall_dly <= 1'b1 ;
        stall_dly2 <= 1'b1 ;
        stall_dly3 <= 1'b1 ;
	end
	else begin
		stall_dly <= stall;
		stall_dly2 <= stall_dly;
		stall_dly3 <= stall_dly2;
	end
end

//assign stall_ex = stall & stall_dly;
assign stall_ex = stall | stall_dly;
//assign stall_ma = stall_dly & stall;
//assign stall_wb = stall_dly2 & stall_dly;
assign stall_ma = stall_dly2 & stall;
assign stall_wb = stall_dly3 & stall_dly;

assign stall_1shot = stall & ~stall_dly;
assign stall_1shot_dly = stall_dly & ~stall_dly2;

// pipeline reset signal

wire start_reset = 1'b0;
//wire start_reset = cpu_start & ~cpu_run_state;
wire end_reset = 1'b0;
//wire end_reset = quit_cmd & cpu_run_state;


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
