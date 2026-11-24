org 0
times 0x100 db 0
bits 16
start:
  mov ax, 0x1234
  mov bx, 0x1111
  add ax, bx
  mov [0x200], ax
  push ax
  pop cx
  mov si, 0x300
  mov cx, 5
  rep stosb
  xor dx, dx
  mov ax, 100
  mov bx, 7
  div bx
  call sub1
  hlt
sub1:
  inc dx
  ret
