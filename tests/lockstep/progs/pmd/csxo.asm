%include "pmhead.inc"
; a data read through CS of an execute-only code segment: #GP(0) (i486 PRM 6.2.1, "No
; instruction may read an executable segment unless the readable bit is set")
tests:
  mov ax, 0x40
  mov es, ax
  mov eax, [gdtr+2]
  mov dword [es:eax + 0x38], 0x0000ffff
  mov dword [es:eax + 0x3c], 0x00cf9801       ; 38: code32 DPL0, execute-only, base 10000h
  mov ax, 0x10
  mov es, ax
  mov dword [resume], r1
  mov ebx, 0x1111
  jmp 0x38:xo1
xo1:
  mov ebx, [cs:val]                           ; #GP(0), EBX kept
r1:
  mov dword [resume], r2
  mov esi, val
  mov edi, dst
  jmp 0x38:xo2
xo2:
  cs movsd                                    ; #GP(0), ESI/EDI/dst kept
r2:
  mov ecx, [nfault]
  movzx edx, word [lastec]
  mov dword [lastec], 0
  mov eax, [dst]
  hlt
align 4
val: dd 0x12345678
dst: dd 0
align 8
idt: times 256*8 db 0
