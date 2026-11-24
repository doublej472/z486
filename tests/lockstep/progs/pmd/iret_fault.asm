%include "pmhead.inc"
; outer-level IRETD whose return SS is invalid: #GP at CPL 0, no stack switch (i486 PRM IRET)
tests:
%macro iret_case 4   ; ss, cs, label, index
  mov dword [resume], %3
  push dword %1
  push dword 0xd000
  push dword 0x202
  push dword %2
  push dword r3code
  iretd
%3:
  mov ebx, [lastec]
  mov [log + 4*%4], ebx
  mov ax, 0x10
  mov ds, ax
%endmacro
  iret_case 0, 0x1b, c1, 0
  iret_case 0x10, 0x1b, c2, 1
  iret_case 0x13, 0x1b, c3, 2
  iret_case 0x40, 0x1b, c4, 3
  mov eax, [nfault]
  hlt
r3code:
  mov eax, 0x3333
  hlt
align 4
log: times 64 dd 0
align 8
idt: times 256*8 db 0
