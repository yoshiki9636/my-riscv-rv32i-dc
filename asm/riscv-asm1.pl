#!/usr/bin/perl
#/*
# * My RISC-V RV32I CPU
# *   RV32I Simple Assembler 
# *    Perl code
# * @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
# * @copylight	2021 Yoshiki Kurokawa
# * @license		https://opensource.org/licenses/MIT     MIT license
# * @version		0.1
# * @version		0.2 define is added
# */

use Getopt::Long;


GetOptions('v' => \$v, 'p=s' => \$p);

if (defined($p)) {
 	if ($p =~ /^0x/) { $pc = hex($p); }
	else { $pc = int($p); }
}
else {
	$pc = 0;
}
$name = $ARGV[0];
@value = ();
%defvalue = ();

while(<>) {
	if (/^;offset\s+(\w)/) { next; }
	elsif (/^;/) { next; }
	elsif (/^:(\w+)/) { $value{$1} = $pc; }
	elsif (/^#immdefine (\w+) (\w+)/) {
		@def = ( @def, $1 );
		$s = $1;
		$w = $2;
 		if ($w =~ /^0x/) { $defvalue{$s} = hex($w); }
		else { $defvalue{$s} = int($w); }
	}
	elsif (/^\s*nop/) {
		$pc += 4; }
	elsif (/^\s*lui\s+x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*auipc\s+x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*addi\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*slti\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*sltiu\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*xori\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*ori\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*andi\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*slli\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*srli\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*srai\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*add\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$pc += 4; }
	elsif (/^\s*sub\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$pc += 4; }
	elsif (/^\s*sll\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$pc += 4; }
	elsif (/^\s*slt\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$pc += 4; }
	elsif (/^\s*sltu\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$pc += 4; }
	elsif (/^\s*xor\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$pc += 4; }
	elsif (/^\s*srl\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$pc += 4; }
	elsif (/^\s*sra\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$pc += 4; }
	elsif (/^\s*or\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$pc += 4; }
	elsif (/^\s*and\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$pc += 4; }
	elsif (/^\s*lb\s+x(\d+),\s*(\w+)\s*\(\s*x(\d+)\s*\)/) {
		$pc += 4; }
	elsif (/^\s*lh\s+x(\d+),\s*(\w+)\s*\(\s*x(\d+)\s*\)/) {
		$pc += 4; }
	elsif (/^\s*lw\s+x(\d+),\s*(\w+)\s*\(\s*x(\d+)\s*\)/) {
		$pc += 4; }
	elsif (/^\s*lbu\s+x(\d+),\s*(\w+)\s*\(\s*x(\d+)\s*\)/) {
		$pc += 4; }
	elsif (/^\s*lhu\s+x(\d+),\s*(\w+)\s*\(\s*x(\d+)\s*\)/) {
		$pc += 4; }
	elsif (/^\s*sb\s+x(\d+),\s*(\w+)\s*\(\s*x(\d+)\s*\)/) {
		$pc += 4; }
	elsif (/^\s*sh\s+x(\d+),\s*(\w+)\s*\(\s*x(\d+)\s*\)/) {
		$pc += 4; }
	elsif (/^\s*sw\s+x(\d+),\s*(\w+)\s*\(\s*x(\d+)\s*\)/) {
		$pc += 4; }
	elsif (/^\s*jal\s+x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*jalr\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*beq\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*bne\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*blt\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*bge\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*bltu\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*bgeu\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*csrr[wsc]\s+x(\d+),\s*(\w+),\s*x(\d+)/) {
		$pc += 4; }
	elsif (/^\s*csrr[wsc]i\s+x(\d+),\s*(\w+),\s*(\w+)/) {
		$pc += 4; }
	elsif (/^\s*ecall/) {
		$pc += 4; }
	elsif (/^\s*mret/) {
		$pc += 4; }
	elsif (/^\s*illegal_ops/) {
		$pc += 4; }
}

$ARGV[0] = $name;
if (defined($p)) {
 	if ($p =~ /^0x/) { $pc = hex($p); }
	else { $pc = int($p); }
}
else {
	$pc = 0;
}
$jump_offset = 0;

