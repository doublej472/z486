BITS 32
org 0
start:
    mov eax, 0x11223344
    mov ecx, 0x11223344
    mov edx, 0x55667788
    cmpxchg ecx, edx
    jne fail
    cmp ecx, 0x55667788
    jne fail
    mov al, 1
    mov dx, 0xE0
    out dx, al
    hlt
fail:
    mov al, 0xFF
    mov dx, 0xE0
    out dx, al
    hlt
