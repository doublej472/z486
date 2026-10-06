; pte_snoop - a snooped external PTE write must reach the next walk
;
; The first load of 0x9000 walks; the external master (+xdma_*) rewrites its
; PTE (frame 0x9000 -> 0xA000) with a snoop just after the walker's PTE line
; read.  After INVLPG the next load must walk again and see the new frame: the
; walker must not use a PTE line the snoop invalidated (e.g. a fill installed
; after the snoop).
BITS 32
ORG 0
start:
    mov esp, 0x8000
    mov dword [0x9000], 0x11111111
    mov dword [0xA000], 0x22222222
    invd                          ; the PT line is not cached yet
    invlpg [0x9000]               ; and 0x9000 is not in the TLB
    mov eax, [0x9000]             ; walk; external PTE write races it
    mov ecx, 100
spin:
    loop spin
    invlpg [0x9000]
    mov eax, [0x9000]
    out 0xe4, eax
    cmp eax, 0x22222222
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
fail:
    mov al, 0xff
    out 0xe0, al
    hlt
