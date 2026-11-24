%include "pmhead.inc"
; g25 minimised: 16-bit code, IRET, two ALU ops, SUB, then ADC byte [bx+si+d8], imm to a read-only
; page (CR0.WP): the write takes #PF; the #PF frame's FLAGS must be SUB's result
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
  mov dword [es:0x21000 + 0x08*4], 0x08005     ; page 8000: read-only
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
  mov edi, idt + 0x31*8
  mov eax, hiret
  mov [edi], ax
  shr eax, 16
  mov [edi+6], ax
  jmp 0x38:c16
hiret: iretd
hpf:
  push eax
  mov eax, [esp + 12]
  mov [pflog], eax
  inc dword [pfcnt]
  mov eax, cr2
  shr eax, 12
  or dword [es:0x21000 + eax*4], 3
  mov eax, cr2
  invlpg [es:eax]
  pop eax
  add esp, 4
  iretd
bits 16
c16:
  mov ax, 0x40
  mov ds, ax
  mov dword [0xb000], 0x11223344
  mov dword [es:0x21000 + 0x09*4], 0x09004     ; page 9000 not present
  invlpg [es:0x9000]
  mov bx, 0xa000
  mov si, 0xe010                               ; bx+si+52h = 8062h (read-only page 8)
  mov dx, 0x1234
  mov cx, 0x5678
  mov ax, 0x005a
  sub al, 0xa5                                 ; AL=5A: CF=1 OF=1 -> EFLAGS 0893h
  adc byte [bx+si+0x52], 0x4d                ; read OK, write #PF (read-only page)
  cmp [0xb000], cl
  pushf
  pop word [es:0x9100]
  mov al, [0x8062]
  hlt
flg: dw 0
bits 32
align 4
pfcnt: dd 0
pflog: dd 0
align 8
idt: times 256*8 db 0
