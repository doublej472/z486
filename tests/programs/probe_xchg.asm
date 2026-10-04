; XCHG (86/87/90+r) - uncovered probe: reg, accumulator, memory, byte, NOP form
BITS 32
ORG 0
STATUS_PORT equ 0xE0
MEM equ 0x00005000
start:
    cli
    mov esp, 0x00003F00
; general form r/m32, r32
    mov eax, 0x11111111
    mov ebx, 0x22222222
    xchg eax, ebx
    cmp eax, 0x22222222
    jne fail
    cmp ebx, 0x11111111
    jne fail
; accumulator form (90+r)
    mov ecx, 0x33333333
    xchg ecx, eax
    cmp eax, 0x33333333
    jne fail
    cmp ecx, 0x22222222
    jne fail
; memory form
    mov dword [MEM], 0x44444444
    mov eax, 0x55555555
    xchg eax, [MEM]
    cmp eax, 0x44444444
    jne fail
    cmp dword [MEM], 0x55555555
    jne fail
; byte form
    mov byte [MEM], 0x66
    mov eax, 0x00000077
    xchg al, [MEM]
    cmp al, 0x66
    jne fail
    cmp byte [MEM], 0x77
    jne fail
; XCHG EAX,EAX is the canonical NOP: must leave EAX alone
    mov eax, 0xCDCDCDCD
    xchg eax, eax
    cmp eax, 0xCDCDCDCD
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
