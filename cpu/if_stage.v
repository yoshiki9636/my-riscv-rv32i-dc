/*
 * My RISC-V RV32I CPU
 *   CPU Instruction Fetch Stage Module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2021 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 * @version		0.2 add ecall
 */

module if_stage
	#(parameter IWIDTH = 14)
	(
	input clk,
	input rst_n,
	// to ID stage
	output [31:0] inst_id,
	output [31:2] pc_id,
	// from EX stage : jmp/br
	input jmp_condition_ex,
	input [31:2] jmp_adr_ex,
	input ecall_condition_ex,
	input [31:2] csr_mtvec_ex,
	input cmd_mret_ex,
	input [31:2] csr_mepc_ex,
	input cmd_sret_ex,
	input [31:2] csr_sepc_ex,
	input cmd_uret_ex,
    input g_interrupt,
	output post_jump_cmd_cond,
	input g_exception,
	// from monitor
	input [IWIDTH+1:2] i_ram_radr,
	output [31:0] i_ram_rdata,
	input [IWIDTH+1:2] i_ram_wadr, // unused
	input [31:0] i_ram_wdata, // unused
	input i_ram_wen, // unused
	input i_read_sel,

	// from dram bus
	input [127:0] ic_rdat_m_data,
	input [15:0] ic_rdat_m_mask, // unused
	input ic_rdat_m_valid,

	// from/to ilu
	input [IWIDTH-3:0] ic_ram_wadr_all,

	output [31:2] pc_if,
	output reg [31:2] pc_id_pre,
	//output pc_valid_id, // currently set to 1'b1

	// other place
	input pc_start,
	input [31:2] start_adr_lat,
	input dc_wbback_state,
	input stall,
	input stall_1shot,
	input stall_dly,
	input stall_ld,
	input stall_ld_ex,
	input rst_pipe,
	input dc_stall_fin,
	input dc_stall_fin2,
	input ic_stall,
	input ic_stall_dly,
	input ic_stall_fin,
	input ic_stall_fin2,
	output reg stall_ld_add,
	output [31:0] pc_data
	);


// valid signal
//assign pc_valid_id = 1'b1; // zantei
//reg [31:2] pc_if;
reg post_intr_ecall_exception;
wire intr_ecall_exception = ecall_condition_ex | g_interrupt | g_exception ;
wire jump_cmd_cond = jmp_condition_ex | cmd_mret_ex | cmd_sret_ex | cmd_uret_ex;

wire jmp_cond = intr_ecall_exception | ( jump_cmd_cond & ~post_intr_ecall_exception);
wire [31:2] jmp_adr = intr_ecall_exception ? csr_mtvec_ex :
                      cmd_mret_ex ? csr_mepc_ex :
                      cmd_sret_ex ? csr_sepc_ex : jmp_adr_ex;

reg use_collision;
reg [31:2] pc_if_pre;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		pc_if_pre <= 30'd0;
	else if (pc_start)
		pc_if_pre <= start_adr_lat;
	else if (stall | stall_ld)
		pc_if_pre <= pc_if_pre;	
	else if (jmp_cond)
		pc_if_pre <= jmp_adr;
	else if (ic_stall)
		pc_if_pre <= pc_if_pre;	
	else
		pc_if_pre <= pc_if + 30'd1;
end

reg [31:2] pc_if_roll;

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        pc_if_roll <= 30'd0;
	else if (pc_start)
		pc_if_roll <= start_adr_lat;
	else if (jmp_cond)
        pc_if_roll <= jmp_adr;
	else if (~ic_stall)
        pc_if_roll <= pc_if_pre;
end

//assign pc_if = pc_if_pre;
assign pc_if = ic_stall_dly ? pc_if_roll : pc_if_pre;

//reg [31:2] pc_id_pre;
reg [31:2] pc_collision;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n)
		pc_id_pre <= 30'd0;
	else if (rst_pipe)
		pc_id_pre <= 30'd0;
	else if (ic_stall | stall | stall_ld)
		pc_id_pre <= pc_id_pre;	
	else
		pc_id_pre <= pc_if;
end

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        pc_collision <= 30'd0;
	else if (rst_pipe)
        pc_collision <= 30'd0;	
	else if (stall_1shot & stall_ld_ex )
        pc_collision <= pc_id;
