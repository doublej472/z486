; cmpxchg_ro - CMPXCHG whose compare fails still writes (486), so a
; read-only destination raises #PF; locked and unlocked
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

    mov esi, 1                           ; read-only page: P (W, U masked)
    mov edi, c1
    mov eax, 0x12345678                  ; compare fails ([0x9000] = 0)
    mov ebx, 7
    cmpxchg [0x9000], ebx                ; 486 writes the old value back: #PF
c1: mov edi, c2
    mov eax, 0x12345678
    lock cmpxchg [0x9000], ebx
c2: cmp ebp, 2
    jne fail
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
