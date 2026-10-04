; seg_limit_older_commit.asm - a younger faulting direct load must not take
; down an older in-limit load still in the pipe.
;
; ES limit 0x1F; [es:ebx] with ebx=0x20 faults. Each case runs an older access
; (hot/cold load; stores/RMW/push-pop in 17+) before the faulting load. Hot: the
; fault cancelled the older WB commit (ECX lost); cold: the replay token's
; verdict fired while the older submitted (fault lost).
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
    mov ebp, 0                  ; pass offset (cold lines differ per pass)
pass_top:

    ; case 1: mov hot pad 0
    mov edi, 0x100
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c1_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ecx, 0
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 0 nop
    mov ecx, [ds:edi]
c1_probe:
    mov al, [es:ebx]
c1_after:
    mov edx, c1_probe
    mov esi, 1
    call check

    ; case 2: mov hot pad 1
    mov edi, 0x100
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c2_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ecx, 0
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 1 nop
    mov ecx, [ds:edi]
c2_probe:
    mov al, [es:ebx]
c2_after:
    mov edx, c2_probe
    mov esi, 2
    call check

    ; case 3: mov hot pad 2
    mov edi, 0x100
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c3_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ecx, 0
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 2 nop
    mov ecx, [ds:edi]
c3_probe:
    mov al, [es:ebx]
c3_after:
    mov edx, c3_probe
    mov esi, 3
    call check

    ; case 4: mov hot pad 3
    mov edi, 0x100
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c4_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ecx, 0
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 3 nop
    mov ecx, [ds:edi]
c4_probe:
    mov al, [es:ebx]
c4_after:
    mov edx, c4_probe
    mov esi, 4
    call check

    ; case 5: mov cold pad 0
    lea edi, [ebp+0x8140]
    mov dword [ds:edi], VAL
    mov dword [ds:0xF08], c5_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ecx, 0
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 0 nop
    mov ecx, [ds:edi]
c5_probe:
    mov al, [es:ebx]
c5_after:
    mov edx, c5_probe
    mov esi, 5
    call check

    ; case 6: mov cold pad 1
    lea edi, [ebp+0x8180]
    mov dword [ds:edi], VAL
    mov dword [ds:0xF08], c6_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ecx, 0
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 1 nop
    mov ecx, [ds:edi]
c6_probe:
    mov al, [es:ebx]
c6_after:
    mov edx, c6_probe
    mov esi, 6
    call check

    ; case 7: mov cold pad 2
    lea edi, [ebp+0x81c0]
    mov dword [ds:edi], VAL
    mov dword [ds:0xF08], c7_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ecx, 0
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 2 nop
    mov ecx, [ds:edi]
c7_probe:
    mov al, [es:ebx]
c7_after:
    mov edx, c7_probe
    mov esi, 7
    call check

    ; case 8: mov cold pad 3
    lea edi, [ebp+0x8200]
    mov dword [ds:edi], VAL
    mov dword [ds:0xF08], c8_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ecx, 0
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 3 nop
    mov ecx, [ds:edi]
c8_probe:
    mov al, [es:ebx]
c8_after:
    mov edx, c8_probe
    mov esi, 8
    call check

    ; case 9: add hot pad 0
    mov edi, 0x100
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c9_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ecx, 0
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 0 nop
    add ecx, [ds:edi]
c9_probe:
    mov al, [es:ebx]
c9_after:
    mov edx, c9_probe
    mov esi, 9
    call check

    ; case 10: add hot pad 1
    mov edi, 0x100
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c10_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ecx, 0
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 1 nop
    add ecx, [ds:edi]
c10_probe:
    mov al, [es:ebx]
c10_after:
    mov edx, c10_probe
    mov esi, 10
    call check

    ; case 11: add hot pad 2
    mov edi, 0x100
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c11_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ecx, 0
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 2 nop
    add ecx, [ds:edi]
c11_probe:
    mov al, [es:ebx]
c11_after:
    mov edx, c11_probe
    mov esi, 11
    call check

    ; case 12: add hot pad 3
    mov edi, 0x100
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c12_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ecx, 0
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 3 nop
    add ecx, [ds:edi]
c12_probe:
    mov al, [es:ebx]
c12_after:
    mov edx, c12_probe
    mov esi, 12
    call check

    ; case 13: add cold pad 0
    lea edi, [ebp+0x8340]
    mov dword [ds:edi], VAL
    mov dword [ds:0xF08], c13_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ecx, 0
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 0 nop
    add ecx, [ds:edi]
c13_probe:
    mov al, [es:ebx]
c13_after:
    mov edx, c13_probe
    mov esi, 13
    call check

    ; case 14: add cold pad 1
    lea edi, [ebp+0x8380]
    mov dword [ds:edi], VAL
    mov dword [ds:0xF08], c14_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ecx, 0
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 1 nop
    add ecx, [ds:edi]
c14_probe:
    mov al, [es:ebx]
c14_after:
    mov edx, c14_probe
    mov esi, 14
    call check

    ; case 15: add cold pad 2
    lea edi, [ebp+0x83c0]
    mov dword [ds:edi], VAL
    mov dword [ds:0xF08], c15_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ecx, 0
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 2 nop
    add ecx, [ds:edi]
c15_probe:
    mov al, [es:ebx]
c15_after:
    mov edx, c15_probe
    mov esi, 15
    call check

    ; case 16: add cold pad 3
    lea edi, [ebp+0x8400]
    mov dword [ds:edi], VAL
    mov dword [ds:0xF08], c16_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ecx, 0
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 3 nop
    add ecx, [ds:edi]
c16_probe:
    mov al, [es:ebx]
c16_after:
    mov edx, c16_probe
    mov esi, 16
    call check


    ; case 17: store-type older "mov [ds:edi], ecx" hot pad 0
    mov edi, 0x200
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c17_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 0 nop
    mov [ds:edi], ecx
c17_probe:
    mov al, [es:ebx]
c17_after:
    mov edx, c17_probe
    mov esi, 17
    call check

    ; case 18: store-type older "mov [ds:edi], ecx" hot pad 1
    mov edi, 0x200
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c18_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 1 nop
    mov [ds:edi], ecx
c18_probe:
    mov al, [es:ebx]
c18_after:
    mov edx, c18_probe
    mov esi, 18
    call check

    ; case 19: store-type older "mov [ds:edi], ecx" hot pad 2
    mov edi, 0x200
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c19_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 2 nop
    mov [ds:edi], ecx
c19_probe:
    mov al, [es:ebx]
c19_after:
    mov edx, c19_probe
    mov esi, 19
    call check

    ; case 20: store-type older "mov [ds:edi], ecx" cold pad 0
    lea edi, [ebp+0xc500]
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c20_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 0 nop
    mov [ds:edi], ecx
c20_probe:
    mov al, [es:ebx]
c20_after:
    mov edx, c20_probe
    mov esi, 20
    call check

    ; case 21: store-type older "mov [ds:edi], ecx" cold pad 1
    lea edi, [ebp+0xc540]
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c21_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 1 nop
    mov [ds:edi], ecx
c21_probe:
    mov al, [es:ebx]
c21_after:
    mov edx, c21_probe
    mov esi, 21
    call check

    ; case 22: store-type older "mov [ds:edi], ecx" cold pad 2
    lea edi, [ebp+0xc580]
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c22_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 2 nop
    mov [ds:edi], ecx
c22_probe:
    mov al, [es:ebx]
c22_after:
    mov edx, c22_probe
    mov esi, 22
    call check

    ; case 23: store-type older "mov [ds:edi], cl" hot pad 0
    mov edi, 0x200
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c23_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 0 nop
    mov [ds:edi], cl
c23_probe:
    mov al, [es:ebx]
c23_after:
    mov edx, c23_probe
    mov esi, 23
    call check

    ; case 24: store-type older "mov [ds:edi], cl" hot pad 1
    mov edi, 0x200
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c24_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 1 nop
    mov [ds:edi], cl
c24_probe:
    mov al, [es:ebx]
c24_after:
    mov edx, c24_probe
    mov esi, 24
    call check

    ; case 25: store-type older "mov [ds:edi], cl" hot pad 2
    mov edi, 0x200
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c25_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 2 nop
    mov [ds:edi], cl
c25_probe:
    mov al, [es:ebx]
c25_after:
    mov edx, c25_probe
    mov esi, 25
    call check

    ; case 26: store-type older "mov [ds:edi], cl" cold pad 0
    lea edi, [ebp+0xc680]
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c26_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 0 nop
    mov [ds:edi], cl
c26_probe:
    mov al, [es:ebx]
c26_after:
    mov edx, c26_probe
    mov esi, 26
    call check

    ; case 27: store-type older "mov [ds:edi], cl" cold pad 1
    lea edi, [ebp+0xc6c0]
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c27_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 1 nop
    mov [ds:edi], cl
c27_probe:
    mov al, [es:ebx]
c27_after:
    mov edx, c27_probe
    mov esi, 27
    call check

    ; case 28: store-type older "mov [ds:edi], cl" cold pad 2
    lea edi, [ebp+0xc700]
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c28_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 2 nop
    mov [ds:edi], cl
c28_probe:
    mov al, [es:ebx]
c28_after:
    mov edx, c28_probe
    mov esi, 28
    call check

    ; case 29: store-type older "add [ds:edi], ecx" hot pad 0
    mov edi, 0x200
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c29_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 0 nop
    add [ds:edi], ecx
c29_probe:
    mov al, [es:ebx]
c29_after:
    mov edx, c29_probe
    mov esi, 29
    call check

    ; case 30: store-type older "add [ds:edi], ecx" hot pad 1
    mov edi, 0x200
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c30_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 1 nop
    add [ds:edi], ecx
c30_probe:
    mov al, [es:ebx]
c30_after:
    mov edx, c30_probe
    mov esi, 30
    call check

    ; case 31: store-type older "add [ds:edi], ecx" hot pad 2
    mov edi, 0x200
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c31_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 2 nop
    add [ds:edi], ecx
