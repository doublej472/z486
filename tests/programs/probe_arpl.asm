; ARPL (63). r/m16 RPL is raised to the r16 RPL; ZF=1 iff it changed.
BITS 32
ORG 0
STATUS_PORT equ 0xE0
start:
    cli
    mov esp, 0x00003F00
; dest RPL 0, source RPL 3 -> dest becomes RPL 3 and ZF=1
    mov eax, 0x0013
    mov ebx, 0x0010
    arpl bx, ax
    setz cl                    ; capture ZF before any flag-clobbering compare
    cmp bx, 0x0013
    jne fail
    cmp cl, 1
    jne fail
; dest RPL already equal -> unchanged, ZF=0
    mov eax, 0x0003
    mov ebx, 0x0013
    arpl bx, ax
    setz cl
    cmp bx, 0x0013
    jne fail
    cmp cl, 0
    jne fail
; dest RPL 2, source RPL 1 -> unchanged, ZF=0
    mov eax, 0x0001
    mov ebx, 0x0022
    arpl bx, ax
    setz cl
    cmp bx, 0x0022
    jne fail
    cmp cl, 0
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
