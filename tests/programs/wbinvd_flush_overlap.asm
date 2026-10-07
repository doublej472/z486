; wbinvd_flush_overlap.asm - WBINVD against a concurrently held platform flush
;
; The testbench runs with +cache_flush_stress: the platform cache_flush input
; is driven as repeated levels held for a long window, so a WBINVD can begin in
; the window after a platform cache_flush_done while the platform level is
; still high.  Before the instruction had its own request path, that window was
; the P1 wedge: the ORed input never dropped, the controller never re-armed,
; cache_flush_done never pulsed, and the CPU stalled forever.
;
; The program loops over data offsets, each iteration:
;   1. caches a known value and reads it back;
;   2. DMA-pokes a different value behind the caches (no snoop);
;   3. executes WBINVD;
;   4. confirms the poked value is visible, i.e. the walk actually ran.
; A dropped or wedged WBINVD either times out (no STATUS_PASS) or leaves the
; old value, both of which fail the test.  The pre-WBINVD value is deliberately
; NOT asserted to stay cached: the stress platform flush may invalidate the
; line at any time, which is legal and must not confuse the check.
;
; INVD/WBINVD are not privileged in real mode.  DS is loaded with segment
; 0x2000 so the data window starts at physical 0x20000.

BITS 32
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
POKE_ADDR   equ 0xC4
POKE_DATA   equ 0xC8

STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

DS_DATA     equ 0x2000          ; DS base = 0x20000
DATA_PHYS   equ 0x20000
ITERATIONS  equ 16

start:
    cli
    xor eax, eax
    mov ss, eax
    mov esp, 0x7F00
    mov ax, DS_DATA
    mov ds, ax
    mov es, ax

    mov ecx, ITERATIONS
loop:
    ; A different 64-byte-strided offset every iteration.
    mov ebx, ecx
    shl ebx, 6

    mov dword [ebx], 0x11112222
    mov eax, [ebx]                  ; install the line; let the store drain
    cmp eax, 0x11112222
    jne fail_cached

    mov eax, DATA_PHYS
    add eax, ebx
    mov dx, POKE_ADDR
    out dx, eax
    mov eax, 0x33334444
    mov dx, POKE_DATA
    out dx, eax

    db 0x0f, 0x09                   ; WBINVD

    mov eax, [ebx]                  ; refetches the poked value
    cmp eax, 0x33334444
    jne fail_post

    dec ecx
    jnz loop

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt

fail_cached:
    mov eax, 0x0D000001
    jmp fail
fail_post:
    mov eax, 0x0D000003
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt
