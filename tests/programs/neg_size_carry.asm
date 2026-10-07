; neg_size_carry.asm - NEG must derive CF from the byte/word operand, not the
; full 32-bit dst. LOCK/cold-page byte/word NEG of 0 with dirty upper bytes
; must retire CF=0.
BITS 32
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

MB  equ 0x1000       ; byte operand, low byte 0 with dirty upper bytes
MW  equ 0x1004       ; word operand, low word 0 with dirty upper word
MD  equ 0x1008       ; dword control operand

start:
    cli
    mov esp, 0x00003F00
    xor edi, edi

;--- 1: lock neg byte [MB], [MB]=0x00, [MB+1..3]=0xFF -> CF=0, ZF=1
    mov eax, 0xFFFFFF00
    mov [MB], eax
    mov dl, [MB]                 ; warm the line
    lock neg byte [MB]
    jnc .c1
    or  edi, 0x01
.c1:

;--- 2: lock neg word [MW], [MW]=0x0000, [MW+2..3]=0xFFFF -> CF=0
    mov eax, 0xFFFF0000
    mov [MW], eax
    mov edx, [MW]
    lock neg word [MW]
    jnc .c2
    or  edi, 0x02
.c2:

;--- 3: first data touch of the code page (cold line, LOCK-free RMW) with the
;       same zero byte / dirty neighbours -> CF=0
    neg byte [es:CLEAN]
    jnc .c3
    or  edi, 0x04
.c3:

;--- 4: control - lock neg byte with operand 1 -> CF=1
    mov byte [MB], 1
    mov dl, [MB]
    lock neg byte [MB]
    jc  .c4
    or  edi, 0x08
.c4:

;--- 5: control - lock neg dword with operand 0 -> CF=0
    mov dword [MD], 0
    mov edx, [MD]
    lock neg dword [MD]
    jnc .c5
    or  edi, 0x10
.c5:

    test edi, edi
    jz  .pass
    mov eax, edi
    mov dx, DATA_PORT
    out dx, eax
    jmp .fail

.pass:
    mov al, 0x01
    mov dx, STATUS_PORT
    out dx, al
    hlt

.fail:
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
    hlt

; Dirty byte lane for the cold-page NEG: 0x00 followed by three 0xFF bytes.
; It sits inside the loaded code image so the page is only PTE-Accessed, never
; PTE-Dirty, until the NEG write-back above.
align 4
CLEAN:
    db 0x00, 0xFF, 0xFF, 0xFF
