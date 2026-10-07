; A 486 writes the memory destination of CMPXCHG even when unequal.
; XADD and both CMPXCHG outcomes must restart without retiring source/AX or
; arithmetic flags when that write faults. LOCK register forms must #UD.
BITS 32
ORG 0
DATA_LINEAR equ 0x20000000
align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff
    dq 0x20cf93000000ffff
    dq 0x30cf93000000ffff
    dq 0x00cf93000000ffff     ; FS: physical page tables, linear base zero
gdt_end:
gdtr: dw gdt_end-gdt-1
      dd 0x10000+gdt
align 8
idt:
    times 6 dq 0
    dw ud_handler, 8
    db 0, 0x8e
    dw 0
    times 7 dq 0
    dw pf_handler, 8
    db 0, 0x8e
    dw 0
idt_end:
idtr: dw idt_end-idt-1
      dd 0x10000+idt

pf_handler:
    cmp dword [ss:esp], 3    ; present, write, supervisor
    jne fail
    mov edx, cr2
    cmp edx, DATA_LINEAR
    jne fail
    mov edx, [ss:esp+12]
    and edx, 0x8d5
    cmp edx, 0x8d5           ; fault restores the pre-instruction flags
    jne fail
    cmp ebx, 0x33334444
    jne fail
    cmp edi, 1
    je .xadd
    cmp edi, 2
    je .equal
    cmp edi, 3
    jne fail
    cmp eax, 0x55556666
    jne fail
    cmp dword [ss:esp+4], cmp_unequal
    jne fail
    jmp .skip
.equal:
    cmp eax, 0x11112222
    jne fail
    cmp dword [ss:esp+4], cmp_equal
    jne fail
    jmp .skip
.xadd:
    cmp eax, 0x1234
    jne fail
    cmp dword [ss:esp+4], xadd_site
    jne fail
.skip:
    add dword [ss:esp+4], 3
    inc ebp
    add esp, 4
    iretd

ud_handler:
    cmp eax, 0x55556666
    jne fail
    cmp ebx, 0x33334444
    jne fail
    cmp edi, 4
    je .xadd
    cmp edi, 5
    jne fail
    cmp dword [ss:esp], lock_cmp_reg
    jne fail
    jmp .skip
.xadd:
    cmp dword [ss:esp], lock_xadd_reg
    jne fail
.skip:
    add dword [ss:esp], 4
    inc ebp
    iretd

fail:
    mov eax, edi
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt

times 0x200-($-$$) db 0x90
start:
    cli
    mov esp, 0xf00
    lgdt [cs:gdtr]
    lidt [cs:idtr]
    mov ax, 0x20
    mov fs, ax
    xor ebp, ebp
    xor esi, esi
    mov dword [esi], 0x11112222
    ; DS page zero is in the second generated PT (0x2000). Change it through
    ; the D-cache, then invalidate its translation. CR0.WP is set by the JSON.
    mov dword [fs:0x2000], 0x00020021
    invlpg [esi]
    mov ebx, 0x33334444
    mov edi, 1
    mov eax, 0x1234
    push dword 0x8d7
    popfd
xadd_site:
    xadd [esi], eax
    cmp ebp, 1
    jne fail
    mov edi, 2
    mov eax, 0x11112222
    push dword 0x8d7
    popfd
cmp_equal:
    cmpxchg [esi], ebx
    cmp ebp, 2
    jne fail
    mov edi, 3
    mov eax, 0x55556666
    push dword 0x8d7
    popfd
cmp_unequal:
    cmpxchg [esi], ebx
    cmp ebp, 3
    jne fail
    cmp dword [esi], 0x11112222
    jne fail
    mov edi, 4
lock_xadd_reg:
    db 0xf0, 0x0f, 0xc1, 0xd8   ; invalid LOCK XADD EAX,EBX
    cmp ebp, 4
    jne fail
    mov edi, 5
lock_cmp_reg:
    db 0xf0, 0x0f, 0xb1, 0xd8   ; invalid LOCK CMPXCHG EAX,EBX
    cmp ebp, 5
    jne fail
    mov al, 1
    out 0xe0, al
    hlt
