; tlb_pwt - TR7 reports the PTE's PWT for a walked TLB entry
;
; Intel486 PRM 10.6.2: TR7 "PWT Corresponds to the PWT bit of a page table
; entry" (and PCD likewise); a lookup that hits loads them into TR7.
; Page 0x23000 gets PTE.PWT=1 (case 1) and PTE.PCD=1 (case 2, control).
; Port 0xE4: case, then the TR7 seen.
BITS 32
ORG 0
PT0 equ 0x1000
start:
    mov esp, 0x8000
    ; 2: PCD (control)
    mov dword [PT0 + 0x23*4], 0x00023073   ; P RW A D PCD
    invlpg [0x23000]
    mov eax, [0x23000]
    mov eax, 0x00023fe1
    mov tr6, eax
    mov ecx, tr7
    mov ebx, 2
    test ecx, 0x10
    jz fail
    test ecx, 0x800                        ; PCD
    jz fail
    ; 1: PWT
    mov dword [PT0 + 0x23*4], 0x0002306b   ; P RW A D PWT
    invlpg [0x23000]
    mov eax, [0x23000]                     ; walk
    mov eax, 0x00023fe1                    ; lookup, V, attributes don't care
    mov tr6, eax
    mov ecx, tr7
    mov ebx, 1
    test ecx, 0x10                         ; hit
    jz fail
    test ecx, 0x400                        ; PWT
    jz fail
    mov dword [PT0 + 0x23*4], 0x00023063
    invlpg [0x23000]
    mov al, 1
    out 0xe0, al
    hlt
fail:
    mov eax, ebx
    out 0xe4, eax
    mov eax, ecx
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
