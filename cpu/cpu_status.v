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
	// FPGA (2026-09-07): fires one cycle after cpu_start falls (i.e. the
	// cycle cmd_jal_ex/cmd_jalr_ex/cmd_br_ex would otherwise reload from
	// whatever jump/branch instruction was frozen in ID at the moment the
	// CPU was quit-stopped mid a tight self-loop like `j .` - restarting
	// via monitor g<addr> after such a stop was observed to silently
	// re-jump back to the old halt address instead of the new one. See
	// id_stage.v's use of this signal.
	output jmp_regs_flush,
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
reg [2:0] cpu_stopping_cntr;

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

// negedge-of-cpu_start detector, synchronous (cpu_start is a UART-monitor
// one-shot pulse in the clk domain already, not a separate clock/reset -
// detect its fall the normal way, not via `negedge cpu_start` sensitivity).
reg cpu_start_dly;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		cpu_start_dly <= 1'b0;
	else
		cpu_start_dly <= cpu_start;
end
assign jmp_regs_flush = cpu_start_dly & ~cpu_start;


//wire cpu_running = cpu_run_state; 

// stall signal : currently controlled by outside
// add lsu stall
reg stall_dly3;

assign stall = ~cpu_run_state | dc_stall;
//assign stall = ~cpu_run_state | ic_stall | dc_stall;

// FPGA (2026-09-15, ILA diagnostic, see project memory
// project_slub_debug_u_axi_hang): dc_stall_stuck_cntr (lsu_stage.v) read
// back as 0 during a confirmed real-hardware hang (PC frozen, pc_hang_probe
// confirmed) - i.e. dc_stall itself is NOT what's holding the pipeline at
// that sample point. `stall = ~cpu_run_state | dc_stall`, so if dc_stall
// is 0 while the CPU is still frozen, cpu_run_state must be 0 - meaning
// something dropped either quit_cmd (the external monitor's manual halt -
// should never assert on its own during an unattended boot) or
// init_calib_complete (the vendor MIG's DDR-calibration-done signal - not
// expected to ever fall after initial power-up calibration, but is
// completely opaque vendor-IP-internal state, same blind spot as the
// DRAM-bank-conflict hypothesis this investigation has been circling).
// Catch whichever one it is directly: trigger on cpu_run_state's falling
// edge after having been running.
reg dbg_cpu_run_state_dly;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		dbg_cpu_run_state_dly <= 1'b0;
	else
		dbg_cpu_run_state_dly <= cpu_run_state;
end
(* mark_debug = "true" *) wire dbg_cpu_run_state_fell = dbg_cpu_run_state_dly & ~cpu_run_state;
(* mark_debug = "true" *) wire dbg_cpu_run_state_ila = cpu_run_state;
(* mark_debug = "true" *) wire dbg_init_calib_complete_ila = init_calib_complete;
(* mark_debug = "true" *) wire dbg_quit_cmd_ila = quit_cmd;
(* mark_debug = "true" *) wire dbg_stall_ila = stall;
(* mark_debug = "true" *) wire dbg_dc_stall_top_ila = dc_stall;
(* mark_debug = "true" *) wire dbg_ic_stall_top_ila = ic_stall;

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
        rst_pipe <= 1'b1 ;
	else if ( cpu_start )
		rst_pipe <= 1'b0;
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
