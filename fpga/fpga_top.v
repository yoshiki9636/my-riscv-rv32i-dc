/*
 * My RISC-V RV32I CPU
 *   FPGA Top Module for Tang Premier
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

//`define TANG_PRIMER
`define ARTY_A7

// 2026-08-09: IWIDTH/DWIDTH shrunk 12->10 (16KB->4KB each) as a deliberate
// bug-hunting lever, not a permanent sizing choice. Hypothesis (user,
// 2026-08-09): the long-running wild-write/wild-jump corruption saga
// (see project_rtl_lab3_dram_review.md / project_pc_jump_trace_logger_rtl.md
// memory) correlates with if_stage.v's cache_miss_current FSM entering its
// "true I$+D$ overlap" states (IDST_ISWD/IDST_DSWI/IDST_SYWB) - notably the
// still-unpatched IDST_ISWD 2'b10 self-loop ("not occured" case that DOES
// occur, see the 2026-07-31 investigation). Shrinking both caches raises
// the per-cycle miss rate and therefore the overlap-state entry rate,
// making this condition (and, if the hypothesis holds, the resulting
// corruption) more frequent/reproducible without changing any functional
// logic. Paired with ic_dc_overlap_monitor.v's hardware counters so the
// effect can be measured quantitatively (entries/dwell cycles), not judged
// only by "crashed sooner". Revert to 12 (16KB) once the experiment is
// done or inconclusive - this is not believed to be the right permanent
// cache size.
//
// 2026-09-07: DWIDTH shrunk further, 12->4 (16KB->64B, 4 lines), IWIDTH
// left at 12 (I$ untouched this time - see below for why). This is
// specifically to run rtl_atomic_test/dcache_random_torture_test.S on
// real hardware: two separate simulation testbenches (lsu_stage_local_tb.v,
// dcache_axi_integration_tb.v - see project_slub_debug_u_axi_hang memory)
// both failed to reproduce a real, confirmed D$ coherence bug (a valid
// line whose tag never matches again after a normal refill) despite heavy
// aliasing/fuzzing/CDC-phase-sweep coverage, so the next attempt is a
// dedicated real-hardware stress program instead of more simulation
// guessing. Unlike the 2026-08-09 IWIDTH+DWIDTH shrink above (done during
// a FULL LINUX BOOT, where a too-small cache was found to trip a
// completely different, earlier bug before ever reaching the one under
// investigation - see project_ic_dc_overlap_monitor memory, "8KB was the
// sweet spot, 4KB was too aggressive"), this test program is D$-only,
// kernel-free, self-checking bare-metal code with no other subsystem to
// fail into - so there is no equivalent risk in going this small, and
// IWIDTH doesn't need to shrink at all since this test's own code/loop
// footprint is tiny and stays cache-hot regardless of I$ size. Revert
// DWIDTH to 12 (or whatever the 2026-08-09 experiment's current value is)
// before resynthesizing anything other than this specific test program.
//
// 2026-09-15: this leftover-4 config got resynthesized into a real
// Linux-boot bitstream by accident, and it hung far earlier than ever seen
// before - inside setup_arch's DRAM self-test loop (0x00457314, a straight
// 1MB write-then-read-back sweep), nowhere near place_entity/kernfs.
// pc_hang_probe's SYS_PHP_EVER (0x00049977) showed dc_stall/dc_tag_miss_ma/
// ic_stall/jump_under_ic_stall all firing together - the same "valid line,
// tag never matches" D$ coherence bug from project_slub_debug_u_axi_hang.
// Initial instinct was to revert this to 12 and move on, but the actual
// goal is finding the RTL bug, not getting further in boot - and this is
// by far the fastest, simplest, most deterministic real-hardware repro of
// that bug found yet (a plain linear 1MB sweep, no OS, no scheduler, no
// interrupts yet, hangs within ~335ms every time) vs. the place_entity
// route which needs a full boot to even get there. Deliberately KEPT at 4
// for now to drive the RTL investigation - do not revert to 12 without
// re-reading this note and project_slub_debug_u_axi_hang's 2026-09-15
// entries first.
module fpga_top
    #(parameter IWIDTH = 12,
      parameter DWIDTH = 4,
      parameter SWIDTH = 13)
    (
	input clkin,
	input rst_n,
	input rx,
	output tx,
	input interrupt_0,
	output [2:0] rgb_led,
	output [2:0] rgb_led1,
	output [2:0] rgb_led2,
	output [2:0] rgb_led3,
	inout [7:0] gpio,
	output spi_sck,
	output [1:0] spi_csn,
	output spi_mosi,
	input spi_miso,

// ddr signal
	inout [15:0] ddr3_dq,
	inout [1:0] ddr3_dqs_n,
	inout [1:0] ddr3_dqs_p,
	output [13:0] ddr3_addr,
	output [2:0] ddr3_ba,
	output ddr3_ras_n,
	output ddr3_cas_n,
	output ddr3_we_n,
	output ddr3_reset_n,
	output [0:0] ddr3_ck_p,
	output [0:0] ddr3_ck_n,
	output [0:0] ddr3_cke,
	output [0:0] ddr3_cs_n,
	output [1:0] ddr3_dm,
	output [0:0] ddr3_odt

	);

wire dma_wstart_rq; // input
wire [31:0] dma_win_addr; // input
wire [127:0] dma_in_wdata; // input
wire [15:0] dma_in_mask; // input
wire dma_finish_wresp; // output
wire dma_rstart_rq; // input
wire [31:0] dma_rin_addr; // input
wire [127:0] dma_rdat_m_data; // output
wire [15:0] dma_rdat_m_mask; // output
wire dma_rdat_m_valid; // output
wire dma_finish_mrd; // output

wire uart_wstart_rq; // input
wire [31:0] uart_win_addr; // input
wire [127:0] uart_in_wdata; // input
wire [15:0] uart_in_mask; // input
wire uart_finish_wresp; // output
wire uart_rstart_rq; // input
wire [31:0] uart_rin_addr; // input
wire [127:0] uart_rdat_m_data; // output
wire [15:0] uart_rdat_m_mask = 16'd0; // output
wire uart_rdat_m_valid; // output
wire uart_finish_mrd; // output

wire dc_wstart_rq; // input
wire [31:0] dc_win_addr; // input
wire [127:0] dc_in_wdata; // input
wire [15:0] dc_in_mask; // input
wire dc_finish_wresp; // output
wire dc_rstart_rq; // input
wire [31:0] dc_rin_addr; // input
wire [127:0] dc_rdat_m_data; // output
wire [15:0] dc_rdat_m_mask; // output
wire dc_rdat_m_valid; // output
wire dc_finish_mrd; // output

wire ic_rstart_rq; // output
wire [31:0] ic_rin_addr; // output
wire [127:0] ic_rdat_m_data; // input
wire [15:0] ic_rdat_m_mask; // input
wire ic_rdat_m_valid; // input
wire ic_finish_mrd; // input
//wire start_icflush; // input

// FPGA (2026-08-27): axi_bus_top debug monitor taps, see
// project_slub_debug_u_axi_hang / icr_start_rq_probe.v
wire ic_req_rd_mon;
wire ic_gnt_rd_mon;
wire ic_arvalid_mon;
wire [3:0] sel_rd_mon;
wire [2:0] ic_rdat_m_current_mon;
wire [3:0] ic_next_rid_lat_mon;
wire rvalid_mon;
wire [3:0] rid_mon;
wire [2:0] ic_miss_current_mon;
wire ic_tag_miss_id_mon;
wire ic_tag_empty_id_mon;
wire [15:0] icr_start_rq_count_mon;
wire [15:0] dcflush_cntr_mon;
wire [15:0] ic_retry_repeat_cntr_mon;
wire [31:0] ic_curric_ent_radr_keeper_mon;

// FPGA (2026-08-27, same session): D$-side mirror of the taps above, see
// lsu_stage.v / axi_bus_top.v / project_slub_debug_u_axi_hang.
wire dc_req_rd_mon;
wire dc_gnt_rd_mon;
wire dc_arvalid_mon;
wire [2:0] dc_rdat_m_current_mon;
wire [3:0] dc_next_rid_lat_mon;
wire [3:0] dc_miss_current_mon;
wire dc_tag_miss_ma_mon;
wire dc_tag_empty_ma_mon;
wire [15:0] dc_retry_repeat_cntr_mon;
wire [31:0] current_radr_keeper_mon;

// axi bus to DRAM
wire awvalid; // output
wire awready; // input
wire [3:0] awid; // output
wire [31:0] awaddr; // output
wire [5:0] awatop; // output
wire wvalid; // output
wire wready; // input
wire [31:0] wdata; // output
wire [3:0] wstrb; // output
wire wlast; // output
wire bvalid; // input
wire bready; // output
wire [3:0] bid; // input
wire bcomp; // input
wire arvalid; // output
wire arready; // input
wire [3:0] arid; // output
wire [31:0] araddr; // output
wire rvalid; // input
wire rready; // output
wire [3:0] rid; // input
wire [31:0] rdata; // input
wire rlast; // input

// mig i/f signals
wire [27:0] app_addr; // output
wire [2:0] app_cmd; // output
wire app_en; // output
wire app_rdy; // input
wire [127:0] app_wdf_data; // output
wire [15:0] app_wdf_mask; // output
wire app_wdf_wren; // output
wire app_wdf_end; // output
wire app_wdf_rdy; // input
wire [127:0] app_rd_data; // input
wire app_rd_data_end; // input
wire app_rd_data_valid; // input

//wire [DWIDTH+1:2] d_ram_radr = { DWIDTH{ 1'b0 }};
//wire [DWIDTH+1:2] d_ram_wadr = { DWIDTH{ 1'b0 }};
//wire [31:0] d_ram_wdata = 32'd0;
wire [SWIDTH+1:2] scr_ram_radr;
wire [SWIDTH+1:2] scr_ram_wadr;
wire [31:0] scr_ram_rdata;
wire [31:0] scr_ram_wdata;
wire scr_ram_wen;
wire scr_read_sel;
//wire d_ram_wen = 1'b0;
//wire d_read_sel = 1'b0;

wire [IWIDTH+1:2] i_ram_radr = 0;
wire [IWIDTH+1:2] i_ram_wadr = 0;
wire [31:0] i_ram_rdata;
wire [31:0] i_ram_wdata = 0;
wire i_ram_wen = 0;
wire i_read_sel = 0;

//wire dma_io_we;
//wire [15:2] dma_io_wadr;
//wire [31:0] dma_io_wdata;
//wire [15:2] dma_io_radr;
//wire dma_io_radr_en;
// io bus for all
wire dma_io_we; // output
wire [15:2] dma_io_wadr; // output
wire [31:0] dma_io_wdata; // output
wire [15:2] dma_io_radr; // output
wire dma_io_radr_en; // output
// io bus for uart
wire dma_io_we_u; // output
wire [15:2] dma_io_wadr_u; // output
wire [31:0] dma_io_wdata_u; // output
wire [15:2] dma_io_radr_u; // output
wire dma_io_radr_en_u; // output

// io bus logics
//wire dma_io_we = dma_io_we_c | dma_io_we_u;
//wire [15:2] dma_io_wadr = dma_io_we_u ? dma_io_wadr_u : dma_io_wadr_c;
//wire [31:0] dma_io_wdata = dma_io_we_u ? dma_io_wdata_u : dma_io_wdata_c;
//wire dma_io_radr_en = dma_io_radr_en_c | dma_io_radr_en_u;
//wire [15:2] dma_io_radr = dma_io_radr_en_u ? dma_io_radr_u : dma_io_radr_c;

wire [31:0] dma_io_rdata_u_fin;
wire [31:0] dma_io_rdata;
wire [31:0] dma_io_rdata_in = 32'hdeadbeef; // input
//wire [31:0] dma_io_rdata_in = 32'd0; // input
wire [31:0] dma_io_rdata_in_2; // input
wire [31:0] dma_io_rdata_in_3; // input
wire [31:0] dma_io_rdata_in_4; // input
wire [31:0] dma_io_rdata_in_5; // input
wire [31:0] dma_io_rdata_in_6; // input
wire [31:0] dma_io_rdata_in_7; // input - dram_top output, feeds ic_dc_overlap_monitor

// pc_ex tap (was for forwarding_hazard_monitor, removed 2026-09-06 for
// timing; pc_ex still feeds ic_dc_overlap_monitor)
wire [31:2] fwdmon_pc_ex;

// ic_dc_overlap_monitor taps (2026-08-09), see ic_dc_overlap_monitor.v.
// Reuses fwdmon_pc_ex above (pc_ex is already tapped out of cpu_top.v) and
// the existing top-level `stall` wire (already fed to io_frc/interrupter)
// for dc_stall - only cache_miss_current/ic_stall need new wires.
wire [3:0] icdcmon_cache_miss_current;
wire icdcmon_ic_stall;

// pc_hang_probe load-use stall-chain taps (2026-09-06), registered in cpu_top.v
wire dbg_stall_ld;
wire dbg_stall_ld_add;
wire dbg_dc_stall;
wire dbg_rst_pipe;
wire dbg_use_collision;
wire dbg_jump_under_ic_stall;
wire dbg_ucp;

// pc_jump_trace_logger cross-wiring removed 2026-09-06 (module removed for
// timing - its scratch-RAM burst write-back kept the dcflush_cntr ->
// scr_ram address mux alive, making dcflush_cntr_reg the repeated Vivado
// WNS startpoint; see cpu_top.v's scratch-RAM port comment).

wire ibus_ren;
wire [19:2] ibus_radr;
wire [15:0] ibus32_rdata = 16'd0;
wire ibus_wen;
wire [19:2] ibus_wadr;
wire [15:0] ibus32_wdata;

// csr monitor bus
wire csr_radr_en_mon; // output
wire [11:0] csr_radr_mon; // output
wire [11:0] csr_wadr_mon; // output
wire csr_we_mon; // output
wire [31:0] csr_wdata_mon; // output
wire [31:0] csr_rdata_mon; // input

// register file monitor bus
wire rf_radr_en_mon; // output
wire [4:0] rf_radr_mon; // output
wire [4:0] rf_wadr_mon; // output
wire rf_we_mon; // output
wire [31:0] rf_wdata_mon; // output
wire [31:0] rf_rdata_mon; // input

wire [31:2] start_adr;
wire cpu_start;
wire quit_cmd;
wire [31:0] pc_data;
// bus i/f logic signals
//wire dcw_start_rq; // output
//wire [31:0] dcw_in_addr; // output
//wire [15:0] dcw_in_mask; // output
//wire [127:0] dcw_in_data; // output
//wire dcw_finish_wresp; // input
//wire dcr_rstart_rq; // output
//wire [31:0] dcr_rin_addr; // output
wire rqfull_1; // output
//wire [127:0] rdat_m_data; // input
//wire rdat_m_valid; // input
//wire finish_mrd; // input
wire start_dcflush;
wire dcflush_running;

wire clk;
//wire mclk = clk;
//wire mclk_not_used;
// for debug
wire tx_fifo_full;
wire tx_fifo_overrun;
wire tx_fifo_underrun;

//wire init_calib_complete = 1'b1;

// for uart output
wire [7:0] uart_io_char;
wire uart_io_we;
wire uart_io_full;
wire rout_en;
wire [7:0] rout;
wire ext_uart_interrpt_1shot;
wire rx_disable_echoback;

`ifdef ARTY_A7
wire locked;
//wire clk_166mhz;
wire clk_200mhz;

 // Instantiation of the clocking network
 //--------------------------------------
  clk_wiz_0 clknetwork
   (
    // Clock out ports
    .clk_out1           (clk_200mhz),
    .clk_out2           (clk),
    //.clk_out2           (clk_166mhz),
    //.clk_out3           (clk),
    //.clk_out2           (clk),

    // Status and control signals
    .reset              (~rst_n),
    .locked             (locked),
   // Clock in ports
    .clk_in1            (clkin)
    );
`endif

wire sys_clk_i = clkin; // input
//wire sys_clk_i = clk_166mhz; // input
wire clk_ref_i = clk_200mhz; // input
wire ui_clk;
wire ui_clk_sync_rst;
//wire mrst_n = rst_n;
wire mclk = ui_clk;
wire mrst_n = ~ui_clk_sync_rst;
//wire mrst_n = rst_n;

// MIG interface
wire app_sr_req = 1'b0; // input
wire app_ref_req = 1'b0; // input
wire app_zq_req = 1'b0; // input
wire app_sr_active; // output
wire app_ref_ack; // output
wire app_zq_ack; // output

wire init_calib_complete; // output
wire [11:0] device_temp; // output
wire calib_tap_req; // output
wire calib_tap_load = 1'b0; // input
wire [6:0] calib_tap_addr = 7'd0; // input
wire [7:0] calib_tap_val = 8'd0; // input
wire calib_tap_load_done = 1'b0; // input
wire sys_rst = rst_n; // input

wire cpu_run_state;

wire [15:0] uart_term = 16'd54;

wire cmd_ld_ma;
wire cmd_st_ma;
wire [31:0] rd_data_ma;
wire [2:0] dbg_bpoint;

//wire [7:0] gpio; // zantei

// for free run counter signals
wire csr_mtie;
wire csr_rmie;
wire csr_meie;
wire frc_cntr_val_leq;
wire frc_cntr_val_leq_1shot;

// spi select signal : not used for 5 stage 
wire spi_select_io; // not used
//wire spi_sck;
//wire [1:0] spi_csn; // zantei
//wire spi_mosi; // zantei
//wire spi_miso = 1'b0; // zantei

// for interrupt
wire g_interrupt_1shot;
wire g_interrupt;
//wire ic_stall;
wire stall;

cpu_top #(.DWIDTH(DWIDTH), .IWIDTH(IWIDTH), .SWIDTH(SWIDTH)) cpu_top (
	.clk(clk),
	.rst_n(rst_n),
	.init_calib_complete(init_calib_complete),
	.cpu_start(cpu_start),
	.quit_cmd(quit_cmd),
	.start_adr(start_adr),
	.cpu_run_state(cpu_run_state),

	//.d_ram_radr(d_ram_radr),
	//.d_ram_wadr(d_ram_wadr),
	//.d_ram_rdata(d_ram_rdata),
	//.d_ram_wdata(d_ram_wdata),
    .scr_ram_radr(scr_ram_radr),
    .scr_ram_wadr(scr_ram_wadr),
    .scr_ram_wdata(scr_ram_wdata),
    .scr_ram_rdata(scr_ram_rdata),
	.scr_ram_wen(scr_ram_wen),
	.scr_read_sel(_read_sel),
	//.d_ram_wen(d_ram_wen),
	//.d_read_sel(d_read_sel),

	.i_ram_radr(i_ram_radr),
	.i_ram_wadr(i_ram_wadr),
	.i_ram_rdata(i_ram_rdata),
	.i_ram_wdata(i_ram_wdata),
	.i_ram_wen(i_ram_wen),
	.i_read_sel(i_read_sel),
	.pc_data(pc_data),
	.dma_io_we(dma_io_we),
	.dma_io_wadr(dma_io_wadr),
	.dma_io_wdata(dma_io_wdata),
	.dma_io_radr(dma_io_radr),
	.dma_io_radr_en(dma_io_radr_en),
	//.dma_io_rdata_in(dma_io_rdata_in),
	.dma_io_rdata_in(dma_io_rdata),

	.dma_io_we_u(dma_io_we_u),
	.dma_io_wadr_u(dma_io_wadr_u),
	.dma_io_wdata_u(dma_io_wdata_u),
	.dma_io_radr_u(dma_io_radr_u),
	.dma_io_radr_en_u(dma_io_radr_en_u),
	.dma_io_rdata_in_u_fin(dma_io_rdata_u_fin),

	.dma_wstart_rq(dma_wstart_rq),
	.dma_win_addr(dma_win_addr),
	.dma_in_wdata(dma_in_wdata),
	.dma_in_mask(dma_in_mask),
	.dma_finish_wresp(dma_finish_wresp),
	.dma_rstart_rq(dma_rstart_rq),
	.dma_rin_addr(dma_rin_addr),
	.dma_rdat_m_data(dma_rdat_m_data),
	.dma_rdat_m_mask(dma_rdat_m_mask),
	.dma_rdat_m_valid(dma_rdat_m_valid),
	.dma_finish_mrd(dma_finish_mrd),

	.icr_start_rq(ic_rstart_rq),
	.ic_rin_addr(ic_rin_addr),
	.ic_rdat_m_data(ic_rdat_m_data),
	.ic_rdat_m_mask(ic_rdat_m_mask),
	.ic_rdat_m_valid(ic_rdat_m_valid),
	.ic_finish_mrd(ic_finish_mrd),
	// FPGA FIX (2026-07-19): was 1'b0 - the monitor had NO way to
	// invalidate the I$, so a reflash/restart without an FPGA
	// reconfigure executed stale old-kernel lines out of the 16KB I$.
	// The existing D$-flush monitor command (zcmd_setdfl) now flushes
	// BOTH caches; issue it after quit and before loading a new image.
	.start_icflush(start_dcflush),

    .csr_radr_en_mon(csr_radr_en_mon),
    .csr_radr_mon(csr_radr_mon),
    .csr_wadr_mon(csr_wadr_mon),
    .csr_we_mon(csr_we_mon),
    .csr_wdata_mon(csr_wdata_mon),
    .csr_rdata_mon(csr_rdata_mon),

    .rf_radr_en_mon(rf_radr_en_mon),
    .rf_radr_mon(rf_radr_mon),
    .rf_wadr_mon(rf_wadr_mon),
    .rf_we_mon(rf_we_mon),
    .rf_wdata_mon(rf_wdata_mon),
    .rf_rdata_mon(rf_rdata_mon),

	.dcw_start_rq(dc_wstart_rq),
	.dcw_in_addr(dc_win_addr),
	.dcw_in_mask(dc_in_mask),
	.dcw_in_data(dc_in_wdata),
	.dcw_finish_wresp(dc_finish_wresp),
	.dcr_start_rq(dc_rstart_rq),
	.dcr_rin_addr(dc_rin_addr),
	.rqfull_1(rqfull_1),
	.rdat_m_data(dc_rdat_m_data),
	.rdat_m_valid(dc_rdat_m_valid),
	.finish_mrd(dc_finish_mrd),
	.start_dcflush(start_dcflush),
	.dcflush_running(dcflush_running),
	//.interrupt_0(interrupt_0),
	.cmd_ld_ma(cmd_ld_ma),
	.cmd_st_ma(cmd_st_ma),
	.rd_data_ma(rd_data_ma),
	.csr_mtie(csr_mtie),
	.frc_cntr_val_leq(frc_cntr_val_leq),
    .frc_cntr_val_leq_1shot(frc_cntr_val_leq_1shot),
    .csr_rmie(csr_rmie),
    .csr_meie(csr_meie),
    .g_interrupt_1shot(g_interrupt_1shot),
    .g_interrupt(g_interrupt),
    //.ic_stall(ic_stall),
    .stall(stall),

    .fwdmon_pc_ex(fwdmon_pc_ex),

    .icdcmon_cache_miss_current(icdcmon_cache_miss_current),
    .icdcmon_ic_stall(icdcmon_ic_stall),
    .dbg_stall_ld(dbg_stall_ld),
    .dbg_stall_ld_add(dbg_stall_ld_add),
    .dbg_dc_stall(dbg_dc_stall),
    .dbg_rst_pipe(dbg_rst_pipe),
    .dbg_use_collision(dbg_use_collision),
    .dbg_jump_under_ic_stall(dbg_jump_under_ic_stall),
    .dbg_ucp(dbg_ucp),

    .ic_miss_current_mon(ic_miss_current_mon),
    .ic_tag_miss_id_mon(ic_tag_miss_id_mon),
    .ic_tag_empty_id_mon(ic_tag_empty_id_mon),
    .icr_start_rq_count_mon(icr_start_rq_count_mon),
    .dcflush_cntr_mon(dcflush_cntr_mon),
    .ic_retry_repeat_cntr_mon(ic_retry_repeat_cntr_mon),
    .ic_curric_ent_radr_keeper_mon(ic_curric_ent_radr_keeper_mon),

    .dc_miss_current_mon(dc_miss_current_mon),
    .dc_tag_miss_ma_mon(dc_tag_miss_ma_mon),
    .dc_tag_empty_ma_mon(dc_tag_empty_ma_mon),
    .dc_retry_repeat_cntr_mon(dc_retry_repeat_cntr_mon),
    .current_radr_keeper_mon(current_radr_keeper_mon)
	);

axi_bus_top axi_bus_top (
	.clk(clk),
	.rst_n(rst_n),
	.dma_wstart_rq(dma_wstart_rq),
	.dma_win_addr(dma_win_addr),
	.dma_in_wdata(dma_in_wdata),
	.dma_in_mask(dma_in_mask),
	.dma_finish_wresp(dma_finish_wresp),
	.dma_rstart_rq(dma_rstart_rq),
	.dma_rin_addr(dma_rin_addr),
	.dma_rdat_m_data(dma_rdat_m_data),
	.dma_rdat_m_mask(dma_rdat_m_mask),
	.dma_rdat_m_valid(dma_rdat_m_valid),
	.dma_finish_mrd(dma_finish_mrd),
	.uart_wstart_rq(uart_wstart_rq),
	.uart_win_addr(uart_win_addr),
	.uart_in_wdata(uart_in_wdata),
	.uart_in_mask(uart_in_mask),
	.uart_finish_wresp(uart_finish_wresp),
	.uart_rstart_rq(uart_rstart_rq),
	.uart_rin_addr(uart_rin_addr),
	.uart_rdat_m_data(uart_rdat_m_data),
	.uart_rdat_m_mask(uart_rdat_m_mask),
	.uart_rdat_m_valid(uart_rdat_m_valid),
	.uart_finish_mrd(uart_finish_mrd),
	.dc_wstart_rq(dc_wstart_rq),
	.dc_win_addr(dc_win_addr),
	.dc_in_wdata(dc_in_wdata),
	.dc_in_mask(dc_in_mask),
	.dc_finish_wresp(dc_finish_wresp),
	.dc_rstart_rq(dc_rstart_rq),
	.dc_rin_addr(dc_rin_addr),
	.dc_rdat_m_data(dc_rdat_m_data),
	.dc_rdat_m_mask(dc_rdat_m_mask),
	.dc_rdat_m_valid(dc_rdat_m_valid),
	.dc_finish_mrd(dc_finish_mrd),

	.ic_rstart_rq(ic_rstart_rq),
	.ic_rin_addr(ic_rin_addr),
	.ic_rdat_m_data(ic_rdat_m_data),
	.ic_rdat_m_mask(ic_rdat_m_mask),
	.ic_rdat_m_valid(ic_rdat_m_valid),
	.ic_finish_mrd(ic_finish_mrd),

	.awvalid(awvalid),
	.awready(awready),
	.awid(awid),
	.awaddr(awaddr),
	.awatop(awatop),
	.wvalid(wvalid),
	.wready(wready),
	.wdata(wdata),
	.wstrb(wstrb),
	.wlast(wlast),
	.bvalid(bvalid),
	.bready(bready),
	.bid(bid),
	.bcomp(bcomp),
	.arvalid(arvalid),
	.arready(arready),
	.arid(arid),
	.araddr(araddr),
	.rvalid(rvalid),
	.rready(rready),
	.rid(rid),
	.rdata(rdata),
	.rlast(rlast),

	.ic_req_rd_mon(ic_req_rd_mon),
	.ic_gnt_rd_mon(ic_gnt_rd_mon),
	.ic_arvalid_mon(ic_arvalid_mon),
	.sel_rd_mon(sel_rd_mon),
	.ic_rdat_m_current_mon(ic_rdat_m_current_mon),
	.ic_next_rid_lat_mon(ic_next_rid_lat_mon),
	.rvalid_mon(rvalid_mon),
	.rid_mon(rid_mon),

	.dc_req_rd_mon(dc_req_rd_mon),
	.dc_gnt_rd_mon(dc_gnt_rd_mon),
	.dc_arvalid_mon(dc_arvalid_mon),
	.dc_rdat_m_current_mon(dc_rdat_m_current_mon),
	.dc_next_rid_lat_mon(dc_next_rid_lat_mon)
	);

dram_top #(.SWIDTH(SWIDTH)) dram_top (
	.mclk(mclk),
	.mrst_n(mrst_n),
	.app_addr(app_addr),
	.app_cmd(app_cmd),
	.app_en(app_en),
	.app_rdy(app_rdy),
	.app_wdf_data(app_wdf_data),
	.app_wdf_mask(app_wdf_mask),
	.app_wdf_wren(app_wdf_wren),
	.app_wdf_end(app_wdf_end),
	.app_wdf_rdy(app_wdf_rdy),
	.app_rd_data(app_rd_data),
	.app_rd_data_end(app_rd_data_end),
	.app_rd_data_valid(app_rd_data_valid),
	.clk(clk),
	.rst_n(rst_n),
	.dma_io_we(dma_io_we),
	.dma_io_wadr(dma_io_wadr),
	.dma_io_wdata(dma_io_wdata),
	.dma_io_radr(dma_io_radr),
	.dma_io_radr_en(dma_io_radr_en),
	.dma_io_rdata_in(dma_io_rdata_in_6),
	.dma_io_rdata(dma_io_rdata_in_7),
	.awvalid(awvalid),
	.awready(awready),
	.awid(awid),
	.awaddr(awaddr),
	.awatop(awatop),
	.wvalid(wvalid),
	.wready(wready),
	.wdata(wdata),
	.wstrb(wstrb),
	.wlast(wlast),
	.bvalid(bvalid),
	.bready(bready),
	.bid(bid),
	.bcomp(bcomp),
	.arvalid(arvalid),
	.arready(arready),
	.arid(arid),
	.araddr(araddr),
	.rvalid(rvalid),
	.rready(rready),
	.rid(rid),
	.rdata(rdata),
	.rlast(rlast)
	);

// forwarding_hazard_monitor removed 2026-09-06 (timing recovery; its
// investigation concluded no real harm - forwarding.v asymmetry is
// neutralised by wbk_rd_reg_wb forced-clear). The dma_io_* daisy chain
// now goes dram_top -> ic_dc_overlap_monitor directly.

// ---- ILA debug taps (registered mirror, clk domain) added 2026-09-17 to
// identify which of axi_bus_top's 4 request channels (ic/dc/uart/dma) is
// generating req_queue traffic while cpu_start has never been asserted
// since reset (mig_if.v's dbg_accept_mismatch_ila chase led here - see
// project memory project_dram_write_loss_async_queue_theory). Registered
// here, not tapped raw, to keep ILA fanout off axi_bus_top's own arbitration
// path, per feedback_register_debug_mon_taps. ----
(* mark_debug = "true" *) reg dbg_ic_rstart_rq_ila, dbg_dc_rstart_rq_ila, dbg_uart_rstart_rq_ila;
(* mark_debug = "true" *) reg dbg_dma_rstart_rq_ila, dbg_dma_wstart_rq_ila;
(* mark_debug = "true" *) reg dbg_awvalid_ila, dbg_arvalid_ila;

always @ (posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        dbg_ic_rstart_rq_ila   <= 1'b0;
        dbg_dc_rstart_rq_ila   <= 1'b0;
        dbg_uart_rstart_rq_ila <= 1'b0;
        dbg_dma_rstart_rq_ila  <= 1'b0;
        dbg_dma_wstart_rq_ila  <= 1'b0;
        dbg_awvalid_ila        <= 1'b0;
        dbg_arvalid_ila        <= 1'b0;
    end else begin
        dbg_ic_rstart_rq_ila   <= ic_rstart_rq;
        dbg_dc_rstart_rq_ila   <= dc_rstart_rq;
        dbg_uart_rstart_rq_ila <= uart_rstart_rq;
        dbg_dma_rstart_rq_ila  <= dma_rstart_rq;
        dbg_dma_wstart_rq_ila  <= dma_wstart_rq;
        dbg_awvalid_ila        <= awvalid;
        dbg_arvalid_ila        <= arvalid;
    end
end

// I$/D$ overlap FSM statistics monitor (2026-08-09), tail of the
// dma_io_* daisy chain right after dram_top - see ic_dc_overlap_monitor.v.
wire [31:0] dma_io_rdata_in_9;
wire [31:0] dma_io_rdata_in_10;

ic_dc_overlap_monitor ic_dc_overlap_monitor (
	.clk(clk),
	.rst_n(rst_n),
	.cache_miss_current(icdcmon_cache_miss_current),
	.ic_stall(icdcmon_ic_stall),
	.dc_stall(stall),
	.pc_ex(fwdmon_pc_ex),
	.dma_io_we(dma_io_we),
	.dma_io_wadr(dma_io_wadr),
	.dma_io_wdata(dma_io_wdata),
	.dma_io_radr(dma_io_radr),
	.dma_io_radr_en(dma_io_radr_en),
	.dma_io_rdata_in(dma_io_rdata_in_7),
	.dma_io_rdata(dma_io_rdata_in_9)
	);

// I$ read-request-channel stall probe (2026-08-27), new tail of the
// dma_io_* daisy chain right after ic_dc_overlap_monitor - see
// icr_start_rq_probe.v / project_slub_debug_u_axi_hang.
icr_start_rq_probe icr_start_rq_probe (
	.clk(clk),
	.rst_n(rst_n),
	.ic_req_rd(ic_req_rd_mon),
	.ic_gnt_rd(ic_gnt_rd_mon),
	.ic_arvalid(ic_arvalid_mon),
	.sel_rd(sel_rd_mon),
	.ic_rdat_m_current(ic_rdat_m_current_mon),
	.ic_next_rid_lat(ic_next_rid_lat_mon),
	.rvalid(rvalid_mon),
	.rid(rid_mon),
	.ic_miss_current(ic_miss_current_mon),
	.ic_tag_miss_id(ic_tag_miss_id_mon),
	.ic_tag_empty_id(ic_tag_empty_id_mon),
	.icr_start_rq_count(icr_start_rq_count_mon),
	.dcflush_cntr(dcflush_cntr_mon),
	.dcflush_running(dcflush_running),
	.ic_stall(icdcmon_ic_stall),
	.ic_retry_repeat_cntr(ic_retry_repeat_cntr_mon),
	.ic_curric_ent_radr_keeper(ic_curric_ent_radr_keeper_mon),
	.dc_req_rd(dc_req_rd_mon),
	.dc_gnt_rd(dc_gnt_rd_mon),
	.dc_arvalid(dc_arvalid_mon),
	.dc_rdat_m_current(dc_rdat_m_current_mon),
	.dc_next_rid_lat(dc_next_rid_lat_mon),
	.dc_miss_current(dc_miss_current_mon),
	.dc_tag_miss_ma(dc_tag_miss_ma_mon),
	.dc_tag_empty_ma(dc_tag_empty_ma_mon),
	.dc_retry_repeat_cntr(dc_retry_repeat_cntr_mon),
	.current_radr_keeper(current_radr_keeper_mon),
	.dma_io_we(dma_io_we),
	.dma_io_wadr(dma_io_wadr),
	.dma_io_wdata(dma_io_wdata),
	.dma_io_radr(dma_io_radr),
	.dma_io_radr_en(dma_io_radr_en),
	.dma_io_rdata_in(dma_io_rdata_in_9),
	.dma_io_rdata(dma_io_rdata_in_10)
	);

// PC-unchanged hang probe (2026-09-06), tail of the dma_io_* daisy chain
// right after icr_start_rq_probe. Timing-safe by construction: reuses only
// nets already tapped for ic_dc_overlap_monitor (fwdmon_pc_ex,
// icdcmon_cache_miss_current, icdcmon_ic_stall), registers them at entry,
// and drives nothing back into the CPU. See pc_hang_probe.v.
pc_hang_probe pc_hang_probe (
	.clk(clk),
	.rst_n(rst_n),
	.pc_ex(fwdmon_pc_ex),
	.cache_miss_current(icdcmon_cache_miss_current),
	.ic_stall(icdcmon_ic_stall),
	.dc_miss_current(dc_miss_current_mon),
	.stall_ld(dbg_stall_ld),
	.stall_ld_add(dbg_stall_ld_add),
	.dc_stall(dbg_dc_stall),
	.rst_pipe(dbg_rst_pipe),
	.dc_tag_miss_ma(dc_tag_miss_ma_mon),
	.dc_tag_empty_ma(dc_tag_empty_ma_mon),
	.use_collision(dbg_use_collision),
	.jump_under_ic_stall(dbg_jump_under_ic_stall),
	.ucp(dbg_ucp),
	.dma_io_we(dma_io_we),
	.dma_io_wadr(dma_io_wadr),
	.dma_io_wdata(dma_io_wdata),
	.dma_io_radr(dma_io_radr),
	.dma_io_radr_en(dma_io_radr_en),
	.dma_io_rdata_in(dma_io_rdata_in_10),
	.dma_io_rdata(dma_io_rdata)
	);

mig_7series_0 mig_7series_0 (
	.ddr3_dq(ddr3_dq),
	.ddr3_dqs_n(ddr3_dqs_n),
	.ddr3_dqs_p(ddr3_dqs_p),
	.ddr3_addr(ddr3_addr),
	.ddr3_ba(ddr3_ba),
	.ddr3_ras_n(ddr3_ras_n),
	.ddr3_cas_n(ddr3_cas_n),
	.ddr3_we_n(ddr3_we_n),
	.ddr3_reset_n(ddr3_reset_n),
	.ddr3_ck_p(ddr3_ck_p),
	.ddr3_ck_n(ddr3_ck_n),
	.ddr3_cke(ddr3_cke),
	.ddr3_cs_n(ddr3_cs_n),
	.ddr3_dm(ddr3_dm),
	.ddr3_odt(ddr3_odt),
	.sys_clk_i(sys_clk_i),
	.clk_ref_i(clk_ref_i),
	.app_addr(app_addr),
	.app_cmd(app_cmd),
	.app_en(app_en),
	.app_wdf_data(app_wdf_data),
	.app_wdf_end(app_wdf_end),
	.app_wdf_mask(app_wdf_mask),
	.app_wdf_wren(app_wdf_wren),
	.app_rd_data(app_rd_data),
	.app_rd_data_end(app_rd_data_end),
	.app_rd_data_valid(app_rd_data_valid),
	.app_rdy(app_rdy),
	.app_wdf_rdy(app_wdf_rdy),
	.app_sr_req(app_sr_req),
	.app_ref_req(app_ref_req),
	.app_zq_req(app_zq_req),
	.app_sr_active(app_sr_active),
	.app_ref_ack(app_ref_ack),
	.app_zq_ack(app_zq_ack),
	.ui_clk(ui_clk),
	.ui_clk_sync_rst(ui_clk_sync_rst),
	.init_calib_complete(init_calib_complete),
	.device_temp(device_temp),
	//.calib_tap_req(calib_tap_req),
	//.calib_tap_load(calib_tap_load),
	//.calib_tap_addr(calib_tap_addr),
	//.calib_tap_val(calib_tap_val),
	//.calib_tap_load_done(calib_tap_load_done),
	.sys_rst(sys_rst)
	);

/*
dummy_mig dummy_mig (
	.mclk(mclk),
	.mrst_n(mrst_n),
	.app_addr(app_addr),
	.app_cmd(app_cmd),
	.app_en(app_en),
	.app_rdy(app_rdy),
	.app_wdf_data(app_wdf_data),
	.app_wdf_mask(app_wdf_mask),
	.app_wdf_wren(app_wdf_wren),
	.app_wdf_end(app_wdf_end),
	.app_wdf_rdy(app_wdf_rdy),
	.app_rd_data(app_rd_data),
	.app_rd_data_end(app_rd_data_end),
	.app_rd_data_valid(app_rd_data_valid)
	);
*/

