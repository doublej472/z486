%include "pmhead.inc"
; MOV Sreg with a selector beyond the GDT limit: #GP(selector) (i486 PRM MOV / 6.3.1), whatever
; lies in memory behind the table
tests:
  mov ax, 0x40
  mov es, ax
  mov edi, 0x21000
  xor eax, eax
.pt: lea edx, [eax*4]
  shl edx, 10
  or edx, 7
  mov [es:edi + eax*4], edx
  inc eax
  cmp eax, 1024
  jb .pt
  mov dword [es:0x20000], 0x21007
  mov eax, 0x20000
  mov cr3, eax
  mov eax, cr0
  or eax, 0x80010000
  mov cr0, eax
  jmp .f
.f:
  mov dword [resume], r1
  mov eax, [gdtr+2]
  mov dword [es:eax + 0xfff8], 0
  mov dword [es:eax + 0xfffc], 0x00007200     ; behind the limit: a not-present data descriptor
  mov ax, 0xfff8
  mov fs, ax
r1:
  mov ebx, [lastec]
  mov dword [resume], r2
  mov ax, 0x0058                              ; index 11: just beyond the limit (GDT 0-0x57)
  mov ecx, [gdtr+2]
  mov dword [es:ecx + 0x58], 0
  mov dword [es:ecx + 0x5c], 0x00007200
  mov gs, ax
r2:
  mov edx, [lastec]
  mov esi, [nfault]
  hlt
align 8
idt: times 256*8 db 0