end

assign pc_id = use_collision ?  pc_collision : pc_id_pre;
assign pc_data = {pc_if, 2'd0};

// instruction RAM

//wire [11:0] inst_radr_if; // input
wire [31:0] inst_rdata_id; // output
wire [IWIDTH+1:2] iram_radr;

//assign inst_radr_if = pc_if[IWIDTH+1:2]; // depend on size of iram
assign iram_radr = i_read_sel ? i_ram_radr : pc_if[IWIDTH+1:2] ;
assign i_ram_rdata = inst_rdata_id;

/*
inst_1r1w #(.IWIDTH(IWIDTH)) inst_1r1w (
	.clk(clk),
	.ram_radr(iram_radr),
	.ram_rdata(inst_rdata_id),
	.ram_wadr(i_ram_wadr),
	.ram_wdata(i_ram_wdata),
	.ram_wen(i_ram_wen)
	);
*/
inst_ram #(.IWIDTH(IWIDTH)) inst_ram (
	.clk(clk),
	.rst_n(rst_n),
	.ram_radr_part(iram_radr),
	.ram_rdata(inst_rdata_id),
	// direct write from monitor unsupported
	//.ram_wadr(i_ram_wadr),
	//.ram_wdata(i_ram_wdata),
	//.ram_wen(i_ram_wen),
	.ram_wadr_all(ic_ram_wadr_all),
	.ram_wdata_all(ic_rdat_m_data),
	.ram_wen_all(ic_rdat_m_valid)
	);

reg [31:0] inst_roll;
reg [31:0] inst_collision;
reg [2:0] dc_after_ic;
reg [2:0] ic_after_dc;