uart_top #(.DWIDTH(DWIDTH), .IWIDTH(IWIDTH), .SWIDTH(SWIDTH)) uart_top (
	.clk(clk),
	.rst_n(rst_n),
	.rx(rx),
	.tx(tx),

    .d_ram_radr(uart_rin_addr),
    .d_ram_wadr(uart_win_addr),
    .d_ram_rdata(uart_rdat_m_data),
    .d_ram_wdata(uart_in_wdata),
    .d_ram_wen(uart_wstart_rq),
    .uart_finish_wresp(uart_finish_wresp),
    .scr_ram_radr(scr_ram_radr),
    .scr_ram_wadr(scr_ram_wadr),
    .scr_ram_wdata(scr_ram_wdata),
    .scr_ram_rdata(scr_ram_rdata),
	.scr_ram_wen(scr_ram_wen),
	.scr_read_sel(_read_sel),
    //.d_read_sel(uart_d_read_sel),
    .d_ram_mask(uart_in_mask),
    .u_read_req(uart_rstart_rq),
    .read_valid(uart_rdat_m_valid),
	//.d_ram_radr(d_ram_radr),
	//.dread_start(dread_start),
	//.d_ram_rdata(d_ram_rdata),
	//.read_valid(read_valid),
	//.d_ram_wadr(d_ram_wadr),
	//.d_ram_wdata(d_ram_wdata),
	//.d_ram_mask(d_ram_mask),
	//.d_ram_wen(d_ram_wen),
	//.uart_finish_wresp(uart_finish_wresp),
	//.d_read_sel(d_read_sel),

	.dma_io_we(dma_io_we_u),
	.dma_io_wadr(dma_io_wadr_u),
	.dma_io_wdata(dma_io_wdata_u),
	.dma_io_radr(dma_io_radr_u),
	.dma_io_radr_en(dma_io_radr_en_u),
	.dma_io_rdata_in(dma_io_rdata_u_fin),

	.csr_radr_en_mon(csr_radr_en_mon),
	.csr_radr_mon(csr_radr_mon),
	.csr_wadr_mon(csr_wadr_mon),
	.csr_we_mon(csr_we_mon),
	.csr_wdata_mon(csr_wdata_mon),
	.csr_rdata_mon(csr_rdata_mon),

	.rf_radr_en_mon(rf_radr_en_mon),
	.rf_radr_mon(rf_radr_mon),
	.rf_wadr_mon(rf_wadr_mon),
	.rf_we_mon(rf_we_mon),
	.rf_wdata_mon(rf_wdata_mon),
	.rf_rdata_mon(rf_rdata_mon),

	.pc_data(pc_data),
	.cmd_ld_ma(cmd_ld_ma),
	.cmd_st_ma(cmd_st_ma),
	.rd_data_ma(rd_data_ma),
	.dbg_bpoint(dbg_bpoint),

	.cpu_start(cpu_start),
	.cpu_run_state(cpu_run_state),
	.quit_cmd(quit_cmd),
	.start_adr(start_adr),
	.uart_io_char(uart_io_char),
	.uart_io_we(uart_io_we),
	.uart_io_full(uart_io_full),
	.uart_term(uart_term),
	.rout_en(rout_en),
	.rout(rout),
	.rx_disable_echoback(rx_disable_echoback),
	.start_dcflush(start_dcflush)
	);

