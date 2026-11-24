%include "pmhead3.inc"
; LDT limit: selector 14h (index 2, TI=1) beyond an LDT of limit 0Fh, a valid descriptor behind it
tests:
  mov ax, 0x50
  lldt ax
  mov dword [resume], after
  mov ax, 0x14
  mov fs, ax                     ; #GP(14)
  mov ebx, 0xbad
after:
  mov ecx, [nfault]
  mov edx, [lastec]
  hlt
align 8
ldt:
  dq 0
  dq 0
  dw 0xffff, 0x0000
  db 0x01, 0x93, 0xcf, 0x00      ; behind the limit: a valid data descriptor
align 8
idt: times 256*8 db 0