while(<>) {
	if (/^;offset\s+(\w)/) {
		$w = $1;
		if ($w =~ /^0x/) { $jump_offset = hex($w); } else { $sump_offset = $w; }
 	}
	elsif (/^;/) { next; }
	elsif (/^#immdefine/) { next; }
	elsif (/^:(\w+)/) {
		if ($v == 1) {
			print " // $_";
		}
		next;
	}
	elsif (/^\s*$/) { next; }
	elsif (/^\s*nop/) {
		$code = 0x00000013;
	}
	elsif (/^\s*lui\s+x(\d+),\s*(\w+)/) {
		$rd = $1 << 7;
		#if (defined($defvalue{$2})) { $imm = $defvalue{$2} << 12; } else { $imm = $2 << 12; }
		$w = $2;
		if (defined($defvalue{$w})) { $imm = $defvalue{$w} << 12; } elsif ($w =~ /^0x/) { $imm = hex($w) << 12 ; } else { $imm = $w << 12; }
		$op1 = 0x0d << 2;
		$code = $imm + $rd + $op1 + 3;
	}
	elsif (/^\s*auipc\s+x(\d+),\s*(\w+)/) {
		$rd = $1 << 7;
		#if (defined($defvalue{$2})) { $imm = $defvalue{$2} << 12; } else { $imm = $2 << 12; }
		$w = $2;
		if (defined($defvalue{$w})) { $imm = $defvalue{$w} << 12; } elsif ($w =~ /^0x/) { $imm = hex($w) << 12 ; } else { $imm = $w << 12; }
		$op1 = 0x05 << 2;
		$code = $imm + $rd + $op1 + 3;
	}
	elsif (/^\s*addi\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		#if (defined($defvalue{$3})) { $imm = $defvalue{$3} << 20; } else { $imm = $3 << 20; }
		$w = $3;
		if (defined($defvalue{$w})) { $imm = $defvalue{$w} << 20; } elsif ($w =~ /^0x/) { $imm = hex($w) << 20 ; } else { $imm = $w << 20; }
		#print "$w $imm\n";
		$op1 = 0x04 << 2;
		$op2 = 0x0 << 12;
		$code = $imm + $rs1 + $rd + $op1 + $op2 + 3;
	}
	elsif (/^\s*slti\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		#if (defined($defvalue{$3})) { $imm = $defvalue{$3} << 20; } else { $imm = $3 << 20; }
		$w = $3;
		if (defined($defvalue{$w})) { $imm = $defvalue{$w} << 20; } elsif ($w =~ /^0x/) { $imm = hex($w) << 20 ; } else { $imm = $w << 20; }
		$op1 = 0x04 << 2;
		$op2 = 0x2 << 12;
		$code = $imm + $rs1 + $rd + $op1 + $op2 + 3;
	}
	elsif (/^\s*sltiu\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		#if (defined($defvalue{$3})) { $imm = $defvalue{$3} << 20; } else { $imm = $3 << 20; }
		$w = $3;
		if (defined($defvalue{$w})) { $imm = $defvalue{$w} << 20; } elsif ($w =~ /^0x/) { $imm = hex($w) << 20 ; } else { $imm = $w << 20; }
		$op1 = 0x04 << 2;
		$op2 = 0x3 << 12;
		$code = $imm + $rs1 + $rd + $op1 + $op2 + 3;
	}
	elsif (/^\s*xori\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		#if (defined($defvalue{$3})) { $imm = $defvalue{$3} << 20; } else { $imm = $3 << 20; }
		$w = $3;
		if (defined($defvalue{$w})) { $imm = $defvalue{$w} << 20; } elsif ($w =~ /^0x/) { $imm = hex($w) << 20 ; } else { $imm = $w << 20; }
		$op1 = 0x04 << 2;
		$op2 = 0x4 << 12;
		$code = $imm + $rs1 + $rd + $op1 + $op2 + 3;
	}
	elsif (/^\s*ori\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		#if (defined($defvalue{$3})) { $imm = $defvalue{$3} << 20; } else { $imm = $3 << 20; }
		$w = $3;
		if (defined($defvalue{$w})) { $imm = $defvalue{$w} << 20; } elsif ($w =~ /^0x/) { $imm = hex($w) << 20 ; } else { $imm = $w << 20; }
		$op1 = 0x04 << 2;
		$op2 = 0x6 << 12;
		$code = $imm + $rs1 + $rd + $op1 + $op2 + 3;
	}
	elsif (/^\s*andi\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		#if (defined($defvalue{$3})) { $imm = $defvalue{$3} << 20; } else { $imm = $3 << 20; }
		$w = $3;
		if (defined($defvalue{$w})) { $imm = $defvalue{$w} << 20; } elsif ($w =~ /^0x/) { $imm = hex($w) << 20 ; } else { $imm = $w << 20; }
		$op1 = 0x04 << 2;
		$op2 = 0x7 << 12;
		$code = $imm + $rs1 + $rd + $op1 + $op2 + 3;
	}
	elsif (/^\s*slli\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		$shamt = $3 << 20;
		$op1 = 0x04 << 2;
		$op2 = 0x1 << 12;
		$op3 = 0x0 << 27;
		$code = $shamt + $rs1 + $rd + $op1 + $op2 + $op3 + 3;
	}
	elsif (/^\s*srli\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		$shamt = $3 << 20;
		$op1 = 0x04 << 2;
		$op2 = 0x5 << 12;
		$op3 = 0x0 << 27;
		$code = $shamt + $rs1 + $rd + $op1 + $op2 + $op3 + 3;
	}
	elsif (/^\s*srai\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		$shamt = $3 << 20;
		$op1 = 0x04 << 2;
		$op2 = 0x5 << 12;
		$op3 = 0x08 << 27;
		$code = $shamt + $rs1 + $rd + $op1 + $op2 + $op3 + 3;
	}
	elsif (/^\s*add\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		$rs2 = $3 << 20;
		$op1 = 0x0c << 2;
		$op2 = 0x0 << 12;
		$op3 = 0x00 << 27;
		$code = $rs2 + $rs1 + $rd + $op1 + $op2 + $op3 + 3;
	}
	elsif (/^\s*sub\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		$rs2 = $3 << 20;
		$op1 = 0x0c << 2;
		$op2 = 0x0 << 12;
		$op3 = 0x08 << 27;
		$code = $rs2 + $rs1 + $rd + $op1 + $op2 + $op3 + 3;
	}
	elsif (/^\s*sll\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		$rs2 = $3 << 20;
		$op1 = 0x0c << 2;
		$op2 = 0x1 << 12;
		$op3 = 0x00 << 27;
		$code = $rs2 + $rs1 + $rd + $op1 + $op2 + $op3 + 3;
	}
	elsif (/^\s*slt\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		$rs2 = $3 << 20;
		$op1 = 0x0c << 2;
		$op2 = 0x2 << 12;
		$op3 = 0x00 << 27;
		$code = $rs2 + $rs1 + $rd + $op1 + $op2 + $op3 + 3;
	}
	elsif (/^\s*sltu\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		$rs2 = $3 << 20;
		$op1 = 0x0c << 2;
		$op2 = 0x3 << 12;
		$op3 = 0x00 << 27;
		$code = $rs2 + $rs1 + $rd + $op1 + $op2 + $op3 + 3;
	}
	elsif (/^\s*xor\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		$rs2 = $3 << 20;
		$op1 = 0x0c << 2;
		$op2 = 0x4 << 12;
		$op3 = 0x00 << 27;
		$code = $rs2 + $rs1 + $rd + $op1 + $op2 + $op3 + 3;
	}
	elsif (/^\s*srl\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		$rs2 = $3 << 20;
		$op1 = 0x0c << 2;
		$op2 = 0x5 << 12;
		$op3 = 0x00 << 27;
		$code = $rs2 + $rs1 + $rd + $op1 + $op2 + $op3 + 3;
	}
	elsif (/^\s*sra\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		$rs2 = $3 << 20;
		$op1 = 0x0c << 2;
		$op2 = 0x5 << 12;
		$op3 = 0x08 << 27;
		$code = $rs2 + $rs1 + $rd + $op1 + $op2 + $op3 + 3;
	}
	elsif (/^\s*or\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		$rs2 = $3 << 20;
		$op1 = 0x0c << 2;
		$op2 = 0x6 << 12;
		$op3 = 0x00 << 27;
		$code = $rs2 + $rs1 + $rd + $op1 + $op2 + $op3 + 3;
	}
	elsif (/^\s*and\s+x(\d+),\s*x(\d+),\s*x(\d+)/) {
		$rd = $1 << 7;
		$rs1 =$2 << 15;
		$rs2 =$3 << 20;
		$op1 = 0x0c << 2;
		$op2 = 0x7 << 12;
		$op3 = 0x00 << 27;
		$code = $rs2 + $rs1 + $rd + $op1 + $op2 + $op3 + 3;
	}
	elsif (/^\s*lb\s+x(\d+),\s*(\w+)\s*\(\s*x(\d+)\s*\)/) {
		$rd = $1 << 7;
		$rs1 = $3 << 15;
		$ofs = $2 << 20;
		$op1 = 0x00 << 2;
		$op2 = 0x0 << 12;
		$code = $ofs + $rs1 + $rd + $op1 + $op2 + 3;
	}
	elsif (/^\s*lh\s+x(\d+),\s*(\w+)\s*\(\s*x(\d+)\s*\)/) {
		$rd = $1 << 7;
		$rs1 = $3 << 15;
		$ofs = $2 << 20;
		$op1 = 0x00 << 2;
		$op2 = 0x1 << 12;
		$code = $ofs + $rs1 + $rd + $op1 + $op2 + 3;
	}
	elsif (/^\s*lw\s+x(\d+),\s*(\w+)\s*\(\s*x(\d+)\s*\)/) {
		$rd = $1 << 7;
		$rs1 = $3 << 15;
		$ofs = $2 << 20;
		$op1 = 0x00 << 2;
		$op2 = 0x2 << 12;
		$code = $ofs + $rs1 + $rd + $op1 + $op2 + 3;
	}
	elsif (/^\s*lbu\s+x(\d+),\s*(\w+)\s*\(\s*x(\d+)\s*\)/) {
		$rd = $1 << 7;
		$rs1 = $3 << 15;
		$ofs = $2 << 20;
		$op1 = 0x00 << 2;
		$op2 = 0x4 << 12;
		$code = $ofs + $rs1 + $rd + $op1 + $op2 + 3;
	}
	elsif (/^\s*lhu\s+x(\d+),\s*(\w+)\s*\(\s*x(\d+)\s*\)/) {
		$rd = $1 << 7;
		$rs1 = $3 << 15;
		$ofs = $2 << 20;
		$op1 = 0x00 << 2;
		$op2 = 0x5 << 12;
		$code = $ofs + $rs1 + $rd + $op1 + $op2 + 3;
	}
	elsif (/^\s*sb\s+x(\d+),\s*(\w+)\s*\(\s*x(\d+)\s*\)/) {
		$rs2 = $1 << 20;
		$rs1 = $3 << 15;
		$ofs_u = int($2 / 32) << 25;
		$ofs_l = $2 % 32 << 7;
		$op1 = 0x08 << 2;
		$op2 = 0x0 << 12;
		$code = $ofs_u + $ofs_l + $rs1 + $rs2 + $op1 + $op2 + 3;
	}
	elsif (/^\s*sh\s+x(\d+),\s*(\w+)\s*\(\s*x(\d+)\s*\)/) {
		$rs2 = $1 << 20;
		$rs1 = $3 << 15;
		$ofs_u = int($2 / 32) << 25;
		$ofs_l = $2 % 32 << 7;
		$op1 = 0x08 << 2;
		$op2 = 0x1 << 12;
		$code = $ofs_u + $ofs_l + $rs1 + $rs2 + $op1 + $op2 + 3;
	}
	elsif (/^\s*sw\s+x(\d+),\s*(\w+)\s*\(\s*x(\d+)\s*\)/) {
		$rs2 = $1 << 20;
		$rs1 = $3 << 15;
		$ofs_u = int($2 / 32) << 25;
		$ofs_l = $2 % 32 << 7;
		$op1 = 0x08 << 2;
		$op2 = 0x2 << 12;
		$code = $ofs_u + $ofs_l + $rs1 + $rs2 + $op1 + $op2 + 3;
	}
	elsif (/^\s*jal\s+x(\d+),\s*(\w+)/) {
        if (defined($value{$2})) { $ofs = $value{$2} - $pc; }
        else { die "Error: Label $3 is not defined."; }
		$rd = $1 << 7;
		$ofs1 = (($ofs >> 20) & 0x1) << 31;
		$ofs2 = (($ofs >>  1) & 0x3ff) << 21;
		$ofs3 = (($ofs >> 11) & 0x1) << 20;
		$ofs4 = (($ofs >> 12) & 0xff) << 12;
		$op1= 0x1b << 2;
		$code = $ofs1 + $ofs2 + $ofs3 + $ofs4 + $rd + $op1 + 3;
	}
	elsif (/^\s*jalr\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
        if (defined($value{$3})) { $ofs = $value{$3} + $jump_offset;  }
        else { die "Error: Label $3 is not defined."; }
		$ofs = ($ofs & 0xfff) << 20;
		$rd = $1 << 7;
		$rs1 = $2 << 15;
		$op1 = 0x19 << 2;
		$op2 = 0x0 << 12;
		$code = $ofs + $rs1 + $rd + $op1 + $op2 + 3;
	}
	elsif (/^\s*beq\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$rs2 = $2 << 20;
		$rs1 = $1 << 15;
        if (defined($value{$3})) { $ofs = ($value{$3} - $pc) & 0x1fff; }
        else { die "Error: Label $3 is not defined."; }
		$ofs1 = (($ofs >> 12) & 0x1) << 31;
		$ofs2 = (($ofs >>  5) & 0x3f) << 25;
		$ofs3 = (($ofs >>  1) & 0xf) << 8;
		$ofs4 = (($ofs >> 11) & 0x1) << 7;
		$op1 = 0x18 << 2;
		$op2 = 0x0 << 12;
		$code = $ofs1 + $ofs2 + $ofs3 + $ofs4 + $rs2 + $rs1 + $op1 + $op2 + 3;
	}
	elsif (/^\s*bne\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$rs2 = $2 << 20;
		$rs1 = $1 << 15;
                if (defined($value{$3})) { $ofs = ($value{$3} - $pc) & 0x1fff; }
                else { die "Error: Label $3 is not defined."; }
		$ofs1 = (($ofs >> 12) & 0x1) << 31;
		$ofs2 = (($ofs >>  5) & 0x3f) << 25;
		$ofs3 = (($ofs >>  1) & 0xf) << 8;
		$ofs4 = (($ofs >> 11) & 0x1) << 7;
		$op1 = 0x18 << 2;
		$op2 = 0x1 << 12;
		$code = $ofs1 + $ofs2 + $ofs3 + $ofs4 + $rs2 + $rs1 + $op1 + $op2 + 3;
	}
	elsif (/^\s*blt\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$rs2 = $2 << 20;
		$rs1 = $1 << 15;
                if (defined($value{$3})) { $ofs = ($value{$3} - $pc) & 0x1fff; }
                else { die "Error: Label $3 is not defined."; }
		$ofs1 = (($ofs >> 12) & 0x1) << 31;
		$ofs2 = (($ofs >>  5) & 0x3f) << 25;
		$ofs3 = (($ofs >>  1) & 0xf) << 8;
		$ofs4 = (($ofs >> 11) & 0x1) << 7;
		$op1 = 0x18 << 2;
		$op2 = 0x4 << 12;
		$code = $ofs1 + $ofs2 + $ofs3 + $ofs4 + $rs2 + $rs1 + $op1 + $op2 + 3;
	}
	elsif (/^\s*bge\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$rs2 = $2 << 20;
		$rs1 = $1 << 15;
                if (defined($value{$3})) { $ofs = ($value{$3} - $pc) & 0x1fff; }
                else { die "Error: Label $3 is not defined."; }
		$ofs1 = (($ofs >> 12) & 0x1) << 31;
		$ofs2 = (($ofs >>  5) & 0x3f) << 25;
		$ofs3 = (($ofs >>  1) & 0xf) << 8;
		$ofs4 = (($ofs >> 11) & 0x1) << 7;
		$op1 = 0x18 << 2;
		$op2 = 0x5 << 12;
		$code = $ofs1 + $ofs2 + $ofs3 + $ofs4 + $rs2 + $rs1 + $op1 + $op2 + 3;
	}
	elsif (/^\s*bltu\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$rs2 = $2 << 20;
		$rs1 = $1 << 15;
                if (defined($value{$3})) { $ofs = ($value{$3} - $pc) & 0x1fff; }
                else { die "Error: Label $3 is not defined."; }
		$ofs1 = (($ofs >> 12) & 0x1) << 31;
		$ofs2 = (($ofs >>  5) & 0x3f) << 25;
		$ofs3 = (($ofs >>  1) & 0xf) << 8;
		$ofs4 = (($ofs >> 11) & 0x1) << 7;
		$op1 = 0x18 << 2;
		$op2 = 0x6 << 12;
		$code = $ofs1 + $ofs2 + $ofs3 + $ofs4 + $rs2 + $rs1 + $op1 + $op2 + 3;
	}
	elsif (/^\s*bgeu\s+x(\d+),\s*x(\d+),\s*(\w+)/) {
		$rs2 = $2 << 20;
		$rs1 = $1 << 15;
                if (defined($value{$3})) { $ofs = ($value{$3} - $pc) & 0x1fff; }
                else { die "Error: Label $3 is not defined."; }
		$ofs1 = (($ofs >> 12) & 0x1) << 31;
		$ofs2 = (($ofs >>  5) & 0x3f) << 25;
		$ofs3 = (($ofs >>  1) & 0xf) << 8;
		$ofs4 = (($ofs >> 11) & 0x1) << 7;
		$op1 = 0x18 << 2;
		$op2 = 0x7 << 12;
		$code = $ofs1 + $ofs2 + $ofs3 + $ofs4 + $rs2 + $rs1 + $op1 + $op2 + 3;
	}
	elsif (/^\s*csrr([wsc])\s+x(\d+),\s*(\w+),\s*x(\d+)/) {
		$rd = $2 << 7;
		$rs1 = $4 << 15;
		$op1 = 0x73;
		$op2 = ($1 eq "w") ? 1 :
		       ($1 eq "s") ? 2 : 3;
		$op2 = $op2 << 12;
		$w = $3;
		if (defined($defvalue{$w})) { $ofs = $defvalue{$w} << 20; } elsif ($w =~ /^0x/) { $ofs = hex($w) << 20 ; } else { $ofs = $w << 20; }
		$code = $rs1 + $rd + $op1 + $op2 + $ofs;
	}
	elsif (/^\s*csrr([wsc])i\s+x(\d+),\s*(\w+),\s*(\w+)/) {
		$rd = $2 << 7;
		$w2 = $3;
		$w3 = $1;
		$w = $4;
		if (defined($defvalue{$w})) { $imm = $defvalue{$w} << 15; } elsif ($w =~ /^0x/) { $imm = hex($w) << 15 ; } else { $imm = $w << 15; }
		$op1 = 0x73;
		$op2 = ($w3 eq "w") ? 5 :
		       ($w3 eq "s") ? 6 : 7;
		$op2 = $op2 << 12;
		if (defined($defvalue{$w2})) { $ofs = $defvalue{$w2} << 20; } elsif ($w2 =~ /0x/) { $ofs = hex($w2) << 20 ; } else { $ofs = $w2 << 20; }
		$code = $rd + $imm + $op1 + $op2 + $ofs;
	}
	elsif (/^\s*ecall/) {
		$code = 0x73;
	}
	elsif (/^\s*mret/) {
		$code = 0x30200073;
	}
	elsif (/^\s*illegal_ops/) {
		$code = 0xffffffff;
	}
	else {
		print "ERROR no format found : $_\n";
		exit;
	}

	# code
	printf("%08x",$code);
	$pcadr = sprintf("%08x",$pc);
	$bit_pattern = sprintf("%032b", $code);
	$bit_pattern =~ s/(.....)(..)(.....)(.....)(...)(.....)(.....)(..)/$1 $2 $3 $4 $5 $6 $7 $8/;
	# CR/comment
	if ($v == 1) {
		$pcadrsim = sprintf("%08x",$pc/4);
		print " // $pcadr: $pcadrsim: $bit_pattern $_";
	}
	else {
		print "\n";
	}
	$pc += 4;

}

