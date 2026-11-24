%include "pmhead.inc"
; far JMP / LLDT-free: CS selector just beyond the GDT limit, a valid code descriptor behind it
tests:
  mov ax, 0x40
  mov es, ax
  mov ecx, [gdtr+2]
  movzx eax, word [gdtr]
  inc eax                                       ; first selector beyond the limit
  mov [sel], ax
  mov dword [es:ecx + eax], 0x0000ffff
  mov dword [es:ecx + eax + 4], 0x00cf9a01      ; code32, base 10000, 4 GB
  mov dword [resume], after
  jmp far [fp]
inside:
  mov ebx, 0xbad
after:
  mov ax, 0x10
  mov ds, ax
  mov ecx, [nfault]
  mov edx, [lastec]
  hlt
align 4
fp: dd inside
sel: dw 0
align 8
idt: times 256*8 db 0
