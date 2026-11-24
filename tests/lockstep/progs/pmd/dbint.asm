%include "pmhead.inc"
; data breakpoint (DR0, write, dword) on the stack slot INT n's frame writes: #DB (trap) at the
; boundary after INT n, i.e. before the handler's first instruction (i486 PRM 12.2.3/12.3.1.4)
tests:
  mov edi, idt + 0x30*8
  mov eax, h30
  mov [edi], ax
  shr eax, 16
  mov [edi+6], ax
  mov edi, idt + 1*8
  mov eax, h1
  mov [edi], ax
  shr eax, 16
  mov [edi+6], ax
  lea eax, [esp - 4 + 0x10000]   ; linear address of the EFLAGS slot (SS base 10000)
  mov dr0, eax
  mov eax, 0x000d0002            ; G0, RW0 = 01 (write), LEN0 = 11 (dword)
  mov dr7, eax
  xor ebx, ebx
  xor ecx, ecx
  int 0x30
  mov eax, dr6
  hlt
h30:
  inc ebx                       ; first handler instruction
  mov edx, ecx                  ; ECX = 1 if #DB came before it
  iretd
h1:
  inc ecx
  mov esi, [esp]                ; pushed EIP of the #DB frame
  mov eax, dr6
  mov [dblog], eax
  xor eax, eax
  mov dr6, eax
  mov dr7, eax
  iretd
align 4
dblog: dd 0
align 8
idt: times 256*8 db 0
