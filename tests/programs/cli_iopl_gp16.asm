; cli_iopl_gp16.asm - CLI at CPL 3 with IOPL 0 faults at the CLI
;
; Windows' VMM runs ring-3 code with IOPL below CPL and emulates the #GP of
; CLI/STI: it decodes the instruction at the frame's CS:EIP. A frame that
; points past the CLI makes it report an application GPF (Win95 Setup,
; SYSDETMG.DLL: cmp/jc/ja/cmp/jc; cli; call far [bp-4]). 16-bit ring-3
; code runs CLI in several shapes; the #GP handler checks each frame's EIP
; against the CLI's address and skips it. The test ends with a HLT, which
; also faults at CPL 3.
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
SEL_CODE3   equ 0x18    ; 16-bit code, DPL 3
SEL_DATA3   equ 0x20
SEL_TSS     equ 0x28

SEL_CODE3_RPL3 equ (SEL_CODE3 | 3)
SEL_DATA3_RPL3 equ (SEL_DATA3 | 3)

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

    ; IRET outer-level to 16-bit ring 3 with IOPL=0, IF=1
    push dword SEL_DATA3_RPL3   ; SS3
    push dword STACK3_TOP       ; ESP3
    push dword 0x00000202       ; EFLAGS IOPL=0
    push dword SEL_CODE3_RPL3
    push dword ring3_entry
    iretd

BITS 16
ring3_entry:
    mov ax, SEL_DATA3_RPL3
    mov ds, ax
    mov bp, sp
    sub sp, 8
    mov word [bp-4], far_target
    mov word [bp-2], SEL_CODE3_RPL3

    nop
site1:
    cli                         ; straight line

    mov ax, 1
    mov cx, 2
    cmp ax, cx
    jnc skip2                  ; not taken
site2:
    cli
skip2:

    mov dx, 2
    mov bx, 1
    cmp dx, bx
    ja site3                    ; taken, to the CLI
    jmp ring3_fail
site3:
    cli

    mov cx, 3
loop4:
    dec cx
    jnz loop4
site4:
    cli

    ; SYSDETMG shape: both compares fall through to CLI; call far
    mov dx, 0
    mov bx, 0
    mov ax, 5
    mov cx, 1
    cmp dx, bx
    jc ring3_fail
    ja ring3_fail
    cmp ax, cx
    jc ring3_fail
site5:
    cli
    call far [bp-4]
    cmp ax, 0x5A5A
    jne ring3_fail

    ; the same, entered by a taken branch from the loop above
    mov si, 2
loop6:
    dec si
    jz fall6
    mov dx, 1
    mov bx, 0
    cmp dx, bx
    jc loop6
    ja site6
    jmp ring3_fail
fall6:
    jmp ring3_fail
site6:
    cli
    call far [bp-4]

done_site:
    hlt                         ; faults: the handler checks the count
    jmp $

ring3_fail:
    jmp ring3_fail_far

far_target:
    mov ax, 0x5A5A
    retf

ring3_fail_far:
    out 0x81, al                ; #GP at an unexpected EIP: the handler fails
    jmp $

;------------------------------------------------------------------
; Ring 0 #GP handler via DPL0 386 interrupt gate
;------------------------------------------------------------------
BITS 32
isr_gp:
    ; frame: [esp]=err, +4 EIP, +8 CS, +12 EFLAGS, +16 ESP3, +20 SS3
    push ds
    push eax
    push ebx
    mov ax, SEL_DATA0
    mov ds, ax
    mov ebx, [gp_count]
    mov eax, [esp+16]           ; EIP
    cmp ebx, NSITES
    je .done
    cmp eax, [sites + ebx*4]
    jne fail_22
    mov eax, [esp+12]
    cmp eax, 0
    jne fail_21
    mov eax, [esp+20]
    cmp ax, SEL_CODE3_RPL3
    jne fail_23
    inc dword [gp_count]
    inc dword [esp+16]          ; skip the 1-byte CLI
    pop ebx
    pop eax
    pop ds
    add esp, 4                  ; error code
    iretd
.done:
    cmp eax, done_site
    jne fail_24
    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt

fail_21:
    mov eax, 0x21
    jmp fail
fail_22:
    ; code: 0x22 | site index << 8 | reported EIP << 16
    shl eax, 16
    mov al, 0x22
    mov ah, bl
    jmp fail
fail_23:
    mov eax, 0x23
    jmp fail
fail_24:
    shl eax, 16
    mov al, 0x24
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
NSITES equ 6
align 4
gp_count:
    dd 0
sites:
    dd site1, site2, site3, site4, site5, site6

align 8
gdt:
    dq 0x0000000000000000
    ; 0x08: ring0 32-bit code, base 0x10000
    dq 0x00CF9B010000FFFF
    ; 0x10: ring0 32-bit data, base 0x10000
    dq 0x00CF93010000FFFF
    ; 0x18: ring3 16-bit code, base 0x10000, limit 0xFFFF
    dq 0x0000FB010000FFFF
    ; 0x20: ring3 data, base 0x10000 (DPL=3)
    dq 0x00CFF3010000FFFF
    ; 0x28: available 386 TSS (type 9), base = tss386+0x10000, limit 0x67
    dw 0x0067
    dw tss386
    db 0x01
    db 0x89
    db 0x00
    db 0x00
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x00010000

; IDT: vector 0x0D = 386 interrupt gate, DPL0, ring0 handler
align 8
idt:
    times 0x0D dq 0
    dw isr_gp                   ; offset [15:0]
    dw SEL_CODE0
    db 0
    db 10001110b                ; P=1 DPL=0 type=E (386 int gate)
    dw 0                        ; offset [31:16]
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x00010000

; 386 TSS: ESP0 at +4, SS0 at +8
align 4
tss386:
    dd 0
    dd STACK0_TOP               ; +4  ESP0
    dd SEL_DATA0                ; +8  SS0
    times 23 dd 0
tss386_end:
