; xadd_cmpxchg.asm - 486 XADD (0F C0/C1) and CMPXCHG (0F B0/B1).
; XADD: old destination goes to the source register, sum to the destination.
; CMPXCHG: EAX == destination -> ZF=1 and destination = source;
;          otherwise ZF=0 and EAX = destination.
BITS 32
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

D1 equ 0x4000
D2 equ 0x4004
D3 equ 0x4008
D4 equ 0x400c
D5 equ 0x4010

start:
    ; ---- XADD memory, register (0F C1) ----
    mov dword [D1], 0x00000010
    mov eax, 0x00000005
    xadd [D1], eax                     ; [D1]=0x15, eax=0x10
    cmp eax, 0x00000010
    jne fail1
    cmp dword [D1], 0x00000015
    jne fail1

    ; ---- XADD register, register (0F C0) ----
    mov ecx, 7
    mov edx, 2
    xadd ecx, edx                      ; ecx=9, edx=7
    cmp ecx, 9
    jne fail2
    cmp edx, 7
    jne fail2

    ; ---- XADD flags: the sum's flags, not the moved old value ----
    mov dword [D4], 0xffffffff
    mov eax, 0x00000001
    xadd [D4], eax                     ; 0xffffffff + 1 = 0, CF=1, ZF=1
    jnc fail3
    jnz fail3

    ; ---- CMPXCHG equal (0F B1): ZF=1, destination = source ----
    mov dword [D2], 0x11223344
    mov eax, 0x11223344
    mov ebx, 0x55667788
    cmpxchg [D2], ebx
    jne fail4                          ; jne == !ZF
    cmp eax, 0x11223344
    jne fail4
    cmp dword [D2], 0x55667788
    jne fail4

    ; ---- CMPXCHG unequal: ZF=0, EAX = destination, destination unchanged ----
    mov dword [D3], 0x0a0b0c0d
    mov eax, 0x01020304
    mov ebx, 0x55667788
    cmpxchg [D3], ebx
    je fail5                           ; je == ZF must be 0
    cmp eax, 0x0a0b0c0d
    jne fail5
    cmp dword [D3], 0x0a0b0c0d
    jne fail5

    ; ---- CMPXCHG byte form (0F B0) ----
    mov byte [D5], 0x77
    mov al, 0x77
    mov bl, 0x88
    cmpxchg [D5], bl
    jne fail6
    cmp byte [D5], 0x88
    jne fail6

    ; ---- LOCK-prefixed forms must execute, not fault ----
    mov dword [D3], 0x00000001
    mov eax, 0x00000001
    mov ebx, 0x00000002
    lock cmpxchg [D3], ebx
    jne fail7
    cmp dword [D3], 0x00000002
    jne fail7

    mov al, 0x01
    mov dx, STATUS_PORT
    out dx, al
    hlt

fail1: mov eax, 1
       jmp fail
fail2: mov eax, 2
       jmp fail
fail3: mov eax, 3
       jmp fail
fail4: mov eax, 4
       jmp fail
fail5: mov eax, 5
       jmp fail
fail6: mov eax, 6
       jmp fail
fail7: mov eax, 7
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
hang:
    hlt
    jmp hang
