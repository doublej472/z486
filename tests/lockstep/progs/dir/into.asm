; INTO right after a flag producer (rgen386 r139: REPE CMPSB setting OF, then INTO)
org 0
times 0x100 db 0
  xor ax, ax
  mov es, ax
  mov word [es:4*4], h4
  mov word [es:4*4+2], 0x1000
  mov ax, 0x2000
  mov ds, ax
  mov es, ax
  mov byte [0x10], 0x80
  mov byte [0x20], 0x01
  xor bx, bx               ; counts INT 4
  cld
%macro icase 1
  mov si, 0x10
  mov di, 0x20
  mov cx, 1
  %1
  into
%endmacro
  icase {repe cmpsb}              ; 80h - 01h: OF = 1
  icase {cmpsb}
  icase {repne cmpsb}
  icase {mov al, 0x80}
  sub al, 1
  mov al, 0x7f
  icase {add al, 1}
  mov al, 0x7f
  icase {inc al}
  mov ax, 0x8000
  icase {neg ax}
  mov al, 0x40
  icase {shl al, 1}
  mov al, 0x80
  icase {cmp al, 1}
  mov al, 0x80
  icase {scasb}
  mov ax, 0x4000
  icase {imul ax, ax, 4}
  mov al, 0x80
  icase {rep scasb}
  mov cx, bx
  hlt
h4: inc bx
  iret
