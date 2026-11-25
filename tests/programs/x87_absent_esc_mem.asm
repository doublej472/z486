; x87_absent_esc_mem.asm - with no FPU (ENABLE_X87=0, or +z486_x87_off), an
; ESC instruction with a memory operand and CR0.EM=0, TS=0 is a no-op: no
; coprocessor bus cycle and no access to its operand.
;
; A 486SX has no defined behaviour here.  Intel486 Microprocessors and Related
; Products (1995, 241731-002) p. 2-53, CR0 EM bit: "For Intel486 SX and
; IntelSX2 processors, the EM bit should be set to one. [...] If EM bit is 0
; for the Intel486 SX and IntelSX2 processors, the system will hang."  (The
; Embedded Intel486 Processor Family Developer's Manual, 273021-001, p. 4-15:
; "the system hangs".)  z486 chooses the no-op that the control and register
; ESC forms already take (x87_off_sx), as 86Box's 486SX does.  An i486 never
; runs the 386/387 I/O protocol (800000F8h/800000FCh); the PC-9821 core's I/O
; fabric ignores A31, so such a cycle would reach ports F8h/FCh.  The bench
; counts I/O writes to ports F8h-FFh (address bits 15:2), read back at D8h.
;
; The defined cases are checked too (databook Table 4-6; i486 PRM 9.9.7):
; EM=1 -> #NM for every ESC form; EM=0, TS=1 -> #NM; neither makes a
; coprocessor cycle.
;
; Phases (each runs every form once, operand [si], 2-byte instructions):
;   1: EM=0 TS=0, SI=FFFEh: every operand crosses the DS limit, so any access
;      to it would raise #GP (vector 13); none may fault.
;   2: EM=0 TS=0, SI=0100h; then no byte around either operand (FF00h-01FFh)
;      may have changed.
;   3: EM=1: one #NM per form.
;   4: EM=0 TS=1 MP=0: one #NM per form.
; After each phase: no coprocessor I/O write (port D8h reads 0).
; Fail (port E4): (phase << 16) | (check << 8) | form, then 0FFh on E0.
;   check 1: an exception other than an expected #NM (vector in bits 31:24)
;   check 2: a coprocessor I/O write (count in bits 31:24)
;   check 3: a planted byte changed (offset in bits 31:24)
;   check 4: #NM count wrong (count in bits 31:24)

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
CPIO_PORT   equ 0xD8
DSEG        equ 0x2000
PLANT       equ 0xA5
NFORMS      equ 25

start:
    jmp main
    times 0x80-($-$$) db 0

main:
    cli
    cld
    mov ax, cs
    mov ss, ax
    mov sp, 0x0FF0
    xor ax, ax
    mov ds, ax
    mov word [6*4], exc_06
    mov [6*4+2], cs
    mov word [7*4], exc_07
    mov [7*4+2], cs
    mov word [12*4], exc_0c
    mov [12*4+2], cs
    mov word [13*4], exc_0d
    mov [13*4+2], cs
    mov word [8*4], exc_08
    mov [8*4+2], cs

    ; plant FF00h-FFFFh and 0000h-01FFh of the data segment
    mov ax, DSEG
    mov es, ax
    mov ax, (PLANT << 8) | PLANT
    mov di, 0xFF00
    mov cx, 0x80
    rep stosw
    xor di, di
    mov cx, 0x100
    rep stosw
    mov ax, DSEG
    mov ds, ax

    in eax, CPIO_PORT
    mov [cs:cpio_base], eax

    ; phase 1
    mov byte [cs:phase], 1
    mov byte [cs:nm_ok], 0
    mov si, 0xFFFE
    call forms
    call check_cpio

    ; phase 2
    mov byte [cs:phase], 2
    mov si, 0x0100
    call forms
    call check_cpio
    mov bx, 0xFF00              ; FF00h-FFFFh and 0000h-01FFh: phase 1's
.scan:                          ; operands at FFFEh and phase 2's at 0100h
    cmp byte [bx], PLANT
    jne .changed
    inc bx
    cmp bx, 0x0200
    jne .scan
    jmp phase3
