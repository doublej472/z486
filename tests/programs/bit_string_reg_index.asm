; Exercise the signed register-index paths of memory BT/BTS/BTR/BTC.  These
; are the only instruction paths whose Intel microcode uses SRCREG directly
; as a shifter operand (words 136 and 14F).

BITS 32
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

BIT_BASE  equ 0x7000
WORD_BASE equ 0x7100

start:
    mov dword [BIT_BASE - 4], 0x80000000
    mov dword [BIT_BASE],     0x00000000
    mov dword [BIT_BASE + 4], 0x00000001
    mov word  [WORD_BASE - 2], 0x8000
    mov word  [WORD_BASE],     0x0000
    mov word  [WORD_BASE + 2], 0x0001
    times 32 nop

    ; BT uses the signed high part of the register index to select the memory
    ; element, then the low part as the bit position within that element.
    mov ecx, -1
    bt dword [BIT_BASE], ecx
    jnc fail_1

    xor ecx, ecx
    bt dword [BIT_BASE], ecx
    jc fail_2

    mov ecx, 32
    bt dword [BIT_BASE], ecx
    jnc fail_3

    ; BTS must both report the old value and update the selected dword.
    mov ecx, 5
    bts dword [BIT_BASE], ecx
    jc fail_4
    cmp dword [BIT_BASE], 0x00000020
    jne fail_5
    bts dword [BIT_BASE], ecx
    jnc fail_6

    ; BTR clears the selected bit and reports its old value.
    btr dword [BIT_BASE], ecx
    jnc fail_7
    cmp dword [BIT_BASE], 0
    jne fail_8
    btr dword [BIT_BASE], ecx
    jc fail_9

    ; BTC follows the same address path and toggles in both directions.
    mov ecx, 6
    btc dword [BIT_BASE], ecx
    jc fail_10
    cmp dword [BIT_BASE], 0x00000040
    jne fail_11
    btc dword [BIT_BASE], ecx
    jnc fail_12
    cmp dword [BIT_BASE], 0
    jne fail_13

    ; A negative modifying index must update the preceding dword.
    mov ecx, -2
    bts dword [BIT_BASE], ecx
    jc fail_14
    cmp dword [BIT_BASE - 4], 0xC0000000
    jne fail_15
    btr dword [BIT_BASE], ecx
    jnc fail_16
    cmp dword [BIT_BASE - 4], 0x80000000
    jne fail_17

    ; Repeat representative reads and writes at word size.  This checks that
    ; the preread shifter path retains the architectural operand size.
    mov cx, -1
    bt word [WORD_BASE], cx
    jnc fail_18

    mov cx, 16
    bt word [WORD_BASE], cx
    jnc fail_19

    mov cx, 7
    bts word [WORD_BASE], cx
    jc fail_20
    cmp word [WORD_BASE], 0x0080
    jne fail_21
    btr word [WORD_BASE], cx
    jnc fail_22
    cmp word [WORD_BASE], 0
    jne fail_23

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
hang:
    hlt
    jmp hang

fail_1:  mov eax, 1
    jmp fail
fail_2:  mov eax, 2
    jmp fail
fail_3:  mov eax, 3
    jmp fail
fail_4:  mov eax, 4
    jmp fail
fail_5:  mov eax, 5
    jmp fail
fail_6:  mov eax, 6
    jmp fail
fail_7:  mov eax, 7
    jmp fail
fail_8:  mov eax, 8
    jmp fail
fail_9:  mov eax, 9
    jmp fail
fail_10: mov eax, 10
    jmp fail
fail_11: mov eax, 11
    jmp fail
fail_12: mov eax, 12
    jmp fail
fail_13: mov eax, 13
    jmp fail
fail_14: mov eax, 14
    jmp fail
fail_15: mov eax, 15
    jmp fail
fail_16: mov eax, 16
    jmp fail
fail_17: mov eax, 17
    jmp fail
fail_18: mov eax, 18
    jmp fail
fail_19: mov eax, 19
    jmp fail
fail_20: mov eax, 20
    jmp fail
fail_21: mov eax, 21
    jmp fail
fail_22: mov eax, 22
    jmp fail
fail_23: mov eax, 23
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    jmp hang
