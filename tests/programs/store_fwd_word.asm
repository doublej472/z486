; store_fwd_word.asm - 16-bit store->load forwarding through the D-cache storeq.
; A word/byte store still pending in the storeq must be visible to a later load
; of the same address: immediate/register sources, partial byte reads, byte-store
; combining, youngest-wins, unaligned byte-enable straddles, and a different-
; address control that must NOT forward.
BITS 32
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4

W0 equ 0x5000
W1 equ 0x5004
W2 equ 0x5008
W3 equ 0x500C

start:
    cli
    mov esp, 0x00003F00
    xor edi, edi

;--- 1: exact form -- mov word [mem], imm16 -> mov bx, [mem]
    mov word [W0], 0x5208
    mov bx, [W0]
    cmp bx, 0x5208
    je  .c1
    or  edi, 0x01
.c1:

;--- 2: register source -- mov word [mem], reg16 -> mov reg16, [mem]
    mov bx, 0xBEEF
    mov word [W0], bx
    mov cx, [W0]
    cmp cx, 0xBEEF
    je  .c2
    or  edi, 0x02
.c2:

;--- 3: word store -> low byte load (partial read of the pending store)
    mov word [W0], 0x52A1
    mov al, [W0]
    cmp al, 0xA1
    je  .c3
    or  edi, 0x04
.c3:

;--- 4: word store -> high byte load (the other byte lane)
    mov ah, [W0 + 1]
    cmp ah, 0x52
    je  .c4
    or  edi, 0x08
.c4:

;--- 5: two byte stores -> word load (combine two pending byte stores)
    mov byte [W1], 0x34
    mov byte [W1 + 1], 0x12
    mov bx, [W1]
    cmp bx, 0x1234
    je  .c5
    or  edi, 0x10
.c5:

;--- 6: youngest wins -- two word stores to the same address, last one reads back
    mov word [W1], 0x1111
    mov word [W1], 0x5208
    mov bx, [W1]
    cmp bx, 0x5208
    je  .c6
    or  edi, 0x20
.c6:

;--- 7: unaligned word store -> load (byte enables straddle the dword)
    mov word [W2 + 1], 0x5208
    mov bx, [W2 + 1]
    cmp bx, 0x5208
    je  .c7
    or  edi, 0x40
.c7:

;--- 8: control -- a load of an unrelated address must not pick up the store
    mov word [W0], 0x5208
    mov bx, [W3]            ; W3 is never written -> must read 0
    cmp bx, 0
    je  .c8
    or  edi, 0x80
.c8:

;--- 9: word store overwrites a pending dword store's low half -> dword load
    mov dword [W0], 0xDEADBEEF
    mov word [W0], 0x5208
    mov eax, [W0]
    cmp eax, 0xDEAD5208
    je  .c9
    or  edi, 0x100
.c9:

    test edi, edi
    jz  .pass
    mov eax, edi
    mov dx, DATA_PORT
    out dx, eax
    jmp .fail

.pass:
    mov al, 0x01
    mov dx, STATUS_PORT
    out dx, al
    hlt

.fail:
    mov al, 0xFF
    mov dx, STATUS_PORT
    out dx, al
    hlt
