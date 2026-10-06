; lock_forms - one locked bus read and one locked write per locked RMW
BITS 32
ORG 0
start:
    mov esp, 0x8000
    mov ecx, 1
    mov dword [0x9000], 1
    mov dword [0x9040], 1
    mov dword [0x9080], 1
    mov dword [0x90c0], 1
    mov dword [0x9100], 1
    mov dword [0x9140], 1
    mov dword [0x9180], 1
    mov dword [0x91c0], 1
    mov dword [0x9200], 1
    mov dword [0x9240], 1
    mov eax, [0x9500]            ; spacer
    lock add [0x9000], ecx       ; 01 /r
    nop
    nop
    lock add dword [0x9040], 5   ; 83 /0
    nop
    nop
    lock inc dword [0x9080]      ; FF /0
    nop
    nop
    lock not dword [0x90c0]      ; F7 /2
    nop
    nop
    lock bts dword [0x9100], 3   ; 0F BA /5
    nop
    nop
    lock xadd [0x9140], ecx      ; 0F C1
    nop
    nop
    xchg [0x9180], ecx           ; 87 (implicitly locked)
    nop
    nop
    lock sub word [0x91c0], cx   ; 66 29
    nop
    nop
    lock and byte [0x9200], cl   ; 20
    nop
    nop
    mov eax, 5
    lock cmpxchg [0x9240], ecx   ; compare fails: 486 writes the old value back
    nop
    nop
    mov al, 1
    out 0xe0, al
    hlt
