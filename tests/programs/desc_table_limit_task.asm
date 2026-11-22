; desc_table_limit_task - descriptor-table limit faults of the privilege-return,
; task-gate and task-switch selector loads
;
; Companion of desc_table_limit (the plain segment and CS loads).  Each case
; names a selector whose index is past the GDT limit while a valid descriptor
; of the right kind sits behind the table, so a CPU that reads it without the
; limit test loads it.  Expected faults, i486 PRM (240486):
;   RET (outer level): "IF SS selector index is not within its descriptor
;     table limits THEN #GP(SS selector)";
;   IRET with NT=1: "Back link selector ... index must be within GDT limits
;     ELSE #TS(new TSS selector)";
;   JMP to a task gate: the TSS selector "must be within GDT limits ELSE
;     #GP(TSS selector)";
;   task switch, Table 7-1 (the new task's LDT, SS, CS, DS selectors): "index
;     within the descriptor table limit" else #TS(selector), raised in the
;     context of the new task.
; The error code is the selector with its RPL bits cleared; only its low word
; is checked.  The handlers keep their state in memory because a task switch
; loads the general registers from the new TSS.
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4 the case number,
; 0x8000 + n for an unexpected exception n, 0x9000 + case when the selector
; loaded (no fault).

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_CODE3   equ 0x18
SEL_DATA3   equ 0x20
SEL_TSS_M   equ 0x28            ; the starting task
SEL_TSS_DS  equ 0x30            ; new task: DS past the limit
SEL_TSS_LDT equ 0x38            ; new task: LDT selector past the limit
SEL_TSS_SS  equ 0x40            ; new task: SS past the limit
SEL_TSS_CS  equ 0x48            ; new task: CS past the limit
SEL_TGATE   equ 0x50            ; task gate DPL 0 -> SEL_X_TSS
; past the GDT limit (57h):
SEL_X_DATA3 equ 0x58            ; data DPL 3
SEL_X_DATA0 equ 0x60            ; data DPL 0
SEL_X_TSS   equ 0x68            ; available 386 TSS
SEL_X_LDT   equ 0x70            ; LDT
SEL_X_CODE  equ 0x78            ; code DPL 0
SEL_X_BUSY  equ 0x80            ; busy 386 TSS (a valid IRET back link)

R0_STACK    equ 0x9000
TASK_STACK  equ 0xA000

start:
    cli
    cld
    mov ax, cs
    mov ds, ax
    lgdt [gdt_desc]
    lidt [idt_desc]
    mov eax, cr0
    or  al, 1
    mov cr0, eax
    jmp dword SEL_CODE0:pm

BITS 32
pm:
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, R0_STACK
    mov ax, SEL_TSS_M
    ltr ax

; EXPECT vector, code, instruction: the instruction raises exception `vector`
; with error code `code`; execution resumes after it, segments reloaded.
%macro EXPECT 3+
    inc dword [case_no]
    mov dword [exp_vec], %1
    mov dword [exp_code], %2
    mov dword [resume], %%resume
    mov dword [got], 0
    mov [saved_esp], esp
    %3
    mov eax, [case_no]
    add eax, 0x9000
    jmp report
%%resume:
    cmp dword [got], 1
    jne fail
%endmacro

    ; outer-level RETF to CPL 3 whose SS is past the limit: #GP(SS)
    push dword SEL_X_DATA3 | 3
    push dword 0x8000
    push dword SEL_CODE3 | 3
    push dword escaped
    EXPECT 13, SEL_X_DATA3, retf
    ; IRETD with NT=1 and the back link past the limit: #TS(back link)
    mov dword [tss_m + 0], SEL_X_BUSY
    pushfd
    or dword [esp], 0x4000
    popfd
    EXPECT 10, SEL_X_BUSY, iretd
    ; JMP to a task gate whose TSS selector is past the limit: #GP(TSS)
    EXPECT 13, SEL_X_TSS, jmp SEL_TGATE:0
    ; task switches whose new selectors are past the limit: #TS(selector)
    EXPECT 10, SEL_X_LDT, jmp SEL_TSS_LDT:0
    EXPECT 10, SEL_X_DATA0, jmp SEL_TSS_SS:0
    EXPECT 10, SEL_X_CODE, jmp SEL_TSS_CS:0
    EXPECT 10, SEL_X_DATA3, jmp SEL_TSS_DS:0

    mov al, 0x01
    out STATUS_PORT, al
    hlt

escaped:
task_entry:
    mov eax, [cs:case_no]
    add eax, 0x9000
    jmp report
fail:
    mov eax, [case_no]
report:
    out DATA_PORT, eax
    mov al, 0xFF
    out STATUS_PORT, al
    hlt

; Exception handler body: vector in EAX.  Check vector and error code, then
; restore the flat ring-0 state and resume.
%macro HANDLER 1
handler_%1:
    mov eax, %1
    jmp common_handler
%endmacro
%assign v 0
%rep 14
HANDLER v
%assign v v+1
%endrep

common_handler:
    mov dx, SEL_DATA0
    mov ds, dx
    cmp eax, [exp_vec]
    jne .unexpected
    mov eax, [esp]
    cmp ax, [exp_code]
    jne fail
    mov dword [got], 1
    mov es, dx
    mov ss, dx
    mov esp, [saved_esp]
    pushfd
    and dword [esp], ~0x4000            ; clear NT
    popfd
    jmp [resume]
.unexpected:
    add eax, 0x8000
    jmp report

align 4
case_no:    dd 0
exp_vec:    dd 0
exp_code:   dd 0
resume:     dd 0
got:        dd 0
saved_esp:  dd 0

%macro TSSDESC 1
    dw 0x0067
    dw %1
    db 0x01, 0x89, 0x00, 0x00
%endmacro

align 8
gdt:
    dq 0
    dq 0x00CF9B010000FFFF           ; 08: code DPL 0, base 10000h
    dq 0x00CF93010000FFFF           ; 10: data DPL 0
    dq 0x00CFFB010000FFFF           ; 18: code DPL 3
    dq 0x00CFF3010000FFFF           ; 20: data DPL 3
    TSSDESC tss_m                   ; 28
    TSSDESC tss_ds                  ; 30
    TSSDESC tss_ldt                 ; 38
    TSSDESC tss_ss                  ; 40
    TSSDESC tss_cs                  ; 48
    dw 0, SEL_X_TSS                 ; 50: task gate DPL 0
    db 0x00, 0x85
    dw 0
gdt_end:
    ; past the limit: descriptors that would load
    dq 0x00CFF3010000FFFF           ; 58: data DPL 3
    dq 0x00CF93010000FFFF           ; 60: data DPL 0
    TSSDESC tss_x                   ; 68: available TSS
    dw 0x000F                       ; 70: LDT
    dw ldt
    db 0x01, 0x82, 0x00, 0x00
    dq 0x00CF9B010000FFFF           ; 78: code DPL 0
    dw 0x0067                       ; 80: busy TSS
    dw tss_x
    db 0x01, 0x8B, 0x00, 0x00

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x10000

align 8
ldt:
    dq 0
    dq 0

%macro GATE 1
    dw handler_%1
    dw SEL_CODE0
    db 0, 0x8E
    dw 0
%endmacro
align 8
idt:
%assign v 0
%rep 14
    GATE v
%assign v v+1
%endrep
idt_end:
idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x10000

; a 32-bit TSS: es, cs, ss, ds, ldt
%macro TSS 5
    dd 0, R0_STACK, SEL_DATA0, 0, 0, 0, 0, 0
    dd task_entry, 0x00000002
    dd 0, 0, 0, 0, TASK_STACK, 0, 0, 0
    dd %1, %2, %3, %4, SEL_DATA0, SEL_DATA0, %5
    dw 0, 104
%endmacro
align 4
tss_m:   TSS SEL_DATA0, SEL_CODE0, SEL_DATA0, SEL_DATA0, 0
align 4
tss_ds:  TSS SEL_DATA0, SEL_CODE0, SEL_DATA0, SEL_X_DATA3, 0
align 4
tss_ldt: TSS SEL_DATA0, SEL_CODE0, SEL_DATA0, SEL_DATA0, SEL_X_LDT
align 4
tss_ss:  TSS SEL_DATA0, SEL_CODE0, SEL_X_DATA0, SEL_DATA0, 0
align 4
tss_cs:  TSS SEL_DATA0, SEL_X_CODE, SEL_DATA0, SEL_DATA0, 0
align 4
tss_x:   TSS SEL_DATA0, SEL_CODE0, SEL_DATA0, SEL_DATA0, 0
