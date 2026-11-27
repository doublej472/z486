; tf_trap_at_fetch_fault - a single-step trap beats the next fetch's #GP
;
; Intel 64 and IA-32 SDM Vol. 3A, 6.9, Table 6-2: class 4, "Traps on the
; Previous Instruction ... Debug Trap Exceptions (TF flag set ...)", is above
; class 7, "Faults from Fetching Next Instruction ... Code-Segment Limit
; Violation".  Intel486 PRM, "Real Address Mode Exceptions": an instruction
; that ends exactly at 0FFFFh executes and the next fetch raises interrupt 13.
;
; Each slot enters TSEG:FFFx by IRET with TF set, so the one instruction
; there is single-stepped (TF is sampled at its start).  Expected per slot:
; one #DB with IP 0000h, CS TSEG pushed, and no #GP.  The #DB handler resumes
; at the slot's continuation with TF clear.  Port 0xE4 reports
; (slot << 8) | field for each mismatch: 1 = #DB count, 2 = #DB IP,
; 3 = #DB CS, 4 = #GP count.
BITS 16
ORG 0
TSEG   equ 0x3000
NSLOT  equ 4

start:
    cli
    cld
    xor ax, ax
    mov ss, ax
    mov sp, 0x7000
    mov es, ax
    mov word [es:1*4], db_handler
    mov [es:1*4+2], cs
    mov word [es:13*4], gp_handler
    mov [es:13*4+2], cs
    mov ax, cs
    mov ds, ax
    mov ax, TSEG
    mov es, ax

    ; Slot 0: DIV BX (F7 F3, microcoded) at FFFE.
    mov word [cur], 0
    mov word [es:0xfffe], 0xf3f7
    mov ax, 0x1234
    xor dx, dx
    mov bx, 7
    mov di, 0xfffe
    call enter_tf
cont0:
    ; Slot 1: MOV EAX,imm32 (6 bytes) at FFFA.
    mov word [cur], 1
    mov di, 0xfffa
    mov si, code_a
    mov cx, 6
    rep movsb
    mov di, 0xfffa
    call enter_tf
cont1:
    ; Slot 2: NOP at FFFF.
    mov word [cur], 2
    mov byte [es:0xffff], 0x90
    mov di, 0xffff
    call enter_tf
cont2:
    ; Slot 3: IMUL EAX,EBX (0F AF C3, 3 bytes) at FFFD.
    mov word [cur], 3
    mov word [es:0xfffd], 0xaf0f
    mov byte [es:0xffff], 0xc3
    mov eax, 0x12345
    mov ebx, 0x777
    mov di, 0xfffd
    call enter_tf
cont3:

    ; ---- check ----
    xor bx, bx
    xor si, si
.loop:
    mov di, si
    add di, di
    cmp byte [r_db + si], 1
    je .e1
    mov dl, 1
    call report
.e1:
    cmp word [r_ip + di], 0x0000
    je .e2
    mov dl, 2
    call report
.e2:
    cmp word [r_cs + di], TSEG
    je .e3
    mov dl, 3
    call report
.e3:
    cmp byte [r_gp + si], 0
    je .e4
    mov dl, 4
    call report
.e4:
    inc si
    cmp si, NSLOT
    jb .loop
    test bx, bx
    jnz bad
    mov al, 1
    out 0xe0, al
    hlt
bad:
    mov al, 0xff
    out 0xe0, al
    hlt

; IRET to TSEG:DI with TF set (the return address on the stack is dropped:
; every handler resumes at the slot's continuation).
enter_tf:
    add sp, 2
    pushf
    pop cx
    or cx, 0x0100
    push cx
    push es
    push di
    iret

report:                         ; si = slot, dl = field
    inc bx
    push eax
    mov ax, si
    mov ah, al
    mov al, dl
    movzx eax, ax
    out 0xe4, eax
    pop eax
    ret

; Both handlers record the frame and resume at the slot's continuation with
; TF clear.
db_handler:
    push bp
    mov bp, sp
    push si
    push ax
    mov si, [cs:cur]
    inc byte [cs:r_db + si]
    add si, si
    mov ax, [bp + 2]
    mov [cs:r_ip + si], ax
    mov ax, [bp + 4]
    mov [cs:r_cs + si], ax
    jmp resume

gp_handler:
    push bp
    mov bp, sp
    push si
    push ax
    mov si, [cs:cur]
    inc byte [cs:r_gp + si]
    add si, si
resume:
    mov ax, [cs:conts + si]
    mov [bp + 2], ax
    mov [bp + 4], cs
    and word [bp + 6], 0xfeff
    pop ax
    pop si
    pop bp
    iret

code_a: db 0x66, 0xb8, 0x11, 0x22, 0x33, 0x44     ; mov eax, 44332211h

align 4
cur:    dw 0
conts:  dw cont0, cont1, cont2, cont3
r_ip:   times NSLOT dw 0xeeee
r_cs:   times NSLOT dw 0xeeee
r_db:   times NSLOT db 0
r_gp:   times NSLOT db 0
