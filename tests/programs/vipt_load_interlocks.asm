; Direct-load writeback interlock regressions.  Every producer/consumer pair
; is deliberately back-to-back so D2 must either forward the loaded GPR or
; wait until its architectural writeback before latching the consumer EA.

BITS 32
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

PROD_BASE equ 0x1000
SLOT_BASE equ 0x1948

VALUE_BASE    equ 0x51A7B001
VALUE_INDEX   equ 0x51A7B002
VALUE_SPLIT   equ 0x51A7B003
VALUE_ESP     equ 0x51A7B004
VALUE_ADDR16  equ 0x51A7B005
VALUE_SS16    equ 0x51A7B006
VALUE_STACK   equ 0x51A7B007
VALUE_POP     equ 0x51A7B008
VALUE_AFTER_POP equ 0x51A7B009
VALUE_AFTER_ADD equ 0x51A7B00A
VALUE_STORE_ALIAS equ 0x51A7B00B

start:
    mov esi, PROD_BASE

    ; Producer pointers.
    mov dword [SLOT_BASE + 0x00], 0x3000
    mov dword [SLOT_BASE + 0x04], 0x0400
    mov dword [SLOT_BASE + 0x08], 0x0800
    mov dword [SLOT_BASE + 0x0c], 0x2800
    mov dword [SLOT_BASE + 0x10], 0x0800
    mov dword [SLOT_BASE + 0x14], 0x0fd8

    ; Consumer values.  The final value is in SS and reproduces the addressing
    ; form used by the Second Reality extender during startup.
    mov dword [0x3000 + 0x6d8], VALUE_BASE
    mov dword [0x2000 + 0x0400 * 4 + 0x2d0], VALUE_INDEX
    mov dword [0x0800 + 0x0800 * 2 + 0x4d0], VALUE_SPLIT
    mov dword [ss:0x2800 + 0x4d8], VALUE_ESP
    mov dword [0x0800 + 0x0200 + 0x180], VALUE_ADDR16
    mov dword [ss:0x0ffc], VALUE_SS16
    mov dword [ss:0x2900], VALUE_POP
    mov dword [0x3c00], VALUE_AFTER_POP
    mov dword [0x3d00], VALUE_AFTER_ADD

    ; Drain posted stores, then fill every producer and consumer line.  The
    ; gaps keep warmup itself from depending on the interlock under test.
    times 32 nop
    mov eax, [SLOT_BASE + 0x00]
    times 4 nop
    mov eax, [SLOT_BASE + 0x04]
    times 4 nop
    mov eax, [SLOT_BASE + 0x08]
    times 4 nop
    mov eax, [SLOT_BASE + 0x0c]
    times 4 nop
    mov eax, [SLOT_BASE + 0x10]
    times 4 nop
    mov eax, [SLOT_BASE + 0x14]
    times 4 nop
    mov eax, [0x36d8]
    times 4 nop
    mov eax, [0x32d0]
    times 4 nop
    mov eax, [0x1cd0]
    times 4 nop
    mov eax, [ss:0x2cd8]
    times 4 nop
    mov eax, [0x0b80]
    times 4 nop
    mov eax, [ss:0x0ffc]
    times 8 nop

    ; 1. Loaded register becomes the base of a disp32 EA.
    mov ecx, 16
