; esc_db6_mem - ESC DB /6 with a memory operand is an ESC like any other
;
; DB /6 m (2nd byte mod != 11, reg = 110) is one of the ESC 3 encodings the
; i486 PRM defines no instruction for: its FPU instruction encoding table
; (Appendix/Chapter 26, "Floating-Point Instruction Formats") lists DB /0, /2,
; /3, /5 and /7 memory forms only, like /1 and /4.  It is still an ESC
; instruction (opcode 11011xxx), so the PRM's ESC rules apply to it:
;   9.9.7 Interrupt 7 - Device Not Available: "The processor executes an ESC
;   instruction, and the EM bit of the CR0 register is set" / "... ESC
;   instruction, and the TS bit of the CR0 register is set" -> #NM (vector 7),
;   a fault, CS:EIP naming the ESC, no error code.
; With EM=TS=0 it must complete like its neighbours DB /1 m and DB /4 m: no
; #UD (Table 9-3's note), execution continues after the full instruction
; (ModR/M + SIB + disp32 here), no GPR, ESP or memory change.  In no case may
; it run the reset microcode (CS=F000, EIP=FFF0), which it did when the
; second-level PLA word for {DB group, reg 6, memory} was 000.
;
; Results: port 0xE0 status (0x01 pass / 0xFF fail), port 0xE4 fail code.
BITS 32
ORG 0
align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff     ; 08: code, base 0x10000
    dq 0x00cf93020000ffff     ; 10: data, base 0x20000
    dq 0x00cf93030000ffff     ; 18: stack, base 0x30000
gdt_end:
gdtr: dw gdt_end-gdt-1
      dd 0x10000+gdt
align 8
idt:
    times 6 dq 0
    dw ud_handler, 8          ; 6: #UD -> fail
    db 0, 0x8e
    dw 0
    dw nm_handler, 8          ; 7: #NM
    db 0, 0x8e
    dw 0
    times 5 dq 0
    dw gp_handler, 8          ; 13: #GP -> fail
    db 0, 0x8e
    dw 0
idt_end:
idtr: dw idt_end-idt-1
      dd 0x10000+idt

; #NM: the frame names the ESC (a fault), CS = 8.  Count it, clear EM and TS
; so the ESC re-executes, and return to it.
nm_handler:
    mov edx, 0x20
    cmp dword [ss:esp], ecx   ; ECX = the expected faulting EIP
    jne fail_edx
    mov edx, 0x21
    cmp dword [ss:esp+4], 8
    jne fail_edx
    inc ebp
    push eax
    mov eax, cr0
    and eax, ~0xc             ; clear TS (bit 3) and EM (bit 2)
    mov cr0, eax
    pop eax
    iretd

ud_handler:
    mov edx, 0x30
    jmp fail_edx
gp_handler:
    mov edx, 0x31
fail_edx:
    mov edi, edx
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
    mov dword [0x800], 0x96969696
    mov dword [0x804], 0xa5a5a5a5
    mov dword [0x808], 0x5a5a5a5a
    mov dword [0x80c], 0x3c3c3c3c

    ; 1. EM=1: #NM once, then (EM cleared by the handler) the ESC completes.
    xor ebp, ebp
    mov eax, 0x11223344
    mov ebx, 0x55667788
    mov esi, 0x800
    mov edi, 1
    mov ecx, cr0
    or ecx, 4                 ; EM
    mov cr0, ecx
    mov ecx, esc_em
esc_em:
    db 0xdb, 0x36             ; DB /6 [esi]
    mov edi, 2
    cmp ebp, 1
    jne fail
    call check_state

    ; 2. TS=1, EM=0: #NM once, then the ESC completes.
    xor ebp, ebp
    mov edi, 3
    mov ecx, cr0
    or ecx, 8                 ; TS
    mov cr0, ecx
    mov ecx, esc_ts
esc_ts:
    db 0xdb, 0x74, 0x26, 0x04 ; DB /6 [esi+4] (SIB form, disp8)
    mov edi, 4
    cmp ebp, 1
    jne fail
    call check_state

    ; 3. EM=TS=0: no exception at all; the full 7-byte form falls through.
    mov edi, 5
    mov ecx, 0
esc_clear:
    db 0xdb, 0xb4, 0x26       ; DB /6 [esi+disp32]
    dd 8
    mov edi, 6
    cmp ebp, 1                ; no further #NM
    jne fail
    call check_state

    ; 4. Its neighbours DB /1 m and DB /4 m, for comparison: no exception.
    mov edi, 7
    db 0xdb, 0x0e             ; DB /1 [esi]
    db 0xdb, 0x66, 0x0c       ; DB /4 [esi+0Ch]
    mov edi, 8
    cmp ebp, 1
    jne fail
    call check_state

    mov al, 1
    out 0xe0, al
    hlt

; Every ESC above leaves the GPRs, the stack and its operand bytes as they were.
check_state:
    mov edx, 0x10
    cmp eax, 0x11223344
    jne fail_edx
    mov edx, 0x11
    cmp ebx, 0x55667788
    jne fail_edx
    mov edx, 0x12
    cmp esi, 0x800
    jne fail_edx
    mov edx, 0x13
    cmp esp, 0xf00-4          ; the CALL's return address only
    jne fail_edx
    mov edx, 0x17
    cmp dword [0x800], 0x96969696
    jne fail_edx
    mov edx, 0x14
    cmp dword [0x804], 0xa5a5a5a5
    jne fail_edx
    mov edx, 0x15
    cmp dword [0x808], 0x5a5a5a5a
    jne fail_edx
    mov edx, 0x16
    cmp dword [0x80c], 0x3c3c3c3c
    jne fail_edx
    ret
