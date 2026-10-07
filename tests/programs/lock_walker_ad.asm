; lock_walker_ad - the walker's PTE dirty-bit update vs an external write
;
; A store to a clean page makes the walker read its PTE and write it back with
; D set.  The testbench's lock-honouring external master (+xdma_*) writes the
; same PTE (setting AVL bit 9) right after the walker's PTE read.  A 486 sets
; A/D with a locked read-modify-write, so the external write lands either
; before the locked read (the walker merges it) or after the locked write: the
; AVL bit always survives.  An unlocked update writes the stale PTE back.
BITS 32
ORG 0
start:
    mov esp, 0x8000
    mov dword [0x9000], 1        ; TLB miss, D=0: walk + PTE write-back
    invd                         ; write-through L1: drop the stale PTE line
    mov eax, [0x1024]            ; PTE of linear 0x9000
    out 0xe4, eax
    test eax, 0x200              ; external write's AVL bit
    jz fail
    mov al, 1
    out 0xe0, al
    hlt
fail:
    mov al, 0xff
    out 0xe0, al
    hlt