io_led io_led (
	.clk(clk),
	.rst_n(rst_n),
	.dma_io_we(dma_io_we),
	.dma_io_wadr(dma_io_wadr),
	.dma_io_wdata(dma_io_wdata),
	.dma_io_radr(dma_io_radr),
	.dma_io_radr_en(dma_io_radr_en),
	.dma_io_rdata_in(dma_io_rdata_in_2),
	.dma_io_rdata(dma_io_rdata_in_3),
	.rgb_led(rgb_led),
	.rgb_led1(rgb_led1),
	.rgb_led2(rgb_led2),
	.rgb_led3(rgb_led3),
	.dbg_bpoint(dbg_bpoint),
	.cpu_start(cpu_start),
	.gpio(gpio)
	);

io_uart_out io_uart_out (
    .clk(clk),
    .rst_n(rst_n),
    .dma_io_we(dma_io_we),
    .dma_io_wadr(dma_io_wadr),
    .dma_io_wdata(dma_io_wdata),
    .dma_io_radr(dma_io_radr),
    .dma_io_radr_en(dma_io_radr_en),
    .dma_io_rdata_in(dma_io_rdata_in),
    .dma_io_rdata(dma_io_rdata_in_2),
    .uart_io_char(uart_io_char),
    .uart_io_we(uart_io_we),
    .uart_io_full(uart_io_full),
    //.init_uart(init_uart),
    //.uart_term(uart_term),
    .cpu_run_state(cpu_run_state),
    .rout_en(rout_en),
    .rout(rout),
    .ext_uart_interrpt_1shot(ext_uart_interrpt_1shot),
    .rx_disable_echoback(rx_disable_echoback)
    );

