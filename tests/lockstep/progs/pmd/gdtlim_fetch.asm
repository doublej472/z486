%include "pmhead.inc"
; g301 shape: an instruction-fetch #PF, the handler maps the page (DS loads, OR to the PTE, INVLPG,
; POP DS, IRET), then MOV GS with a selector beyond the GDT limit: #GP(FFF8) expected
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
  mov edi, idt + 14*8
  mov eax, hpf
  mov [edi], ax
  shr eax, 16
  mov [edi+6], ax
  mov eax, [gdtr+2]
  mov dword [es:eax + 0xfff8], 0x0000ffff     ; behind the limit: a present data descriptor
  mov dword [es:eax + 0xfffc], 0x00cf9300
  mov dword [es:0x21000 + 0x15*4], 0x15006     ; code page 15000 (image 5000) not present
  invlpg [es:0x15000]
  mov dword [resume], done
  jmp tgt
hpf:                                           ; as rgen386's: PTE(CR2) |= P|W through a table window
  push eax
  push ds
  mov ax, 0x40
  mov ds, ax
  mov eax, cr2
  shr eax, 12
  or dword [0x21000 + eax*4], 3
  mov eax, cr2
  invlpg [eax]
  pop ds
  pop eax
  add esp, 4
  iretd
done:
  mov ax, 0x10
  mov ds, ax
  mov ebx, [lastec]
  mov ecx, [nfault]
  mov dx, gs
  hlt
align 8
idt: times 256*8 db 0
times 0x5000 - ($ - $$) db 0
tgt:
  imul esi, [ebx]
  xadd edi, esi
  mov ax, 0xfff8
  mov gs, ax                                   ; #GP(FFF8)
  mov ebx, 0xbad
  jmp done
