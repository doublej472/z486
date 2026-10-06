; lar_ldt.asm - LAR on an LDT selector, 32-bit operand size
;
; Links 386 Pro's DOS extender (Phar Lap 386|DOS-Extender 4.1) checks whether
; its stack segment is 32-bit with MOV EAX,[sel]; LAR EAX,EAX; TEST EAX,
; 400000h (D/B), the selector an LDT data segment (TI=1, RPL 3, DPL 3).
; LAR must set ZF and load the descriptor's high dword masked by 00FxFF00
; (i486 PRM), so D/B is visible. Cases: selector loaded from memory just
; before (as Links), from an immediate, LAR from memory, and LAR to another
; register, Links' exact sequence (POP to memory, load back, LAR), and a
; page-granular LDT (G=1, limit field 0) as Phar Lap's, which z486 took as
; a 0-byte limit, so every LDT selector failed LAR.
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
SEL_LDT     equ 0x18
SEL_LDT_G   equ 0x20
LSEL_DATA3  equ 0x17    ; LDT 2, TI=1, RPL 3

AR_MASK     equ 0x00F0FF00          ; the limit nibble (x) is undefined
AR_EXPECT   equ 0x00C0F300          ; G, D/B, present, DPL 3, data RW

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
    mov esp, 0x3000
    mov ax, SEL_LDT
    lldt ax

    ; A: selector loaded from memory, LAR EAX,EAX (Links)
    mov ebx, 0x10
    mov eax, [selvar]
    lar eax, eax
    jnz fail
    test eax, 0x00400000
    jz fail
    and eax, AR_MASK
    cmp eax, AR_EXPECT
    jne fail

    ; B: selector from an immediate
    mov ebx, 0x20
    mov eax, LSEL_DATA3
    lar eax, eax
    jnz fail
    and eax, AR_MASK
    cmp eax, AR_EXPECT
    jne fail

    ; C: LAR from memory
    mov ebx, 0x30
    lar eax, [selvar]
    jnz fail
    and eax, AR_MASK
    cmp eax, AR_EXPECT
    jne fail

    ; D: LAR to another register
    mov ebx, 0x40
    mov ecx, [selvar]
    lar edx, ecx
    jnz fail
    and edx, AR_MASK
    cmp edx, AR_EXPECT
    jne fail

    ; E: Links' exact sequence: POP the selector to memory, load it back
    ;    (16-bit addressing in 32-bit code), LAR, test D/B
    mov ebx, 0x50
    mov dword [selvar2], 0
    push dword LSEL_DATA3
    a16 pop dword [selvar2]
    a16 mov eax, [selvar2]
    lar eax, eax
    test eax, 0x00400000
    jz fail
    and eax, AR_MASK
    cmp eax, AR_EXPECT
    jne fail

    ; F: a page-granular LDT (limit field 0, G=1: 4 KB, as Phar Lap's).
    ;    The selector is inside it; LAR must not treat it as past the limit.
    mov ebx, 0x60
    mov ax, SEL_LDT_G
    lldt ax
    mov eax, LSEL_DATA3
    lar eax, eax
    jnz fail
    and eax, AR_MASK
    cmp eax, AR_EXPECT
    jne fail
    ; and one really past a byte-granular limit fails with ZF clear
    mov ebx, 0x61
    mov ax, SEL_LDT
    lldt ax
    mov eax, 0x1F                   ; LDT 3: past ldt_end
    lar eax, eax
    jz fail

    mov al, STATUS_PASS
    out STATUS_PORT, al
    hlt

fail:
    mov eax, ebx
    out DATA_PORT, eax
    mov al, STATUS_FAIL
    out STATUS_PORT, al
    hlt

align 4
selvar:
    dd LSEL_DATA3
selvar2:
    dd 0

align 8
gdt:
    dq 0x0000000000000000
    ; 0x08: ring0 32-bit code, base 0x10000
    dq 0x00CF9B010000FFFF
    ; 0x10: ring0 32-bit data, base 0x10000
    dq 0x00CF93010000FFFF
    ; 0x18: LDT, base = ldt+0x10000
    dw ldt_end - ldt - 1
    dw ldt
    db 0x01
    db 0x82
    db 0x00
    db 0x00
    ; 0x20: the same LDT, limit field 0 with G=1 (4 KB)
    dw 0x0000
    dw ldt
    db 0x01
    db 0x82
    db 0x80
    db 0x00
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

align 8
ldt:
    dq 0
    dq 0
    ; 0x14: ring-3 32-bit data, G=1, B=1, base 0x10000
    dq 0x00CFF3010000FFFF
ldt_end:
