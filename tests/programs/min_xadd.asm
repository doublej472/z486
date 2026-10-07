BITS 32
org 0
start:
    mov ecx, 7
    mov edx, 2
    xadd ecx, edx
    cmp ecx, 9
    jne fail
    cmp edx, 7
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
