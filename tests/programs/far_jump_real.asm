; far_jump_real.asm - real-mode far transfers: immediate jmp/call far (0xEA/0x9A),
; memory-indirect jmp/call far (FF /5, FF /3), and retf.
BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

; The test framework loads this image at CS=0x1000 (base 0x10000) in real mode.
SEG_CODE equ 0x1000

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x8000
    mov ax, cs
    mov ds, ax          ; DS = CS so data pointers hit the code page

    ; --- 1: immediate far jump (0xEA, 16:16) -------------------------------
    jmp SEG_CODE:t1_target
t1_dead:
    mov al, 0xEE
    jmp fail
t1_target:
    mov dl, 0x01        ; landed via immediate far jump

    ; --- 2: memory-indirect far jump (FF /5) -------------------------------
    mov word [jptr+0], t2_target
    mov word [jptr+2], cs
    jmp far [jptr]
t2_dead:
    mov al, 0xED
    jmp fail
t2_target:
    mov dl, 0x02        ; landed via jmp m16:16

    ; --- 3: memory-indirect far call (FF /3) + retf ------------------------
    mov word [cptr+0], t3_sub
    mov word [cptr+2], cs
    call far [cptr]     ; pushes CS:IP, jumps through the pointer
    cmp dl, 0x03        ; retf returned here
    jne fail

    ; --- 4: immediate far call (0x9A) + retf -------------------------------
    call SEG_CODE:t4_sub
    cmp dl, 0x04
    jne fail

    mov al, 0x01
    mov dx, STATUS_PORT
    out dx, al
    hlt

t3_sub:
    mov dl, 0x03
    retf

t4_sub:
    mov dl, 0x04
    retf

fail:
    mov dx, DATA_PORT
    out dx, ax
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
    hlt

jptr: dw 0, 0
cptr: dw 0, 0
