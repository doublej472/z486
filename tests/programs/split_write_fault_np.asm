; split_write_fault_np - a page-crossing MOV whose second page is not present
; must fault before writing its first half
;
; [0x5FFE] spans 0x5000 (RW, its TLB entry flushed so the first page is
; walked) and 0x6000 (not present).  The #PF handler checks that the first
; page still holds its old bytes, maps 0x6000 and restarts the store.
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
    mov dword [0x5FFC], 0x22221111
    invlpg [0x5000]
    mov dword [0x5FFE], 0xDDCCBBAA
    cmp ebp, 1                           ; exactly one #PF
    jne fail
    mov eax, cr2
    cmp eax, 0x6000
    jne fail
    mov eax, [0x5FFC]
    out 0xe4, eax
    cmp eax, 0xBBAA1111
    jne fail
    mov ax, [0x6000]
    cmp ax, 0xDDCC
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
pf_handler:
    inc ebp
    cmp dword [0x5FFC], 0x22221111       ; first half not yet written
    jne fail
    mov dword [PTE6], 0x6003             ; map 0x6000 present, RW
    invlpg [0x6000]
    add esp, 4                           ; drop the error code, restart
    iretd
fail:
    mov al, 0xff
    out 0xe0, al
    hlt
