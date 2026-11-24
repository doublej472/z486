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
  times 16 db 0x2e
  inc word [0]           ; CS override x16 on INC [0] (19 bytes)
  mov bx, [0]
  mov ax, cs
  mov ds, ax
  mov cx, [0]
  hlt
h13: mov bx, 0xdddd
  hlt
