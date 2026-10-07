; Page-walker reads must observe a PTE changed through the D-cache, including
; after the old translation was cached. INVLPG remains software's responsibility.
BITS 32
ORG 0
start:
    mov dword [0x5000], 0x11112222
    mov dword [0x6000], 0x33334444
    mov eax, [0x5000]             ; warm old translation/data
    cmp eax, 0x11112222
    jne fail
    ; FS is a zero-base alias of the low physical page-table area. The second
    ; generated PT is DS's at 0x2000; index 5 now targets physical page 0x26.
    mov dword [fs:0x2014], 0x00026063
    invlpg [0x5000]
    mov eax, [0x5000]
    cmp eax, 0x33334444
    jne fail
    ; A write through the new translation must update only the new frame.
    mov dword [0x5000], 0xaabbccdd
    cmp dword [0x6000], 0xaabbccdd
    jne fail
    cmp dword [fs:0x25000], 0x11112222
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
fail:
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
