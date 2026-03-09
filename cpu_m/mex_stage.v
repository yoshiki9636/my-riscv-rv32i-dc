/*
 * My RISC-V RV32I CPU
 *   CPU Execution Stage Module
 *    Verilog code
 * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
 * @copylight	2026 Yoshiki Kurokawa
 * @license		https://opensource.org/licenses/MIT     MIT license
 * @version		0.1
 */

module mex_stage(
	input clk,
	input rst_n,

	// from EX
	input [31:0] rs1_sel,
	input [31:0] rs2_sel,
    // microcode

	input cmd_mul_ex,
	input cmd_mulh_ex,
	input cmd_mulhsu_ex,
	input cmd_mulhu_ex,
	input cmd_div_ex,
	input cmd_divu_ex,
	input cmd_rem_ex,
	input cmd_remu_ex,
	input cmd_mul_decode_ex,
	input cmd_div_decode_ex,
	input cmd_rem_decode_ex,

	// to EX
	output [31:0] m_result_ex,
	output m_cmd_finished,
	output divide_by_zero,
	output div_stall

	);


// mult all

wire signed [63:0] mult_ss = $signed( rs1_sel ) * $signed( rs2_sel );
wire signed [63:0] mult_su = $signed( rs1_sel ) * $signed( {1'b0, rs2_sel} );
wire signed [63:0] mult_uu = rs1_sel * rs2_sel;

wire [31:0] mult_sel = cmd_mul_ex ? mult_ss[31:0] :
                       cmd_mulh_ex ? mult_ss[63:32] :
                       cmd_mulhsu_ex ? mult_su[63:32] :
                       cmd_mulhu_ex ? mult_uu[63:32] : 32'd0;

wire mul_cmds = cmd_mul_ex | cmd_mulh_ex | cmd_mulhsu_ex | cmd_mulhu_ex;

// div
// setup: signed -> unsignd

wire [31:0] inv_rs1_sel = ( ~rs1_sel ) + 32'd1;
wire [31:0] inv_rs2_sel = ( ~rs2_sel ) + 32'd1;
wire sign_rs1_sel = rs1_sel[31] & (cmd_div_ex | cmd_rem_ex);
wire sign_rs2_sel = rs2_sel[31] & (cmd_div_ex | cmd_rem_ex);
wire sign_result = sign_rs1_sel ^ sign_rs2_sel;
wire [31:0] us_rs1_sel = sign_rs1_sel ? inv_rs1_sel : rs1_sel;
wire [31:0] us_rs2_sel = sign_rs2_sel ? inv_rs2_sel : rs2_sel;

// upper 0 bit encoder

function [5:0] upper0enc ;
input [31:0] bits;
begin
	casez(bits)
        32'b1???_????_????_????_????_????_????_????: upper0enc = 6'd0;
        32'b01??_????_????_????_????_????_????_????: upper0enc = 6'd1;
        32'b001?_????_????_????_????_????_????_????: upper0enc = 6'd2;
        32'b0001_????_????_????_????_????_????_????: upper0enc = 6'd3;
        32'b0000_1???_????_????_????_????_????_????: upper0enc = 6'd4;
        32'b0000_01??_????_????_????_????_????_????: upper0enc = 6'd5;
        32'b0000_001?_????_????_????_????_????_????: upper0enc = 6'd6;
        32'b0000_0001_????_????_????_????_????_????: upper0enc = 6'd7;
        32'b0000_0000_1???_????_????_????_????_????: upper0enc = 6'd8;
        32'b0000_0000_01??_????_????_????_????_????: upper0enc = 6'd9;
        32'b0000_0000_001?_????_????_????_????_????: upper0enc = 6'd10;
        32'b0000_0000_0001_????_????_????_????_????: upper0enc = 6'd11;
        32'b0000_0000_0000_1???_????_????_????_????: upper0enc = 6'd12;
        32'b0000_0000_0000_01??_????_????_????_????: upper0enc = 6'd13;
        32'b0000_0000_0000_001?_????_????_????_????: upper0enc = 6'd14;
        32'b0000_0000_0000_0001_????_????_????_????: upper0enc = 6'd15;
        32'b0000_0000_0000_0000_1???_????_????_????: upper0enc = 6'd16;
        32'b0000_0000_0000_0000_01??_????_????_????: upper0enc = 6'd17;
        32'b0000_0000_0000_0000_001?_????_????_????: upper0enc = 6'd18;
        32'b0000_0000_0000_0000_0001_????_????_????: upper0enc = 6'd19;
        32'b0000_0000_0000_0000_0000_1???_????_????: upper0enc = 6'd20;
        32'b0000_0000_0000_0000_0000_01??_????_????: upper0enc = 6'd21;
        32'b0000_0000_0000_0000_0000_001?_????_????: upper0enc = 6'd22;
        32'b0000_0000_0000_0000_0000_0001_????_????: upper0enc = 6'd23;
        32'b0000_0000_0000_0000_0000_0000_1???_????: upper0enc = 6'd24;
        32'b0000_0000_0000_0000_0000_0000_01??_????: upper0enc = 6'd25;
        32'b0000_0000_0000_0000_0000_0000_001?_????: upper0enc = 6'd26;
        32'b0000_0000_0000_0000_0000_0000_0001_????: upper0enc = 6'd27;
        32'b0000_0000_0000_0000_0000_0000_0000_1???: upper0enc = 6'd28;
        32'b0000_0000_0000_0000_0000_0000_0000_01??: upper0enc = 6'd29;
        32'b0000_0000_0000_0000_0000_0000_0000_001?: upper0enc = 6'd30;
        32'b0000_0000_0000_0000_0000_0000_0000_0001: upper0enc = 6'd31;
        32'b0000_0000_0000_0000_0000_0000_0000_0000: upper0enc = 6'd32;
    endcase
end
endfunction

wire [5:0] lbits_rs1 = upper0enc( us_rs1_sel );
wire [5:0] lbits_rs2 = upper0enc( us_rs2_sel );
wire [5:0] lbits_diff = lbits_rs2 - lbits_rs1;

wire zero_dividend = lbits_rs1[5];
assign divide_by_zero = lbits_rs2[5];
wire divisor_bigger_dividend = ( us_rs2_sel > us_rs1_sel);

wire [31:0] rs1_lsh = ( us_rs1_sel << lbits_rs1[4:0] );
wire [31:0] rs2_lsh = ( us_rs2_sel << lbits_rs2[4:0] );

wire div_start = (cmd_div_decode_ex | cmd_rem_decode_ex) & ~( zero_dividend | divide_by_zero | divisor_bigger_dividend );


// state machine
reg [1:0] div_state;
reg [5:0] cntr;

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n)
		div_state <= 2'b00;
	else if ((div_state == 2'b00)&&(div_start))
		div_state <= 2'b01;
	else if ((div_state == 2'b01)&&(cntr == 6'd0))
		div_state <= 2'b10;
	else if (div_state == 2'b10)
		div_state <= 2'b00;
end

wire div_result_valid = (div_state == 2'b10);


reg [31:0] dividend_mex1;
reg [31:0] divisor_mex1;
reg [31:0] preserved_divisor;
reg [31:0] quotient_mex1;
reg [5:0] lbits_rs1_mex1;
reg [5:0] lbits_diff_mex1;
reg sign_div_mx1;
reg sign_rem1_mx1;
reg sign_rem2_mx1;
reg mode_rem_mx1;
wire [31:0] dividend_next;
wire [31:0] divisor_next;
wire quotient_bit;

always @ ( posedge clk or negedge rst_n) begin   
	if (~rst_n) begin
		dividend_mex1 <= 32'd0;
		divisor_mex1 <= 32'd0;
		quotient_mex1 <= 32'd0;
		cntr <= 6'd32;
		sign_div_mx1 <= 1'b0;
		sign_rem1_mx1 <= 1'b0;
		sign_rem2_mx1 <= 1'b0;
		mode_rem_mx1 <= 1'b0;
		preserved_divisor <= 32'd0;
		lbits_rs1_mex1 <= 6'd0;
		lbits_diff_mex1 <= 6'd0;
	end
	else if (div_start) begin
		dividend_mex1 <= rs1_lsh;
		divisor_mex1 <= rs2_lsh;
		quotient_mex1 <= 32'd0;
		cntr <= lbits_diff;
		sign_div_mx1 <= sign_result;
		sign_rem1_mx1 <= sign_rs1_sel;
		sign_rem2_mx1 <= sign_rs2_sel;
		mode_rem_mx1 <= cmd_rem_decode_ex;
		preserved_divisor <= rs2_lsh;
		lbits_rs1_mex1 <= lbits_rs1;
		lbits_diff_mex1 <= lbits_diff;
	end
	else if(cntr[5] == 1'b0) begin
		dividend_mex1 <= dividend_next;
		divisor_mex1 <= divisor_next;
		quotient_mex1[cntr] <= quotient_bit;
		cntr <= cntr - 6'd1;
		preserved_divisor <= divisor_mex1;
	end
end

assign quotient_bit = ( dividend_mex1 >= divisor_mex1 );
assign dividend_next = quotient_bit ? dividend_mex1 - divisor_mex1 : dividend_mex1;
assign divisor_next = divisor_mex1 >> 1;

wire div_result_end = cntr[5] ;

// post shift and signed

wire [5:0] rsbits_div = 6'd31 - lbits_diff_mex1;

//wire [31:0] div_result = quotient_mex1 >> rsbits_div;
wire [31:0] inv_div_result = ( ~quotient_mex1 ) + 32'd1;
wire [31:0] sign_div_result = sign_div_mx1 ? inv_div_result : quotient_mex1;
wire [31:0] final_div_result = divide_by_zero ? 32'hffff_ffff :
                               div_result_valid ? sign_div_result : 32'd0;
                               //(zero_dividend | divisor_bigger_dividend) ? 32'd0 

// reminder

wire sing_ptn_xor = sign_rem1_mx1 ^ sign_rem2_mx1;

wire [31:0] onemore_dividend_mex1 = dividend_mex1 - preserved_divisor;
wire [31:0] rem_tmp = sing_ptn_xor ? onemore_dividend_mex1 : dividend_mex1;
wire [31:0] inv_rem_tmp = ( ~rem_tmp ) + 32'd1;
wire [31:0] rem_tmp2 = sign_rem1_mx1 ? inv_rem_tmp : rem_tmp;
wire signed [31:0] rem_result = $signed( rem_tmp2 ) >>> $signed( lbits_rs1_mex1 );

wire [31:0] final_rem_result = div_result_valid ? rem_result :
                               divide_by_zero ? rs1_sel :
                               divisor_bigger_dividend ? rs1_sel : 32'd0;

// state is valid even if divide by logic
assign div_stat_valid =  (zero_dividend | divide_by_zero | divisor_bigger_dividend) & cmd_div_decode_ex | div_result_valid;

assign m_result_ex = cmd_mul_decode_ex ? mult_sel :
                     mode_rem_mx1 ? final_rem_result : final_div_result;

assign div_stall = div_start | (cntr[5] == 1'b0);

assign m_cmd_finished = mul_cmds | div_stat_valid;

endmodule
