; cr0_ops - every CR0 writer keeps the 486 CR0 rules
;
; LMSW loads only PE/MP/EM/TS and cannot clear PE (486 PRM LMSW page); CLTS
; clears only TS; a task switch sets TS and nothing else (486 PRM 4.1.3,
; 7.5).  ET (bit 4) reads 1 throughout; NE/WP/AM/CD survive every writer.
; MOV CR3 keeps PCD/PWT (bits 4/3).  Fail codes on port 0xE4: the number of
; the failed check; the following 0xE4 write is the CR0/CR3 value seen.
BITS 16
org 0
SEL_CODE0   equ 0x08
SEL_DATA0   equ 0x10
SEL_TSS_OLD equ 0x18
SEL_TSS_NEW equ 0x20
%macro CHK 2            ; expected CR0, code
    mov eax, cr0
    mov ebx, %2
    cmp eax, %1
    jne fail_v
%endmacro

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
    mov ax, SEL_TSS_OLD
    ltr ax

    ; NE | WP | AM | PE (+ET hardwired)
    mov eax, 0x00050021
    mov cr0, eax
    CHK 0x00050031, 1
    ; LMSW: MP EM TS from the source, PE kept, upper bits kept
    mov ax, 0x000e
    lmsw ax
    CHK 0x0005003f, 2
    ; LMSW 0 cannot clear PE; ET stays 1 even with source bit 4 = 0
    mov ax, 0xfff0
    lmsw ax
    CHK 0x00050031, 3
    ; LMSW from memory
    mov word [scratch], 0x0008
    lmsw [scratch]
    CHK 0x00050039, 4
    ; CLTS clears TS only
    clts
    CHK 0x00050031, 5
    ; CD set (NW=0, legal): writers keep CD
    mov eax, 0x40050021
    mov cr0, eax
    CHK 0x40050031, 6
    mov ax, 0x0008
    lmsw ax
    CHK 0x40050039, 7
    clts
    CHK 0x40050031, 8
    ; SMSW r16 and to memory
    mov ax, 0x0002
    lmsw ax
    mov dword [scratch], 0xffffffff
    smsw [scratch]
    mov eax, [scratch]
    mov ebx, 9
    cmp eax, 0xffff0033
    jne fail_v
    ; task switch sets TS, keeps the rest (MP=1 from above)
    jmp SEL_TSS_NEW:0
    mov ebx, 10
    jmp fail_b

task_entry:
    CHK 0x4005003b, 11
    clts
    ; CR3: PCD/PWT stored and read back
    mov eax, 0x00001018
    mov cr3, eax
    mov eax, cr3
    mov ebx, 12
    cmp eax, 0x00001018
    jne fail_v
    xor eax, eax
    mov cr3, eax
    mov eax, 0x00000011
    mov cr0, eax
    mov al, 1
    out 0xe0, al
    hlt

fail_v:
    xchg eax, ebx
    out 0xe4, eax
    xchg eax, ebx
    out 0xe4, eax
    mov eax, ebx
    out 0xe4, eax
fail_b:
    mov eax, ebx
    out 0xe4, eax
    mov al, 0xff
    out 0xe0, al
    hlt

align 4
scratch: dd 0

align 8
gdt:
    dq 0
    dq 0x00CF9B010000FFFF       ; 08: 32-bit code, base 10000h
    dq 0x00CF93010000FFFF       ; 10: 32-bit data, base 10000h
    dw 0x0067                   ; 18: available 386 TSS (old)
    dw tss_old
    db 0x01
    db 10001001b
    db 0
    db 0
    dw 0x0067                   ; 20: available 386 TSS (new)
    dw tss_new
    db 0x01
    db 10001001b
    db 0
    db 0
gdt_end:
gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt + 0x10000

align 4
tss_old:
    times 26 dd 0
align 4
tss_new:
    dd 0, 0, 0, 0, 0, 0, 0
    dd 0                        ; 1C CR3 (paging disabled)
    dd task_entry               ; 20 EIP
    dd 0x00000002               ; 24 EFLAGS
    dd 0, 0, 0, 0               ; EAX ECX EDX EBX
    dd 0x4000                   ; 38 ESP
    dd 0                        ; 3C EBP
    dd 0, 0                     ; ESI EDI
    dd SEL_DATA0                ; 48 ES
    dd SEL_CODE0                ; 4C CS
    dd SEL_DATA0                ; 50 SS
    dd SEL_DATA0                ; 54 DS
    dd 0, 0                     ; FS GS
    dd 0                        ; 60 LDTR
    dw 0                        ; 64 T
    dw 0x0068                   ; 66 I/O bitmap beyond TSS limit
