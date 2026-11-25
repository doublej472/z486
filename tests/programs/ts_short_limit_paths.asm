; ts_short_limit_paths - every task-switch source raises #TS(TSS selector) for
; a new TSS whose limit is below the minimum (67h for a 386 TSS, 2Bh for a 286
; TSS), in the old task's context
;
; Intel486 PRM 7.5 lists the four sources of a task switch: JMP or CALL to a
; TSS descriptor, JMP or CALL to a task gate, an interrupt or exception through
; a task gate in the IDT, and IRET with NT set.  Table 7-1, step 4: "TSS
; segment limit greater than or equal to 108" -> TS, error code "New Task's
; TSS"; 9.9.10 Table 9-5: "TSS segment limit less than 67H" -> invalid TSS,
; error code index = the TSS segment; until the new TSS is verified "the
; exception occurs in the context of the original task".  ts_short_limit
; covers JMP to a TSS, JMP through a task gate and CALL to a TSS; this
; program covers the other sources:
;   1 CALL through a task gate (386 TSS, limit 20h)
;   2 INT n through an IDT task gate (386 TSS, limit 20h)
;   3 IRET with NT = 1, back link to a busy 386 TSS with limit 20h
;   4 JMP through a task gate to a 286 TSS with limit 2Ah
;   5 INT n through an IDT task gate to that 286 TSS
; Each site checks the vector (10), the error code (the TSS selector: INT n
; is not an external event, EXT = 0) and the pushed EIP (the instruction).
; Afterwards TR is unchanged and neither short TSS became busy, and the old
; task's TR descriptor cache is intact: its TSS descriptor has G = 1 and raw
; limit 0 (FFFh), the short TSSs G = 0, so a cache that took the short TSS's
; G / limit[19:16] / base[31:24] (the first descriptor-cache word of the
; switch) would fault the final JMP to a valid TSS when it saves the old
; task.  That JMP must save the old task into tss_a (fail 0x18: its EIP
; field) and run the new task (fail 0x19: TR).
; Fail code (port E4): err[7:0]<<24 | vector<<16 | site*16 + 1 vector,
; 2 error code, 4 EIP; F0000000h | (1 << site): pushed RF was wrong.
; (derived from ts_short_limit)
BITS 32
ORG 0
RF equ 0x10000
SEL_CODE  equ 0x08
SEL_DATA  equ 0x10
SEL_STACK equ 0x18
SEL_RO    equ 0x20
SEL_NP    equ 0x28
SEL_TSS   equ 0x40
SEL_TSSSH equ 0x48
SEL_GATE  equ 0x30
SEL_TSS286 equ 0x38
SEL_TSSBSY equ 0x50
SEL_GATE286 equ 0x58
SEL_TSSOK  equ 0x60

align 8
gdt:
    dq 0
    dq 0x00CF9B010000FFFF       ; 08 code, base 10000h
    dq 0x00CF93010000FFFF       ; 10 data, base 10000h
    dq 0x004093010000FFFF       ; 18 stack, base 10000h, byte limit FFFFh, B=1
    dq 0x00CF91010000FFFF       ; 20 read-only data
    dq 0x00CF13010000FFFF       ; 28 data, not present
    dw 0, SEL_TSSSH, 0x8500, 0  ; 30 task gate -> 48
    dw 0x002a, tss_b            ; 38 286 TSS, limit 2Ah (< 2Bh)
    db 0x01, 0x81, 0x00, 0x00
tss_desc:                       ; 40 available 386 TSS, G = 1, raw limit 0 (FFFh)
    dw 0x0000
    dw tss_a
    db 0x01, 0x89, 0x80, 0x00
tss_short:                      ; 48 386 TSS, limit 20h (< 67h)
    dw 0x0020
    dw tss_b
    db 0x01, 0x89, 0x00, 0x00
tss_busy_short:                 ; 50 busy 386 TSS, limit 20h (< 67h)
    dw 0x0020
    dw tss_c
    db 0x01, 0x8B, 0x00, 0x00
    dw 0, SEL_TSS286, 0x8500, 0 ; 58 task gate -> 38
    dw 0x0067                   ; 60 available 386 TSS (the final switch)
    dw tss_d
    db 0x01, 0x89, 0x00, 0x00
gdt_end:
gdtr: dw gdt_end-gdt-1
      dd 0x10000+gdt

align 8
idt:
%assign v 0
%rep 34
    dw stub_ %+ v, SEL_CODE
    db 0, 0x8e
    dw 0
%assign v v+1
%endrep
    dw 0, SEL_TSSSH, 0x8500, 0  ; 22h task gate -> 48
    dw 0, SEL_TSS286, 0x8500, 0 ; 23h task gate -> 38
idt_end:
idtr: dw idt_end-idt-1
      dd 0x10000+idt

%assign v 0
%rep 34
stub_ %+ v:
    push dword v
    jmp hcommon
%assign v v+1
%endrep

; vectors with an error code: 8, 10-14, 17
errmask: dd (1<<8)|(1<<10)|(1<<11)|(1<<12)|(1<<13)|(1<<14)|(1<<17)
last_vec: dd 0
last_err: dd 0
last_eip: dd 0
last_efl: dd 0
rf_bad: dd 0
bnds: dd 0, 10

