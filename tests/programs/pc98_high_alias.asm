; Execute through the high firmware alias, above the L1 physical tag reach.
; The harness mirrors reads into low ROM backing and ignores high-ROM writes.
; Verify execution before/after a write attempt and WBINVD; fetches must never
; allocate a truncated tag. This pins CPU routing, not NEC ROM contents.
BITS 32
ORG 0
start:
    mov esp, 0x70000
    call target
    cmp eax, 0x11223344
    jne fail
    mov dword [target+1], 0x55667788
    jmp short serialize
serialize:
    call target
    cmp eax, 0x11223344
    jne fail
    wbinvd
    call target
    cmp eax, 0x11223344
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
fail:
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
align 16
target:
    mov eax, 0x11223344
    ret
