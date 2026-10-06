; debug_task - debug state across a task switch
;
; A task switch clears DR7's local enables (L0-L3) and keeps the global ones.
; A new TSS with its T bit set raises #DB (DR6.BT) before the new task's first
; instruction executes.
BITS 16
org 0
STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_TSS_OLD equ 0x18
SEL_TSS_NEW equ 0x20

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
    mov esp, 0x3000
    mov ax, SEL_TSS_OLD
    ltr ax
    xor ebp, ebp
    xor eax, eax
    mov dr6, eax
    mov eax, 0x0000000d               ; L0, G1, L2 enabled; DR0-2 match nothing
    mov dr7, eax
    jmp SEL_TSS_NEW:0
    mov eax, 0x10
    jmp fail

task_entry:
    cmp ebp, 1                        ; the #DB came first
    jne fail_1
    mov eax, [db_dr6]
    test eax, 0x8000                  ; BT
    jz fail_2
    mov eax, [db_eip]
    cmp eax, task_entry
    jne fail_3
    mov eax, dr7
    and eax, 0xff
    cmp eax, 0x08                     ; L0/L2 cleared, G1 kept
    jne fail_4
    mov al, 1
    out STATUS_PORT, al
    hlt

db_handler:
    push eax
    mov eax, dr6
    mov [db_dr6], eax
    mov eax, [esp + 4]
    mov [db_eip], eax
    xor eax, eax
    mov dr6, eax
    inc ebp
    pop eax
    iretd

fail_1:
    mov eax, 1
    jmp fail
fail_2:
    mov eax, 2
    jmp fail
fail_3:
    mov eax, 3
    jmp fail
fail_4:
    mov eax, 4
fail:
    out DATA_PORT, eax
    mov al, 0xff
    out STATUS_PORT, al
    hlt

align 4
db_dr6: dd 0
db_eip: dd 0

align 8
gdt:
    dq 0
    dq 0x00CF9B010000FFFF       ; 08: 32-bit code, base 10000h
    dq 0x00CF93010000FFFF       ; 10: 32-bit data, base 10000h
    dw 0x0067                   ; 18: available 386 TSS (old)
    dw tss_old
    db 0x01
    db 10001001b
    db 0
    db 0
    dw 0x0067                   ; 20: available 386 TSS (new)
    dw tss_new
    db 0x01
    db 10001001b
    db 0
    db 0
gdt_end:
gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x10000

align 8
idt:
    dq 0
    dw db_handler, SEL_CODE0
    db 0, 0x8e
    dw 0
idt_end:
idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x10000

align 4
tss_old:
    times 26 dd 0
align 4
tss_new:
    dd 0, 0, 0, 0, 0, 0, 0
    dd 0                        ; 1C CR3 (paging disabled)
    dd task_entry               ; 20 EIP
    dd 0x00000002               ; 24 EFLAGS
    dd 0, 0, 0, 0               ; EAX ECX EDX EBX
    dd 0x4000                   ; 38 ESP
    dd 0                        ; 3C EBP
    dd 0, 0                     ; ESI EDI
    dd SEL_DATA0                ; 48 ES
    dd SEL_CODE0                ; 4C CS
    dd SEL_DATA0                ; 50 SS
    dd SEL_DATA0                ; 54 DS
    dd 0, 0                     ; FS GS
    dd 0                        ; 60 LDTR
    dw 1                        ; 64 T: debug trap on entry
    dw 0x0068                   ; 66 I/O bitmap beyond TSS limit
