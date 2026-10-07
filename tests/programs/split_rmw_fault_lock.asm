; audit_split_rmw_fault - a page-crossing RMW whose second page faults on the
; write must not have written its first half
;
; [0x8FFE] spans 0x8000 (RW) and 0x9000 (read-only, CR0.WP=1).  ADD faults on
; the write to 0x9000; the #PF handler makes the page writable (PTE R/W,
; INVLPG) and restarts the instruction.  A fault is restartable, so the dword
; must end as exactly old + 0x00010001.  A first-half write before the fault
; adds the low word twice.  Run unlocked (+0) and locked (+1 via EBX).
%define LOCKED
BITS 32
ORG 0
GDT equ 0xA800
IDT equ 0xB000
PTE9 equ 0x1024                          ; PTE of linear 0x9000
start:
    mov esp, 0x8000
    mov dword [GDT+0], 0
    mov dword [GDT+4], 0
    mov dword [GDT+8], 0x0000ffff
    mov dword [GDT+12], 0x00cf9b01
    mov dword [GDT+16], 0x0000ffff
    mov dword [GDT+20], 0x00cf9300
    mov word [0xA000], 23
    mov dword [0xA002], GDT
    lgdt [0xA000]
    mov eax, pf_handler
    mov word [IDT+14*8+0], ax
    mov word [IDT+14*8+2], 0x08
    mov word [IDT+14*8+4], 0x8e00
    shr eax, 16
    mov word [IDT+14*8+6], ax
    mov word [0xA010], 0x7ff
    mov dword [0xA012], IDT
    lidt [0xA010]
    xor ebp, ebp
    mov dword [0x8FFC], 0x00050000       ; low word of [0x8FFE] = 5
%ifdef LOCKED
    lock add dword [0x8FFE], 0x00010001
%else
    add dword [0x8FFE], 0x00010001
%endif
    cmp ebp, 1                           ; exactly one #PF
    jne fail
    mov eax, [0x8FFC]
    out 0xe4, eax
    cmp eax, 0x00060000                  ; 5 + 1, not 5 + 2
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
pf_handler:
    inc ebp
    or dword [PTE9], 2                   ; make 0x9000 writable
    invlpg [0x9000]
    add esp, 4                           ; drop the error code, restart
    iretd
fail:
    mov al, 0xff
    out 0xe0, al
    hlt
