; common protected-mode prologue (image at 1000:0000, entry 1000:0100): flat-ish 32-bit PM,
; selectors: see the GDT below; IDT: every vector -> fault handler
org 0
times 0x100 db 0
bits 16
  cli
  lgdt [cs:gdtr]
  lidt [cs:idtr]
  mov eax, cr0
  or al, 1
  mov cr0, eax
  jmp dword 0x08:pm32
%macro desc 4  ; base, limit, access, flags
  dw (%2) & 0xffff, (%1) & 0xffff
  db ((%1) >> 16) & 0xff, %3, (((%2) >> 16) & 0x0f) | ((%4) << 4), ((%1) >> 24) & 0xff
%endmacro
align 8
gdt:
  dq 0
  desc 0x10000, 0xfffff, 0x9a, 0xc   ; 08 code32 DPL0
  desc 0x10000, 0xfffff, 0x92, 0xc   ; 10 data32 DPL0
  desc 0x10000, 0xfffff, 0xfa, 0xc   ; 18 (1B) code32 DPL3
  desc 0x10000, 0xfffff, 0xf2, 0xc   ; 20 (23) data32 DPL3
  desc 0x10000, 0xfffff, 0x7a, 0xc   ; 28 (2B) code32 DPL3, not present
  desc 0x10000, 0xffff, 0x92, 0x0    ; 30 data16 DPL0
  desc 0x10000, 0xffff, 0x9a, 0x0    ; 38 code16 DPL0
  desc 0, 0xfffff, 0x92, 0xc         ; 40 flat data DPL0
  desc 0x10000 + (tss - $$), 0x67, 0x89, 0  ; 48 TSS
  desc 0x10000 + (ldt - $$), 0x0f, 0x82, 0  ; 50 LDT, limit 0Fh (2 entries)
gdt_end:
gdtr: dw gdt_end - gdt - 1
      dd 0x10000 + gdt
idtr: dw 256*8 - 1
      dd 0x10000 + idt
align 4
tss: dd 0, 0xe000, 0x10
  times 0x68-12 db 0
bits 32
pm32:
  mov ax, 0x10
  mov ds, ax
  mov es, ax
  mov ss, ax
  mov esp, 0xf000
  mov ax, 0x48
  ltr ax
  ; IDT: vectors with an error code -> hec, the rest -> hnoec
  mov edi, idt
  xor ecx, ecx
.idtl:
  mov eax, hnoec
  cmp ecx, 8
  je .ec
  cmp ecx, 10
  jb .st
  cmp ecx, 14
  ja .st17
.ec: mov eax, hec
  jmp .st
.st17: cmp ecx, 17
  je .ec
.st:
  mov [edi], ax
  mov word [edi+2], 0x08
  mov word [edi+4], 0x8e00
  shr eax, 16
  mov [edi+6], ax
  add edi, 8
  inc ecx
  cmp ecx, 256
  jb .idtl
  jmp tests
; handlers: log (error code), then resume at [resume]
hec:
  pop dword [lastec]
hnoec:
  push eax
  mov eax, [resume]
  mov [esp+4], eax
  mov dword [esp+8], 0x08      ; (always resume in ring 0 code)
  pop eax
  inc dword [nfault]
  iretd
align 4
resume: dd 0
lastec: dd 0
nfault: dd 0