.base_loop:
    xor eax, eax
    mov eax, [esi + 0x948]
    mov ebx, [eax + 0x6d8]
    cmp ebx, VALUE_BASE
    jne fail_base
    loop .base_loop

    ; 2. Loaded register becomes a scaled index in a three-term EA.
    xor ecx, ecx
    mov edi, 0x2000
    mov ecx, [esi + 0x94c]
    mov ebx, [edi + ecx * 4 + 0x2d0]
    cmp ebx, VALUE_INDEX
    jne fail_index

    ; 3. One loaded register supplies both base and scaled index.
    xor edx, edx
    mov edx, [esi + 0x950]
    mov ebx, [edx + edx * 2 + 0x4d0]
    cmp ebx, VALUE_SPLIT
    jne fail_split

    ; 4. ESP is an ordinary ModR/M base here, not an implicit stack access.
    mov esp, 0x0800
    mov ebp, esp
    mov esp, [esi + 0x954]
    mov eax, [esp + 0x4d8]
    mov esp, ebp
    cmp eax, VALUE_ESP
    jne fail_esp

    ; 5. A loaded ESP feeds the implicit stack address on its WB forwarding
    ; edge. Verify PUSH used that value rather than the replaced ESP.
    mov eax, VALUE_STACK
    mov esp, [SLOT_BASE + 0x0c]
    push eax
    mov esp, ebp
    times 16 nop
    cmp dword [ss:0x27fc], VALUE_STACK
    jne fail_stack

    ; 6. A direct 32-bit load feeds a 16-bit-address consumer.
    mov ebx, 0
    mov esi, 0x0200
    mov ebx, [SLOT_BASE + 0x10]
    a16 mov eax, [bx + si + 0x180]
    cmp eax, VALUE_ADDR16
    jne fail_addr16

    ; 7. Exact Second Reality pattern: loaded BX plus disp8, address-size
    ; override, operand-size dword, and explicit SS override.
    mov ebx, 0
    mov ebx, [SLOT_BASE + 0x14]
    a16 mov edx, [ss:bx + 0x24]
    cmp edx, VALUE_SS16
    jne fail_ss16

    ; 8. A cold POP occupies the memory pipeline while the following direct
    ; load waits for a VIPT probe.  Its reclaimed RNI slot must stay stale;
    ; replaying that uStep repeatedly increments ESP.
    times 16 nop
    mov esp, 0x2900
    pop eax
    mov ebx, [0x3c00]
    cmp eax, VALUE_POP
    jne fail_pop_value
    cmp ebx, VALUE_AFTER_POP
    jne fail_after_pop
    cmp esp, 0x2904
    jne fail_pop_esp

    ; 9. Second Reality's actual stale-slot case is an ALU write to ESP, not
    ; the preceding POP.  Keep its RNI commit one-shot while a cold direct
    ; load waits in D2.
    times 16 nop
    mov esp, 0x2a00
    add esp, 6
    mov ebx, [0x3d00]
    cmp ebx, VALUE_AFTER_ADD
    jne fail_after_add
    cmp esp, 0x2a06
    jne fail_add_esp

    ; 10. Quake unlinks adjacent list nodes with this exact sequence.  Keep
    ; the page's TLB entry clean so the store must first set the PTE dirty bit;
    ; the following direct load must not bypass that older store.
    mov edx, 0x5000
    mov ebx, edx
    mov eax, [edx + 0x0c]
    times 16 nop
    mov ecx, VALUE_STORE_ALIAS
    mov [edx + 0x0c], ecx
    mov ecx, [ebx + 0x0c]
    cmp ecx, VALUE_STORE_ALIAS
    jne fail_store_alias

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
hang:
    hlt
    jmp hang

fail_base:
    mov eax, 1
    jmp fail
fail_index:
    mov eax, 2
    jmp fail
fail_split:
    mov eax, 3
    jmp fail
fail_esp:
    mov eax, 4
    jmp fail
fail_stack:
    mov eax, 5
    jmp fail
fail_addr16:
    mov eax, 6
    jmp fail
fail_ss16:
    mov eax, 7
    jmp fail
fail_pop_value:
    mov eax, 8
    jmp fail
fail_after_pop:
    mov eax, 9
    jmp fail
fail_pop_esp:
    mov eax, 10
    jmp fail
fail_after_add:
    mov eax, 11
    jmp fail
fail_add_esp:
    mov eax, 12
    jmp fail
fail_store_alias:
    mov eax, 13
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    jmp hang
