%include "pmhead2.inc"
; INT n through a gate whose offset is beyond the new CS limit: #GP(0), never execute there
tests:
  mov edi, idt + 0x40*8
  mov word [edi], 0x3000
  mov word [edi+2], 0x50
  mov word [edi+4], 0x8e00
  mov word [edi+6], 0
  mov dword [resume], after
  xor ebx, ebx
  int 0x40
after:
  mov ecx, [nfault]
  mov edx, [lastec]
  hlt
align 8
idt: times 256*8 db 0
times 0x3000 - ($ - $$) db 0x90
  mov ebx, 0xbad           ; beyond the CS limit of selector 50
  hlt
