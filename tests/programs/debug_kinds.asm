; debug_kinds - data breakpoints on every access kind (486)
;
; DR0 = X, L0, RW0 = 11 (read/write) or 01 (write), LEN0 = 11.  Each case
; performs one access kind touching X and must trap once after the
; instruction: DR6.B0 set, saved EIP = the following instruction.  Data
; breakpoints match linear addresses of every data access of the instruction
; (Intel486 PRM 11.2.4/11.3.1.2).  Cases record failures to port 0xE4 as
; (case << 8) | reason and continue; reasons: 1 no trap, 2 wrong EIP,
; 3 B0 clear.
BITS 32
ORG 0
CODE_BASE equ 0x10000
LOG       equ 0x5000
X         equ 0x9000
CNT       equ 0x5810
%macro DR7SET 1
    mov eax, %1
    mov dr7, eax
%endmacro
; CASE n, rw(0x000f0001 RW/LEN), next-label
%macro BEGIN 2
    mov esp, 0x8000
    xor eax, eax
    mov dr6, eax
    mov dword [LOG], 0
    mov dword [LOG+4], 0
    mov dword [LOG+12], 0
    mov dword [LOG+20], 0
    mov dword [LOG+28], 0
    mov dword [CNT], 0
    mov eax, X
    mov dr0, eax
    DR7SET %2
    mov ecx, %1
%endmacro
%macro END 2
%2:
    DR7SET 0
    mov esp, 0x8000
    mov ecx, %1
    mov edx, %2
    call check
%endmacro

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
    times 3 dq 0
    dw bound_handler, 8                ; #BR (5): never expected
    db 0, 0x8e
    dw 0
    times 26 dq 0
    dw int_handler, 8                  ; vector 32
    db 0, 0x8e
    dw 0
idt_end:
idtr: dw idt_end-idt-1
      dd CODE_BASE+idt

db_handler:
    push eax
    push ebx
    mov ebx, [CNT]
    cmp ebx, 4
    jae .skip                          ; keep the first four entries
    shl ebx, 3
    mov eax, dr6
    mov [LOG + ebx], eax
    mov eax, [esp + 8]
    mov [LOG + ebx + 4], eax
.skip:
    inc dword [CNT]
    xor eax, eax                       ; DR6 is sticky: BEGIN clears it
    mov dr7, eax                       ; one trap per case; IRET may reread X
    pop ebx
    pop eax
    iretd
bound_handler:
    mov eax, 0xBB00
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
int_handler:
    iretd

; ecx = case, edx = expected EIP
check:
    cmp dword [CNT], 0
    jne .t
    mov eax, ecx
    shl eax, 8
    or eax, 1
    out 0xe4, eax
    inc dword [0x5800]
    ret
.t:
    ; a nested #DB (delivery frame written over X) runs its handler first,
    ; so search every logged entry for the instruction's own trap
    xor ebx, ebx
.s:
    cmp [LOG + ebx*8 + 4], edx
    je .e
    inc ebx
    cmp ebx, [CNT]
    jae .bad
    cmp ebx, 4
    jb .s
.bad:
    mov eax, ecx
    shl eax, 8
    or eax, 2
    out 0xe4, eax
    mov eax, [LOG+4]
    out 0xe4, eax
    inc dword [0x5800]
    ret
.e:
    test dword [LOG + ebx*8], 1
    jnz .ok
    mov eax, ecx
    shl eax, 8
    or eax, 3
    out 0xe4, eax
    inc dword [0x5800]
.ok:
    ret

