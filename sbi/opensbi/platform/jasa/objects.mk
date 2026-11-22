#
# SPDX-License-Identifier: BSD-2-Clause
#
# OpenSBI platform : my-riscv-rv32i-dc (RV32IMA + Sv32, Arty A7)
#   build : see ../../build.sh
#

platform-objs-y += platform.o

PLATFORM_RISCV_XLEN = 32
PLATFORM_RISCV_ABI = ilp32
PLATFORM_RISCV_ISA = rv32ima_zicsr_zifencei
PLATFORM_RISCV_CODE_MODEL = medany

# fw_jump : OpenSBI at 0x0, the kernel (S-mode) at 4MB, the DTB at 2MB
FW_TEXT_START = 0x00000000
FW_JUMP = y
FW_JUMP_ADDR = 0x00400000
FW_JUMP_FDT_ADDR = 0x00200000
# fw_payload : the payload (kernel image) is linked into the firmware
FW_PAYLOAD = y
FW_PAYLOAD_OFFSET = 0x00400000
FW_PAYLOAD_FDT_ADDR = 0x00200000
