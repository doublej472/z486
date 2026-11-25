%include "pmhead.inc"
; INT n through a gate beyond the IDT limit: #GP(vector*8+2) (i486 PRM INT n pseudo-code,
; "Interrupt vector must be within IDT table limits"), never the gate stored behind the limit
tests:
  mov dword [resume], r1
  lidt [idtr_40]                              ; vectors 00h-3Fh
  int 0x40                                    ; first vector beyond: #GP(202h)
r1:
  movzx ebx, word [lastec]                    ; (the upper half is B10)
  mov dword [lastec], 0
  mov dword [resume], r2
  lidt [idtr_40p]                             ; limit ends inside gate 40h
  int 0x40
r2:
  movzx edx, word [lastec]
  mov dword [lastec], 0
  lidt [idtr]
  mov esi, [nfault]
  hlt
idtr_40:  dw 0x1ff
          dd 0x10000 + idt
idtr_40p: dw 0x203
          dd 0x10000 + idt
align 8
idt: times 256*8 db 0