times 0x300-($-$$) db 0x90
start:
    cli
    mov esp, 0x8000
    lgdt [cs:gdtr]
    lidt [cs:idtr]
    mov dword [0x5800], 0
    cld
    mov dword [X], 0x11
    mov dword [X+4], 0x10
    mov dword [X-4], 0

    ; 1 MOVSD source = X
    BEGIN 1, 0x000f0001
    mov esi, X
    mov edi, X+0x100
    movsd
    END 1, n1
    ; 2 MOVSD destination = X
    BEGIN 2, 0x000d0001
    mov esi, X+0x100
    mov edi, X
    movsd
    END 2, n2
    ; 3 CMPSD (second operand ES:EDI = X)
    BEGIN 3, 0x000f0001
    mov esi, X+0x100
    mov edi, X
    cmpsd
    END 3, n3
    ; 4 SCASD
    BEGIN 4, 0x000f0001
    mov edi, X
    scasd
    END 4, n4
    ; 5 LODSD
    BEGIN 5, 0x000f0001
    mov esi, X
    lodsd
    END 5, n5
    ; 6 STOSD
    BEGIN 6, 0x000d0001
    mov edi, X
    stosd
    END 6, n6
    ; 7 INSB (memory write)
    BEGIN 7, 0x000d0001
    mov edi, X
    mov dx, 0x80
    insb
    END 7, n7
    ; 8 OUTSB (memory read)
    BEGIN 8, 0x000f0001
    mov esi, X
    mov dx, 0x80
    outsb
    END 8, n8
    ; 9 PUSH (write, ESP -> X)
    BEGIN 9, 0x000d0001
    mov esp, X+4
    push eax
    END 9, n9
    ; 10 POP (read from X) - delivery frame may also match; first entry checked
    BEGIN 10, 0x000f0001
    mov esp, X
    pop eax
    END 10, n10
    ; 11 CALL near pushes return address at X
    BEGIN 11, 0x000d0001
    mov esp, X+4
    call c11
c11:
    END 11, n11
    ; 12 RET reads X
    mov dword [X], n12
    BEGIN 12, 0x000f0001
    mov esp, X
    ret
    END 12, n12
    ; 13 LDS reads offset at X-4... selector at X (word)
    mov dword [X-4], 0
    mov dword [X], 0x10
    BEGIN 13, 0x000f0001
    lds eax, [X-4]
    END 13, n13
    ; 14 LSS
    mov dword [X-4], 0x8000
    mov dword [X], 0x10
    BEGIN 14, 0x000f0001
    lss esp, [X-4]
    END 14, n14
    ; 15 XCHG mem
    BEGIN 15, 0x000d0001
    xchg [X], eax
    END 15, n15
    ; 16 LOCK ADD mem
    BEGIN 16, 0x000d0001
    lock add dword [X], 1
    END 16, n16
    ; 17 BOUND reads bounds at X-4 (low) and X (high)
    mov dword [X-4], 0
    mov dword [X], 0x100
    BEGIN 17, 0x000f0001
    mov eax, 5
    bound eax, [X-4]
    END 17, n17
    ; 18 ENTER pushes EBP at X
    BEGIN 18, 0x000d0001
    mov esp, X+4
    enter 0, 0
    END 18, n18
    ; 19 LEAVE pops EBP from X
    mov dword [X], 0
    BEGIN 19, 0x000f0001
    mov ebp, X
    mov esp, 0x7000
    leave
    END 19, n19
    ; 20 XADD mem
    BEGIN 20, 0x000d0001
    xadd [X], eax
    END 20, n20
    ; 21 CMPXCHG mem (equal -> write)
    BEGIN 21, 0x000d0001
    mov eax, [X]
    cmpxchg [X], ebx
    END 21, n21
    ; 22 PUSH mem source = X (read)
    BEGIN 22, 0x000f0001
    push dword [X]
    END 22, n22
    ; 23 POP mem destination = X (write)
    BEGIN 23, 0x000d0001
    push dword 5
    pop dword [X]
    END 23, n23
    ; 24 SGDT stores 6 bytes at X-4
    BEGIN 24, 0x000d0001
    sgdt [X-4]
    END 24, n24
    ; 25 PUSHAD writes X (ESP start X+8: writes X+4..X-28)
    BEGIN 25, 0x000d0001
    mov esp, X+8
    pushad
    END 25, n25
    ; 26 (info: documented limit, a trap inside INT n is dropped)
    BEGIN 26, 0x000d0001
    mov esp, X+8
    int 32
