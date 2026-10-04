; io_store_out_in.asm
; Port I/O must stay ordered after an older posted store, and an I/O read must
; return its own data (not a stale/prefetch bus word), with the store queue
; draining between the two.
;
; Each iteration posts a store to a scratch buffer and then issues OUT DX,AX
; followed immediately by IN EAX,DX. The testbench returns 0xFFFFFFFF for every
; I/O read, so AND-accumulating into EBX must leave EBX = 0xFFFFFFFF; any I/O
; read that latches stale code/prefetch data (the z386 I/O-read race) or a
; dropped/duplicated request drops bits. The posted store in front of the OUT
; exercises the store-queue drain that gates direct I/O ordering.
;
; Needs mem_latency > 1 (see .json) so the I/O read spans multiple bus cycles
; and a prefetch can interleave.
;
; Result protocol: port 0xE0 status (0x01 pass / 0xFF fail), 0xE4 = bad EBX.

BITS 16
org 0

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

IO_COUNT equ 3000
SCRATCH  equ 0x4000

start:
    cli
    mov ax, cs
    mov ds, ax
    mov ss, ax
    mov sp, 0x7000

    mov dx, 0x03DA          ; any I/O port; tb returns 0xFFFFFFFF for IN
    mov di, SCRATCH
    mov ebx, 0xFFFFFFFF     ; AND accumulator - must stay all-ones
    mov ecx, IO_COUNT
.loop:
    mov ax, 0x55AA
    mov [di], ax            ; posted store (drained before the OUT below)
    out dx, ax              ; I/O write, ordered after the store
    in  eax, dx             ; I/O read -> must read 0xFFFFFFFF
    and ebx, eax
    add di, 2
    dec ecx
    jnz .loop

    cmp ebx, 0xFFFFFFFF
    jne .fail

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
    jmp .hang
.fail:
    mov eax, ebx
    mov dx, DATA_PORT
    out dx, eax
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
.hang:
    hlt
    jmp .hang
