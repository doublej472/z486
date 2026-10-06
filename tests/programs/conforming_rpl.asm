; conforming_rpl.asm - far CALL/JMP to conforming code: DPL <= CPL, RPL ignored
;
; i486 PRM (6.3.2): a direct far transfer to a conforming code segment
; requires DPL <= CPL; the selector's RPL is not checked, and CPL is kept.
;
;   A) CPL 0: CALL to conforming DPL 3 (RPL 3) must #GP(selector).
;   B) CPL 0: JMP to conforming DPL 3 (RPL 3) must #GP(selector).
;   C) CPL 3: CALL to conforming DPL 3 with RPL 0 runs at CPL 3.
;   D) CPL 3: CALL to conforming DPL 0 with RPL 0 and RPL 3 run at CPL 3.
;   E) CPL 3: JMP to conforming DPL 3 with RPL 0, which jumps back.
; The test ends with a HLT at CPL 3; its #GP passes once all ran.
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4 code.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_CONF0   equ 0x18    ; conforming, DPL 0
SEL_DATA3   equ 0x20
SEL_TSS     equ 0x28
SEL_CODE3   equ 0x30    ; non-conforming, DPL 3
SEL_CONF3   equ 0x38    ; conforming, DPL 3

SEL_DATA3_RPL3 equ (SEL_DATA3 | 3)
SEL_CODE3_RPL3 equ (SEL_CODE3 | 3)

STACK0_TOP  equ 0x3000
STACK3_TOP  equ 0x4000

start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]

    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp dword SEL_CODE0:pm_entry

BITS 32
pm_entry:
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, STACK0_TOP
    mov ax, SEL_TSS
    ltr ax

    mov dword [stage], 1
site_a:
    call SEL_CONF3|3:conf_target    ; A: #GP, the handler resumes at after_a
after_a:
    cmp dword [stage], 2
    jne fail_stage
site_b:
    jmp SEL_CONF3|3:conf_target     ; B: #GP, the handler resumes at after_b
after_b:
    cmp dword [stage], 3
    jne fail_stage

    ; to ring 3
    push dword SEL_DATA3_RPL3
    push dword STACK3_TOP
    push dword 0x00000002
    push dword SEL_CODE3_RPL3
    push dword ring3_entry
    iretd

ring3_entry:
    mov ax, SEL_DATA3_RPL3
    mov ds, ax
    mov dword [stage], 4
    mov dword [seen_cs], 0
    call SEL_CONF3:conf_target      ; C: RPL 0, DPL 3
    cmp word [seen_cs], SEL_CONF3|3
    jne r3_fail

    mov dword [stage], 5
    mov dword [seen_cs], 0
    call SEL_CONF0:conf_target      ; D: RPL 0, DPL 0
    cmp word [seen_cs], SEL_CONF0|3
    jne r3_fail
    mov dword [seen_cs], 0
    call SEL_CONF0|3:conf_target    ; D: RPL 3, DPL 0
    cmp word [seen_cs], SEL_CONF0|3
    jne r3_fail

    mov dword [stage], 6
    mov dword [seen_cs], 0
    jmp SEL_CONF3:conf_jmp_target   ; E: RPL 0, DPL 3
back_e:
    cmp word [seen_cs], SEL_CONF3|3
    jne r3_fail

    mov dword [stage], 7
done_site:
    hlt
    jmp $

r3_fail:
    mov dword [stage], 0x31
    hlt

conf_target:
    mov ax, cs
    mov [seen_cs], ax
    retf

conf_jmp_target:
    mov ax, cs
    mov [seen_cs], ax
    jmp SEL_CODE3_RPL3:back_e

fail_stage:
    mov eax, [stage]
    shl eax, 8
    mov al, 0x40
    jmp fail

;------------------------------------------------------------------
; Ring 0 #GP handler (DPL0 386 interrupt gate)
;------------------------------------------------------------------
isr_gp:
    ; frame: [esp]=err, +4 EIP, +8 CS, +12 EFLAGS (+16 ESP, +20 SS from ring 3)
    push eax
    push ds
    mov ax, SEL_DATA0
    mov ds, ax
    mov eax, [stage]
    cmp eax, 1
    je .stage_a
    cmp eax, 2
    je .stage_b
    cmp eax, 7
    je .done
    jmp .bad
.stage_a:
    cmp dword [esp+12], site_a
    jne .bad
    cmp dword [esp+8], SEL_CONF3
    jne .bad
    mov dword [esp+12], after_a
    mov dword [stage], 2
    jmp .resume
.stage_b:
    cmp dword [esp+12], site_b
    jne .bad
    cmp dword [esp+8], SEL_CONF3
    jne .bad
    mov dword [esp+12], after_b
    mov dword [stage], 3
.resume:
    pop ds
    pop eax
    add esp, 4
    iretd
.done:
    cmp dword [esp+12], done_site
    jne .bad
    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt
.bad:
    ; code: stage | EIP << 16, then the error code
    mov eax, [esp+12]
    shl eax, 16
    mov al, [stage]
    mov dx, DATA_PORT
    out dx, eax
    mov eax, [esp+8]
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt

fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt

;==================================================================
; Data
;==================================================================
align 4
stage:
    dd 0
seen_cs:
    dd 0

align 8
gdt:
    dq 0x0000000000000000
    ; 0x08: ring0 32-bit code, base 0x10000
    dq 0x00CF9B010000FFFF
    ; 0x10: ring0 32-bit data, base 0x10000
    dq 0x00CF93010000FFFF
    ; 0x18: conforming DPL 0 32-bit code, base 0x10000
    dq 0x00CF9F010000FFFF
    ; 0x20: ring3 data, base 0x10000
    dq 0x00CFF3010000FFFF
    ; 0x28: available 386 TSS (type 9), base = tss386+0x10000, limit 0x67
    dw 0x0067
    dw tss386
    db 0x01
    db 0x89
    db 0x00
    db 0x00
    ; 0x30: ring3 32-bit code, base 0x10000
    dq 0x00CFFB010000FFFF
    ; 0x38: conforming DPL 3 32-bit code, base 0x10000
    dq 0x00CFFF010000FFFF
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

align 8
idt:
    times 0x0D dq 0
    dw isr_gp
    dw SEL_CODE0
    db 0
    db 10001110b
    dw 0
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x00010000

align 4
tss386:
    dd 0
    dd STACK0_TOP               ; +4  ESP0
    dd SEL_DATA0                ; +8  SS0
    times 22 dd 0
    dw 0
    dw 104                      ; no I/O bitmap
tss386_end:
