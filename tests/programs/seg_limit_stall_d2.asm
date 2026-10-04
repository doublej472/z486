; seg_limit_stall_d2.asm - a limit-violating direct load must #GP even when
; its successor holds stall_d2 (split EA) for the load's whole life, and
; RD_FAST RMWs behind stores/IO must #GP.
;
; ES limit 0x1F. Cases 1-20: mov edx,[es:0x1d] then split-EA successors;
; 21+: an older store/OUT then an RMW to ES:0x1d.
;
; Port 0xE0: 0x01 pass / 0xFF fail; on fail 0xE4 = three bitmasks.

BITS 32
ORG 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

VAL       equ 0x5A5A1234

gp_handler:
    add esp, 4                  ; error code
    mov edx, [ss:esp]           ; faulting EIP
    mov [ds:0xF00], edx
    mov [ds:0xF04], ecx
    mov edx, [ds:0xF08]         ; continuation
    mov [ss:esp], edx
    iretd

align 8
gdt:
    dq 0
    dq 0x00cf9b010000ffff
    dq 0x00cf93040000ffff
    dq 0x00cf93030000ffff
gdt_end:
gdt_desc:
    dw gdt_end - gdt - 1
    dd 0x00010000 + gdt

align 8
idt:
    times 13 dq 0
    dw gp_handler
    dw 0x0008
    db 0
    db 0x8e
    dw 0
    times 2 dq 0
idt_end:
idt_desc:
    dw idt_end - idt - 1
    dd 0x00010000 + idt





times 0x200 - ($ - $$) db 0x90
start:
    mov dword [ds:0x100], VAL
    cli
    lgdt [cs:gdt_desc]
    lidt [cs:idt_desc]
    mov esp, 0x00000F00
    mov dword [ds:0xF10], 0
    mov dword [ds:0xF14], 0
    mov dword [ds:0xF1C], 0
    mov ebp, 0
