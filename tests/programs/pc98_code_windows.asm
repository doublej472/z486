; Execute and modify a code line through the PC-98 aperture/window-0 overlay.
; The DIRECT version must invalidate its cached I-line on the CPU write;
; NO_ALLOC must answer the overlay fetch without installing an I-line.
; Both still require a control transfer to serialize self-modifying code.
BITS 32
ORG 0
start:
    mov esp, 0x70000
    call target
    cmp eax, 0x11223344
    jne fail
    mov dword [target + 1], 0x55667788
    jmp short serialize
serialize:
    call target
    cmp eax, 0x55667788
    jne fail
    ; Flush must not break instruction fetch from either window.
    wbinvd
    call target
    cmp eax, 0x55667788
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