io_frc io_frc (
    .clk(clk),
    .rst_n(rst_n),
    .dma_io_we(dma_io_we),
    .dma_io_wadr(dma_io_wadr),
    .dma_io_wdata(dma_io_wdata),
    .dma_io_radr(dma_io_radr),
    .dma_io_radr_en(dma_io_radr_en),
    .dma_io_rdata_in(dma_io_rdata_in_3),
    .dma_io_rdata(dma_io_rdata_in_4),
    .csr_mtie(csr_mtie),
    .csr_rmie(csr_rmie),
    .frc_cntr_val_leq(frc_cntr_val_leq),
    .frc_cntr_val_leq_1shot(frc_cntr_val_leq_1shot),
    .stall(stall)
    );

interrupter interrupter (
    .clk(clk),
    .rst_n(rst_n),
    .interrupt_0(interrupt_0),
    .ext_uart_interrpt_1shot(ext_uart_interrpt_1shot),
    .csr_rmie(csr_rmie),
    .csr_meie(csr_meie),
    .g_interrupt_1shot(g_interrupt_1shot),
    .g_interrupt(g_interrupt),
    //.ic_stall(ic_stall),
    .stall(stall),
    .dma_io_we(dma_io_we),
    .dma_io_wadr(dma_io_wadr),
    .dma_io_wdata(dma_io_wdata),
    .dma_io_radr(dma_io_radr),
    .dma_io_radr_en(dma_io_radr_en),
    .dma_io_rdata_in(dma_io_rdata_in_4),
    .dma_io_rdata(dma_io_rdata_in_5)
    );

io_spi_lite io_spi_lite(
    .clk(clk),
    .rst_n(rst_n),
    .dma_io_we(dma_io_we),
    .dma_io_wadr(dma_io_wadr),
    .dma_io_wdata(dma_io_wdata),
    .dma_io_radr(dma_io_radr),
    .dma_io_radr_en(dma_io_radr_en),
    .dma_io_rdata_in(dma_io_rdata_in_5),
    .dma_io_rdata(dma_io_rdata_in_6),
    .spi_select_io(spi_select_io),
    .spi_sck(spi_sck),
    .spi_csn(spi_csn),
    .spi_mosi(spi_mosi),
    .spi_miso(spi_miso)
    );

endmodule

