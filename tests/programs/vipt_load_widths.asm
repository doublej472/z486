; Direct VIPT byte/word and extension regressions.  Exercises every byte lane,
; contained word lanes, crossing fallback, partial-register merge/forwarding,
; and the MOVZX/MOVSX destination convention.

BITS 32
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

WIDTH_BASE equ 0x6000

start:
    mov dword [WIDTH_BASE + 0x00], 0x80FE7F11
    mov dword [WIDTH_BASE + 0x04], 0x44332281
    mov dword [WIDTH_BASE + 0x08], 0x807F01FF
    mov dword [WIDTH_BASE + 0x20], 0x00500040
    mov dword [0x4000], 0x51A7B101
    mov dword [0x5000], 0x51A7B102

    ; Drain the posted stores and make the source lines cache-resident.
    times 32 nop
    mov edx, [WIDTH_BASE + 0x00]
    mov edx, [WIDTH_BASE + 0x04]
    mov edx, [WIDTH_BASE + 0x08]
    mov edx, [WIDTH_BASE + 0x20]
    mov edx, [0x4000]
    mov edx, [0x5000]
    times 8 nop

    ; Plain byte MOV preserves the other destination bytes.  AH also aliases
    ; EAX rather than architectural register number four.
    mov eax, 0xAABBCCDD
    mov al, [WIDTH_BASE + 0x00]
    cmp eax, 0xAABBCC11
    jne fail_1

    mov eax, 0x11223344
    mov ah, [WIDTH_BASE + 0x03]
    cmp eax, 0x11228044
    jne fail_2

    ; Contained words can begin in lanes zero through two and preserve the
    ; upper destination half.
    mov eax, 0xAABBCCDD
    mov ax, [WIDTH_BASE + 0x00]
    cmp eax, 0xAABB7F11
    jne fail_3

    mov eax, 0xAABBCCDD
    mov ax, [WIDTH_BASE + 0x01]
    cmp eax, 0xAABBFE7F
    jne fail_4

    mov eax, 0xAABBCCDD
    mov ax, [WIDTH_BASE + 0x02]
    cmp eax, 0xAABB80FE
    jne fail_5

    ; Lane-three words and unaligned dwords are structurally accepted by D2,
    ; then use the registered slow path after EX detects crossing.
    mov eax, 0xAABBCCDD
    mov ax, [WIDTH_BASE + 0x03]
    cmp eax, 0xAABB8180
    jne fail_6

    mov eax, [WIDTH_BASE + 0x01]
    cmp eax, 0x8180FE7F
    jne fail_7

    ; Zero-extension writes the complete destination selected by ModR/M.reg.
    movzx ecx, byte [WIDTH_BASE + 0x03]
    cmp ecx, 0x00000080
    jne fail_8

    movzx edx, word [WIDTH_BASE + 0x02]
    cmp edx, 0x000080FE
    jne fail_9

    ; Sign-extension uses the selected lane after the raw cache dword has been
    ; registered.
    movsx ebx, byte [WIDTH_BASE + 0x04]
    cmp ebx, 0xFFFFFF81
    jne fail_10

    movsx edi, word [WIDTH_BASE + 0x0A]
    cmp edi, 0xFFFF807F
    jne fail_11

    ; Focused WB forwarding must merge a high-byte result before a following
    ; EA reads EAX.  The word MOVZX case also checks its nonstandard decoded
    ; destination field on an immediate address consumer.
    mov eax, 0x00003000
    mov ah, [WIDTH_BASE + 0x20]
    mov ebx, [eax]
    cmp ebx, 0x51A7B101
    jne fail_12

    xor esi, esi
    movzx esi, word [WIDTH_BASE + 0x21]
    mov ebx, [esi]
    cmp ebx, 0x51A7B102
    jne fail_13

    ; Address-size-16 loads use the same preread/finalize token.  The address
    ; unit masks the offset before relocation, and a base+index+displacement
    ; form still takes its deliberate split-EA cycle before issue.
    mov bx, WIDTH_BASE - 0x100
    mov si, 0x00f0
    a16 mov ecx, [bx + si + 0x10]
    cmp ecx, 0x80FE7F11
    jne fail_14

    ; A loaded a16 pointer retains the ordinary one-cycle EA interlock and is
    ; forwarded into the following 32-bit-addressed consumer.
    xor esi, esi
    mov bx, WIDTH_BASE
    a16 mov si, [bx + 0x21]
    mov ebx, [esi]
    cmp ebx, 0x51A7B102
    jne fail_15

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
    jmp fail
fail_9:
    mov eax, 9
    jmp fail
fail_10:
    mov eax, 10
    jmp fail
fail_11:
    mov eax, 11
    jmp fail
fail_12:
    mov eax, 12
    jmp fail
fail_13:
    mov eax, 13
    jmp fail
fail_14:
    mov eax, 14
    jmp fail
fail_15:
    mov eax, 15
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    jmp hang
