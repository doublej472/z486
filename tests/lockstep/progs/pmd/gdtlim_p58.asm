%include "pmhead.inc"
; MOV Sreg with a selector beyond the GDT limit: #GP(selector) (i486 PRM MOV / 6.3.1), whatever
; lies in memory behind the table
tests:
  mov ax, 0x40
  mov es, ax
  mov dword [resume], r1
  mov eax, [gdtr+2]
  mov dword [es:eax + 0xfff8], 0x0000ffff
  mov dword [es:eax + 0xfffc], 0x00cf9300     ; behind the limit: a PRESENT data descriptor
  mov ax, 0xfff8
  mov fs, ax
r1:
  mov ebx, [lastec]
  mov dword [resume], r2
  mov ax, 0x0058                              ; index 11: just beyond the limit (GDT 0-0x57)
  mov ecx, [gdtr+2]
  mov dword [es:ecx + 0x58], 0x0000ffff
  mov dword [es:ecx + 0x5c], 0x00cf9300
  mov gs, ax
r2:
  mov edx, [lastec]
  mov esi, [nfault]
  hlt
align 8
idt: times 256*8 db 0
