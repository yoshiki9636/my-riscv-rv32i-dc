/*
 * My RISC-V RV32I CPU
 *   lab7_mmu simulation testbench
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2026 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 *
 * real cpu_top -> axi_bus_top -> dram_top (CDC afifos)
 *   MEM_MIG   : -> mig_if -> behavioral MIG stub in this file (1MB, random latency)
 *   MEM_SDRAM : -> sdram_if_sim.v (behavioral, 1MB)
 * board / memory are taken from fpga/fpga_config.vh (iverilog -I../fpga)
 * IWIDTH / DWIDTH / SWIDTH = fpga_top.v setting of the board
 *   Arty A7 : 12 / 10 (4 way D$ : 16KB) / 13, others : 10 / 10 / 13
 *
 * Test program interface (MMIO, cpu_top dma_io_* bus):
 *   0xC000_FFC0 (TOHOST) : write 1 = PASS, other value = FAIL (code)
 *   0xC000_FFC4 (PUTC)   : write a character (shown on the console)
 *
 * plusargs:
 *   +HEX=<file>      program image (objcopy -O verilog, 32bit words), default test.hex
 *   +MAXCYC=<n>      timeout cycles (default 200000)
 *   +TRACE           print every trap
 *   +COMMIT          print every register write back / MMIO write / D$ write back
 *                    (used to compare the RTL with the pre-MMU RTL : see cmp.sh)
 */

`timescale 1ns/1ps
`include "fpga_config.vh"

module tb_mmu;

`ifdef TB_IWIDTH
localparam IWIDTH = `TB_IWIDTH;   // iverilog -DTB_IWIDTH=n : I$ size override (debug)
`elsif BOARD_ARTY_A7
localparam IWIDTH = 12;
`else
localparam IWIDTH = 10;
`endif
`ifdef TB_DWIDTH
localparam DWIDTH = `TB_DWIDTH;   // iverilog -DTB_DWIDTH=n : D$ way size override
`else
localparam DWIDTH = 10;
`endif
`ifdef TB_DWAYS
localparam DWAYS = `TB_DWAYS;     // iverilog -DTB_DWAYS=n : D$ ways (1/2/4/8) override
`elsif BOARD_ARTY_A7
localparam DWAYS = 4;
`else
localparam DWAYS = 1;
`endif
localparam SWIDTH = 13;

localparam [15:2] TOHOST_ADR = 14'h3FF0;
localparam [15:2] PUTC_ADR   = 14'h3FF1;
localparam [15:2] UART_TX_ADR = 14'h3F00; // io_uart_out SYS_UART_OUTC (0xC000_FC00)

