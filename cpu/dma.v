/*
 * My RISC-V RV32I CPU
 *   Tiny DMA Module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2023 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module dma
	#(parameter SWIDTH = 13)
	(
	input clk,
	input rst_n,

	// from io_rw block
	input dma_io_we,
	input [15:2] dma_io_wadr,
	input [31:0] dma_io_wdata,
	input [15:2] dma_io_radr,
	input dma_io_radr_en,
	input [31:0] dma_io_rdata_in,
	output [31:0] dma_io_rdata,
	// from/to MA

	// from/to dma scrach memory access interface
	output [SWIDTH-3:0] scr_ram_radr_all,
	input [127:0] scr_ram_rdata_all,
	output scr_ram_ren_all,
	output [SWIDTH-3:0] scr_ram_wadr_all,
	output [127:0] scr_ram_wdata_all,
	output scr_ram_wen_all,

	// dma axi write bus manager
	output dma_wstart_rq,
	output [31:0] dma_win_addr,
	output [127:0] dma_in_wdata,
	output [15:0] dma_in_mask,
	input dma_finish_wresp,
	// dma axi read bus manager
	output dma_rstart_rq,
	output [31:0] dma_rin_addr,
	input [127:0] dma_rdat_m_data,
	input [15:0] dma_rdat_m_mask,
	input dma_rdat_m_valid,
	input dma_finish_mrd


	//output dma_we_ma,
	//output [15:2] dataram_wadr_ma,
	//output [15:0] dataram_wdata_ma,
	//output dma_re_ma,
	//output [15:2] dataram_radr_ma,
	//input [15:0] dataram_rdata_wb,

	// form/to io bus part
    //output ibus_ren,
    //output [19:2] ibus_radr,
    //input [15:0] ibus32_rdata,
    //output ibus_wen,
    //output [19:2] ibus_wadr,
    //output reg [15:0] ibus32_wdata,

	// reset pipe
	//input rst_pipe

	);

// address register
// 0xc000_e000 -
`define SYS_DMA_START 14'h3800
`define SYS_DMA_SCSTR 14'h3801
`define SYS_DMA_MESTR 14'h3802
`define SYS_DMA_DCNTR 14'h3803

// read decoder
wire status_re_pre = dma_io_radr_en & (dma_io_radr == `SYS_DMA_START);
wire scr_start_adr_re_pre = dma_io_radr_en & (dma_io_radr == `SYS_DMA_SCSTR);
wire mem_start_adr_re_pre = dma_io_radr_en & (dma_io_radr == `SYS_DMA_MESTR);
wire dcntr_re_pre = dma_io_radr_en & (dma_io_radr == `SYS_DMA_DCNTR);

reg status_re;
reg scr_start_adr_re;
reg mem_start_adr_re;
reg dcntr_re;

wire read_run;
wire write_run;
reg [SWIDTH+1:4] scr_start_adr;
reg [31:4] mem_start_adr;
reg [SWIDTH-3:0] dcntr;
//reg [SWIDTH-2:0] btb_cntr;

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
        status_re <= 1'b0;
        scr_start_adr_re <= 1'b0;
        mem_start_adr_re <= 1'b0;
        dcntr_re <= 1'b0;
	end
	else begin
        status_re <= status_re_pre;
        scr_start_adr_re <= scr_start_adr_re_pre;
        mem_start_adr_re <= mem_start_adr_re_pre;
        dcntr_re <= dcntr_re_pre;
	end
end

assign dma_io_rdata = status_re ? { 16'd0, 14'd0, write_run, read_run } :
					  scr_start_adr_re ? { { 28-SWIDTH{1'b0}}, scr_start_adr, 4'd0 } :
					  mem_start_adr_re ? { mem_start_adr, 4'd0 } :
					  dcntr_re ? {  { 31-SWIDTH{1'b0}}, dcntr } : dma_io_rdata_in;

// write decoder
// inhibit to write 2'b11 to start regster 
wire read_start_we  = dma_io_we & (dma_io_wadr == `SYS_DMA_START) & ~dma_io_wdata[1] &  dma_io_wdata[0];
wire write_start_we = dma_io_we & (dma_io_wadr == `SYS_DMA_START) &  dma_io_wdata[1] & ~dma_io_wdata[0];
wire scr_start_adr_we  = dma_io_we & (dma_io_wadr == `SYS_DMA_SCSTR);
wire mem_start_adr_we  = dma_io_we & (dma_io_wadr == `SYS_DMA_MESTR);
wire dcntr_we  = dma_io_we & (dma_io_wadr == `SYS_DMA_DCNTR);

// registers

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n)
        scr_start_adr <= { SWIDTH-2{ 1'b0 }};
	else if (scr_start_adr_we)
        scr_start_adr <= dma_io_wdata[SWIDTH+1:4];
end	

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n)
        mem_start_adr <= 28'd0;
	else if (mem_start_adr_we)
        mem_start_adr <= dma_io_wdata[31:4];
end

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n)
        dcntr <= { SWIDTH-2{ 1'b0 }};
	else if (dcntr_we)
		dcntr <= dma_io_wdata[SWIDTH-3:0];
end

// scr_mem dma state machine
`define DMAM_IDLE  3'b000
`define DMAM_RDMRQ 3'b001
`define DMAM_RDMEM 3'b010
`define DMAM_WTSCR 3'b011
`define DMAM_R1SCR 3'b100
`define DMAM_R2SCR 3'b101
`define DMAM_WTMRQ 3'b110
`define DMAM_WTMEM 3'b111

reg [2:0] scr_mem_ma_state_current;
wire final_cycle;

function [2:0] scr_mem_ma_state;
input [2:0] scr_mem_ma_state_current;
input read_start_we;
input write_start_we;
input dma_finish_wresp;
input dma_rdat_m_valid;
input final_cycle;
begin
	case(scr_mem_ma_state_current)
		`DMAM_IDLE: begin
			casez({read_start_we, write_start_we})
				2'b1?: scr_mem_ma_state = `DMAM_RDMRQ;
				2'b01: scr_mem_ma_state = `DMAM_R1SCR;
				2'b00: scr_mem_ma_state = `DMAM_IDLE;
				default: scr_mem_ma_state = `DMAM_IDLE;
			endcase
		end
		// mem->scr read DMA
		`DMAM_RDMRQ: begin
			scr_mem_ma_state = `DMAM_RDMEM;
		end
		`DMAM_RDMEM: begin
			if (dma_rdat_m_valid) scr_mem_ma_state = `DMAM_WTSCR;
			else scr_mem_ma_state = `DMAM_RDMEM;
		end
		`DMAM_WTSCR: begin
			if (final_cycle) scr_mem_ma_state = `DMAM_IDLE;
			else scr_mem_ma_state = `DMAM_RDMRQ;
		end
		// scr->mem write DMA
		`DMAM_R1SCR: begin
			scr_mem_ma_state = `DMAM_R2SCR;
		end
		`DMAM_R2SCR: begin
			scr_mem_ma_state = `DMAM_WTMRQ;
		end
		`DMAM_WTMRQ: begin
			scr_mem_ma_state = `DMAM_WTMEM;
		end
		`DMAM_WTMEM: begin
			casez({dma_finish_wresp, final_cycle})
				2'b11: scr_mem_ma_state = `DMAM_IDLE;
				2'b10: scr_mem_ma_state = `DMAM_R1SCR;
				2'b0?: scr_mem_ma_state = `DMAM_WTMEM;
				default: scr_mem_ma_state = `DMAM_IDLE;
			endcase
		end
		default: scr_mem_ma_state = `DMAM_IDLE;
	endcase
end
endfunction

wire [2:0] scr_mem_ma_state_next = scr_mem_ma_state( scr_mem_ma_state_current,
                                                     read_start_we,
                                                     write_start_we,
                                                     dma_finish_wresp,
                                                     dma_rdat_m_valid,
                                                     final_cycle );

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		scr_mem_ma_state_current <= `DMAM_IDLE;
	else
		scr_mem_ma_state_current <= scr_mem_ma_state_next;
end

// control signals
reg [SWIDTH-3:0] trans_cntr;

wire trans_cnt_down = (scr_mem_ma_state_current == `DMAM_WTSCR) | ((scr_mem_ma_state_current == `DMAM_WTMEM) & dma_finish_wresp);
wire bbwt_from_mem = (scr_mem_ma_state_current == `DMAM_RDMEM) & dma_rdat_m_valid;
wire bbwt_from_scr = (scr_mem_ma_state_current == `DMAM_R2SCR);

assign final_cycle = (trans_cntr == { {SWIDTH-3{ 1'b0 }}, 1'b1});
assign read_run = (scr_mem_ma_state_current == `DMAM_RDMRQ)|(scr_mem_ma_state_current == `DMAM_RDMEM)|(scr_mem_ma_state_current == `DMAM_WTSCR);
assign write_run = (scr_mem_ma_state_current == `DMAM_R1SCR)|(scr_mem_ma_state_current == `DMAM_R2SCR)|(scr_mem_ma_state_current == `DMAM_WTMRQ)|(scr_mem_ma_state_current == `DMAM_WTMEM);

// scr address counter
reg [SWIDTH-3:0] scr_adr;
always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n)
        scr_adr <= { SWIDTH-3{ 1'b0 }};
	else if (read_start_we|write_start_we)
        scr_adr <= scr_start_adr;
	else if (trans_cnt_down)
        scr_adr <= scr_adr + { {SWIDTH-4{ 1'b0 }}, 1'b1};
end

// mem address counter
reg [31:4] mem_adr;
always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n)
        mem_adr <= 28'd0;
	else if (read_start_we|write_start_we)
        mem_adr <= mem_start_adr;
	else if (trans_cnt_down)
        mem_adr <= mem_adr + 30'd1;
end

// transfer counter
always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n)
		trans_cntr <= { SWIDTH-2{ 1'b0 }};
	else if (read_start_we|write_start_we)
		trans_cntr <= dcntr;
	else if ((trans_cnt_down)&(trans_cntr > { SWIDTH-2{ 1'b0 }}))
		trans_cntr <= trans_cntr - { {SWIDTH-3{ 1'b0 }}, 1'b1};
end

// bus bridge FF
reg [127:0] busbridge;
always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n)
		busbridge <= 128'd0;
	else if (bbwt_from_mem)
		busbridge <= dma_rdat_m_data;
	else if (bbwt_from_scr)
		busbridge <= scr_ram_rdata_all;
end

// bus signals
// to scrach memory

assign scr_ram_radr_all = scr_adr;
assign scr_ram_ren_all = (scr_mem_ma_state_current == `DMAM_R1SCR);
assign scr_ram_wadr_all = scr_adr;
assign scr_ram_wdata_all = busbridge;
assign scr_ram_wen_all = (scr_mem_ma_state_current == `DMAM_WTSCR);

// to SDRAM

// dma axi write bus manager

assign dma_wstart_rq = (scr_mem_ma_state_current == `DMAM_WTMRQ);
assign dma_win_addr = { mem_adr, 4'b0 };
assign dma_in_wdata = busbridge;
assign dma_in_mask = 16'h0000;

// dma axi read bus manager

assign dma_rstart_rq = (scr_mem_ma_state_current == `DMAM_RDMRQ);
assign dma_rin_addr = { mem_adr, 4'b0 };


endmodule
