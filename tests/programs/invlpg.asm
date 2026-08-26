; invlpg.asm - 486 single-page TLB invalidation
;
; Populate two neighboring translations, rewrite both PTEs, invalidate only
; the first page, and verify that the first translation changes while the
; neighboring cached translation remains intact.

BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

TARGET      equ 0x00020000
NEIGHBOR    equ 0x00021000
NEW_TARGET  equ 0x00030000
NEW_NEIGHBOR equ 0x00031000

; CR3=0 and every address is in PDE 0, whose generated page table is at 0x1000.
TARGET_PTE   equ 0x00001080
NEIGHBOR_PTE equ 0x00001084
PTE_FLAGS    equ 0x00000023       ; present, writable, accessed

start:
    mov esp, 0x0003F000

    mov dword [TARGET], 0x11111111
    mov dword [NEIGHBOR], 0x22222222
    mov dword [NEW_TARGET], 0x33333333
    mov dword [NEW_NEIGHBOR], 0x44444444

    ; Populate both old translations in the TLB.
    mov eax, [TARGET]
    cmp eax, 0x11111111
    jne .fail_1
    mov eax, [NEIGHBOR]
    cmp eax, 0x22222222
    jne .fail_2

    ; Redirect both virtual pages, but invalidate only TARGET.
    mov dword [TARGET_PTE], NEW_TARGET | PTE_FLAGS
    mov dword [NEIGHBOR_PTE], NEW_NEIGHBOR | PTE_FLAGS
    mov ebx, TARGET
    invlpg [ebx]

    mov eax, [TARGET]
    cmp eax, 0x33333333
    jne .fail_3

    ; INVLPG must not flush the neighboring cached translation.
    mov eax, [NEIGHBOR]
    cmp eax, 0x22222222
    jne .fail_4

    mov al, 0x01
    out STATUS_PORT, al
    hlt

.fail_1:
    mov eax, 1
    jmp .fail
.fail_2:
    mov eax, 2
    jmp .fail
.fail_3:
    mov eax, 3
    jmp .fail
.fail_4:
    mov eax, 4
.fail:
    out DATA_PORT, eax
    mov al, 0xFF
    out STATUS_PORT, al
    hlt