pass_top:

    ; case 1: faulting hot load then "mov ecx, [edx+edx*2+0x10]" pad 0
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c1_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 0 nop
c1_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    mov ecx, [edx+edx*2+0x10]
c1_after:
    mov edx, c1_probe
    mov esi, 1
    call check

    ; case 2: faulting hot load then "mov ecx, [edx+edx*2+0x10]" pad 1
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c2_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 1 nop
c2_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    mov ecx, [edx+edx*2+0x10]
c2_after:
    mov edx, c2_probe
    mov esi, 2
    call check

    ; case 3: faulting hot load then "mov ecx, [edx+edx*2+0x10]" pad 2
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c3_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 2 nop
c3_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    mov ecx, [edx+edx*2+0x10]
c3_after:
    mov edx, c3_probe
    mov esi, 3
    call check

    ; case 4: faulting hot load then "mov ecx, [edx+edx*2+0x10]" pad 3
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c4_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 3 nop
c4_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    mov ecx, [edx+edx*2+0x10]
c4_after:
    mov edx, c4_probe
    mov esi, 4
    call check

    ; case 5: faulting hot load then "mov ecx, [ebx+esi*4+0x10]" pad 0
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c5_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 0 nop
c5_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    mov ecx, [ebx+esi*4+0x10]
c5_after:
    mov edx, c5_probe
    mov esi, 5
    call check

    ; case 6: faulting hot load then "mov ecx, [ebx+esi*4+0x10]" pad 1
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c6_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 1 nop
c6_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    mov ecx, [ebx+esi*4+0x10]
c6_after:
    mov edx, c6_probe
    mov esi, 6
    call check

    ; case 7: faulting hot load then "mov ecx, [ebx+esi*4+0x10]" pad 2
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c7_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 2 nop
c7_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    mov ecx, [ebx+esi*4+0x10]
c7_after:
    mov edx, c7_probe
    mov esi, 7
    call check

    ; case 8: faulting hot load then "mov ecx, [ebx+esi*4+0x10]" pad 3
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c8_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 3 nop
c8_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    mov ecx, [ebx+esi*4+0x10]
c8_after:
    mov edx, c8_probe
    mov esi, 8
    call check

    ; case 9: faulting hot load then "add ecx, [edx+0x10]" pad 0
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c9_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 0 nop
c9_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    add ecx, [edx+0x10]
c9_after:
    mov edx, c9_probe
    mov esi, 9
    call check

    ; case 10: faulting hot load then "add ecx, [edx+0x10]" pad 1
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c10_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 1 nop
c10_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    add ecx, [edx+0x10]
c10_after:
    mov edx, c10_probe
    mov esi, 10
    call check

    ; case 11: faulting hot load then "add ecx, [edx+0x10]" pad 2
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c11_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 2 nop
c11_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    add ecx, [edx+0x10]
c11_after:
    mov edx, c11_probe
    mov esi, 11
    call check

    ; case 12: faulting hot load then "add ecx, [edx+0x10]" pad 3
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c12_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 3 nop
c12_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    add ecx, [edx+0x10]
c12_after:
    mov edx, c12_probe
    mov esi, 12
    call check

    ; case 13: faulting hot load then "mov ecx, [edx]" pad 0
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c13_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 0 nop
c13_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    mov ecx, [edx]
c13_after:
    mov edx, c13_probe
    mov esi, 13
    call check

    ; case 14: faulting hot load then "mov ecx, [edx]" pad 1
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c14_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 1 nop
c14_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    mov ecx, [edx]
c14_after:
    mov edx, c14_probe
    mov esi, 14
    call check

    ; case 15: faulting hot load then "mov ecx, [edx]" pad 2
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c15_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 2 nop
c15_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    mov ecx, [edx]
c15_after:
    mov edx, c15_probe
    mov esi, 15
    call check

    ; case 16: faulting hot load then "mov ecx, [edx]" pad 3
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c16_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 3 nop
c16_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    mov ecx, [edx]
c16_after:
    mov edx, c16_probe
    mov esi, 16
    call check

    ; case 17: faulting hot load then "mov dword [ds:0xF40], 0x12345678" pad 0
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c17_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 0 nop
c17_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    mov dword [ds:0xF40], 0x12345678
c17_after:
    mov edx, c17_probe
    mov esi, 17
    call check

    ; case 18: faulting hot load then "mov dword [ds:0xF40], 0x12345678" pad 1
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c18_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 1 nop
c18_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    mov dword [ds:0xF40], 0x12345678
c18_after:
    mov edx, c18_probe
    mov esi, 18
    call check

    ; case 19: faulting hot load then "mov dword [ds:0xF40], 0x12345678" pad 2
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c19_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 2 nop
c19_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    mov dword [ds:0xF40], 0x12345678
c19_after:
    mov edx, c19_probe
    mov esi, 19
    call check

    ; case 20: faulting hot load then "mov dword [ds:0xF40], 0x12345678" pad 3
    mov ecx, VAL
    mov eax, [ds:0x1c]          ; warm the line holding ES:0x20
    mov dword [ds:0xF08], c20_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    xor esi, esi
    mov edx, 0x100
    imul edi, edi
    imul edi, edi
    imul edi, edi
    times 3 nop
c20_probe:
    mov edx, [es:ebx]           ; 0x1d..0x20 crosses limit 0x1f: #GP
    mov dword [ds:0xF40], 0x12345678
c20_after:
    mov edx, c20_probe
    mov esi, 20
    call check


    ; case 21: "mov [ds:0x200], ecx" then RMW "inc dword [es:ebx]" pad 0
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c21_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 0 nop
    mov [ds:0x200], ecx
c21_probe:
    inc dword [es:ebx]
c21_after:
    mov edx, c21_probe
    mov esi, 21
    call check

    ; case 22: "mov [ds:0x200], ecx" then RMW "inc dword [es:ebx]" pad 1
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c22_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 1 nop
    mov [ds:0x200], ecx
c22_probe:
    inc dword [es:ebx]
c22_after:
    mov edx, c22_probe
    mov esi, 22
    call check

    ; case 23: "mov [ds:0x200], ecx" then RMW "add [es:ebx], ecx" pad 0
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c23_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 0 nop
    mov [ds:0x200], ecx
c23_probe:
    add [es:ebx], ecx
c23_after:
    mov edx, c23_probe
    mov esi, 23
    call check

    ; case 24: "mov [ds:0x200], ecx" then RMW "add [es:ebx], ecx" pad 1
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c24_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 1 nop
    mov [ds:0x200], ecx
c24_probe:
    add [es:ebx], ecx
c24_after:
    mov edx, c24_probe
    mov esi, 24
    call check

    ; case 25: "mov [ds:0x200], ecx" then RMW "not byte [es:ebx+3]" pad 0
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c25_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 0 nop
    mov [ds:0x200], ecx
