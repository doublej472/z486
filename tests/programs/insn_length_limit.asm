; insn_length_limit - an instruction longer than 15 bytes raises #GP(0)
;
; i486 Programmer's Reference Manual: an instruction is at most 15 bytes long
; (instruction format, prefixes), and the general-protection exception list
; (interrupt 13; 80386 PRM 9.8.13, item 15) includes "Exceeding the
; instruction length limit of 15 bytes".  In real-address mode the same
; condition is interrupt 13.
; The fault is reported before the instruction does anything, so the saved
; CS:IP is the instruction's first (prefix) byte and no register or memory
; operand changes.
;
; Each case is a run of redundant prefixes followed by one instruction; the
; lengths straddle the limit (15 executes, 16 and more fault).  The body
; kinds cover a one-byte opcode, a ModR/M + disp16 + imm16 body, a ModR/M-only
; body (the whole instruction is structural), an 0F opcode (0F counts towards
; the length; at 15 prefixes it is itself byte 16), and a 66 67 body with a
; SIB, disp32 and imm32.  Every case runs at the 16 offsets of a 16-byte line
; so the instruction starts at each byte of a queue word and line.
;
; The case is copied to TSEG:BASE+align, followed by a far JMP to ok_cont.
; The #GP handler records the count and the pushed CS:IP and resumes at
; gp_cont.  Port 0xE4 reports (case << 8) | (align << 4) | field for each
; mismatch: field 1 the #GP count, 2 the pushed IP, 3 the pushed CS,
; 4 BX, 5 AX, 6 the memory dword.
BITS 16
ORG 0
PCS    equ 0x1000               ; this program's CS
TSEG   equ 0x3000               ; where each case runs
DSEG   equ 0x2000               ; the memory operand's segment
BASE   equ 0x0100
MEMOFS equ 0x1234
MEMINI equ 0x01020304

K_BX   equ 0                    ; inc bx: BX 0 -> 1
K_ADDW equ 1                    ; add word [MEMOFS], 5678h
K_INCW equ 2                    ; inc word [si], si = MEMOFS
K_BTS  equ 3                    ; bts ax, 3: AX 0 -> 8
K_MOVD equ 4                    ; mov dword [eax+ebx*4+MEMOFS], 9ABCDEF0h

start:
    cli
    cld
    xor ax, ax
    mov ss, ax
    mov sp, 0x7000
    mov es, ax
    mov word [es:13*4], gp_handler
    mov word [es:13*4+2], PCS
    mov ax, cs
    mov ds, ax

    xor bp, bp                  ; failure count
    mov word [ccase], 0
case_loop:
    mov word [calign], 0
align_loop:
    ; Copy case bytes, then JMP PCS:ok_cont, to TSEG:BASE+align.
    mov ax, TSEG
    mov es, ax
    mov si, [ccase]
    imul si, si, CASE_SZ
    add si, cases
    mov di, BASE
    add di, [calign]
    mov [ctarget], di
    movzx cx, byte [si + 2]     ; length
    push si
    mov si, [si]                ; bytes
    rep movsb
    pop si
    mov si, jmp_back
    mov cx, jmp_back_len
    rep movsb

    ; Reset the observed state.
    mov byte [r_gp], 0
    mov word [r_ip], 0xeeee
    mov word [r_cs], 0xeeee
    mov ax, DSEG
    mov es, ax
    mov dword [es:MEMOFS], MEMINI

    ; Run it: DS = DSEG, EAX = EBX = 0, SI = MEMOFS.
    mov ax, DSEG
    mov ds, ax
    xor eax, eax
    xor ebx, ebx
    mov si, MEMOFS
    push word TSEG
    push word [cs:ctarget]
    retf

ok_cont:
gp_cont:
    mov [cs:r_bx], bx
    mov [cs:r_ax], ax
    mov ax, cs
    mov ds, ax
    mov ax, DSEG
    mov es, ax
    mov eax, [es:MEMOFS]
    mov [r_mem], eax

    ; ---- check ----
    mov si, [ccase]
    imul si, si, CASE_SZ
    add si, cases
    ; Expected #GP count, IP, CS.
    mov al, [si + 3]            ; expect_gp
    cmp al, [r_gp]
    je .c1
    mov dl, 1
    call report
.c1:
    cmp byte [si + 3], 0
    je .no_gp
    mov ax, [ctarget]
    cmp ax, [r_ip]
    je .c2
    mov dl, 2
    call report
.c2:
    cmp word [r_cs], TSEG
    je .c3
    mov dl, 3
    call report
.c3:
    ; A faulting instruction changes nothing.
    cmp word [r_bx], 0
    je .c4
    mov dl, 4
    call report
.c4:
    cmp word [r_ax], 0
    je .c5
    mov dl, 5
    call report
.c5:
    cmp dword [r_mem], MEMINI
    je .next
    mov dl, 6
    call report
    jmp .next
.no_gp:
    ; Executed: the body's one effect, nothing else.
    mov word [x_bx], 0
    mov word [x_ax], 0
    mov dword [x_mem], MEMINI
    mov al, [si + 4]
    cmp al, K_BX
    jne .k1
    mov word [x_bx], 1
.k1:
    cmp al, K_ADDW
    jne .k2
    mov dword [x_mem], MEMINI + 0x5678
.k2:
    cmp al, K_INCW
    jne .k3
    mov dword [x_mem], MEMINI + 1
.k3:
    cmp al, K_BTS
    jne .k4
    mov word [x_ax], 8
.k4:
    cmp al, K_MOVD
    jne .k5
    mov dword [x_mem], 0x9abcdef0
.k5:
    mov ax, [x_bx]
    cmp ax, [r_bx]
    je .e4
    mov dl, 4
    call report