wire ic_stall_1shot = ic_stall & ~ic_stall_dly;

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        inst_roll <= 32'h0000_0013;
	else if (rst_pipe)
        inst_roll <= 32'h0000_0013;	
	//else if (ic_stall_1shot & stall_1shot)
        //inst_roll <= inst_rdata_id;
	//else if (ic_stall_fin2 & stall )
	//else if (ic_stall_fin  & stall & (dc_after_ic == 3'b010 ) & (ic_after_dc == 3'b100))
        //inst_roll <= inst_rdata_id;
	else if (ic_stall_fin2 & stall & (dc_after_ic == 3'b010 ) & (ic_after_dc == 3'b100))
        inst_roll <= inst_roll;
	else if (ic_stall_fin  & stall & (dc_after_ic == 3'b010 ) & (ic_after_dc == 3'b011))
        //inst_roll <= inst_rdata_id;
        inst_roll <= inst_roll;
	else if (ic_stall_fin2 & stall & (dc_after_ic == 3'b010 ) & (ic_after_dc == 3'b011))
        inst_roll <= inst_roll;
	else if (ic_stall_fin2 & stall & (dc_after_ic == 3'b010 ))
        inst_roll <= inst_rdata_id;
	else if (ic_stall_fin2 & stall & (dc_after_ic == 3'b110 ) & (ic_after_dc == 3'b100))
        inst_roll <= inst_roll;
	else if (ic_stall_fin2 & stall & (dc_after_ic == 3'b110 ) & (ic_after_dc == 3'b110))
        inst_roll <= inst_roll;
	else if (ic_stall_fin2 & stall & (dc_after_ic == 3'b110 ))
        inst_roll <= inst_rdata_id;
	//else if (ic_stall_fin & stall )
	//else if (ic_stall_fin2 & stall & (dc_after_ic == 3'b010 ) & (ic_after_dc == 3'b010))
        //inst_roll <= inst_rdata_id;
	//else if ( stall_1shot | ~stall_dly & stall_ld )
	//else if ((~ic_stall | (ic_after_dc != 2'b00)) & ( stall_1shot | ~stall_dly & stall_ld ))
	else if (~ic_stall & ( stall_1shot | ~stall_dly & stall_ld ))
        inst_roll <= inst_rdata_id;
end

reg post_jump_cmd_c2;
reg stall_ld_ex_smpl;

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
		stall_ld_ex_smpl <= 1'b0;
	else if (~ic_stall)
		stall_ld_ex_smpl <= 1'b0;
	else if (ic_stall & ~ic_stall_dly & ~post_jump_cmd_c2 & stall_ld_ex)
		stall_ld_ex_smpl <= 1'b1;
end

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        inst_collision <= 32'h0000_0013;
	else if (rst_pipe)
        inst_collision <= 32'h0000_0013;	
	else if (stall_1shot & stall_ld_ex )
        inst_collision <= inst_roll;
end

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        use_collision <= 1'b0;
	else if (rst_pipe)
        use_collision <= 1'b0;
	else if (dc_stall_fin2)
        use_collision <= 1'b0;
	else if (stall_1shot & stall_ld_ex )
        use_collision <= 1'b1;
end

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        stall_ld_add <= 1'b0;
	else if (rst_pipe)
        stall_ld_add <= 1'b0;
	else if (dc_stall_fin)
        stall_ld_add <= 1'b0;
	else if (stall_1shot & stall_ld_ex )
        stall_ld_add <= 1'b1;
end

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        ic_after_dc <= 3'b000;
	else if (~ic_stall & ~stall)
        ic_after_dc <= 3'b000;
	else if (dc_wbback_state & (ic_after_dc == 3'b001))
        ic_after_dc <= 3'b100;
	else if (dc_wbback_state & (ic_after_dc[1:0] == 2'b10))
        ic_after_dc <= 3'b000;
	else if (ic_stall_1shot & stall_1shot)
        //ic_after_dc <= 3'b010;
        ic_after_dc <= 3'b110;
	else if (~ic_stall & stall & (ic_after_dc == 3'b000))
        ic_after_dc <= 3'b001;
	else if (ic_stall & stall & (ic_after_dc == 3'b001))
        ic_after_dc <= 3'b010;
	else if (ic_stall & ~stall & (ic_after_dc == 3'b010))
        ic_after_dc <= 3'b011;
	//else
        //ic_after_dc <= 2'b00;
end

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        dc_after_ic <= 3'b000;
	else if (~ic_stall & ~stall)
        dc_after_ic <= 3'b000;
	else if (ic_stall & ~stall & (dc_after_ic == 3'b000))
        dc_after_ic <= 3'b001;
	else if (dc_wbback_state & ic_stall & stall & (ic_after_dc != 3'b000))
        dc_after_ic <= 3'b110;
	else if (ic_stall & stall & (dc_after_ic == 3'b001))
        dc_after_ic <= 3'b010;
	else if (~ic_stall & stall & (dc_after_ic == 3'b010))
        dc_after_ic <= 3'b011;
	else if (~ic_stall & stall & (dc_after_ic == 3'b110))
        dc_after_ic <= 3'b111;
	//else
        //ic_after_dc <= 2'b00;
end

                 //((dc_after_ic == 3'b111) & dc_stall_fin2) ? inst_rdata_id : // 
assign inst_id = ((ic_after_dc == 3'b011) & ic_stall_fin2) ? use_collision ? inst_collision : inst_roll : // for ic stall after dc stall
                 ((dc_after_ic == 3'b011) & dc_stall_fin2) ? use_collision ? inst_collision : inst_roll : // 
                 ((dc_after_ic == 3'b111) & dc_stall_fin2) ? use_collision ? inst_collision : inst_roll : // 
                 ( stall_ld_ex_smpl & ic_stall_fin2) ? inst_roll :
                 //((ic_stall|ic_stall_dly)&dc_stall_fin2) ? inst_roll : // 1shot ok dc stall inside ic stall
                 (ic_stall|ic_stall_dly) ? 32'h0000_0013 : // nop for icache stall
                 use_collision  ?  inst_collision : // for load store btb
                 (stall_dly | stall_ld_ex) ? inst_roll : // for load bypass pattern without store
                 inst_rdata_id; // other condisitons

// post interrupt / ecall timing
always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n)
        post_intr_ecall_exception <= 1'b0;
	else
        post_intr_ecall_exception <= intr_ecall_exception;
end

// post cump command condition
reg post_jump_cmd_c;

always @ (posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
        post_jump_cmd_c <= 1'b0;
        post_jump_cmd_c2 <= 1'b0;
	end
	else begin
        post_jump_cmd_c <= jump_cmd_cond;
        post_jump_cmd_c2 <= post_jump_cmd_c;
	end
end

assign post_jump_cmd_cond = post_jump_cmd_c;


endmodule
