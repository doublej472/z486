; INVD (0F 08) at CPL0 in protected mode must execute (added by the fork).
BITS 32
ORG 0
STATUS_PORT equ 0xE0
start:
    cli
    mov esp, 0x00003F00
    mov dword [0x00005000], 0x12345678
    invd
    mov eax, dword [0x00005000]
    cmp eax, 0x12345678
    jne fail
    wbinvd
    mov eax, dword [0x00005000]
    cmp eax, 0x12345678
    jne fail
    mov al, 1
    mov dx, STATUS_PORT
    out dx, al
    hlt
fail:
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
    hlt
