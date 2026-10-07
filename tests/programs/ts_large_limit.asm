; ts_large_limit - the TSS minimum-limit check (#TS below 67h) uses the
; whole effective limit: limit[19:16] and the granularity bit
;
; JMP to TSS A, a 386 TSS with byte-granular limit 10000h (limit[15:0] = 0),
; then from task A to TSS B, a 386 TSS with G=1 and raw limit 0 (effective
; FFFh).  Both limits are >= 67h, so both switches must succeed; a check of
; limit[15:0] alone, or one ignoring G, raises #TS (no IDT: shutdown/timeout).
; Fail codes (port E4): 0x21-0x25 task A state, 0x31 task B state.
; (derived from task_switch_jmp386)
; task_switch_jmp386.asm - far JMP to an available 386 TSS
;
; The LOAD_TASK microcode selects DES_TR with IN=2 before walking the new
; TSS.  Losing that segment selection reads offsets from linear address zero
; instead of TR.base + offset and corrupts the entire incoming task state.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

SEL_CODE    equ 0x2B             ; GDT code, RPL 3
SEL_DATA    equ 0x33             ; GDT data, RPL 3
SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_TSS_OLD equ 0x18
SEL_TSS_NEW equ 0x20
SEL_TSS_B   equ 0x38

STACK_OLD   equ 0x3000
STACK_NEW   equ 0x4000

start:
    cli
    lgdt [cs:gdt_desc]

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
    mov esp, STACK_OLD

    mov ax, SEL_TSS_OLD
    ltr ax

    ; A task-switch JMP ignores the pointer offset and loads EIP from tss_new.
    jmp SEL_TSS_NEW:0

    mov eax, 0x10
    jmp fail

task_entry:
    cmp eax, 0x11223344
    jne fail_21
    cmp ebx, 0x55667788
    jne fail_22
    cmp esp, STACK_NEW
    jne fail_23
    mov ax, cs
    cmp ax, SEL_CODE
    jne fail_24
    mov ax, ss
    cmp ax, SEL_DATA
    jne fail_25
    jmp SEL_TSS_B:0
    mov eax, 0x30
    jmp fail

task_b_entry:
    cmp eax, 0xB0B0B0B0
    jne fail_31
    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt

fail_31:
    mov eax, 0x31
    jmp fail
fail_21:
    mov eax, 0x21
    jmp fail
fail_22:
    mov eax, 0x22
    jmp fail
fail_23:
    mov eax, 0x23
    jmp fail
fail_24:
    mov eax, 0x24
    jmp fail
fail_25:
    mov eax, 0x25
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt

align 8
gdt:
    dq 0
    dq 0x00CF9B010000FFFF       ; 08: 32-bit code, base 10000h
    dq 0x00CF93010000FFFF       ; 10: 32-bit data, base 10000h

    ; 18: available 386 TSS, base 10000h + tss_old, limit 67h
    dw 0x0067
    dw tss_old
    db 0x01
    db 10001001b
    db 0
    db 0

    ; 20: available 386 TSS, base 10000h + tss_new, limit 67h
    dw 0x0000                   ; limit[15:0] = 0
    dw tss_new
    db 0x01
    db 10001001b
    db 0x01                     ; G=0, limit[19:16] = 1: limit 10000h
    db 0

    dq 0x00CFFB010000FFFF       ; 28: 32-bit ring-3 code, base 10000h
    dq 0x00CFF3010000FFFF       ; 30: 32-bit ring-3 data, base 10000h
    ; 38: TSS B, G=1, raw limit 0 (effective FFFh)
    dw 0x0000
    dw tss_b
    db 0x01
    db 11101001b                ; DPL3: task A runs at CPL3
    db 0x80
    db 0
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x10000

align 4
tss_old:
    times 26 dd 0

align 4
tss_new:
    dd 0                        ; 00 backlink
    dd 0                        ; 04 ESP0
    dd 0                        ; 08 SS0
    dd 0                        ; 0C ESP1
    dd 0                        ; 10 SS1
    dd 0                        ; 14 ESP2
    dd 0                        ; 18 SS2
    dd 0                        ; 1C CR3 (paging disabled)
    dd task_entry               ; 20 EIP
    dd 0x00003002               ; 24 EFLAGS (IOPL=3 for test status ports)
    dd 0x11223344               ; 28 EAX
    dd 0                        ; 2C ECX
    dd 0                        ; 30 EDX
    dd 0x55667788               ; 34 EBX
    dd STACK_NEW                ; 38 ESP
    dd 0                        ; 3C EBP
    dd 0                        ; 40 ESI
    dd 0                        ; 44 EDI
    dd SEL_DATA                 ; 48 ES
    dd SEL_CODE                 ; 4C CS
    dd SEL_DATA                 ; 50 SS
    dd SEL_DATA                 ; 54 DS
    dd 0                        ; 58 FS
    dd 0                        ; 5C GS
    dd 0                        ; 60 LDTR
    dw 0                        ; 64 debug trap
    dw 0x0068                   ; 66 I/O bitmap beyond TSS limit

align 4
tss_b:
    dd 0, 0, 0, 0, 0, 0, 0      ; 00-18
    dd 0                        ; 1C CR3
    dd task_b_entry             ; 20 EIP
    dd 0x00003002               ; 24 EFLAGS
    dd 0xB0B0B0B0               ; 28 EAX
    dd 0, 0, 0                  ; 2C-34
    dd STACK_NEW                ; 38 ESP
    dd 0, 0, 0                  ; 3C-44
    dd SEL_DATA                 ; 48 ES
    dd SEL_CODE                 ; 4C CS
    dd SEL_DATA                 ; 50 SS
    dd SEL_DATA                 ; 54 DS
    dd 0, 0, 0                  ; 58 FS, 5C GS, 60 LDTR
    dw 0, 0x0068
