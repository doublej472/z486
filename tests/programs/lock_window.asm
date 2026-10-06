; lock_window - locked RMW and XCHG on the uncached device/VGA windows
BITS 32
ORG 0
start:
    mov esp, 0x8000
    mov dword [0xA0000], 1
    mov dword [0xC0000], 1
    mov dword [0xE0000], 1
    mov eax, [0xA0000]
    lock add dword [0xA0000], 5
    mov ecx, 3
    xchg [0xC0000], ecx
    lock inc dword [0xE0000]
    cmp dword [0xA0000], 6
    jne fail
    cmp ecx, 1
    jne fail
    cmp dword [0xE0000], 2
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
fail:
    mov al, 0xff
    out 0xe0, al
    hlt
