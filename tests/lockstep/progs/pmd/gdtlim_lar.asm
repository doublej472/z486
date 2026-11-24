%include "pmhead.inc"
; LAR / LSL / VERR / VERW with a selector just beyond the GDT limit: ZF = 0 (i486 PRM LAR: "IF
; selector index not within the descriptor table limit THEN ZF := 0")
tests:
  mov ax, 0x40
  mov es, ax
  mov ecx, [gdtr+2]
  movzx eax, word [gdtr]
  inc eax
  mov esi, eax
  mov dword [es:ecx + eax], 0x0000ffff
  mov dword [es:ecx + eax + 4], 0x00cf9300
  xor edi, edi
  lar ebx, esi
  setz dl
  shl edi, 1
  or di, dx
  lsl ebx, esi
  setz dl
  shl edi, 1
  or di, dx
  verr si
  setz dl
  shl edi, 1
  or di, dx
  verw si
  setz dl
  shl edi, 1
  or di, dx
  hlt
align 8
idt: times 256*8 db 0