c25_probe:
    not byte [es:ebx+3]
c25_after:
    mov edx, c25_probe
    mov esi, 25
    call check

    ; case 26: "mov [ds:0x200], ecx" then RMW "not byte [es:ebx+3]" pad 1
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c26_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 1 nop
    mov [ds:0x200], ecx
c26_probe:
    not byte [es:ebx+3]
c26_after:
    mov edx, c26_probe
    mov esi, 26
    call check

    ; case 27: "mov [ds:edi], ecx" then RMW "inc dword [es:ebx]" pad 0
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c27_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 0 nop
    mov [ds:edi], ecx
c27_probe:
    inc dword [es:ebx]
c27_after:
    mov edx, c27_probe
    mov esi, 27
    call check

    ; case 28: "mov [ds:edi], ecx" then RMW "inc dword [es:ebx]" pad 1
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c28_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 1 nop
    mov [ds:edi], ecx
c28_probe:
    inc dword [es:ebx]
c28_after:
    mov edx, c28_probe
    mov esi, 28
    call check

    ; case 29: "mov [ds:edi], ecx" then RMW "add [es:ebx], ecx" pad 0
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c29_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 0 nop
    mov [ds:edi], ecx
c29_probe:
    add [es:ebx], ecx
c29_after:
    mov edx, c29_probe
    mov esi, 29
    call check

    ; case 30: "mov [ds:edi], ecx" then RMW "add [es:ebx], ecx" pad 1
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c30_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 1 nop
    mov [ds:edi], ecx
c30_probe:
    add [es:ebx], ecx
c30_after:
    mov edx, c30_probe
    mov esi, 30
    call check

    ; case 31: "mov [ds:edi], ecx" then RMW "not byte [es:ebx+3]" pad 0
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c31_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 0 nop
    mov [ds:edi], ecx
c31_probe:
    not byte [es:ebx+3]
c31_after:
    mov edx, c31_probe
    mov esi, 31
    call check

    ; case 32: "mov [ds:edi], ecx" then RMW "not byte [es:ebx+3]" pad 1
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c32_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 1 nop
    mov [ds:edi], ecx
c32_probe:
    not byte [es:ebx+3]
c32_after:
    mov edx, c32_probe
    mov esi, 32
    call check

    ; case 33: "out 0x80, al" then RMW "inc dword [es:ebx]" pad 0
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c33_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 0 nop
    out 0x80, al
c33_probe:
    inc dword [es:ebx]
c33_after:
    mov edx, c33_probe
    mov esi, 33
    call check

    ; case 34: "out 0x80, al" then RMW "inc dword [es:ebx]" pad 1
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c34_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 1 nop
    out 0x80, al
c34_probe:
    inc dword [es:ebx]
c34_after:
    mov edx, c34_probe
    mov esi, 34
    call check

    ; case 35: "out 0x80, al" then RMW "add [es:ebx], ecx" pad 0
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c35_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 0 nop
    out 0x80, al
c35_probe:
    add [es:ebx], ecx
c35_after:
    mov edx, c35_probe
    mov esi, 35
    call check

    ; case 36: "out 0x80, al" then RMW "add [es:ebx], ecx" pad 1
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c36_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 1 nop
    out 0x80, al
c36_probe:
    add [es:ebx], ecx
c36_after:
    mov edx, c36_probe
    mov esi, 36
    call check

    ; case 37: "out 0x80, al" then RMW "not byte [es:ebx+3]" pad 0
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c37_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 0 nop
    out 0x80, al
c37_probe:
    not byte [es:ebx+3]
c37_after:
    mov edx, c37_probe
    mov esi, 37
    call check

    ; case 38: "out 0x80, al" then RMW "not byte [es:ebx+3]" pad 1
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c38_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 1 nop
    out 0x80, al
c38_probe:
    not byte [es:ebx+3]
c38_after:
    mov edx, c38_probe
    mov esi, 38
    call check

    ; case 39: "mov [ss:esp-8], ecx" then RMW "inc dword [es:ebx]" pad 0
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c39_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 0 nop
    mov [ss:esp-8], ecx
c39_probe:
    inc dword [es:ebx]
c39_after:
    mov edx, c39_probe
    mov esi, 39
    call check

    ; case 40: "mov [ss:esp-8], ecx" then RMW "inc dword [es:ebx]" pad 1
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c40_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 1 nop
    mov [ss:esp-8], ecx
