; A MOV EAX/AL,moffs (A1/A0) load that page-faults restarts at the MOV:
; the #PF frame holds its EIP, and after the handler maps the page the MOV
; loads the value. z486's direct moffs load path pushed the next
; instruction's EIP, so the load was skipped and the register kept its old
; value (Win95 co-simulation: mov eax,[7d6bba84] in a DLL during WordPad
; startup).

BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
CODE_BASE   equ 0x00010000
DATA        equ 0x00020000
DATA_PTE    equ 0x00001000 + (DATA >> 12) * 4

align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff     ; 0x08: code, base 0x00010000
    dq 0x00cf93000000ffff     ; 0x10: data, base 0
    dq 0x00c7930000000fff     ; 0x18: data, base 0, limit 0x7FFFFFFF (not flat)
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd CODE_BASE + gdt

pf_handler:
    push eax
    mov eax, [esp + 8]                  ; frame EIP (after the error code)
    mov [CODE_BASE + pf_eip], eax
    pop eax
    inc dword [CODE_BASE + pf_count]
    or dword [DATA_PTE], 1
    add esp, 4                          ; discard #PF error code
    iretd

align 8
idt:
    times 14 dq 0
    dw pf_handler
    dw 0x0008
    db 0
    db 0x8e
    dw 0
idt_end:

idt_desc:
    dw idt_end - idt - 1
    dd CODE_BASE + idt

align 4
pf_count: dd 0
pf_eip:   dd 0

times 0x200 - ($ - $$) db 0x90
start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    mov esp, 0x38000
    mov dword [DATA + 0x84], 0x12345678

    ; ---- 1. mov eax, [moffs] ----
    and dword [DATA_PTE], 0xFFFFFFFE
    invlpg [DATA]
    mov eax, 0x11111111
load1:
    mov eax, [DATA + 0x84]              ; A1: #PF, restarted
    cmp dword [CODE_BASE + pf_eip], load1
    mov ebx, 0x10
    jne fail
    cmp eax, 0x12345678
    mov ebx, 0x11
    jne fail

    ; ---- 2. mov al, [moffs] ----
    and dword [DATA_PTE], 0xFFFFFFFE
    invlpg [DATA]
    mov eax, 0x11111111
load2:
    mov al, [DATA + 0x84]               ; A0: #PF, restarted
    cmp dword [CODE_BASE + pf_eip], load2
    mov ebx, 0x20
    jne fail
    cmp eax, 0x11111178
    mov ebx, 0x21
    jne fail
    cmp dword [CODE_BASE + pf_count], 2
    mov ebx, 0x30
    jne fail

    ; ---- 3. the load is the first instruction of a called function ----
    and dword [DATA_PTE], 0xFFFFFFFE
    invlpg [DATA]
    mov eax, 0x11111111
    call load3
    cmp dword [CODE_BASE + pf_eip], load3
    mov ebx, 0x40
    jne fail
    cmp eax, 0x12345678
    mov ebx, 0x41
    jne fail

    ; ---- 4. a non-flat DS: the MOV takes the microcode path, whose read
    ;         probe enters paging after younger instructions have issued ----
    mov ax, 0x18
    mov ds, ax
    and dword [DATA_PTE], 0xFFFFFFFE
    invlpg [DATA]
    mov eax, 0x11111111
load4:
    mov eax, [DATA + 0x84]              ; A1 through the microcode read probe
    mov ecx, 0x10
    mov dx, 0x10
    mov ds, dx
    cmp dword [CODE_BASE + pf_eip], load4
    mov ebx, 0x50
    jne fail
    cmp eax, 0x12345678
    mov ebx, 0x51
    jne fail

    mov al, 1
    out STATUS_PORT, al
    hlt

load3:
    mov eax, [DATA + 0x84]              ; A1 at a call target: #PF, restarted
    ret

fail:
    mov eax, ebx
    out DATA_PORT, eax
    mov al, 0xff
    out STATUS_PORT, al
    hlt

times 0x400 - ($ - $$) db 0