c31_probe:
    mov al, [es:ebx]
c31_after:
    mov edx, c31_probe
    mov esi, 31
    call check

    ; case 32: store-type older "add [ds:edi], ecx" cold pad 0
    lea edi, [ebp+0xc800]
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c32_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 0 nop
    add [ds:edi], ecx
c32_probe:
    mov al, [es:ebx]
c32_after:
    mov edx, c32_probe
    mov esi, 32
    call check

    ; case 33: store-type older "add [ds:edi], ecx" cold pad 1
    lea edi, [ebp+0xc840]
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c33_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 1 nop
    add [ds:edi], ecx
c33_probe:
    mov al, [es:ebx]
c33_after:
    mov edx, c33_probe
    mov esi, 33
    call check

    ; case 34: store-type older "add [ds:edi], ecx" cold pad 2
    lea edi, [ebp+0xc880]
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c34_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 2 nop
    add [ds:edi], ecx
c34_probe:
    mov al, [es:ebx]
c34_after:
    mov edx, c34_probe
    mov esi, 34
    call check

    ; case 35: store-type older "push ecx" hot pad 0
    mov edi, 0x200
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c35_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 0 nop
    push ecx
    pop ecx
c35_probe:
    mov al, [es:ebx]
c35_after:
    mov edx, c35_probe
    mov esi, 35
    call check

    ; case 36: store-type older "push ecx" hot pad 1
    mov edi, 0x200
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c36_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 1 nop
    push ecx
    pop ecx
c36_probe:
    mov al, [es:ebx]
c36_after:
    mov edx, c36_probe
    mov esi, 36
    call check

    ; case 37: store-type older "push ecx" hot pad 2
    mov edi, 0x200
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c37_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 2 nop
    push ecx
    pop ecx
c37_probe:
    mov al, [es:ebx]
c37_after:
    mov edx, c37_probe
    mov esi, 37
    call check

    ; case 38: store-type older "push ecx" cold pad 0
    lea edi, [ebp+0xc980]
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c38_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 0 nop
    push ecx
    pop ecx
c38_probe:
    mov al, [es:ebx]
c38_after:
    mov edx, c38_probe
    mov esi, 38
    call check

    ; case 39: store-type older "push ecx" cold pad 1
    lea edi, [ebp+0xc9c0]
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c39_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 1 nop
    push ecx
    pop ecx
c39_probe:
    mov al, [es:ebx]
c39_after:
    mov edx, c39_probe
    mov esi, 39
    call check

    ; case 40: store-type older "push ecx" cold pad 2
    lea edi, [ebp+0xca00]
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c40_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 2 nop
    push ecx
    pop ecx
c40_probe:
    mov al, [es:ebx]
c40_after:
    mov edx, c40_probe
    mov esi, 40
    call check

    ; case 41: store-type older "mov [ss:esp-8], ecx" hot pad 0
    mov edi, 0x200
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c41_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 0 nop
    mov [ss:esp-8], ecx
c41_probe:
    mov al, [es:ebx]
c41_after:
    mov edx, c41_probe
    mov esi, 41
    call check

    ; case 42: store-type older "mov [ss:esp-8], ecx" hot pad 1
    mov edi, 0x200
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c42_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 1 nop
    mov [ss:esp-8], ecx
c42_probe:
    mov al, [es:ebx]
c42_after:
    mov edx, c42_probe
    mov esi, 42
    call check

    ; case 43: store-type older "mov [ss:esp-8], ecx" hot pad 2
    mov edi, 0x200
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c43_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 2 nop
    mov [ss:esp-8], ecx
c43_probe:
    mov al, [es:ebx]
c43_after:
    mov edx, c43_probe
    mov esi, 43
    call check

    ; case 44: store-type older "mov [ss:esp-8], ecx" cold pad 0
    lea edi, [ebp+0xcb00]
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c44_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 0 nop
    mov [ss:esp-8], ecx
c44_probe:
    mov al, [es:ebx]
c44_after:
    mov edx, c44_probe
    mov esi, 44
    call check

    ; case 45: store-type older "mov [ss:esp-8], ecx" cold pad 1
    lea edi, [ebp+0xcb40]
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c45_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 1 nop
    mov [ss:esp-8], ecx
c45_probe:
    mov al, [es:ebx]
c45_after:
    mov edx, c45_probe
    mov esi, 45
    call check

    ; case 46: store-type older "mov [ss:esp-8], ecx" cold pad 2
    lea edi, [ebp+0xcb80]
    mov ecx, [ds:0x100]
    mov dword [ds:0xF08], c46_after
    mov dword [ds:0xF00], 0xFFFFFFFF
    mov ebx, 0x20
    imul edx, edx
    imul edx, edx
    imul edx, edx
    times 2 nop
    mov [ss:esp-8], ecx
c46_probe:
    mov al, [es:ebx]
c46_after:
    mov edx, c46_probe
    mov esi, 46
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

times 0x1000 - ($ - $$) db 0
