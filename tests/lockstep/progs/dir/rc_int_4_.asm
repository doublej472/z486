org 0
times 0x100 db 0
  xor ax, ax
  mov es, ax
  mov word [es:4*4], h4
  mov word [es:4*4+2], 0x1000
  mov ax, 0x2000
  mov ds, ax
  mov es, ax
  mov word [0x10], 0x8080
  mov word [0x20], 0x0101
  mov al, 0x80
  xor bx, bx
  cld
  mov si, 0x10
  mov di, 0x20
  mov cx, 1
  repe cmpsb
  int 4
  mov cx, bx
  hlt
h4: inc bx
  iret
