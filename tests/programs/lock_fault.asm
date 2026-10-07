; lock_fault - locked RMWs that fault must leave LOCK# deasserted
;
; 0x9000 is a read-only page (CR0.WP=1), 0xC000 is not present.  Each case
; takes #PF; the handler checks the error code, skips the instruction and
; the testbench's +expect_lock requires LOCK# low at the end and at least one
; locked read and write (the last, good RMW).  Split cases must write nothing.
BITS 32
ORG 0
GDT equ 0xA800
IDT equ 0xB000
start:
    mov esp, 0x8000
    mov dword [GDT+0], 0
    mov dword [GDT+4], 0
    mov dword [GDT+8], 0x0000ffff        ; 0x08: code, base 0x10000
    mov dword [GDT+12], 0x00cf9b01
    mov dword [GDT+16], 0x0000ffff       ; 0x10: flat data
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
    xor ebp, ebp                         ; #PF count
    mov ecx, 1

    mov esi, 1                           ; expected error code P (W, U masked)
    mov edi, c1
    lock add dword [0x9000], 5           ; read-only page, CPL0, WP=1
c1: mov edi, c2
    xchg [0x9004], ecx                   ; implicitly locked, read-only
c2: mov esi, 0                           ; not present
    mov edi, c3
    lock add dword [0xC000], 5
c3: mov esi, 0                           ; split: 2nd page not present
    mov edi, c4
    lock add dword [0xBFFE], 0x10000
c4: mov esi, 1                           ; split: 2nd page read-only
    mov edi, c5
    lock or dword [0x8FFE], 0x10000
c5: cmp ebp, 5
    jne fail
    cmp dword [0xBFFC], 0                ; the split RMW wrote nothing
    jne fail
    cmp dword [0x8FFC], 0
    jne fail
    lock add dword [0xA100], 1           ; one good locked RMW: +expect_lock
    mov al, 1
    out 0xe0, al
    hlt

pf_handler:
    pop eax                              ; error code
    out 0xe4, eax
    and eax, 5                           ; W is not checked (see report)
    cmp eax, esi
    jne fail
    inc ebp
    mov [esp], edi                       ; resume after the instruction
    iretd
fail:
    mov eax, ebp
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
