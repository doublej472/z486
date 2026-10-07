; cs_limit_fetch_real - real-mode instruction fetch honours the CS limit
;
; Intel486 PRM, "Real Address Mode Exceptions": interrupt 13 if any part of
; an operand lies outside 0-0FFFFh; for the code segment that is every byte of
; the instruction (CS limit 0FFFFh).  Sequential EIP is 32 bits: an
; instruction that ends exactly at 0FFFFh executes and leaves EIP = 10000h,
; so the *next* fetch raises #GP(0) with IP 0000h pushed, and a 32-bit far
; CALL there pushes return EIP 00010000h.  Fetching never wraps to offset 0.
;
; The code under test is copied to TSEG:FFFx.  Linear TSEG*16+10000h and
; TSEG:0000 hold a failure stub, so a core that wraps or runs on linearly is
; caught.  The #GP handler records CS:IP and resumes at the slot's
; continuation; port 0xE4 reports (slot << 8) | field for each mismatch.
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
    mov word [es:13*4], gp_handler
    mov [es:13*4+2], cs
    mov ax, cs
    mov ds, ax
    ; Failure stubs at TSEG:0000 and at the linear continuation past it.
    mov ax, TSEG
    mov es, ax
    xor di, di
    mov si, stub
    mov cx, stub_len
    rep movsb
    mov ax, TSEG + 0x1000
    mov es, ax
    xor di, di
    mov si, stub
    mov cx, stub_len
    rep movsb
    mov ax, TSEG
    mov es, ax

    ; Slot 0: MOV EAX,imm32 (6 bytes) at FFFC crosses the limit: #GP at
    ; FFFC, EAX untouched.
    mov word [cur], 0
    mov di, 0xfffc
    mov si, code_a
    mov cx, 6
    rep movsb
    mov eax, 0x5a5a5a5a
    jmp TSEG:0xfffc
cont0:
    mov [r_eax + 0], eax

    ; Slot 1: MOV EAX,imm32 at FFFA ends at FFFF: it executes, then the fetch
    ; at IP 10000h faults with IP 0000h pushed.
    mov word [cur], 1
    mov di, 0xfffa
    mov si, code_a
    mov cx, 6
    rep movsb
    mov eax, 0x5a5a5a5a
    jmp TSEG:0xfffa
cont1:
    mov [r_eax + 4], eax

    ; Slot 2: CALL FAR ptr16:32 (66 9A, 8 bytes) at FFF8 ends at FFFF and
    ; pushes the 32-bit return EIP 00010000h.
    mov word [cur], 2
    mov di, 0xfff8
    mov si, code_c
    mov cx, 8
    rep movsb
    jmp TSEG:0xfff8
cont2:

    ; Slot 3: a one-byte NOP at FFFF executes; the fetch after it faults.
    mov word [cur], 3
    mov byte [es:0xffff], 0x90
    jmp TSEG:0xffff
cont3:

    ; ---- check ----
    xor bx, bx
    xor si, si
.loop:
    mov di, si
    add di, di
    mov ax, [r_ip + di]
    cmp ax, [x_ip + di]
    je .e1
    mov dl, 1
    call report
.e1:
    mov ax, [r_cs + di]
    cmp ax, [x_cs + di]
    je .e2
    mov dl, 2
    call report
.e2:
    mov al, [r_cnt + si]
    cmp al, 1
    je .e3
    mov dl, 3
    call report
.e3:
    inc si
    cmp si, NSLOT
    jb .loop
    cmp dword [r_eax + 0], 0x5a5a5a5a
    je .e4
    mov si, 0
    mov dl, 4
    call report
.e4:
    cmp dword [r_eax + 4], 0x44332211
    je .e5
    mov si, 1
    mov dl, 4
    call report
.e5:
    cmp dword [r_ret], 0x00010000
    je .e6
    mov si, 2
    mov dl, 5
    call report
.e6:
    cmp word [r_ret + 4], TSEG
    je .e7
    mov si, 2
    mov dl, 6
    call report
.e7:
    test bx, bx
    jnz bad
    mov al, 1
    out 0xe0, al
    hlt
bad:
    mov al, 0xff
    out 0xe0, al
    hlt

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

; Slot 2's far call lands here with CS = this segment: record the 6-byte
; return frame (EIP dword, CS word) and resume.
call_target:
    mov bp, sp
    mov eax, [ss:bp]
    mov [cs:r_ret], eax
    mov ax, [ss:bp + 4]
    mov [cs:r_ret + 4], ax
    add sp, 8
    ; The call completed (no #GP: its successor is never fetched); count the
    ; arrival as the slot's single event.
    inc byte [cs:r_cnt + 2]
    jmp cont2

gp_handler:
    push bp
    mov bp, sp
    push si
    push ax
    mov si, [cs:cur]
    inc byte [cs:r_cnt + si]
    add si, si
    mov ax, [bp + 2]            ; pushed IP
    mov [cs:r_ip + si], ax
    mov ax, [bp + 4]            ; pushed CS
    mov [cs:r_cs + si], ax
    mov ax, [cs:conts + si]
    mov [bp + 2], ax
    mov [bp + 4], cs
    pop ax
    pop si
    pop bp
    iret

stub:
    mov al, 0xff
    out 0xe0, al
    hlt
stub_len equ $ - stub

code_a: db 0x66, 0xb8, 0x11, 0x22, 0x33, 0x44     ; mov eax, 44332211h
code_c: db 0x66, 0x9a
        dd call_target
        dw 0x1000                                 ; this program's CS

align 4
cur:    dw 0
conts:  dw cont0, cont1, cont2, cont3
r_ip:   times NSLOT dw 0xeeee
r_cs:   times NSLOT dw 0xeeee
r_cnt:  times NSLOT db 0
r_eax:  dd 0, 0
r_ret:  dd 0
        dw 0
;               slot0   slot1   slot2   slot3
x_ip:   dw     0xfffc, 0x0000, 0xeeee, 0x0000
x_cs:   dw       TSEG,   TSEG, 0xeeee,   TSEG
