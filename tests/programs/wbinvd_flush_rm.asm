; wbinvd_flush_rm.asm - native whole-L1 flush, platform flush port, INVD/WBINVD
;
; Real-mode (CPL0) program that exercises the three entry points to the native
; whole-L1 flush:
;   A. the platform flush input (I/O port 0xC0) plus a DMA write made behind
;      the CPU's back (I/O ports 0xC4/0xC8, no snoop): the stale line must stay
;      cached until the flush and be invalidated by it;
;   B. INVD (0F 08) after a DMA patch of instruction bytes: the patched code
;      must be fetched once a branch restarts the prefetch;
;   C. WBINVD (0F 09): invalidates the data cache and preserves flags.
;
; INVD and WBINVD are not privileged in real mode.  DS is loaded with segment
; 0x2000 so the data window starts at physical 0x20000, safely outside the
; real-mode 64 KiB segment limit of a zero-based DS.

BITS 32
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
FLUSH_PORT  equ 0xC0
POKE_ADDR   equ 0xC4
POKE_DATA   equ 0xC8

STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

CODE_PHYS   equ 0x10000          ; real-mode CS base chosen by the harness
DS_DATA     equ 0x2000           ; DS base = 0x20000
DAT1_OFF    equ 0x0000
DAT2_OFF    equ 0x0040
DAT1_PHYS   equ 0x20000
DAT2_PHYS   equ 0x20040

start:
    cli
    xor eax, eax
    mov ss, eax
    mov esp, 0x7F00
    mov ax, DS_DATA
    mov ds, ax
    mov es, ax

    ; ---- A: platform flush invalidates a stale data line ----------------
    mov dword [DAT1_OFF], 0x11112222
    mov eax, [DAT1_OFF]
    cmp eax, 0x11112222
    jne fail_a1

    mov eax, DAT1_PHYS
    mov dx, POKE_ADDR
    out dx, eax
    mov eax, 0x33334444
    mov dx, POKE_DATA
    out dx, eax

    mov eax, [DAT1_OFF]              ; still the cached line: no snoop happened
    cmp eax, 0x11112222
    jne fail_a2

    mov dx, FLUSH_PORT
    mov al, 1
    out dx, al
wait_platform_flush:
    in al, dx                        ; bit0 = the requested flush completed
    test al, 1
    jz wait_platform_flush
    mov eax, [DAT1_OFF]              ; invalidated: refetches the poked value
    cmp eax, 0x33334444
    jne fail_a3

    ; ---- B: INVD makes DMA-patched code visible -------------------------
    xor ecx, ecx                     ; ECX = 0 on the first execution
patch_target:
patch_mov:
    mov eax, 0x55556666
    cmp ecx, 0
    jne patched_check
    cmp eax, 0x55556666
    jne fail_b1

    mov eax, CODE_PHYS + patch_mov + 1      ; the imm32 of the mov above
    mov dx, POKE_ADDR
    out dx, eax
    mov eax, 0x77778888
    mov dx, POKE_DATA
    out dx, eax

    mov ecx, 1
    db 0x0f, 0x08                    ; INVD
    jmp patch_target                 ; branch restarts the prefetch

patched_check:
    cmp eax, 0x77778888              ; patched code was fetched
    jne fail_b2

    ; ---- C: WBINVD invalidates the data cache and preserves flags -------
    mov dword [DAT2_OFF], 0x0A0B0C0D
    mov eax, [DAT2_OFF]
    cmp eax, 0x0A0B0C0D
    jne fail_c1

    mov eax, DAT2_PHYS
    mov dx, POKE_ADDR
    out dx, eax
    mov eax, 0x0E0F1011
    mov dx, POKE_DATA
    out dx, eax

    mov eax, [DAT2_OFF]
    cmp eax, 0x0A0B0C0D
    jne fail_c2

    pushfd
    pop ebx
    db 0x0f, 0x09                    ; WBINVD
    pushfd
    pop ecx
    cmp ebx, ecx
    jne fail_c3
    mov eax, [DAT2_OFF]
    cmp eax, 0x0E0F1011
    jne fail_c4

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    hlt

fail_a1:
    mov eax, 0x0A000001
    jmp fail
fail_a2:
    mov eax, 0x0A000002
    jmp fail
fail_a3:
    mov eax, 0x0A000003
    jmp fail
fail_b1:
    mov eax, 0x0B000001
    jmp fail
fail_b2:
    mov eax, 0x0B000002
    jmp fail
fail_c1:
    mov eax, 0x0C000001
    jmp fail
fail_c2:
    mov eax, 0x0C000002
    jmp fail
fail_c3:
    mov eax, 0x0C000003
    jmp fail
fail_c4:
    mov eax, 0x0C000004
fail:
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    hlt
