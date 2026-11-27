; tf_trap_at_page_fault - a single-step trap beats the next fetch's #PF
;
; Intel 64 and IA-32 SDM Vol. 3A, 6.9, Table 6-2: class 4, "Traps on the
; Previous Instruction ... Debug Trap Exceptions (TF flag set ...)", is above
; class 7, "Faults from Fetching Next Instruction ... Code Page Fault".
;
; Each slot places one instruction so it ends at the last byte before the
; not-present page FAULT_LINEAR and enters it by IRETD with TF set, so it is
; single-stepped.  Expected per slot: one #DB with EIP at the page boundary,
; and no #PF.  The #DB handler resumes at the slot's continuation with TF
; clear.  Port 0xE4 reports (slot << 8) | field per mismatch: 1 = #DB count,
; 2 = #DB EIP, 4 = #PF count.
BITS 32
ORG 0

STATUS_PORT equ 0xe0
DATA_PORT equ 0xe4
CODE_BASE equ 0x10000
KSTACK_TOP equ 0x38000
SEL_CODE0 equ 8
SEL_DATA0 equ 0x10
FAULT_OFF equ 0x4000
FAULT_LINEAR equ CODE_BASE + FAULT_OFF
FAULT_PTE equ 0x1000 + (FAULT_LINEAR >> 12) * 4
NSLOT equ 3

gdt:
    dq 0
    dq 0x00cf9b010000ffff
    dq 0x00cf93000000ffff
gdt_end:
gdt_desc:
    dw gdt_end - gdt - 1
    dd CODE_BASE + gdt
align 8
idt:
    dq 0
    dw db_handler, SEL_CODE0
    db 0, 0x8e
    dw 0
    times 11 dq 0
    dw gp_handler, SEL_CODE0
    db 0, 0x8e
    dw 0
    dw pf_handler, SEL_CODE0
    db 0, 0x8e
    dw 0
idt_end:
idt_desc:
    dw idt_end - idt - 1
    dd CODE_BASE + idt

align 4
cur:    dd 0
conts:  dd cont0, cont1, cont2
r_eip:  times NSLOT dd 0xeeeeeeee
r_db:   times NSLOT db 0
r_pf:   times NSLOT db 0

gp_handler:
    mov eax, 0x0d000001
    jmp fail

; #DB: record the frame, resume at the slot's continuation with TF clear.
db_handler:
    push esi
    push eax
    mov esi, [CODE_BASE + cur]
    inc byte [CODE_BASE + r_db + esi]
    mov eax, [esp + 8]
    mov [CODE_BASE + r_eip + esi*4], eax
    jmp resume

; #PF (with error code): record it, drop the error code, resume.
pf_handler:
    push esi
    push eax
    mov esi, [CODE_BASE + cur]
    inc byte [CODE_BASE + r_pf + esi]
    pop eax
    pop esi
    add esp, 4                      ; the error code
    push esi
    push eax
resume:
    mov eax, [CODE_BASE + conts + esi*4]
    mov [esp + 8], eax
    and dword [esp + 16], 0xfffffeff
    pop eax
    pop esi
    iretd

times 0x800 - ($ - $$) db 0x90
start:
    cli
    cld
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, KSTACK_TOP
    and dword [FAULT_PTE], 0xfffffffe
    mov eax, cr3
    mov cr3, eax

    ; Slot 0: DIV EBX (F7 F3, microcoded) ending at FAULT_OFF - 1.
    mov dword [CODE_BASE + cur], 0
    mov word [CODE_BASE + FAULT_OFF - 2], 0xf3f7
    mov eax, 0x12345
    xor edx, edx
    mov ebx, 7
    mov edi, FAULT_OFF - 2
    jmp enter_tf
cont0:
    ; Slot 1: MOV EAX,imm32 (5 bytes).
    mov dword [CODE_BASE + cur], 1
    mov byte [CODE_BASE + FAULT_OFF - 5], 0xb8
    mov dword [CODE_BASE + FAULT_OFF - 4], 0x44332211
    mov edi, FAULT_OFF - 5
    jmp enter_tf
cont1:
    ; Slot 2: NOP.
    mov dword [CODE_BASE + cur], 2
    mov byte [CODE_BASE + FAULT_OFF - 1], 0x90
    mov edi, FAULT_OFF - 1
    jmp enter_tf
cont2:

    xor ebx, ebx
    xor esi, esi
.loop:
    cmp byte [CODE_BASE + r_db + esi], 1
    je .e1
    mov dl, 1
    call report
.e1:
    cmp dword [CODE_BASE + r_eip + esi*4], FAULT_OFF
    je .e2
    mov dl, 2
    call report
.e2:
    cmp byte [CODE_BASE + r_pf + esi], 0
    je .e4
    mov dl, 4
    call report
.e4:
    inc esi
    cmp esi, NSLOT
    jb .loop
    test ebx, ebx
    jnz bad
    mov al, 1
    out STATUS_PORT, al
    hlt
bad:
    mov al, 0xff
    out STATUS_PORT, al
    hlt

; IRETD to CS:EDI with TF set.
enter_tf:
    pushfd
    or dword [esp], 0x100
    push dword SEL_CODE0
    push edi
    iretd

report:                         ; esi = slot, dl = field
    inc ebx
    mov eax, esi
    shl eax, 8
    mov al, dl
    out DATA_PORT, eax
    ret

fail:
    out DATA_PORT, eax
    mov al, 0xff
    out STATUS_PORT, al
    hlt