.changed:
    movzx eax, bx
    shl eax, 24
    or eax, 0x00020300
    jmp fail

phase3:
    mov byte [cs:phase], 3
    mov byte [cs:nm_ok], 1
    mov word [cs:nm_count], 0
    mov eax, cr0
    or al, 4                    ; EM=1
    mov cr0, eax
    call forms
    call check_nm
    call check_cpio

    mov byte [cs:phase], 4
    mov word [cs:nm_count], 0
    mov eax, cr0
    and al, 0xF1                ; EM=0, MP=0, TS=0
    or al, 8                    ; TS=1
    mov cr0, eax
    call forms
    call check_nm
    call check_cpio
    clts

    mov al, 0x01
    out STATUS_PORT, al
    hlt

; Every ESC form with a memory operand, each `ESC modrm` ([si], 2 bytes).
; form_id counts them for the failure code.
%macro FORM 1
    inc byte [cs:form_id]
    %1
%endmacro
forms:
    mov byte [cs:form_id], 0
    FORM {fld dword [si]}           ; D9 /0
    FORM {fld qword [si]}           ; DD /0
    FORM {fld tword [si]}           ; DB /5
    FORM {fild word [si]}           ; DF /0
    FORM {fild dword [si]}          ; DB /0
    FORM {fild qword [si]}          ; DF /5
    FORM {fbld [si]}                ; DF /4
    FORM {fadd dword [si]}          ; D8 /0
    FORM {fmul qword [si]}          ; DC /1
    FORM {fiadd word [si]}          ; DE /0
    FORM {fidiv dword [si]}         ; DA /6
    FORM {fcom dword [si]}          ; D8 /2
    FORM {fst dword [si]}           ; D9 /2
    FORM {fstp qword [si]}          ; DD /3
    FORM {fstp tword [si]}          ; DB /7
    FORM {fist word [si]}           ; DF /2
    FORM {fistp qword [si]}         ; DF /7
    FORM {fbstp [si]}               ; DF /6
    FORM {fldenv [si]}              ; D9 /4
    FORM {fnstenv [si]}             ; D9 /6
    FORM {frstor [si]}              ; DD /4
    FORM {fnsave [si]}              ; DD /6
    FORM {fldcw [si]}               ; D9 /5
    FORM {fnstcw [si]}              ; D9 /7
    FORM {fnstsw [si]}              ; DD /7
    ret

check_cpio:
    in eax, CPIO_PORT
    sub eax, [cs:cpio_base]
    jz .ok
    shl eax, 24
    or eax, 0x00000200
    mov byte [cs:form_id], 0
    jmp fail_phase
.ok:
    ret

check_nm:
    mov ax, [cs:nm_count]
    cmp ax, NFORMS
    je .ok
    movzx eax, ax
    shl eax, 24
    or eax, 0x00000400
    mov byte [cs:form_id], 0
    jmp fail_phase
.ok:
    ret

exc_07:
    cmp byte [cs:nm_ok], 1
    jne .bad
    inc word [cs:nm_count]
    push bp
    mov bp, sp
    add word [bp+2], 2          ; skip the 2-byte ESC instruction
    pop bp
    iret
.bad:
    mov eax, 0x07000100
    jmp fail_phase
exc_06:
    mov eax, 0x06000100
    jmp fail_phase
exc_08:
    mov eax, 0x08000100
    jmp fail_phase
exc_0c:
    mov eax, 0x0C000100
    jmp fail_phase
exc_0d:
    mov eax, 0x0D000100
fail_phase:
    movzx ebx, byte [cs:phase]
    shl ebx, 16
    or eax, ebx
    movzx ebx, byte [cs:form_id]
    or eax, ebx
fail:
    out DATA_PORT, eax
    mov al, 0xFF
    out STATUS_PORT, al
    hlt

align 4
cpio_base: dd 0
nm_count:  dw 0
phase:     db 0
form_id:   db 0
nm_ok:     db 0
