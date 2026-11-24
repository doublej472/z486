%include "pmhead.inc"
; outer-level RETF that faults (protection.sv cpl_transition_r suspect): after the fault the
; ring-0 handler and the code after it must still run with CPL 0
tests:
%macro retf_case 4   ; ss, cs, label, index
  mov dword [resume], %3
  push dword %1
  push dword 0xd000
  push dword %2
  push dword r3code
  retf
%3:
  mov ebx, [lastec]
  mov ax, 0x10           ; DPL 0 data: #GP if the core still thinks CPL = 3
  mov ds, ax
  mov es, ax
  mov fs, ax
  mov ax, 0x30
  mov gs, ax
  mov eax, [nfault]
  mov [log + 4*%4], ebx
  mov dword [resume], %%after
  cli
  sti
  cli
  mov eax, cr0           ; privileged: #GP at CPL 3
  mov [log + 4*%4 + 64], eax
%%after:
%endmacro
  retf_case 0, 0x1b, c1, 0          ; null SS: #GP(0)
  retf_case 0x10, 0x1b, c2, 1       ; SS RPL 0 != CS RPL 3: #GP(10)
  retf_case 0x13, 0x1b, c3, 2       ; SS DPL 0 data with RPL 3: #GP(10)
  retf_case 0x23, 0x2b, c4, 3       ; CS not present: #NP(28)
  retf_case 0x40, 0x1b, c5, 4
  mov eax, [nfault]
  mov ebx, [lastec]
  hlt
r3code:
  mov eax, 0x3333
  hlt
align 4
log: times 64 dd 0
align 8
idt: times 256*8 db 0
