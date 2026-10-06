; rmw_device_reads - bus reads per unlocked RMW in the PC-98 device
; aperture (uncached).  A 486 issues one read and one write per RMW.
BITS 32
ORG 0
start:
    mov esp, 0x8000
    mov al, 0x0f
    mov ecx, 1
    mov dword [0xA8000], 0
    mov dword [0xE0000], 0
    or [0xA8000], al             ; 08 /r  (GRCG/EGC-style plane RMW)
    add [0xE0000], ecx           ; 01 /r
    inc dword [0xE0004]          ; FF /0
    or byte [0xA8004], 0x0f      ; 80 /1
    mov al, 1
    out 0xe0, al
    hlt