c40_probe:
    inc dword [es:ebx]
c40_after:
    mov edx, c40_probe
    mov esi, 40
    call check

    ; case 41: "mov [ss:esp-8], ecx" then RMW "add [es:ebx], ecx" pad 0
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c41_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 0 nop
    mov [ss:esp-8], ecx
c41_probe:
    add [es:ebx], ecx
c41_after:
    mov edx, c41_probe
    mov esi, 41
    call check

    ; case 42: "mov [ss:esp-8], ecx" then RMW "add [es:ebx], ecx" pad 1
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c42_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 1 nop
    mov [ss:esp-8], ecx
c42_probe:
    add [es:ebx], ecx
c42_after:
    mov edx, c42_probe
    mov esi, 42
    call check

    ; case 43: "mov [ss:esp-8], ecx" then RMW "not byte [es:ebx+3]" pad 0
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c43_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 0 nop
    mov [ss:esp-8], ecx
c43_probe:
    not byte [es:ebx+3]
c43_after:
    mov edx, c43_probe
    mov esi, 43
    call check

    ; case 44: "mov [ss:esp-8], ecx" then RMW "not byte [es:ebx+3]" pad 1
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c44_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 1 nop
    mov [ss:esp-8], ecx
c44_probe:
    not byte [es:ebx+3]
c44_after:
    mov edx, c44_probe
    mov esi, 44
    call check

    ; case 45: "nop" then RMW "inc dword [es:ebx]" pad 0
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c45_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 0 nop
    nop
c45_probe:
    inc dword [es:ebx]
c45_after:
    mov edx, c45_probe
    mov esi, 45
    call check

    ; case 46: "nop" then RMW "inc dword [es:ebx]" pad 1
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c46_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 1 nop
    nop
c46_probe:
    inc dword [es:ebx]
c46_after:
    mov edx, c46_probe
    mov esi, 46
    call check

    ; case 47: "nop" then RMW "add [es:ebx], ecx" pad 0
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c47_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 0 nop
    nop
c47_probe:
    add [es:ebx], ecx
c47_after:
    mov edx, c47_probe
    mov esi, 47
    call check

    ; case 48: "nop" then RMW "add [es:ebx], ecx" pad 1
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c48_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 1 nop
    nop
c48_probe:
    add [es:ebx], ecx
c48_after:
    mov edx, c48_probe
    mov esi, 48
    call check

    ; case 49: "nop" then RMW "not byte [es:ebx+3]" pad 0
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c49_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 0 nop
    nop
c49_probe:
    not byte [es:ebx+3]
c49_after:
    mov edx, c49_probe
    mov esi, 49
    call check

    ; case 50: "nop" then RMW "not byte [es:ebx+3]" pad 1
    mov eax, [ds:0x1c]
    mov edi, 0x200
    mov dword [ds:0xF08], c50_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x1d
    imul esi, esi
    imul esi, esi
    times 1 nop
    nop
c50_probe:
    not byte [es:ebx+3]
c50_after:
    mov edx, c50_probe
    mov esi, 50
    call check
    add ebp, 0x1000
    cmp ebp, 0x3000
    jb pass_top
    mov eax, [ds:0xF10]
    or eax, [ds:0xF14]
    or eax, [ds:0xF1C]
    jnz fail_final
    mov al, 0x01
    mov dx, STATUS_PORT
    out dx, al
    hlt
fail_final:
    mov eax, [ds:0xF10]
    mov dx, DATA_PORT
    out dx, eax
    mov eax, [ds:0xF14]
    out dx, eax
    mov eax, [ds:0xF1C]
    out dx, eax
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
    hlt

; edx = expected faulting EIP, esi = case. Records bit (case-1) in F10 for
; "older ECX lost" and in F14 for "no/wrong fault".
check:
    mov eax, [ds:0xF00]
    cmp eax, edx
    jne .badfault
    mov eax, [ds:0xF04]
    cmp eax, VAL
    jne .badecx
    ret
.badfault:
    lea ecx, [esi-1]
    mov eax, 1
    shl eax, cl
    cmp esi, 32
    ja .bf2
    or [ds:0xF14], eax
    ret
.bf2:
    or [ds:0xF1C], eax
    ret
.badecx:
    lea ecx, [esi-1]
    mov eax, 1
    shl eax, cl
    or [ds:0xF10], eax
    ret

times 0x2000 - ($ - $$) db 0
