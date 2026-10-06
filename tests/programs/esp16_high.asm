; esp16_high.asm - ESP[31:16] survives instructions on a 16-bit stack
;
; With a 16-bit SS (B=0) only SP moves; the high word of ESP stays. Win95
; runs ring-3 16-bit code this way (the high word is left over from its
; ring-0 stack), and z486 lost it in two places found by co-simulation:
;   1. POPAD wrote the popped ESP slot into ESP (the slot is discarded).
;   2. A fault in 16-bit code restored ESP (TMPeSP) zero-extended.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

SEL_CODE32 equ 0x08
SEL_DATA32 equ 0x10
SEL_STACK16 equ 0x18
SEL_CODE16 equ 0x20
HIGH_ESP equ 0xABCD8000

start:
    cli
    cld
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    mov eax, cr0
    or  eax, 1
    mov cr0, eax
    db 0x66, 0xEA
    dd pm32_entry
    dw SEL_CODE32

BITS 32
pm32_entry:
    mov ax, SEL_DATA32
    mov ds, ax
    mov es, ax

    ; ---- 1. POPAD on a 16-bit stack discards the ESP slot ----
    mov ax, SEL_STACK16
    mov ss, ax
    mov esp, HIGH_ESP
    pushad                              ; SP 8000 -> 7FE0, ESP slot at 7FEC
    mov dword [ss:0x7FEC], 0x00001234   ; a slot whose high word differs
    popad
    cmp esp, HIGH_ESP
    mov eax, 0x10
    jne fail

    ; ---- 2. A fault in 16-bit code keeps ESP's high word ----
    mov esp, HIGH_ESP
    jmp SEL_CODE16:code16 - 0           ; offset within the 16-bit segment (same base)

BITS 16
code16:
    ud2                                 ; #UD -> ud_handler (32-bit gate, ring 0)
    jmp $

BITS 32
ud_handler:
    ; Frame: EIP, CS, EFLAGS (dwords) below the faulting ESP.
    lea eax, [esp + 12]
    mov ebx, eax
    mov ax, SEL_DATA32
    mov ss, ax
    mov esp, 0x9000
    cmp ebx, HIGH_ESP
    mov eax, 0x20
    jne fail_ebx

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

fail_ebx:
    mov eax, ebx                        ; report the ESP seen
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

BITS 16
align 8
gdt:
    dq 0x0000000000000000
    dq 0x00CF9B010000FFFF               ; 0x08 code32, base 0x10000
    dq 0x00CF93010000FFFF               ; 0x10 data32, base 0x10000
    dq 0x000093010000FFFF               ; 0x18 stack16: B=0, limit FFFF
    dq 0x00009B010000FFFF               ; 0x20 code16, base 0x10000
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

align 8
idt:
    times 6 dq 0
    ; #UD: 32-bit interrupt gate
    dw ud_handler
    dw SEL_CODE32
    db 0
    db 10001110b
    dw 0
    times (256 - 6 - 1) dq 0
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x00010000
