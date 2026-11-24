%include "pmhead.inc"
; 32-bit interrupt gate: the error code is pushed as a doubleword (i486 PRM 9.9 / SDM 6.13:
; "the error code is pushed ... as a doubleword", upper half reserved). Stack slot pre-filled.
tests:
  mov dword [esp-16], 0xffffffff
  mov dword [esp-20], 0xffffffff
  mov dword [resume], r1
  mov eax, 0x7f8
  db 0x8e, 0xd8             ; mov ds, eax (32-bit operand size): #GP(07F8)
r1:
  mov ax, 0x10
  mov ds, ax
  mov eax, [lastec]          ; full dword as pushed
  hlt
align 8
idt: times 256*8 db 0
