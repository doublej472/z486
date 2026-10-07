; BSF/BSR (0F BC / 0F BD) - uncovered probe
BITS 32
ORG 0
STATUS_PORT equ 0xE0
start:
    cli
    mov esp, 0x00003F00
    mov ebx, 0x00800000
    bsf eax, ebx
    cmp eax, 23
    jne fail
    bsr ecx, ebx
    cmp ecx, 23
    jne fail
    mov ebx, 0x00000100
    bsf edx, ebx
    cmp edx, 8
    jne fail
    bsr esi, ebx
    cmp esi, 8
    jne fail
    mov ebx, 0x80000000
    bsf edi, ebx
    cmp edi, 31
    jne fail
    mov ebx, 1
    bsf eax, ebx
    cmp eax, 0
    jne fail
; zero source must set ZF (jne taken means ZF=0 -> bug)
    xor ebx, ebx
    bsf eax, ebx
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
