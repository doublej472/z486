; debug_gd - general detect (DR7.GD) on a 486
;
; With DR7.GD=1, any MOV to or from a debug register raises #DB as a FAULT
; before the instruction executes: DR6.BD (bit 13) is set and the processor
; clears DR7.GD on entry to the handler, so the handler can use the debug
; registers itself.  (Intel486 PRM 11.2.2 "GD is cleared at entry to the
; debug exception handler by the processor"; 11.3.1.3 general-detect fault.)
; Results: port 0xE0 (1 pass / 0xFF fail), 0xE4 fail code.
BITS 32
ORG 0
CODE_BASE equ 0x10000
LOG       equ 0x6000
align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff
    dq 0x00cf93000000ffff
gdt_end:
gdtr: dw gdt_end-gdt-1
      dd CODE_BASE+gdt
align 8
idt:
    dq 0
    dw db_handler, 8
    db 0, 0x8e
    dw 0
idt_end:
idtr: dw idt_end-idt-1
      dd CODE_BASE+idt

; If GD were left set, the handler's own MOV r,DRn would fault again; stop
; after a few nested entries instead of recursing.
db_handler:
    inc ebp
    cmp ebp, 3
    ja nested
    push eax
    push ebx
    mov ebx, ebp
    shl ebx, 4
    mov eax, [esp + 8]
    mov [LOG + ebx + 4], eax          ; saved EIP
    mov eax, dr6
    mov [LOG + ebx], eax
    mov eax, dr7
    mov [LOG + ebx + 8], eax
    xor eax, eax
    mov dr6, eax
    pop ebx
    pop eax
    iretd
nested:
    mov eax, 0x100
    jmp fail

times 0x200-($-$$) db 0x90
start:
    cli
    mov esp, 0x8000
    lgdt [cs:gdtr]
    lidt [cs:idtr]
    xor eax, eax
    mov dr6, eax

    ; 1: MOV DR0,r with GD=1
    xor ebp, ebp
    mov eax, 0x2000
    mov dr7, eax                      ; GD
    mov eax, 0x1234
site1:
    mov dr0, eax
    mov ebx, 1
    cmp ebp, 1
    jne fail_b
    mov ebx, 2
    mov eax, [LOG + 16 + 4]
    cmp eax, site1                    ; fault: EIP names the MOV
    jne fail_b
    mov ebx, 3
    mov eax, [LOG + 16]
    test eax, 0x2000                  ; DR6.BD
    jz fail_b
    mov ebx, 4
    mov eax, [LOG + 16 + 8]
    test eax, 0x2000                  ; GD cleared before the handler ran
    jnz fail_b
    mov ebx, 5
    mov eax, dr0                      ; GD now clear: the retried MOV completed
    cmp eax, 0x1234
    jne fail_b

    ; 2: MOV r,DR6 with GD=1
    xor ebp, ebp
    mov eax, 0x2000
    mov dr7, eax
site2:
    mov ecx, dr6
    mov ebx, 6
    cmp ebp, 1
    jne fail_b
    mov ebx, 7
    mov eax, [LOG + 16 + 4]
    cmp eax, site2
    jne fail_b
    mov ebx, 8
    mov eax, [LOG + 16]
    test eax, 0x2000
    jz fail_b

    xor eax, eax
    mov dr7, eax
    mov al, 1
    out 0xe0, al
    hlt
fail_b:
    mov eax, ebx
fail:
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
