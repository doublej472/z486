; expand_down_b_bit - expand-down data segments use the segment's D/B bit for
; the upper bound, not the instruction's address size.  For a B=0 expand-down
; segment with limit 0FFFh the valid offsets are 1000h..FFFFh, so a dword
; access at 0FFFEh runs past the top and must #GP.  (The sibling core's tests
; only probe offsets well below the top.)
BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

CODE_LINEAR equ 0x00010000
VALID_OFF   equ 0x00001000     ; > limit 0FFFh: valid
TOP_OFF     equ 0x0000FFFE     ; dword: 0FFFEh..10001h, past the B=0 top

MARK_VALID  equ 0x00000F00
MARK_TOP    equ 0x00000F04
MARK_OTHER  equ 0x00000F08

align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff      ; 0x08: code, base 0x00010000
    dq 0x00cf93040000ffff      ; 0x10: data, base 0x00040000 (for loading)
    dq 0x0000960400000fff      ; 0x18: data, expand-down, B=0, base 0x40000, limit 0FFFh
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd CODE_LINEAR + gdt

gp_handler:
    mov eax, [ss:esp]          ; error code
    mov edx, [ss:esp + 4]      ; faulting EIP
    add esp, 4
    cmp edx, probe_valid
    je gp_valid
    cmp edx, probe_top
    je gp_top
    mov dword [ds:MARK_OTHER], 1
    mov dword [ss:esp], unexpected_after
    iretd
gp_valid:
    mov dword [ds:MARK_VALID], 1
    mov dword [ss:esp], valid_after
    iretd
gp_top:
    mov dword [ds:MARK_TOP], 1
    mov dword [ss:esp], top_after
    iretd

align 8
idt:
    times 13 dq 0              ; vectors 0..12 absent
    dw gp_handler              ; vector 13: #GP
    dw 0x0008
    db 0
    db 0x8e
    dw 0
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd CODE_LINEAR + idt

times 0x200 - ($ - $$) db 0x90
start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    mov esp, 0x00000F00

    mov dword [ds:MARK_VALID], 0
    mov dword [ds:MARK_TOP], 0
    mov dword [ds:MARK_OTHER], 0

    mov eax, 0x18
    mov es, eax

    ; control: an offset above the limit is valid in an expand-down segment
    mov ebx, VALID_OFF
probe_valid:
    mov eax, [es:ebx]
valid_after:

    ; the corner: a dword at 0FFFEh runs past the B=0 upper bound -> #GP
    mov ebx, TOP_OFF
probe_top:
    mov eax, [es:ebx]
top_after:
unexpected_after:
    xor ebx, ebx

    cmp dword [ds:MARK_VALID], 0
    jne fail_valid
    cmp dword [ds:MARK_TOP], 1
    jne fail_top
    cmp dword [ds:MARK_OTHER], 0
    jne fail_other

    mov al, 1
    mov dx, STATUS_PORT
    out dx, al
    hlt

fail_valid:
    mov eax, 1
    jmp fail
fail_top:
    mov eax, 2
    jmp fail
fail_other:
    mov eax, 3
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
    hlt
