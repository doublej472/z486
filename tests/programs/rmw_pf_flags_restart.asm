; A memory-destination ALU instruction whose READ succeeds and whose WRITE
; takes #PF (a read-only page under CR0.WP=1) must leave no state behind:
; the #PF frame's EFLAGS image is the value before the instruction, and the
; restarted instruction computes with the carry it started with.
;
; i486 PRM chapter 9: a fault is reported before the faulting instruction,
; which is restarted, so the state is that from before it began; 9.8.14
; (Interrupt 14): the saved CS:EIP point to the instruction that generated
; the page fault.  i486 PRM ADC pseudo-code: DEST <- DEST + SRC
; + CF; SBB: DEST <- DEST - (SRC + CF); RCL rotates through CF.  So with CF=1
; the restarted ADC still adds 1, and the frame carries the flags the POPFD
; loaded (i486 PRM POPF/POPFD), not the ADC's or its successor's result.
;
; Every target line but case 14's is read for the first time by the RMW
; itself (the data lives in this image and nothing touches it earlier), so
; the RMW read misses the L1, as in the lockstep reproducer; case 14 reads its
; line first (an L1 hit).  Each case runs on the core's free-running pipeline
; (no DR7 breakpoint is armed): a hardwired ALU m,imm recipe ends on its store
; word and its successor issues beside it, so the write's #PF arrives after
; that issue (the testbench's +expect_wr_fault_older counts those faults).
; The successors cover the kinds that issue behind the RMW: register CMP, a
; load, a load-CMP, an RMW.  The m,r, INC/NEG and RCL forms take routines
; that finish after their store and are checked alongside.

BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
CB          equ 0x00010000          ; CS base: this image's physical/linear base
RO_PAGE     equ CB + 0x3000         ; data page toggled read-only per case
RO_PTE      equ 0x1000 + (RO_PAGE >> 12) * 4
OTHER       equ CB + 0x4000         ; writable data the successors read
LOW_PAGE    equ 0x8000              ; reachable by 16-bit addressing (DS base 0)
LOW_PTE     equ 0x1000 + (LOW_PAGE >> 12) * 4
ALLSET      equ 0x8d7               ; OF SF ZF AF PF CF (+ reserved bit 1)
ALLCLR      equ 0x002
FMASK       equ 0x8d5               ; arithmetic flags compared in the frame

align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff     ; 0x08: code, base 0x00010000
    dq 0x00cf93000000ffff     ; 0x10: data, base 0
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd CB + gdt

pf_handler:
    push eax
    mov eax, [esp + 4]                  ; error code
    mov [CB + pf_err], eax
    mov eax, [esp + 8]                  ; faulting EIP
    mov [CB + pf_eip], eax
    mov eax, [esp + 16]                 ; EFLAGS image
    mov [CB + pf_flags], eax
    mov eax, cr2
    mov [CB + pf_cr2], eax
    inc dword [CB + pf_count]
    or dword [RO_PTE], 2                ; make both pages writable again
    or dword [LOW_PTE], 2
    invlpg [eax]
    pop eax
    add esp, 4                          ; discard the error code
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
    dd CB + idt

align 4
pf_count: dd 0
pf_err:   dd 0
pf_eip:   dd 0
pf_flags: dd 0
pf_cr2:   dd 0
case_id:  dd 0
nbad:     dd 0

; RMWCASE id, pte, address, flags image, {rmw}, {successor}
; PRECASE id, pte, address, POPFD image, {flag writer}, {rmw}, {successor},
;         expected frame flags: the flags come from an ALU instruction just
;         before the RMW, which issues in that instruction's last cycle.
; Marks the page read-only, loads the flags, runs rmw + successor, then checks
; the #PF the write took.  The result checks follow each use.
%macro RMWCASE 6
    mov dword [CB + case_id], %1
    and dword [%2], ~2
    invlpg [%3]
    mov edi, [CB + pf_count]
    push dword %4
    popfd
    jmp short %%rmw                     ; settle the POPFD before the pair
    align 16
%%rmw:
    %5
    %6
    nop
    nop
    inc edi
    cmp edi, [CB + pf_count]
    CHK 1
    cmp dword [CB + pf_eip], %%rmw - 0  ; EIP rewound to the RMW
    CHK 2
    cmp dword [CB + pf_err], 3          ; P=1 W=1 supervisor
    CHK 3
    cmp dword [CB + pf_cr2], %3
    CHK 4
    mov eax, [CB + pf_flags]
    and eax, FMASK
    cmp eax, (%4) & FMASK
    CHK 5
%endmacro

%macro PRECASE 8
    mov dword [CB + case_id], %1
    and dword [%2], ~2
    invlpg [%3]
    mov edi, [CB + pf_count]
    push dword %4
    popfd
    jmp short %%pre
    align 16
%%pre:
    %5
%%rmw:
    %6
    %7
    nop
    nop
    inc edi
    cmp edi, [CB + pf_count]
    CHK 1
    cmp dword [CB + pf_eip], %%rmw - 0
    CHK 2
    cmp dword [CB + pf_err], 3
    CHK 3
    cmp dword [CB + pf_cr2], %3
    CHK 4
    mov eax, [CB + pf_flags]
    and eax, FMASK
    cmp eax, (%8) & FMASK
    CHK 5
%endmacro

; CHK n: after a compare, report check n of the current case if it differs
; and go on, so one run shows every case.
%macro CHK 1
    je %%ok
    push dword %1
    call bad
%%ok:
%endmacro

times 0x200 - ($ - $$) db 0x90
start:
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    mov esp, 0x38000
    mov ecx, 0x00000041                 ; CL = 41h for the register forms

    ; 1: ADC r/m8, imm8 (80 /2), register-CMP successor
    RMWCASE 1, RO_PTE, RO_PAGE + 0x000, ALLSET, {adc byte [RO_PAGE + 0x000], 0x4d}, {cmp al, cl}
    cmp byte [RO_PAGE + 0x000], 0x10 + 0x4d + 1
    CHK 6

    ; 2: ADC r/m16, imm16 (66 81 /2), load successor
    RMWCASE 2, RO_PTE, RO_PAGE + 0x040, ALLSET, {adc word [RO_PAGE + 0x040], 0x1234}, {mov edx, [OTHER]}
    cmp word [RO_PAGE + 0x040], 0x1111 + 0x1234 + 1
    CHK 6
    cmp edx, 0xa5a55a5a
    CHK 6

    ; 3: ADC r/m32, imm8 (83 /2), load-CMP successor
    RMWCASE 3, RO_PTE, RO_PAGE + 0x080, ALLSET, {adc dword [RO_PAGE + 0x080], byte 0x7f}, {cmp [OTHER], cl}
    cmp dword [RO_PAGE + 0x080], 0x11111111 + 0x7f + 1
    CHK 6

    ; 4: ADC r/m32, imm32 with CF=0 that itself carries out: the restart
    ;    must not add the ADC's own carry
    RMWCASE 4, RO_PTE, RO_PAGE + 0x0c0, ALLCLR, {adc dword [RO_PAGE + 0x0c0], 0x00000001}, {cmp eax, ecx}
    cmp dword [RO_PAGE + 0x0c0], 0
    CHK 6

    ; 5: SBB r/m8, imm8, register-CMP successor
    RMWCASE 5, RO_PTE, RO_PAGE + 0x100, ALLSET, {sbb byte [RO_PAGE + 0x100], 0x01}, {cmp al, cl}
    cmp byte [RO_PAGE + 0x100], 0x10 - 0x01 - 1
    CHK 6

    ; 6: ADC r/m32, r32 (11 /r), load successor
    RMWCASE 6, RO_PTE, RO_PAGE + 0x140, ALLSET, {adc [RO_PAGE + 0x140], ecx}, {mov edx, [OTHER]}
    cmp dword [RO_PAGE + 0x140], 0x22222222 + 0x41 + 1
    CHK 6

    ; 7: ADC r/m8, r8 (10 /r), register-CMP successor
    RMWCASE 7, RO_PTE, RO_PAGE + 0x180, ALLSET, {adc [RO_PAGE + 0x180], cl}, {cmp al, cl}
    cmp byte [RO_PAGE + 0x180], 0x10 + 0x41 + 1
    CHK 6

    ; 8: ADC r/m16, r16 (66 11 /r), load-CMP successor
    RMWCASE 8, RO_PTE, RO_PAGE + 0x1c0, ALLSET, {adc [RO_PAGE + 0x1c0], cx}, {cmp [OTHER], cl}
    cmp word [RO_PAGE + 0x1c0], 0x1111 + 0x41 + 1
    CHK 6

    ; 9: 16-bit addressing (67 80 /2 [bx+si+d8]), register-CMP successor
    mov ebx, 0x6000
    mov esi, 0x2010                     ; bx+si+52h = 8062h
    RMWCASE 9, LOW_PTE, LOW_PAGE + 0x062, ALLSET, {adc byte [bx+si+0x52], 0x4d}, {cmp al, cl}
    cmp byte [LOW_PAGE + 0x062], 0x00 + 0x4d + 1
    CHK 6

    ; 10: INC r/m32 (FF /0): preserves CF, writes ZF/SF/OF/AF/PF
    RMWCASE 10, RO_PTE, RO_PAGE + 0x200, ALLSET, {inc dword [RO_PAGE + 0x200]}, {cmp al, cl}
    cmp dword [RO_PAGE + 0x200], 0x33333334
    CHK 6

    ; 11: NEG r/m8 (F6 /3) with CF=0: NEG of a nonzero value sets CF
    RMWCASE 11, RO_PTE, RO_PAGE + 0x240, ALLCLR, {neg byte [RO_PAGE + 0x240]}, {mov edx, [OTHER]}
    cmp byte [RO_PAGE + 0x240], 0xf0
    CHK 6

    ; 12: RCL r/m32, 1 (D1 /2) with CF=1
    RMWCASE 12, RO_PTE, RO_PAGE + 0x280, ALLSET, {rcl dword [RO_PAGE + 0x280], 1}, {cmp al, cl}
    cmp dword [RO_PAGE + 0x280], 0x80000001
    CHK 6

    ; 13: ADC r/m8, imm8 with an RMW successor
    RMWCASE 13, RO_PTE, RO_PAGE + 0x2c0, ALLSET, {adc byte [RO_PAGE + 0x2c0], 0x4d}, {add [OTHER + 0x40], cl}
    cmp byte [RO_PAGE + 0x2c0], 0x10 + 0x4d + 1
    CHK 6
    cmp byte [OTHER + 0x40], 0x41
    CHK 6

    ; 14: ADC r/m32, imm8 whose line was read before (L1 hit), load successor
    mov eax, [RO_PAGE + 0x300]
    RMWCASE 14, RO_PTE, RO_PAGE + 0x300, ALLSET, {adc dword [RO_PAGE + 0x300], byte 0x01}, {mov edx, [OTHER]}
    cmp dword [RO_PAGE + 0x300], 0x44444444 + 0x01 + 1
    CHK 6

    ; 15: the lockstep reproducer's order: SUB AL,imm sets CF and the ADC
    ;     follows at once.  5Ah - 0A5h = 0B5h: CF=1 (borrow), OF=1 (positive
    ;     minus negative gave negative), SF=1, ZF=0, AF=0 (0Ah >= 5), PF=0
    ;     (five bits set) -> 0883h (i486 PRM SUB / Appendix C flag rules)
    mov eax, 0x5a
    PRECASE 15, RO_PTE, RO_PAGE + 0x340, ALLCLR, {sub al, 0xa5}, {adc byte [RO_PAGE + 0x340], 0x4d}, {cmp al, cl}, 0x883
    cmp byte [RO_PAGE + 0x340], 0x10 + 0x4d + 1
    CHK 6

    ; 16: the same with SBB r/m16, imm8 and a load successor
    mov eax, 0x5a
    PRECASE 16, RO_PTE, RO_PAGE + 0x380, ALLCLR, {sub al, 0xa5}, {sbb word [RO_PAGE + 0x380], byte 0x01}, {mov edx, [OTHER]}, 0x883
    cmp word [RO_PAGE + 0x380], 0x1111 - 0x01 - 1
    CHK 6

    mov dword [CB + case_id], 0
    cmp dword [CB + pf_count], 16
    CHK 1
    cmp dword [CB + nbad], 0
    jne fail
    mov al, 1
    out STATUS_PORT, al
    hlt

; bad: DATA_PORT gets case id << 8 | check (1 #PF count, 2 frame EIP,
; 3 error code, 4 CR2, 5 frame flags, 6 result), then the frame's EFLAGS image
bad:
    pushad
    mov eax, [CB + case_id]
    shl eax, 8
    or eax, [esp + 36]
    out DATA_PORT, eax
    mov eax, [CB + pf_flags]
    out DATA_PORT, eax
    inc dword [CB + nbad]
    popad
    ret 4

fail:
    mov al, 0xff
    out STATUS_PORT, al
    hlt

; The data lines: in this image so the first access to each is the RMW's own.
times 0x3000 - ($ - $$) db 0
    db 0x10                              ; +000
    times 0x040 - ($ - $$ - 0x3000) db 0
    dw 0x1111                            ; +040
    times 0x080 - ($ - $$ - 0x3000) db 0
    dd 0x11111111                        ; +080
    times 0x0c0 - ($ - $$ - 0x3000) db 0
    dd 0xffffffff                        ; +0C0
    times 0x100 - ($ - $$ - 0x3000) db 0
    db 0x10                              ; +100
    times 0x140 - ($ - $$ - 0x3000) db 0
    dd 0x22222222                        ; +140
    times 0x180 - ($ - $$ - 0x3000) db 0
    db 0x10                              ; +180
    times 0x1c0 - ($ - $$ - 0x3000) db 0
    dw 0x1111                            ; +1C0
    times 0x200 - ($ - $$ - 0x3000) db 0
    dd 0x33333333                        ; +200
    times 0x240 - ($ - $$ - 0x3000) db 0
    db 0x10                              ; +240
    times 0x280 - ($ - $$ - 0x3000) db 0
    dd 0x40000000                        ; +280
    times 0x2c0 - ($ - $$ - 0x3000) db 0
    db 0x10                              ; +2C0
    times 0x300 - ($ - $$ - 0x3000) db 0
    dd 0x44444444                        ; +300
    times 0x340 - ($ - $$ - 0x3000) db 0
    db 0x10                              ; +340
    times 0x380 - ($ - $$ - 0x3000) db 0
    dw 0x1111                            ; +380
times 0x4000 - ($ - $$) db 0
    dd 0xa5a55a5a                        ; OTHER
times 0x5000 - ($ - $$) db 0
