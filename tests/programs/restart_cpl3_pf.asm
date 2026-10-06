; restart_cpl3_pf - architectural restart state after #PF in multi-access
; ring-3 instructions
;
; Each site runs at CPL3 on a stack whose only present page is 3000h-3FFFh
; (2000h and 4000h are not present), so the instruction faults part way
; through.  A 486 fault leaves ESP, EIP (= the instruction) and the string
; registers as they were before the faulting iteration.  The ring-0 #PF
; handler records ESP3, EIP and ECX/ESI/EDI/EBP, then resumes after the site.
; Fail (port E4): site*16 + 1 EIP, 2 ESP, 3 ECX, 4 ESI, 5 EDI, 6 EBP,
; 7 no #PF.
BITS 16
org 0
STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_CODE3   equ 0x18
SEL_DATA3   equ 0x20
SEL_TSS     equ 0x28
R0_STACK    equ 0x00014000
V           equ 0x1C00             ; variables (flat, in a present page)
R_EIP       equ V+0
R_ESP       equ V+4
R_ECX       equ V+8
R_ESI       equ V+12
R_EDI       equ V+16
R_EBP       equ V+20
RESUME      equ V+24
R_EAX       equ V+28
COUNT       equ V+32

start:
    cli
    cld
    mov ax, cs
    mov ds, ax
    lgdt [gdt_desc]
    lidt [idt_desc]
    mov eax, cr0
    or  al, 1
    mov cr0, eax
    jmp SEL_CODE0:pm

BITS 32
pm:
    mov ax, SEL_DATA0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, R0_STACK
    mov ax, SEL_TSS
    ltr ax
    mov eax, cr0
    or  eax, 0x80000000
    mov cr0, eax
    push dword SEL_DATA3 | 3
    push dword 0x3800
    push dword 0x3002               ; IOPL3 for the result ports
    push dword SEL_CODE3 | 3
    push dword ring3_entry
    iretd

pf_handler:
    mov [R_EAX], eax
    mov [R_ECX], ecx
    mov [R_ESI], esi
    mov [R_EDI], edi
    mov [R_EBP], ebp
    inc dword [COUNT]
    mov eax, [esp+4]
    mov [R_EIP], eax
    mov eax, [esp+16]
    mov [R_ESP], eax
    mov eax, [RESUME]
    mov [esp+4], eax
    mov dword [esp+16], 0x3800      ; a safe ring-3 ESP
    and dword [esp+12], ~0x400      ; DF=0
    mov eax, [R_EAX]
    add esp, 4
    iretd

fail:
    out DATA_PORT, eax
    mov al, 0xff
    out STATUS_PORT, al
    hlt

; RS site, expected ESP, instruction
%macro RS 3+
    mov dword [RESUME], %%resume
    mov dword [COUNT], 0
    jmp %%site
%%site:
    %3
%%resume:
    mov eax, %1*16+7
    cmp dword [COUNT], 1
    jne fail
    mov eax, %1*16+1
    cmp dword [R_EIP], %%site
    jne fail
    mov eax, %1*16+2
    cmp dword [R_ESP], %2
    jne fail
%endmacro
%macro EXPECT 3
    mov eax, %1*16+%2
    cmp dword [%3], ebx
    jne fail
%endmacro

ring3_entry:
    mov ax, SEL_DATA3 | 3
    mov ds, ax
    mov es, ax
    ; 1: PUSHAD crossing down into 2000h
    mov esp, 0x3010
    RS 1, 0x3010, pushad
    ; 2: POPAD crossing up into 4000h
    mov esp, 0x3FF0
    RS 2, 0x3FF0, popad
    ; 3: ENTER with nesting level 3; the copied frame pointers cross down
    mov ebp, 0x3100
    mov esp, 0x3008
    RS 3, 0x3008, enter 0x10, 3
    mov ebx, 0x3100
    EXPECT 3, 6, R_EBP
    ; 4: far CALL, the EIP push crosses down
    mov esp, 0x3004
    RS 4, 0x3004, call SEL_CODE3|3:ring3_entry
    ; 5: far RET 8, the CS pop crosses up
    mov esp, 0x3FFC
    RS 5, 0x3FFC, retf 8
    ; 6: POP to a not-present memory destination
    mov esp, 0x3800
    RS 6, 0x3800, pop dword [0x2000]
    ; 7: PUSH from a not-present memory source
    mov esp, 0x3800
    RS 7, 0x3800, push dword [0x2000]
    ; 8: near CALL with the push crossing down
    mov esp, 0x3000
    RS 8, 0x3000, call ring3_entry
    ; 9: REP MOVSD whose source crosses into 4000h after 4 iterations
    mov esp, 0x3800
    mov esi, 0x3FF0
    mov edi, 0x3400
    mov ecx, 8
    RS 9, 0x3800, rep movsd
    mov ebx, 4
    EXPECT 9, 3, R_ECX
    mov ebx, 0x4000
    EXPECT 9, 4, R_ESI
    mov ebx, 0x3410
    EXPECT 9, 5, R_EDI
    ; 10: STD REP STOSD whose destination crosses down into 2000h
    mov esp, 0x3800
    mov edi, 0x3008
    mov ecx, 8
    std
    RS 10, 0x3800, rep stosd
    cld
    mov ebx, 5
    EXPECT 10, 3, R_ECX
    mov ebx, 0x2FFC
    EXPECT 10, 5, R_EDI
    ; 11: LEAVE whose EBP pop crosses up
    mov esp, 0x3800
    mov ebp, 0x3FFE
    RS 11, 0x3800, leave
    mov ebx, 0x3FFE
    EXPECT 11, 6, R_EBP
    ; 12: same-level IRETD, the EFLAGS pop crosses up
    mov esp, 0x3FF8
    RS 12, 0x3FF8, iretd
    ; 13: LSS whose selector read crosses up
    mov esp, 0x3800
    RS 13, 0x3800, lss esp, [0x3FFE]
    ; 14: XCHG with a not-present memory operand
    mov esp, 0x3800
    RS 14, 0x3800, xchg [0x2000], eax
    ; 15: PUSHFD with the push crossing down
    mov esp, 0x3000
    RS 15, 0x3000, pushfd
    ; 16: CALL [mem] with the push crossing down
    mov dword [0x3400], ring3_entry
    mov esp, 0x3000
    RS 16, 0x3000, call [0x3400]
    ; 17: 16-bit PUSHAW crossing down
    mov esp, 0x3008
    RS 17, 0x3008, pushaw
    ; 18: POP ESP from a crossing slot
    mov esp, 0x3FFE
    RS 18, 0x3FFE, pop esp
    mov al, 1
    out STATUS_PORT, al
    hlt

align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff
    dq 0x00cf93000000ffff
    dq 0x00cffb010000ffff
    dq 0x00cff3000000ffff
tss_desc:
    dw 0x0067
    dw tss
    db 0x01, 0x89, 0x00, 0x00
gdt_end:
gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x10000

align 8
idt:
    times 14 dq 0
    dw pf_handler, SEL_CODE0
    db 0, 0x8e
    dw 0
idt_end:
idt_desc:
    dw idt_end - idt - 1
    dd idt + 0x10000

align 4
tss:
    dd 0, R0_STACK, SEL_DATA0, 0, 0, 0, 0, 0
    dd 0, 0, 0, 0, 0, 0, 0, 0
    dd 0, 0, 0, 0, 0, 0, 0, 0
    dw 0, 104
