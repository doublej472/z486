; split_write_clean_tlb2 - a page-crossing write whose second page is held
; clean in the TLB walks that page before writing its first half
;
; SDM Vol. 3A 4.8: a write sets the dirty flag in the paging-structure entry,
; so a write through a TLB entry whose D flag is clear re-reads the PTE; here
; the PTE of 0x6000 was made not present after a read cached it clean, so
; that walk faults (#PF, error code 2: write, not present).  As in
; split_write_fault_np, the fault comes before the first half is written
; (SDM Vol. 3A 6.5: a fault is restartable), so the handler sees the first
; page unchanged.
BITS 32
ORG 0
GDT equ 0xA800
IDT equ 0xB000
PTE6 equ 0x1018                          ; PTE of linear 0x6000
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
    mov edi, 0xeeeeeeee
    mov dword [0x5FFC], 0x22221111       ; page 1 dirty in the TLB
    mov eax, [0x6000]                    ; page 2 cached clean
    mov eax, 0x10
    test dword [PTE6], 0x40              ; its D flag is still clear
    jnz fail
    and dword [PTE6], 0xfffffffe         ; not present, TLB not flushed
    mov dword [0x5FFE], 0xDDCCBBAA
    mov eax, 0x11
    cmp ebp, 1                           ; exactly one #PF
    jne fail
    mov eax, 0x12
    cmp edi, 2                           ; write, not present
    jne fail
    mov eax, cr2
    cmp eax, 0x6000
    jne fail
    mov eax, 0x13
    cmp dword [0x5FFC], 0xBBAA1111
    jne fail
    cmp word [0x6000], 0xDDCC
    jne fail
    mov eax, 0x14
    test dword [PTE6], 0x40              ; the restarted write set D
    jz fail
    mov al, 1
    out 0xe0, al
    hlt
pf_handler:
    inc ebp
    mov edi, [esp]                       ; error code
    mov eax, 0x20
    cmp dword [0x5FFC], 0x22221111       ; first half not yet written
    jne fail
    mov dword [PTE6], 0x6023             ; present, RW, A
    invlpg [0x6000]
    add esp, 4                           ; drop the error code, restart
    iretd
fail:
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
