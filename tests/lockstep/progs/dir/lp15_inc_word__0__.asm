org 0
times 0x100 db 0
  xor ax, ax
  mov es, ax
  mov word [es:13*4], h13
  mov word [es:13*4+2], 0x1000
  mov ax, 0x2000
  mov ds, ax
  xor bx, bx
  mov word [0], 0
  times 15 db 0x3e
  inc word [0]
  mov cx, 0x1111
  hlt
h13: mov cx, 0xdddd
  hlt
