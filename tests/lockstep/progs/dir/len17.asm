org 0
times 0x100 db 0
  xor ax, ax
  mov es, ax
  mov word [es:13*4], h13
  mov word [es:13*4+2], 0x1000
  xor bx, bx
  times 16 db 0x26
  nop
  mov bx, 0x1111
  hlt
h13: mov bx, 0xdddd
  hlt
