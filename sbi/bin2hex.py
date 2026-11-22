#!/usr/bin/env python3
# bin2hex.py <in.bin> <out.hex> : memory image for the board loader
#   one 32-bit little endian word per line, format " xxxxxxxx" (same as
#   Image.hex of the nommu Linux), from address 0
import sys
data = open(sys.argv[1], 'rb').read()
data += b'\0' * (-len(data) % 4)
with open(sys.argv[2], 'w') as f:
    for i in range(0, len(data), 4):
        f.write(' %08x\n' % int.from_bytes(data[i:i+4], 'little'))
print('%s : %d words (%d bytes)' % (sys.argv[2], len(data) // 4, len(data)))
