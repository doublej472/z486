org 0
times 0x100 db 0
  mov ax, 0x2000
  mov ds, ax
  mov es, ax
  mov word [0x10], 0x0101
  mov word [0x20], 0x0202
  mov word [0x30], 0
  cld
  xor dx, dx
  mov di, 0x20
  mov cx, 3
  mov al, 0x01
  repne scasb            ; 01 - 02 -> CF=1 SF=1 AF=1, ZF=0 ... ECX runs out
  lahf
  mov bx, dx
  hlt
