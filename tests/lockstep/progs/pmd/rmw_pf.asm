%include "pmhead.inc"
; read-modify-write to a read-only page (CR0.WP = 1): the read succeeds, the write takes #PF.
; The fault must leave no state: the #PF frame's EFLAGS is the result of the instruction before,
; and the restarted ALU op (after the handler makes the page writable) uses those flags.
tests:
  ; page tables at 20000 (directory) / 21000 (first 4 MB, identity), flat selector 40
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
  mov dword [es:0x21000 + 0x30*4], 0x30005     ; page 30000: present, user, READ-ONLY
  mov byte [es:0x31000], 0x11
  mov eax, 0x20000
  mov cr3, eax
  mov eax, cr0
  or eax, 0x80010000                           ; PG | WP
  mov cr0, eax
  jmp .flush
.flush:
  ; #PF handler: page 30000 writable, INVLPG, restart; log the pushed EFLAGS
  mov edi, idt + 14*8
  mov eax, hpf
  mov [edi], ax
  shr eax, 16
  mov [edi+6], ax
  mov ebx, 0
%macro pcase 2
  mov dword [es:0x21000 + 0x30*4], 0x30007
  invlpg [es:0x30000]
  mov dword [es:0x30000], 0x40404040            ; (writable: initialise)
  mov dword [es:0x21000 + 0x30*4], 0x30005     ; read-only again
  invlpg [es:0x30000]
  mov edx, [es:0x30000]                         ; line in the L1, read-only translation in the TLB
  mov al, 0x5a
  %1
  %2
  cmp byte [es:0x31000], 0x7f                   ; a flag writer right behind the RMW
  pushfd
  pop dword [log + ebx*4]
  inc ebx
%endmacro
  pcase {sub al, 0xa5}, {adc byte [es:0x30000], 0x13}
  pcase {add al, 0xa6}, {adc byte [es:0x30000], 0x13}
  pcase {sub al, 0xa5}, {sbb byte [es:0x30000], 0x13}
  pcase {stc}, {adc word [es:0x30000], 1}
  pcase {clc}, {adc word [es:0x30000], 1}
  pcase {cmp al, 0x7f}, {inc byte [es:0x30000]}
  pcase {sub al, 0xa5}, {add byte [es:0x30000], 0x13}
  pcase {sub al, 0xa5}, {rcl byte [es:0x30000], 1}
  pcase {sub al, 0xa5}, {neg byte [es:0x30000]}
  pcase {xor al, al}, {adc dword [es:0x30000], 1}
  pcase {sub al, 0xa5}, {adc byte [es:0x30000], al}
  pcase {sub al, 0xa5}, {sbb [es:0x30000], eax}
  mov eax, [es:0x30000]
  mov ecx, [pfcnt]
  hlt
hpf:
  push eax
  mov eax, [esp + 12]                          ; pushed EFLAGS
  mov [pflog + ecx*4], eax
  inc dword [pfcnt]
  mov dword [es:0x21000 + 0x30*4], 0x30007     ; writable
  mov eax, 0x30000
  invlpg [es:eax]
  pop eax
  add esp, 4
  iretd
align 4
pfcnt: dd 0
log: times 64 dd 0
pflog: times 64 dd 0
align 8
idt: times 256*8 db 0