.e4:
    mov ax, [x_ax]
    cmp ax, [r_ax]
    je .e5
    mov dl, 5
    call report
.e5:
    mov eax, [x_mem]
    cmp eax, [r_mem]
    je .next
    mov dl, 6
    call report

.next:
    inc word [calign]
    cmp word [calign], 16
    jb align_loop
    inc word [ccase]
    cmp word [ccase], NCASE
    jb case_loop

    test bp, bp
    jnz bad
    mov al, 1
    out 0xe0, al
    hlt
bad:
    mov al, 0xff
    out 0xe0, al
    hlt

report:                         ; dl = field; case and align from memory
    inc bp
    push eax
    mov ax, [ccase]
    shl ax, 8
    mov cx, [calign]
    shl cx, 4
    or ax, cx
    or al, dl
    movzx eax, ax
    out 0xe4, eax
    pop eax
    ret

gp_handler:
    push bp
    mov bp, sp
    push ax
    inc byte [cs:r_gp]
    mov ax, [bp + 2]            ; pushed IP
    mov [cs:r_ip], ax
    mov ax, [bp + 4]            ; pushed CS
    mov [cs:r_cs], ax
    mov word [bp + 2], gp_cont
    mov word [bp + 4], PCS
    pop ax
    pop bp
    iret

jmp_back:
    jmp PCS:ok_cont
jmp_back_len equ $ - jmp_back

; ---- cases ----
; Prefix runs: DS (3E) for memory bodies; for INC BX a mix of segment
; overrides and the size prefixes, none of which changes its effect.
%macro mixpfx 1
  %assign i 0
  %rep %1
    %if (i % 7) == 0
      db 0x26
    %elif (i % 7) == 1
      db 0x2e
    %elif (i % 7) == 2
      db 0x36
    %elif (i % 7) == 3
      db 0x3e
    %elif (i % 7) == 4
      db 0x64
    %elif (i % 7) == 5
      db 0x65
    %else
      db 0x67
    %endif
    %assign i i+1
  %endrep
%endmacro

; mkcase label, prefix count, mix(1)/DS(0), body kind
%macro mkcase 4
%1:
  %if %3
    mixpfx %2
  %else
    times %2 db 0x3e
  %endif
  %if %4 == K_BX
    db 0x43                                 ; inc bx
  %elif %4 == K_ADDW
    db 0x81, 0x06
    dw MEMOFS, 0x5678                       ; add word [MEMOFS], 5678h
  %elif %4 == K_INCW
    db 0xff, 0x04                           ; inc word [si]
  %elif %4 == K_BTS
    db 0x0f, 0xba, 0xe8, 0x03               ; bts ax, 3
  %else
    db 0x66, 0x67, 0xc7, 0x84, 0x98
    dd MEMOFS, 0x9abcdef0                   ; mov dword [eax+ebx*4+MEMOFS], 9ABCDEF0h
  %endif
%1_len equ $ - %1
%endmacro

mkcase c_bx14,   14, 1, K_BX               ; 15 bytes
mkcase c_bx15,   15, 1, K_BX               ; 16
mkcase c_bx16,   16, 1, K_BX               ; 17
mkcase c_bx17,   17, 1, K_BX               ; 18
mkcase c_bx30,   30, 1, K_BX               ; 31
mkcase c_add9,    9, 0, K_ADDW             ; 15
mkcase c_add10,  10, 0, K_ADDW             ; 16
mkcase c_add12,  12, 0, K_ADDW             ; 18
mkcase c_add14,  14, 0, K_ADDW             ; 20
mkcase c_inc13,  13, 0, K_INCW             ; 15
mkcase c_inc14,  14, 0, K_INCW             ; 16
mkcase c_inc15,  15, 0, K_INCW             ; 17
mkcase c_bts11,  11, 0, K_BTS              ; 15
mkcase c_bts12,  12, 0, K_BTS              ; 16
mkcase c_bts14,  14, 0, K_BTS              ; 18: 0F is byte 15
mkcase c_bts15,  15, 0, K_BTS              ; 19: 0F is byte 16
mkcase c_mov2,    2, 0, K_MOVD             ; 15
mkcase c_mov3,    3, 0, K_MOVD             ; 16
mkcase c_mov5,    5, 0, K_MOVD             ; 18

; ptr, length, expect_gp, kind
%macro centry 3
    dw %1
    db %1_len, %2, %3, 0
%endmacro
CASE_SZ equ 6
cases:
    centry c_bx14,  0, K_BX
    centry c_bx15,  1, K_BX
    centry c_bx16,  1, K_BX
    centry c_bx17,  1, K_BX
    centry c_bx30,  1, K_BX
    centry c_add9,  0, K_ADDW
    centry c_add10, 1, K_ADDW
    centry c_add12, 1, K_ADDW
    centry c_add14, 1, K_ADDW
    centry c_inc13, 0, K_INCW
    centry c_inc14, 1, K_INCW
    centry c_inc15, 1, K_INCW
    centry c_bts11, 0, K_BTS
    centry c_bts12, 1, K_BTS
    centry c_bts14, 1, K_BTS
    centry c_bts15, 1, K_BTS
    centry c_mov2,  0, K_MOVD
    centry c_mov3,  1, K_MOVD
    centry c_mov5,  1, K_MOVD
NCASE equ ($ - cases) / CASE_SZ

align 4
ccase:   dw 0
calign:  dw 0
ctarget: dw 0
r_gp:    db 0
         db 0
r_ip:    dw 0
r_cs:    dw 0
r_bx:    dw 0
r_ax:    dw 0
r_mem:   dd 0
x_bx:    dw 0
x_ax:    dw 0
x_mem:   dd 0
