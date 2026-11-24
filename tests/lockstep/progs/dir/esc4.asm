; DB /6 with CR0.EM = 1: #NM expected
org 0
times 0x100 db 0
  xor ax, ax
  mov es, ax
  mov word [es:7*4], h7
  mov word [es:7*4+2], 0x1000
  mov word [es:6*4], h6
  mov word [es:6*4+2], 0x1000
  mov eax, cr0
  or al, 4
  mov cr0, eax
  mov si, 0x200
  db 0xdb, 0x34
  mov bx, 0x1111
  hlt
h7: mov bx, 0x7777
  hlt
h6: mov bx, 0x6666
  hlt
