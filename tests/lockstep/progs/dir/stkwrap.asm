; stack operand straddling offset FFFF/0000 with a 16-bit SP: #SS (i486 PRM: "#SS(0) if any part
; of the operand lies outside the stack segment limit"; SingleStepTests 80386 6650 / 66 58)
org 0
times 0x100 db 0
  xor ax, ax
  mov es, ax
  mov word [es:12*4], h12
  mov word [es:12*4+2], 0x1000
  mov word [es:13*4], h12
  mov word [es:13*4+2], 0x1000
  mov ax, 0x2000
  mov ss, ax
  mov eax, 0x11223344
  xor bx, bx
  mov word [cs:resume], r1
  mov sp, 2
  push eax                ; 4 bytes at FFFE..0001: #SS
r1:
  mov word [cs:resume], r2
  mov sp, 0xfffe
  pop eax                 ; FFFE..0001: #SS
r2:
  mov word [cs:resume], r3
  mov sp, 1
  push ax                 ; FFFF..0000: #SS
r3:
  mov word [cs:resume], r4
  mov sp, 0xffff
  pop ax
r4:
  mov sp, 0x100
  mov cx, bx
  hlt
h12:
  inc bx
  mov sp, 0x200
  push word 0
  push word 0x1000
  push word [cs:resume]
  iret
resume: dw 0
