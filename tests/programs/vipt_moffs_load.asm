; Direct VIPT A1 (MOV eAX,moffs) regressions. Exercise an aligned hit, word
; partial write, crossing fallback, segment override, TLB refill, dependent EA,
; older-store ordering, and the address-size fallback left on microcode.

BITS 32
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

SRC_BASE    equ 0x1000
TARGET_OFF  equ 0x3800

VALUE_ALIGNED equ 0x51A7C001
VALUE_WORD    equ 0x000080FE
VALUE_CROSS   equ 0x51A7C003
VALUE_FS      equ 0x51A7C004
VALUE_TARGET  equ 0x51A7C005
VALUE_STORE   equ 0x51A7C006
VALUE_A16     equ 0x51A7C007

start:
    mov dword [SRC_BASE + 0x00], VALUE_ALIGNED
    mov dword [SRC_BASE + 0x04], VALUE_WORD
    mov dword [SRC_BASE + 0x09], VALUE_CROSS
    mov dword [SRC_BASE + 0x20], TARGET_OFF
    mov dword [TARGET_OFF], VALUE_TARGET
    mov dword [0x0400], VALUE_A16
    mov dword [fs:SRC_BASE], VALUE_FS

    ; Drain posted stores and warm the lines without using accumulator moffs.
    times 32 nop
    mov ecx, [SRC_BASE + 0x00]
    mov ecx, [SRC_BASE + 0x04]
    mov ecx, [SRC_BASE + 0x09]
    mov ecx, [SRC_BASE + 0x20]
    mov ecx, [TARGET_OFF]
    mov ecx, [0x0400]
    mov ecx, [fs:SRC_BASE]
    times 8 nop

    ; 1. Aligned cache/TLB hit uses A1 and writes the full accumulator.
    mov eax, [SRC_BASE + 0x00]
    cmp eax, VALUE_ALIGNED
    jne fail_1

    ; 2. Operand-size A1 merges AX while retaining the upper accumulator half.
    mov eax, 0xAABBCCDD
    mov ax, [SRC_BASE + 0x04]
    cmp eax, 0xAABB80FE
    jne fail_2

    ; 3. An unaligned dword is admitted, then uses paging's assembled fallback.
    mov eax, [SRC_BASE + 0x09]
    cmp eax, VALUE_CROSS
    jne fail_3

    ; 4. The D2 relocation uses the decoded segment override, not live DS.
    mov eax, [fs:SRC_BASE]
    cmp eax, VALUE_FS
    jne fail_4

    ; 5. Flush translation state while retaining cache data. The A1 fallback
    ; must refill the direct sidecar from the authoritative/page-walk path.
    mov ecx, cr3
    mov cr3, ecx
    mov eax, [SRC_BASE + 0x00]
    cmp eax, VALUE_ALIGNED
    jne fail_5

    ; 6. Registered A1 writeback forwards EAX to an immediate EA consumer.
    mov eax, [SRC_BASE + 0x20]
    mov ebx, [eax]
    cmp ebx, VALUE_TARGET
    jne fail_6

    ; 7. A preceding A3 store must become ordered before the A1 load.
    mov eax, VALUE_STORE
    mov [SRC_BASE + 0x30], eax
    mov eax, [SRC_BASE + 0x30]
    cmp eax, VALUE_STORE
    jne fail_7

    ; 8. Address-size-16 moffs deliberately remains on the original path.
    a16 mov eax, [word 0x0400]
    cmp eax, VALUE_A16
    jne fail_8

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
hang:
    hlt
    jmp hang

fail_1:
    mov eax, 1
    jmp fail
fail_2:
    mov eax, 2
    jmp fail
fail_3:
    mov eax, 3
    jmp fail
fail_4:
    mov eax, 4
    jmp fail
fail_5:
    mov eax, 5
    jmp fail
fail_6:
    mov eax, 6
    jmp fail
fail_7:
    mov eax, 7
    jmp fail
fail_8:
    mov eax, 8
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    jmp hang
