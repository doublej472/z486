; wbinvd_pm_priv.asm - INVD/WBINVD privilege in protected mode
;
; Phase 1 (CPL0): INVD and WBINVD must execute without faulting, invalidate
; the data cache (a DMA write made behind the CPU becomes visible), and leave
; EFLAGS unchanged.
; Phase 2 (CPL3): INVD must raise #GP(0).  The ring-0 handler runs on the
; TSS stack and checks the error code (0), the saved CS RPL (3), and that the
; saved EIP points at the two-byte INVD, so a wrong fault or a wrong frame is
; reported as a failure.
;
; Code, data, and stack descriptors are based at 0x10000 (the image base) with
; offsets for every reference; one flat data descriptor reaches the physical
; RAM window used for the cache-visibility checks.  Paging is off.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
POKE_ADDR   equ 0xC4
POKE_DATA   equ 0xC8

STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

CODE_BASE   equ 0x10000
DAT_PHYS    equ 0x20040

SEL_CODE0   equ 0x08          ; ring-0 32-bit code, flat
SEL_DATA0   equ 0x10          ; ring-0 32-bit data, flat
SEL_STACK0  equ 0x18          ; ring-0 32-bit stack, flat
SEL_FLAT    equ 0x20          ; ring-0 32-bit flat data (physical window)

VEC_GP      equ 0x0D

STACK0_TOP  equ 0x00008000
STACK3_TOP  equ 0x0000A000

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7000

    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]

    mov eax, cr0
    or  eax, 1
    mov cr0, eax

    db 0x66, 0xEA               ; jmp far ptr16:32
    dd pm_entry
    dw SEL_CODE0

BITS 32
pm_entry:
    mov ax, SEL_DATA0
    mov ds, ax
    mov ss, ax
    mov ax, SEL_FLAT
    mov es, ax
    mov esp, STACK0_TOP

    ; ---- Phase 1: CPL0 INVD/WBINVD are allowed -------------------------
    mov dword [es:DAT_PHYS], 0x11112222
    mov eax, [es:DAT_PHYS]
    cmp eax, 0x11112222
    jne fail_p1a

    mov eax, DAT_PHYS
    mov dx, POKE_ADDR
    out dx, eax
    mov eax, 0x33334444
    mov dx, POKE_DATA
    out dx, eax

    mov eax, [es:DAT_PHYS]          ; still cached: the poke did not snoop
    cmp eax, 0x11112222
    jne fail_p1b

    db 0x0f, 0x08                ; INVD at CPL0
    mov eax, [es:DAT_PHYS]
    cmp eax, 0x33334444
    jne fail_p1c

    mov eax, DAT_PHYS
    mov dx, POKE_ADDR
    out dx, eax
    mov eax, 0x55556666
    mov dx, POKE_DATA
    out dx, eax

    mov eax, [es:DAT_PHYS]          ; refilled from the poked value
    cmp eax, 0x33334444
    jne fail_p1d

    pushfd
    pop ebx
    db 0x0f, 0x09                ; WBINVD at CPL0
    pushfd
    pop ecx
    cmp ebx, ecx
    jne fail_p1e
    mov eax, [es:DAT_PHYS]
    cmp eax, 0x55556666
    jne fail_p1f

    ; A #GP here would mean INVD/WBINVD faulted at CPL0: report it.
    mov dword [cp0_fault_flag], 0

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

BITS 32
; A #GP at CPL0 would be a bug: report the frame's error code as the failure
; code so a regression sees how the fault happened.
gp_handler:
    mov bp, sp
    mov eax, [ss:bp + 0x00]
    or  eax, 0x1D000000
    jmp fail_pm

BITS 32
fail_p1a:
    mov eax, 0x1A000001
    jmp fail_pm
fail_p1b:
    mov eax, 0x1A000002
    jmp fail_pm
fail_p1c:
    mov eax, 0x1A000003
    jmp fail_pm
fail_p1d:
    mov eax, 0x1A000004
    jmp fail_pm
fail_p1e:
    mov eax, 0x1A000005
    jmp fail_pm
fail_p1f:
    mov eax, 0x1A000006
    jmp fail_pm
fail_pm:
    mov dword [cp0_fault_flag], 0xFFFFFFFF
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt
    jmp $

align 8
gdt:
    dq 0x0000000000000000

    ; SEL_CODE0: ring-0 32-bit code, base 0x10000, limit 0xffff.
    dw 0xffff
    dw 0x0000
    db 0x01
    db 10011010b
    db 01000000b
    db 0x00

    ; SEL_DATA0: ring-0 32-bit data, base 0x10000, limit 0xffff.
    dw 0xffff
    dw 0x0000
    db 0x01
    db 10010010b
    db 01000000b
    db 0x00

    ; SEL_STACK0: ring-0 32-bit stack, base 0x10000, limit 0xffff.
    dw 0xffff
    dw 0x0000
    db 0x01
    db 10010010b
    db 01000000b
    db 0x00

    ; SEL_FLAT: ring-0 32-bit data, base 0, 4 GiB (physical RAM window).
    dw 0xffff
    dw 0x0000
    db 0x00
    db 10010010b
    db 11001111b
    db 0x00
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + CODE_BASE

align 8
idt:
    times VEC_GP dq 0

    ; #GP: 32-bit interrupt gate, DPL=0, ring-0 handler.
    dw gp_handler
    dw SEL_CODE0
    db 0
    db 10001110b
    dw 0

    times (256 - VEC_GP - 1) dq 0
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd idt + CODE_BASE

align 4
cp0_fault_flag:
    dd 0