// ---------------- clocks / resets ----------------
reg clk  = 0;
reg mclk = 0;
`ifdef MEM_SDRAM
always #15  clk  = ~clk;    // 33.3MHz : cpu / bus
always #10  mclk = ~mclk;   // 50MHz   : memory side
`else
always #10  clk  = ~clk;    // 50MHz   : cpu / bus
always #6   mclk = ~mclk;   // 83MHz   : MIG ui_clk
`endif

reg rst_n  = 0;
reg mrst_n = 0;

// ================= cpu_top =================
wire cpu_run_state;
wire [31:0] scr_ram_rdata_u, i_ram_rdata_u, csr_rdata_mon_u, pc_data_u;
wire [31:0] rf_mon_unused;
wire [31:0] dma_io_rdata_in_u_fin_u;
wire dma_io_we;
wire dma_io_radr_en;
wire [15:2] dma_io_wadr;
wire [15:2] dma_io_radr;
wire [31:0] dma_io_wdata;

wire icr_start_rq;
wire [31:0] ic_rin_addr;
wire [127:0] ic_rdat_m_data;
wire ic_rdat_m_valid;
wire ic_finish_mrd;

wire dcw_start_rq;
wire [31:0] dcw_in_addr;
wire [15:0] dcw_in_mask;
wire [127:0] dcw_in_data;
wire dcw_finish_wresp;

wire dcr_start_rq;
wire [31:0] dcr_rin_addr;
wire [127:0] rdat_m_data;
wire rdat_m_valid;
wire finish_mrd;

wire [31:0] rd_data_ma_u;
wire cmd_ld_ma_u, cmd_st_ma_u;
wire csr_mtie_u, csr_meie_u, csr_rmie_u;
wire stall_u;

reg cpu_start = 0;
reg [31:2] start_adr = 30'd0;
reg quit_cmd = 0;

wire dma_wstart_rq_u, dma_rstart_rq_u;
wire [31:0] dma_win_addr_u, dma_rin_addr_u;
wire [127:0] dma_in_wdata_u;
wire [15:0] dma_in_mask_u;
wire dma_finish_wresp_u;
wire [127:0] dma_rdat_m_data_u;
wire [15:0] dma_rdat_m_mask_u;
wire dma_rdat_m_valid_u;
wire dma_finish_mrd_u;

wire frc_cntr_val_leq, frc_cntr_val_leq_1shot;
wire [31:0] frc_dma_io_rdata;

`ifdef TB_ORIG
// pre-MMU RTL (orig_rtl/) : no DWAYS parameter
cpu_top #(.IWIDTH(IWIDTH), .DWIDTH(DWIDTH), .SWIDTH(SWIDTH)) dut (
`else
cpu_top #(.IWIDTH(IWIDTH), .DWIDTH(DWIDTH), .SWIDTH(SWIDTH), .DWAYS(DWAYS)) dut (
`endif
    .clk(clk),
    .rst_n(rst_n),

    .init_calib_complete(1'b1),
    .cpu_start(cpu_start),
    .quit_cmd(quit_cmd),
    .start_adr(start_adr),
    .cpu_run_state(cpu_run_state),

    .scr_ram_radr({(SWIDTH){1'b0}}),
    .scr_ram_wadr({(SWIDTH){1'b0}}),
    .scr_ram_rdata(scr_ram_rdata_u),
    .scr_ram_wdata(32'd0),
    .scr_ram_wen(1'b0),
    .scr_read_sel(1'b0),

    .i_ram_radr({(IWIDTH){1'b0}}),
    .i_ram_wadr({(IWIDTH){1'b0}}),
    .i_ram_rdata(i_ram_rdata_u),
    .i_ram_wdata(32'd0),
    .i_ram_wen(1'b0),
    .i_read_sel(1'b0),
    .pc_data(pc_data_u),

    .dma_io_we(dma_io_we),
    .dma_io_wadr(dma_io_wadr),
    .dma_io_wdata(dma_io_wdata),
    .dma_io_radr(dma_io_radr),
    .dma_io_radr_en(dma_io_radr_en),
    .dma_io_rdata_in(frc_dma_io_rdata),

    .dma_io_we_u(1'b0),
    .dma_io_wadr_u({14{1'b0}}),
    .dma_io_wdata_u(32'd0),
    .dma_io_radr_u({14{1'b0}}),
    .dma_io_radr_en_u(1'b0),
    .dma_io_rdata_in_u_fin(dma_io_rdata_in_u_fin_u),

    .dma_wstart_rq(dma_wstart_rq_u),
    .dma_win_addr(dma_win_addr_u),
    .dma_in_wdata(dma_in_wdata_u),
    .dma_in_mask(dma_in_mask_u),
    .dma_finish_wresp(dma_finish_wresp_u),
    .dma_rstart_rq(dma_rstart_rq_u),
    .dma_rin_addr(dma_rin_addr_u),
    .dma_rdat_m_data(dma_rdat_m_data_u),
    .dma_rdat_m_mask(dma_rdat_m_mask_u),
    .dma_rdat_m_valid(dma_rdat_m_valid_u),
    .dma_finish_mrd(dma_finish_mrd_u),

    .icr_start_rq(icr_start_rq),
    .ic_rin_addr(ic_rin_addr),
    .ic_rdat_m_data(ic_rdat_m_data),
    .ic_rdat_m_mask(16'd0),
    .ic_rdat_m_valid(ic_rdat_m_valid),
    .ic_finish_mrd(ic_finish_mrd),
    .start_icflush(1'b0),

    .csr_radr_en_mon(1'b0),
    .csr_radr_mon(12'd0),
    .csr_wadr_mon(12'd0),
    .csr_we_mon(1'b0),
    .csr_wdata_mon(32'd0),
    .csr_rdata_mon(csr_rdata_mon_u),

    .rf_radr_en_mon(1'b0),
    .rf_radr_mon(5'd0),
    .rf_wadr_mon(5'd0),
    .rf_we_mon(1'b0),
    .rf_wdata_mon(32'd0),
    .rf_rdata_mon(rf_mon_unused),

    .dcw_start_rq(dcw_start_rq),
    .dcw_in_addr(dcw_in_addr),
    .dcw_in_mask(dcw_in_mask),
    .dcw_in_data(dcw_in_data),
    .dcw_finish_wresp(dcw_finish_wresp),
    .dcr_start_rq(dcr_start_rq),
    .dcr_rin_addr(dcr_rin_addr),
    .rqfull_1(),
    .rdat_m_data(rdat_m_data),
    .rdat_m_valid(rdat_m_valid),
    .finish_mrd(finish_mrd),
    .start_dcflush(1'b0),
    .dcflush_running(),

    .cmd_ld_ma(cmd_ld_ma_u),
    .cmd_st_ma(cmd_st_ma_u),
    .rd_data_ma(rd_data_ma_u),
    .csr_mtie(csr_mtie_u),
    .frc_cntr_val_leq(frc_cntr_val_leq),
    .frc_cntr_val_leq_1shot(frc_cntr_val_leq_1shot),
    .csr_meie(csr_meie_u),
    .csr_rmie(csr_rmie_u),
    .g_interrupt_1shot(1'b0),
    .g_interrupt(1'b0),
    .stall(stall_u)
    );

// ================= timer (io_frc : CLINT-like MTIME / MTIMECMP) =================
io_frc io_frc_i (
    .clk(clk),
    .rst_n(rst_n),
    .dma_io_we(dma_io_we),
    .dma_io_wadr(dma_io_wadr),
    .dma_io_wdata(dma_io_wdata),
    .dma_io_radr(dma_io_radr),
    .dma_io_radr_en(dma_io_radr_en),
    .dma_io_rdata_in(32'd0),
    .dma_io_rdata(frc_dma_io_rdata),
    .csr_mtie(csr_mtie_u),
    .csr_rmie(csr_rmie_u),
    .frc_cntr_val_leq(frc_cntr_val_leq),
    .frc_cntr_val_leq_1shot(frc_cntr_val_leq_1shot),
    .stall(stall_u)
    );

// ================= AXI-lite bus =================
wire axi_awvalid, axi_awready;
wire [3:0] axi_awid;
wire [31:0] axi_awaddr;
wire [5:0] axi_awatop;
wire axi_wvalid, axi_wready;
wire [31:0] axi_wdata;
wire [3:0] axi_wstrb;
wire axi_wlast;
wire axi_bvalid, axi_bready;
wire [3:0] axi_bid;
wire axi_bcomp;
wire axi_arvalid, axi_arready;
wire [3:0] axi_arid;
wire [31:0] axi_araddr;
wire axi_rvalid, axi_rready;
wire [3:0] axi_rid;
wire [31:0] axi_rdata;
wire axi_rlast;

axi_bus_top axi_bus_top_i (
    .clk(clk),
    .rst_n(rst_n),

    .dma_wstart_rq(dma_wstart_rq_u),
    .dma_win_addr(dma_win_addr_u),
    .dma_in_wdata(dma_in_wdata_u),
    .dma_in_mask(dma_in_mask_u),
    .dma_finish_wresp(dma_finish_wresp_u),
    .dma_rstart_rq(dma_rstart_rq_u),
    .dma_rin_addr(dma_rin_addr_u),
    .dma_rdat_m_data(dma_rdat_m_data_u),
    .dma_rdat_m_mask(dma_rdat_m_mask_u),
    .dma_rdat_m_valid(dma_rdat_m_valid_u),
    .dma_finish_mrd(dma_finish_mrd_u),

    .uart_wstart_rq(1'b0),
    .uart_win_addr(32'd0),
    .uart_in_wdata(128'd0),
    .uart_in_mask(16'd0),
    .uart_finish_wresp(),
    .uart_rstart_rq(1'b0),
    .uart_rin_addr(32'd0),
    .uart_rdat_m_data(),
    .uart_rdat_m_mask(),
    .uart_rdat_m_valid(),
    .uart_finish_mrd(),

    .dc_wstart_rq(dcw_start_rq),
    .dc_win_addr(dcw_in_addr),
    .dc_in_wdata(dcw_in_data),
    .dc_in_mask(dcw_in_mask),
    .dc_finish_wresp(dcw_finish_wresp),
    .dc_rstart_rq(dcr_start_rq),
    .dc_rin_addr(dcr_rin_addr),
    .dc_rdat_m_data(rdat_m_data),
    .dc_rdat_m_mask(),
    .dc_rdat_m_valid(rdat_m_valid),
    .dc_finish_mrd(finish_mrd),

    .ic_rstart_rq(icr_start_rq),
    .ic_rin_addr(ic_rin_addr),
    .ic_rdat_m_data(ic_rdat_m_data),
    .ic_rdat_m_mask(),
    .ic_rdat_m_valid(ic_rdat_m_valid),
    .ic_finish_mrd(ic_finish_mrd),

    .awvalid(axi_awvalid), .awready(axi_awready), .awid(axi_awid), .awaddr(axi_awaddr), .awatop(axi_awatop),
    .wvalid(axi_wvalid), .wready(axi_wready), .wdata(axi_wdata), .wstrb(axi_wstrb), .wlast(axi_wlast),
    .bvalid(axi_bvalid), .bready(axi_bready), .bid(axi_bid), .bcomp(axi_bcomp),
    .arvalid(axi_arvalid), .arready(axi_arready), .arid(axi_arid), .araddr(axi_araddr),
    .rvalid(axi_rvalid), .rready(axi_rready), .rid(axi_rid), .rdata(axi_rdata), .rlast(axi_rlast)
    );

`ifdef MEM_SDRAM
// ================= dram_top (MEM_SDRAM) + behavioral sdram_if =================
wire sdram_init_done;
wire [1:0] sdram_cs;
wire sdram_ras, sdram_cas, sdram_we;
wire [1:0] sdram_ba;
wire [12:0] sdram_adr;
wire [1:0] sdram_dqm;
wire [15:0] sdram_dq_o;
wire sdram_dq_en;

dram_top dram_top_i (
    .mclk(mclk),
    .mrst_n(mrst_n),
    .sdram_init_done(sdram_init_done),
    .sdram_cs(sdram_cs),
    .sdram_ras(sdram_ras),
    .sdram_cas(sdram_cas),
    .sdram_we(sdram_we),
    .sdram_ba(sdram_ba),
    .sdram_adr(sdram_adr),
    .sdram_dqm(sdram_dqm),
    .sdram_dq_i(16'd0),
    .sdram_dq_o(sdram_dq_o),
    .sdram_dq_en(sdram_dq_en),

    .clk(clk),
    .rst_n(rst_n),

    .awvalid(axi_awvalid), .awready(axi_awready), .awid(axi_awid), .awaddr(axi_awaddr), .awatop(axi_awatop),
    .wvalid(axi_wvalid), .wready(axi_wready), .wdata(axi_wdata), .wstrb(axi_wstrb), .wlast(axi_wlast),
    .bvalid(axi_bvalid), .bready(axi_bready), .bid(axi_bid), .bcomp(axi_bcomp),
    .arvalid(axi_arvalid), .arready(axi_arready), .arid(axi_arid), .araddr(axi_araddr),
    .rvalid(axi_rvalid), .rready(axi_rready), .rid(axi_rid), .rdata(axi_rdata), .rlast(axi_rlast)
    );
`else
// ================= dram_top (MEM_MIG) + behavioral MIG stub =================
wire [27:0] app_addr;
wire [2:0]  app_cmd;
wire        app_en;
wire        app_rdy;
wire [127:0] app_wdf_data;
wire [15:0]  app_wdf_mask;
wire         app_wdf_wren;
wire         app_wdf_end;
wire         app_wdf_rdy;
wire [127:0] app_rd_data;
wire         app_rd_data_end;
wire         app_rd_data_valid;

dram_top dram_top_i (
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

    .awvalid(axi_awvalid), .awready(axi_awready), .awid(axi_awid), .awaddr(axi_awaddr), .awatop(axi_awatop),
    .wvalid(axi_wvalid), .wready(axi_wready), .wdata(axi_wdata), .wstrb(axi_wstrb), .wlast(axi_wlast),
    .bvalid(axi_bvalid), .bready(axi_bready), .bid(axi_bid), .bcomp(axi_bcomp),
    .arvalid(axi_arvalid), .arready(axi_arready), .arid(axi_arid), .araddr(axi_araddr),
    .rvalid(axi_rvalid), .rready(axi_rready), .rid(axi_rid), .rdata(axi_rdata), .rlast(axi_rlast)
    );

// MIG stub (in-order, random latency, app_rdy / app_wdf_rdy random stalls)
//   app_addr[18:3] = byte address[19:4] (mig_if : {1'b0, addr[27:4], 3'b000})
reg [127:0] mig_mem [0:65535];
wire [15:0] app_line_idx = app_addr[18:3];
localparam RQDEPTH = 4;
localparam WQDEPTH = 4;

reg [2:0] rdy_stall_cnt;
reg app_rdy_free_r;
reg [2:0] wdf_stall_cnt;
reg app_wdf_rdy_r;
always @ (posedge mclk or negedge mrst_n) begin
    if (~mrst_n) begin
        rdy_stall_cnt <= 0; app_rdy_free_r <= 1'b1;
        wdf_stall_cnt <= 0; app_wdf_rdy_r <= 1'b1;
    end else begin
        if (rdy_stall_cnt != 0) begin
            app_rdy_free_r <= 1'b0; rdy_stall_cnt <= rdy_stall_cnt - 1;
        end else begin
            app_rdy_free_r <= 1'b1;
            if (($random % 5) == 0) rdy_stall_cnt <= (($random & 3) + 1);
        end
        if (wdf_stall_cnt != 0) begin
            app_wdf_rdy_r <= 1'b0; wdf_stall_cnt <= wdf_stall_cnt - 1;
        end else begin
            app_wdf_rdy_r <= 1'b1;
            if (($random % 6) == 0) wdf_stall_cnt <= (($random & 1) + 1);
        end
    end
end
assign app_wdf_rdy = app_wdf_rdy_r;

reg [15:0] rdq_addr_fifo  [0:RQDEPTH-1];
reg [5:0]  rdq_delay_fifo [0:RQDEPTH-1];
reg [1:0]  rdq_head, rdq_tail;
reg [2:0]  rdq_cnt;
reg [15:0]  wrq_addr_fifo  [0:WQDEPTH-1];
reg [127:0] wrq_data_fifo  [0:WQDEPTH-1];
reg [15:0]  wrq_mask_fifo  [0:WQDEPTH-1];
reg [5:0]   wrq_delay_fifo [0:WQDEPTH-1];
reg [1:0]   wrq_head, wrq_tail;
reg [2:0]   wrq_cnt;

assign app_rdy = app_rdy_free_r & (rdq_cnt < RQDEPTH) & (wrq_cnt < WQDEPTH);
wire rd_push   = app_en & app_rdy & (app_cmd == 3'b001);
wire wr_push   = app_en & app_rdy & (app_cmd == 3'b000) & app_wdf_wren & app_wdf_rdy;
wire rd_commit = (rdq_cnt != 0) & (rdq_delay_fifo[rdq_head] == 0);
wire wr_commit = (wrq_cnt != 0) & (wrq_delay_fifo[wrq_head] == 0);
assign app_rd_data_valid = rd_commit;
assign app_rd_data       = mig_mem[rdq_addr_fifo[rdq_head]];
assign app_rd_data_end   = rd_commit;

integer bi;
always @ (posedge mclk or negedge mrst_n) begin
    if (~mrst_n) begin
        rdq_head <= 0; rdq_tail <= 0; rdq_cnt <= 0;
        wrq_head <= 0; wrq_tail <= 0; wrq_cnt <= 0;
    end else begin
        if (rd_push) begin
            rdq_addr_fifo[rdq_tail]  <= app_line_idx;
            rdq_delay_fifo[rdq_tail] <= 4 + ($random & 15);
            rdq_tail <= rdq_tail + 2'd1;
        end
        if (rd_commit)
            rdq_head <= rdq_head + 2'd1;
        else if ((rdq_cnt != 0) && (rdq_delay_fifo[rdq_head] != 0))
            rdq_delay_fifo[rdq_head] <= rdq_delay_fifo[rdq_head] - 1'b1;
        case ({rd_push, rd_commit})
            2'b10:   rdq_cnt <= rdq_cnt + 3'd1;
            2'b01:   rdq_cnt <= rdq_cnt - 3'd1;
            default: rdq_cnt <= rdq_cnt;
        endcase
        if (wr_push) begin
            wrq_addr_fifo[wrq_tail]  <= app_line_idx;
            wrq_data_fifo[wrq_tail]  <= app_wdf_data;
            wrq_mask_fifo[wrq_tail]  <= app_wdf_mask;
            wrq_delay_fifo[wrq_tail] <= 2 + ($random & 7);
            wrq_tail <= wrq_tail + 2'd1;
        end
        if (wr_commit) begin
            for (bi = 0; bi < 16; bi = bi + 1)
                if (~wrq_mask_fifo[wrq_head][bi])
                    mig_mem[wrq_addr_fifo[wrq_head]][bi*8 +: 8] <= wrq_data_fifo[wrq_head][bi*8 +: 8];
            wrq_head <= wrq_head + 2'd1;
        end else if ((wrq_cnt != 0) && (wrq_delay_fifo[wrq_head] != 0))
            wrq_delay_fifo[wrq_head] <= wrq_delay_fifo[wrq_head] - 1'b1;
        case ({wr_push, wr_commit})
            2'b10:   wrq_cnt <= wrq_cnt + 3'd1;
            2'b01:   wrq_cnt <= wrq_cnt - 3'd1;
            default: wrq_cnt <= wrq_cnt;
        endcase
    end
end
`endif

// ================= program load =================
reg [31:0] prog [0:262143];   // 1MB as 32bit words
integer i;
reg [1023:0] hexfile;
integer maxcyc;
reg trace;
reg commit;

initial begin
    if (!$value$plusargs("HEX=%s", hexfile))
        hexfile = "test.hex";
    if (!$value$plusargs("MAXCYC=%d", maxcyc))
        maxcyc = 200000;
    trace = $test$plusargs("TRACE");
    commit = $test$plusargs("COMMIT");

    for (i = 0; i < 262144; i = i + 1)
        prog[i] = 32'h0000_0000;
    $readmemh(hexfile, prog);
    for (i = 0; i < 65536; i = i + 1)
`ifdef MEM_SDRAM
        dram_top_i.sdram_if.mem[i] = { prog[i*4+3], prog[i*4+2], prog[i*4+1], prog[i*4+0] };
`else
        mig_mem[i] = { prog[i*4+3], prog[i*4+2], prog[i*4+1], prog[i*4+0] };
`endif
end

// ================= run =================
integer cyc;
initial begin
    cpu_start = 0;
    rst_n  = 0;
    mrst_n = 0;
    repeat (10) @(posedge clk);
    rst_n = 1;
    repeat (4) @(posedge mclk);
    mrst_n = 1;
    // wait sdram init (mclk) -> start
    repeat (40) @(posedge clk);
    @(negedge clk);
    cpu_start = 1;
    @(negedge clk);
    cpu_start = 0;
end

always @ (posedge clk) begin
    if (~rst_n)
        cyc <= 0;
    else begin
        cyc <= cyc + 1;
        if (cyc == maxcyc) begin
            $display("TIMEOUT : %0d cycles, pc_id=0x%08x", cyc, {dut.pc_id, 2'b00});
            $display("RESULT: TIMEOUT");
            $finish;
        end
    end
end

// ================= MMIO monitor =================
always @ (posedge clk) begin
    if (rst_n & dma_io_we) begin
        if (dma_io_wadr == TOHOST_ADR) begin
            if (dma_io_wdata == 32'd1) begin
                $display("[%0d] TOHOST = 1", cyc);
                $display("RESULT: PASS");
            end
            else begin
                $display("[%0d] TOHOST = 0x%08x", cyc, dma_io_wdata);
                $display("RESULT: FAIL (code 0x%08x)", dma_io_wdata);
            end
            #1 $finish;
        end
        else if ((dma_io_wadr == PUTC_ADR) | (dma_io_wadr == UART_TX_ADR))
            $write("%c", dma_io_wdata[7:0]);
    end
end

// ================= commit log =================
always @ (posedge clk) begin
    if (commit & rst_n) begin
        if (dut.wbk_rd_reg_wb & (dut.rd_adr_wb != 5'd0))
            $display("C %0d WB x%0d=%08x pc=%08x", cyc, dut.rd_adr_wb, dut.wbk_data_wb, {dut.pc_wb, 2'b00});
        if (dma_io_we)
            $display("C %0d IO %05x=%08x", cyc, {dma_io_wadr, 2'b00}, dma_io_wdata);
        if (dcw_start_rq)
            $display("C %0d DCW %08x=%032x", cyc, dcw_in_addr, dcw_in_data);
    end
end

// ================= trace =================
always @ (posedge clk) begin
    if (trace & rst_n & ~stall_u & dut.g_exception)
        $display("[%0d] TRAP g_exception pc_ex=0x%08x pc_ma=0x%08x", cyc, {dut.pc_ex, 2'b00}, {dut.pc_ma, 2'b00});
    if (trace & rst_n & dut.ecall_condition_ex)
        $display("[%0d] TRAP ecall/illegal pc_ex=0x%08x", cyc, {dut.pc_ex, 2'b00});
end

endmodule