hcommon:
    push eax
    push ebx
    mov eax, [ss:esp+8]
    mov [ss:last_vec], eax
    bt [ss:errmask], eax
    jc .err
    mov dword [ss:last_err], -1
    mov eax, [ss:esp+12]
    mov [ss:last_eip], eax
    mov [ss:esp+12], esi
    mov eax, [ss:esp+20]
    mov [ss:last_efl], eax
    pop ebx
    pop eax
    add esp, 4
    iretd
.err:
    mov eax, [ss:esp+12]
    mov [ss:last_err], eax
    mov eax, [ss:esp+16]
    mov [ss:last_eip], eax
    mov [ss:esp+16], esi
    mov eax, [ss:esp+24]
    mov [ss:last_efl], eax
    pop ebx
    pop eax
    add esp, 8
    iretd

fail:
    ; E4 = last_err[7:0] << 24 | last_vec[7:0] << 16 | code
    mov ebx, [ss:last_vec]
    shl ebx, 16
    or eax, ebx
    mov ebx, [ss:last_err]
    shl ebx, 24
    or eax, ebx
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt

; SITE n, vector, errcode (-1 none), expect_rf, insn...
%macro SITE 5+
    mov esi, %%resume
    mov dword [ss:last_vec], 0xff
    nop
%%site:
    %5
%%resume:
    mov eax, %1*16+1
    cmp dword [ss:last_vec], %2
    jne fail
    mov eax, %1*16+2
    cmp dword [ss:last_err], %3
    jne fail
    mov eax, %1*16+4
%if %4
    cmp dword [ss:last_eip], %%site      ; fault: EIP names the instruction
%else
    cmp dword [ss:last_eip], %%resume    ; trap: EIP names the next one
%endif
    jne fail
    mov eax, [ss:last_efl]
    and eax, RF
    mov ebx, %4*RF
    cmp eax, ebx
    je %%rf_ok
    or dword [ss:rf_bad], 1 << %1    ; RF mismatches are collected, not fatal
%%rf_ok:
%endmacro

times 0x400-($-$$) db 0x90
start:
    cli
    lgdt [cs:gdtr]
    lidt [cs:idtr]
    mov ax, SEL_DATA
    mov ds, ax
    mov es, ax
    mov ax, SEL_STACK
    mov ss, ax
    mov esp, 0xF000
    jmp SEL_CODE:.cs
.cs:
    mov ax, SEL_TSS
    ltr ax
    push dword 0x2
    popfd

    SITE 1, 10, SEL_TSSSH, 1, call SEL_GATE:0
    SITE 2, 10, SEL_TSSSH, 1, int 0x22
    mov dword [tss_a], SEL_TSSBSY      ; back link
    push dword 0x4002                  ; NT = 1
    popfd
    SITE 3, 10, SEL_TSSBSY, 1, iretd
    push dword 0x2
    popfd
    SITE 4, 10, SEL_TSS286, 1, jmp SEL_GATE286:0
    SITE 5, 10, SEL_TSS286, 1, int 0x23
    str ax
    movzx eax, ax
    or eax, 0x1600
    cmp ax, 0x1600 | SEL_TSS
    jne fail
    movzx eax, byte [tss_short+5]
    or eax, 0x1700
    cmp eax, 0x1789
    jne fail
    movzx eax, byte [gdt+0x38+5]
    or eax, 0x1700
    cmp eax, 0x1781
    jne fail
    movzx eax, byte [tss_busy_short+5]
    or eax, 0x1700
    cmp eax, 0x178B
    jne fail
    mov eax, [ss:rf_bad]
    test eax, eax
    jz final
    or eax, 0xF0000000           ; F0000000 | bitmask of sites whose RF was wrong
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
final:
    jmp SEL_TSSOK:0
after_final:
    mov eax, 0x19
    jmp fail
task_ok:                        ; the new task (TR = SEL_TSSOK)
    mov eax, 0x18
    cmp dword [tss_a + 0x20], after_final
    jne fail
    mov eax, 0x19
    str bx
    cmp bx, SEL_TSSOK
    jne fail
    mov al, 1
    out 0xe0, al
    hlt

align 4
tss_a: times 26 dd 0
tss_b: times 26 dd 0
tss_c: times 26 dd 0
tss_d:                          ; the final task's state
    dd 0, 0, 0, 0, 0, 0, 0      ; link, ESP0-SS2
    dd 0                        ; CR3
    dd task_ok                  ; EIP
    dd 0x2                      ; EFLAGS
    dd 0, 0, 0, 0               ; EAX, ECX, EDX, EBX
    dd 0xE000, 0, 0, 0          ; ESP, EBP, ESI, EDI
    dd SEL_DATA, SEL_CODE, SEL_STACK, SEL_DATA, SEL_DATA, SEL_DATA ; ES CS SS DS FS GS
    dd 0                        ; LDT
    dd 0                        ; T, I/O map base
    dd 0
