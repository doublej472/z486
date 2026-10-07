; tlb_test2 - TR6/TR7 entries against the other TLB invalidators
;
;  1. An entry installed with TR6 (C=0) is dropped by a CR3 reload.
;  2. A TR6 write with V=0 into the way holding a walked translation
;     invalidates it: the next access walks the (changed) page tables.
;  3. A TR6 lookup after INVLPG reports a miss (PL=0).
;  4. TR7 read straight after a lookup holds the lookup result.
; (Intel486 PRM 10.3 "Testing the TLB"; MOV CR3 and INVLPG flush TLB entries.)
BITS 32
ORG 0
PT0 equ 0x1000
%macro EXPECT 3
    cmp %1, %2
    jne fail_%3
%endmacro

start:
    mov esp, 0x8000
    mov dword [0x26100], 0xabcd1234
    mov dword [0x24100], 0x11111111
    mov dword [0x27100], 0x77777777

    ; 1: TR6-installed entry, then MOV CR3 (reload)
    invlpg [0x24000]
    mov eax, 0x00026c18                ; PA 0x26000, PCD, PWT, HT, REP=2
    mov tr7, eax
    mov eax, 0x00024d40                ; linear 0x24000, V, D, U, W, C=0
    mov tr6, eax
    mov eax, [0x24100]
    EXPECT eax, 0xabcd1234, 1
    mov eax, cr3
    mov cr3, eax
    mov eax, 0x00024fe1                ; lookup: must miss after the flush
    mov tr6, eax
    mov ecx, tr7
    test ecx, 0x10
    jnz fail_3
    mov eax, [0x24100]
    EXPECT eax, 0x11111111, 2

    ; 2: walked entry, find its way, V=0 write to that way
    mov eax, [0x24100]                 ; walked: 0x24000 -> 0x24000
    mov eax, 0x00024fe1
    mov tr6, eax
    mov ecx, tr7                       ; 4: TR7 right after the lookup
    test ecx, 0x10
    jz fail_4
    mov edx, ecx
    and edx, 0xfffff000
    EXPECT edx, 0x00024000, 5
    ; repoint the PTE without invalidating; the TLB keeps the old one
    mov dword [PT0 + 0x24*4], 0x00027063
    mov eax, [0x24100]
    EXPECT eax, 0x11111111, 6
    ; V=0 into the reported way (REP from the lookup, HT=1)
    and ecx, 0x0000000c
    or ecx, 0x00024010                 ; PFN, HT, REP
    mov tr7, ecx
    mov eax, 0x00024540                ; linear 0x24000, V=0, D, U, W, C=0
    mov tr6, eax
    mov eax, [0x24100]
    EXPECT eax, 0x77777777, 7          ; re-walked through the new PTE

    ; 3: INVLPG then lookup misses
    invlpg [0x24000]
    mov eax, 0x00024fe1
    mov tr6, eax
    mov ecx, tr7
    test ecx, 0x10
    jnz fail_8
    mov dword [PT0 + 0x24*4], 0x00024063
    invlpg [0x24000]

    mov al, 1
    out 0xe0, al
    hlt

%assign c 1
%rep 8
fail_ %+ c:
    mov eax, c
    jmp fail
%assign c c+1
%endrep
fail:
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
