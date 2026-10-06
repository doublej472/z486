; sidecar_epoch_wrap.asm - CR3 flushes across a sidecar epoch wrap
;
; The sidecar TLB marks entries valid by epoch: a CR3 write advances the
; epoch, and a wrap scrubs every entry. Cache page Y, remap it, then flush
; CR3 exactly once per epoch value (15 times) while remapping page X each
; time. When the epoch comes back to Y's, Y's stale entry must not match.

BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

PAGE_X      equ 0x00020000
PAGE_Y      equ 0x00022000
X_PHYS_A    equ 0x00030000
X_PHYS_B    equ 0x00031000
Y_PHYS_A    equ 0x00032000
Y_PHYS_B    equ 0x00033000

; CR3=0 and every address is in PDE 0, whose generated page table is at 0x1000.
X_PTE       equ 0x00001080
Y_PTE       equ 0x00001088
PTE_FLAGS   equ 0x00000023       ; present, writable, accessed

start:
    mov esp, 0x0003F000
    mov dword [X_PHYS_A], 0xAAAA0001
    mov dword [X_PHYS_B], 0xBBBB0002
    mov dword [Y_PHYS_A], 0x11110003
    mov dword [Y_PHYS_B], 0x22220004

    mov dword [X_PTE], X_PHYS_A | PTE_FLAGS
    mov dword [Y_PTE], Y_PHYS_A | PTE_FLAGS
    mov eax, cr3
    mov cr3, eax

    ; Cache Y at this epoch, then remap it without a flush.
    mov eax, [PAGE_Y]
    cmp eax, 0x11110003
    jne fail_1
    mov dword [Y_PTE], Y_PHYS_B | PTE_FLAGS

    ; One full epoch cycle of flushes, remapping X each time.
    mov ecx, 15
    call x_rounds

    ; Let the wrap's scrub finish, then Y must see its new mapping.
    mov ecx, 1000
.wait:
    dec ecx
    jnz .wait
    mov eax, [PAGE_Y]
    cmp eax, 0x11110003
    je fail_2
    cmp eax, 0x22220004
    jne fail_3

    ; Back-to-back wraps.
    mov ecx, 30
    call x_rounds

    mov al, 0x01
    out STATUS_PORT, al
    hlt

; ECX rounds: remap X to the other frame, flush CR3, check a direct load.
x_rounds:
    mov esi, PAGE_X
.round:
    mov eax, [X_PTE]
    xor eax, (X_PHYS_A ^ X_PHYS_B)
    mov [X_PTE], eax
    mov edx, cr3
    mov cr3, edx
    mov ebx, [esi]
    and eax, 0xFFFFF000
    cmp eax, X_PHYS_A
    je .expect_a
    cmp ebx, 0xBBBB0002
    jne .fail_x
    jmp .next
.expect_a:
    cmp ebx, 0xAAAA0001
    jne .fail_x
.next:
    dec ecx
    jnz .round
    ret

.fail_x:
    mov eax, ecx
    or eax, 0x100
    jmp fail
fail_1:
    mov eax, 1
    jmp fail
fail_2:
    mov eax, 2
    jmp fail
fail_3:
    mov eax, 3
fail:
    out DATA_PORT, eax
    mov al, 0xFF
    out STATUS_PORT, al
    hlt