n26:
    DR7SET 0
    mov esp, 0x8000
    mov eax, [CNT]
    or eax, 0x2600
    out 0xe4, eax
    ; 27 REP MOVSB, write side, word op size 16
    BEGIN 27, 0x000d0001
    mov esi, X+0x100
    mov edi, X-2
    mov ecx, 4
    rep movsb
    END 27, n27
    ; 28 MOVSW 16-bit addressing (a16) destination
    BEGIN 28, 0x000d0001
    mov esi, X+0x100
    mov edi, X
    a16 movsw
    END 28, n28
    ; 29 bit test with register offset reaching X from X-0x20
    BEGIN 29, 0x000f0001
    mov eax, 8*0x20
    bt [X-0x20], eax
    END 29, n29
    ; 30 SETcc mem
    BEGIN 30, 0x000d0001
    sete [X]
    END 30, n30
    ; 31 SHLD mem
    BEGIN 31, 0x000d0001
    shld [X], eax, 1
    END 31, n31
    ; 32 MOVZX read word
    BEGIN 32, 0x000f0001
    movzx eax, word [X+2]
    END 32, n32
    ; 33 ARPL mem
    mov dword [X], 0x10
    BEGIN 33, 0x000d0001
    mov eax, 0x13
    arpl [X], ax
    END 33, n33
    ; 34 FS-relative with segment override + IMUL mem read
    BEGIN 34, 0x000f0001
    imul eax, [fs:X]
    END 34, n34
    ; 35 CALL indirect through memory (reads X)
    mov dword [X], c35
    BEGIN 35, 0x000f0001
    call [X]
c35:
    END 35, n35
    ; 36 JMP indirect through memory (branch: EIP = target)
    mov dword [X], n36
    BEGIN 36, 0x000f0001
    jmp [X]
    END 36, n36
    ; 37 LGDT reads X-4 (limit/base)
    sgdt [0x9800]
    mov eax, [0x9800]
    mov [X-4], eax
    mov eax, [0x9804]
    mov [X], eax
    BEGIN 37, 0x000f0001
    lgdt [X-4]
    END 37, n37
    ; 38 POPFD from X
    mov dword [X], 0x2
    BEGIN 38, 0x000f0001
    mov esp, X
    popfd
    END 38, n38
    ; 39 IRETD reads X (EIP at X-8)
    mov dword [X-8], n39
    mov dword [X-4], 8
    mov dword [X], 2
    BEGIN 39, 0x000f0001
    mov esp, X-8
    iretd
    END 39, n39
    ; 40 CMPXCHG mem with compare unequal (486 writes back the old value)
    BEGIN 40, 0x000d0001
    mov eax, [X]
    inc eax
    cmpxchg [X], ebx
    END 40, n40

    ; 41 (info) GDT descriptor read by a segment load: DR0 = descriptor 0x10
    mov esp, 0x8000
    xor eax, eax
    mov dr6, eax
    mov dword [CNT], 0
    mov eax, CODE_BASE+gdt+0x10
    mov dr0, eax
    DR7SET 0x000f0001
    mov ax, 0x10
    mov ds, ax
n41:
    DR7SET 0
    mov eax, [CNT]
    or eax, 0x4100
    out 0xe4, eax
    ; 42 (info) IDT gate read by INT 32
    mov esp, 0x8000
    xor eax, eax
    mov dr6, eax
    mov dword [CNT], 0
    mov eax, CODE_BASE+idt+32*8
    mov dr0, eax
    DR7SET 0x000f0001
    int 32
n42:
    DR7SET 0
    mov eax, [CNT]
    or eax, 0x4200
    out 0xe4, eax

    cmp dword [0x5800], 0
    jnz bad
    mov al, 1
    out 0xe0, al
    hlt
bad:
    mov eax, [0x5800]
    or eax, 0x10000
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt
