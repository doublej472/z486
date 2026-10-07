; rmw_reads - bus reads per uncached RMW (CR0.CD=1, line not cached)
BITS 32
ORG 0
start:
    mov esp, 0x8000
    mov ecx, 1
    mov dword [0x9000], 1
    mov dword [0x9040], 1
    mov eax, cr0
    or eax, 0x40000000
    mov cr0, eax
    add [0x9000], ecx            ; 01 /r unlocked, uncached
    nop
    nop
    add dword [0x9040], 5        ; 83 /0 unlocked, uncached
    nop
    mov al, 1
    out 0xe0, al
    hlt
