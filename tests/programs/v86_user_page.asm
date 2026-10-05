; v86_user_page - a V86 guest runs at CPL 3, so an access to a supervisor-only
; page must #PF with the U/S bit set in the error code.  The core's
; `implicit_supervisor` term was `vm && CS[1:0] == 0`, which a V86 code segment
; like 1000h also matches, so V86 accesses were treated as supervisor and lost
; user page protection.  The V86 code/stack pages are user-accessible; the
; data page at 0x12000 is supervisor-only.
BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_STACK0  equ 0x18
SEL_TSS     equ 0x20

STACK0_TOP  equ 0x0FD8
VM86_SEG    equ 0x1000
VM86_SP     equ 0x2E00
SUP_LIN     equ 0x00012000          ; supervisor-only linear page

start:
    cli
    cld
    mov ax, cs
    mov ds, ax
    lgdt [gdt_desc]
    lidt [idt_desc]
    mov eax, cr0
    or  eax, 1
    mov cr0, eax
    jmp SEL_CODE0:pm16_entry

BITS 16
pm16_entry:
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax
    mov ax, SEL_STACK0
    mov ss, ax
    mov sp, STACK0_TOP
    mov ax, SEL_TSS
    ltr ax

    ; enable paging (tables built by the harness)
    mov eax, cr0
    or  eax, 0x80000000
    mov cr0, eax

    ; enter VM86 at CS=VM86_SEG (low bits 00)
    push dword VM86_SEG          ; GS
    push dword VM86_SEG          ; FS
    push dword 0                 ; DS
    push dword 0                 ; ES
    push dword 0                 ; SS
    push dword VM86_SP           ; ESP
    push dword 0x00020202        ; EFLAGS: VM=1, IF=1, IOPL=0
    push dword VM86_SEG          ; CS
    push dword vm86_entry        ; EIP
    iretd

BITS 16
vm86_entry:
    xor ax, ax
    mov ss, ax
    mov sp, VM86_SP
    mov ax, VM86_SEG             ; base 0x10000: covers 0x10000..0x1FFFF
    mov ds, ax
    mov es, ax
vm86_access:
    mov eax, [0x2000]            ; linear 0x12000: supervisor page -> #PF
    ; No fault means user page protection was lost.
    mov eax, 0x0001bad1
    jmp fail

; #PF handler (ring 0).  V86 frame with an error code:
;   [SP+00] error, [SP+04] EIP, [SP+08] CS, [SP+0C] EFLAGS ...
pf_handler:
    mov al, 1
    mov dx, STATUS_PORT
    out dx, al
    hlt

; Any #GP is unexpected here.
gp_handler:
    mov eax, 0x0001bad2
    jmp fail

fail_pf:
    mov eax, 0x0001bad3
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, 0xff
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

align 8
gdt:
    dq 0x0000000000000000

    ; Ring-0 USE16 code, base=0x10000, limit=0xffff.
    dw 0xffff
    dw 0x0000
    db 0x01
    db 10011011b
    db 00000000b
    db 0x00

    ; Ring-0 USE16 data, base=0x10000, limit=0xffff.
    dw 0xffff
    dw 0x0000
    db 0x01
    db 10010011b
    db 00000000b
    db 0x00

    ; Ring-0 USE16 stack, base=0x12000, limit=0x0fff.
    dw 0x0fff
    dw 0x2000
    db 0x01
    db 10010011b
    db 00000000b
    db 0x00

    ; 32-bit TSS, base=0x10000+tss, limit=0x67.
tss_desc:
    dw 0x0067
    dw tss
    db 0x01
    db 10001001b
    db 00000000b
    db 0x00
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

align 8
idt:
    times 13 dq 0

    ; 13: #GP (fail)
    dw gp_handler
    dw SEL_CODE0
    db 0
    db 10001110b
    dw 0

    ; 14: #PF
    dw pf_handler
    dw SEL_CODE0
    db 0
    db 10001110b
    dw 0

    times (256 - 15) dq 0
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x00010000

align 4
tss:
    dd 0                    ; +00 backlink
    dd STACK0_TOP           ; +04 ESP0
    dd SEL_STACK0           ; +08 SS0
    dd 0                    ; +0C ESP1
    dd 0                    ; +10 SS1
    dd 0                    ; +14 ESP2
    dd 0                    ; +18 SS2
    dd 0                    ; +1C CR3
    dd 0                    ; +20 EIP
    dd 0                    ; +24 EFLAGS
    dd 0                    ; +28 EAX
    dd 0                    ; +2C ECX
    dd 0                    ; +30 EDX
    dd 0                    ; +34 EBX
    dd 0                    ; +38 ESP
    dd 0                    ; +3C EBP
    dd 0                    ; +40 ESI
    dd 0                    ; +44 EDI
    dd 0                    ; +48 ES
    dd 0                    ; +4C CS
    dd 0                    ; +50 SS
    dd 0                    ; +54 DS
    dd 0                    ; +58 FS
    dd 0                    ; +5C GS
    dd 0                    ; +60 LDTR
    dw 0                    ; +64 debug trap
    dw 104                  ; +66 IOPB offset
