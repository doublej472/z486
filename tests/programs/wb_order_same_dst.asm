; Two back-to-back memory-writing instructions that name the SAME destination
; register -- `mov r,[mem]` followed by `ALU r,[mem]` -- which is the pattern the
; Doom 1 (1992) compiler emits and Doom 2's newer one does not.
;
; WHY THIS TEST EXISTS. The architectural GPR bank has ONE write port and the
; producers that can drive it in the same cycle are OR-ed together
; (z486.sv's ea_inval_gpr / d2_split_commit_mask one-hots), so when two of them
; target the same register the winner is decided by the order of the assignments
; in data_unit.sv's GPR always_ff. Programme order says the YOUNGER (later)
; instruction must win. If any pair of producers is ordered the other way, the
; older instruction's value survives and the younger one's write is lost --
; which is what a Doom 1 sprite loop would see as "the add was dropped".
;
; THE CONTROLS MATTER AS MUCH AS THE CASES, and they are what makes a clean run
; a refutation rather than an absence of evidence:
;   * the same pair writing a DIFFERENT destination register (C03/C04)
;   * the pair with an unrelated instruction between them (C05/C06 nop,
;     C07 an unrelated load into another register)
; If a same-destination pair is wrong while its different-destination and
; separated forms are right, the write arbitration between those two producers
; is the defect. If everything is right, the two back-to-back writers never
; collide in this configuration and the pattern is safe here.
;
; BOTH FORMS OF THE FIRST INSTRUCTION are exercised because they take different
; paths: `mov eax,[disp32]` can assemble as the moffs form (A1, which z486's
; has_moffs test EXCLUDES from the VIPT direct-load candidate) or as modrm
; (8B 05, which IS a VIPT candidate). NASM picks moffs for a bare symbol, so the
; modrm form is written as raw bytes here. The second instruction of every pair
; is always modrm -- the ALU group has no moffs form -- and for its
; register-direct encoding it is a VIPT ALU candidate.
;
; The whole body runs TWICE, into two result tables: pass 0 with the data still
; cold in the D-cache (the loads take the slow path), pass 1 with every data
; line resident (the VIPT fast path). The two passes are compared against the
; same hand-computed expected table, so a failure names the exact slot and says
; whether it was the cold or the warm pass.
;
; Expected values are ISA arithmetic on the constants in the data block, not
; values read out of the RTL.
;
; VERDICT AND CONFIGURATION. This program passes on the vendored core as it
; stands, in every configuration tried: paging off/on x mem_latency 1/5/8 (six),
; plus the two simulation-only controls that disable the hardwired recipes
; (+z486_hardwired_off, +z486_fast_off). The committed JSON is the most
; demanding of them -- paging ON (identity-mapped, so the TLB/load path is in
; play), mem_latency 5, the second operand of the four cold cases in a line the
; cache has never seen. With the architectural write port instrumented, the two
; writers this pattern can use never write in the same cycle, in this program, in
; z486's whole protected-mode suite, or in the project's 930 542-cycle boot
; golden.
;
; WHAT THE SLOTS PIN. Slots 0..26 characterise the reported pattern: on this core
; its two writers -- the older instruction's deferred ROM load commit and the
; younger instruction's registered VIPT writeback -- never name the same
; register in the same cycle, so the arbitration between them is never exercised
; (planting the opposite priority between those two is a behavioural no-op over
; the whole suite and the boot golden). The pairing that DOES collide is an
; older deferred ROM load commit against a younger EXEC-cycle writeback, which is
; what the POP slots 27..30 reach: there the shipped order lets the younger
; instruction win, and inverting it makes this program fail at slot 27
; (pop eax + add eax,imm32 leaves 0x1234 instead of 0x2345 -- the reported "the
; add was lost"). Slot 27 is the fail-first pin for the write-port arbitration.

BITS 32
org 0x10000

STATUS_PORT equ 0xE0
DATA_PORT   equ 0xE4
STATUS_PASS equ 0x01
STATUS_FAIL equ 0xFF

N_SLOTS   equ 31
SLOT_SIZE equ 4

start:
    mov esp, 0x40000                ; SS base 0: a private stack, nowhere near the data

    ; ---- pass 0: cold (the D-cache has never seen the data lines) ----
    mov edi, R0
    call body

    ; ---- pass 1: warm (every data line is resident now) ----
    mov edi, R1
    call body

    ; ---- compare both passes against the expected table ----
    mov esi, R0
    mov ebp, EXPECT
    mov ecx, N_SLOTS
    xor ebx, ebx                    ; failure code 0 = cold-pass slot 0
cold_loop:
    mov eax, [esi]
    cmp eax, [ebp]
    jne fail_cold
    add esi, SLOT_SIZE
    add ebp, SLOT_SIZE
    inc ebx
    loop cold_loop

    xor ebx, ebx
    mov esi, R1
    mov ebp, EXPECT
    mov ecx, N_SLOTS
warm_loop:
    mov eax, [esi]
    cmp eax, [ebp]
    jne fail_warm
    add esi, SLOT_SIZE
    add ebp, SLOT_SIZE
    inc ebx
    loop warm_loop

    mov al, STATUS_PASS
    mov dx, STATUS_PORT
    out dx, al
hang:
    hlt
    jmp hang

fail_warm:
    add ebx, 0x100                  ; failure code >= 0x100 = warm-pass slot
fail_cold:
    mov edx, DATA_PORT
    mov ecx, eax                    ; keep what the core left behind
    mov eax, ebx
    out dx, eax                     ; which slot (cold: slot, warm: 0x100+slot)
    mov eax, ecx
    out dx, eax                     ; what the core left in the register
    mov eax, [ebp]
    out dx, eax                     ; what the ISA says it should be
    mov al, STATUS_FAIL
    mov dx, STATUS_PORT
    out dx, al
    jmp hang

; ---------------------------------------------------------------------------
; The measured body.  Every case is: set the destination register to a known
; value, run the pair back-to-back, store the destination.  Nothing else sits
; between the two instructions of a pair except in the labelled controls.
; ---------------------------------------------------------------------------
body:
    mov ebp, esp                    ; the pop cases move ESP; the caller's CALL
                                    ; return address must survive
    ; ---- C21..C24: the same pair with the SECOND operand in a line that is
    ; still COLD, so the younger load takes the miss/slow path while the older
    ; one's deferred commit is in flight.  These come first so pass 0 sees the
    ; cold lines; pass 1 sees them warm.
    ; ---- C21 A1 load from a cold line, modrm ALU load from another cold line ----
    mov eax, 0xDEADBEEF
    mov eax, [CPA1]
    add eax, [CPB1]
    mov [edi+0x5C], eax

    ; ---- C22 same, but the younger instruction is a plain load: the
    ; architectural result is the YOUNGER value, and an older-wins collision
    ; would leave CPA2's value in EAX ----
    mov eax, 0xDEADBEEF
    mov eax, [CPA2]
    db 0x8B, 0x05
    dd CPB2
    mov [edi+0x60], eax

    ; ---- C23 the OR form and a cold second operand ----
    mov eax, 0xDEADBEEF
    mov eax, [CPA3]
    or eax, [CPB3]
    mov [edi+0x64], eax

    ; ---- C24 modrm (VIPT) load from a cold line, then a VIPT ALU load from a
    ; different cold line ----
    mov eax, 0xDEADBEEF
    db 0x8B, 0x05
    dd CPA4
    add eax, [CPB4]
    mov [edi+0x68], eax

    ; ---- C01 moffs dword load + modrm dword add ----
    mov eax, 0xDEADBEEF
    mov eax, [DA_MAIN]              ; A1 (moffs): NOT a VIPT direct-load candidate
    add eax, [DB_SAME]              ; 03 05 (modrm): VIPT ALU candidate
    mov [edi+0x00], eax

    ; ---- C02 modrm dword load + modrm dword add ----
    mov eax, 0xDEADBEEF
    db 0x8B, 0x05
    dd DA_MAIN                      ; 8B 05: VIPT plain load
    add eax, [DB_SAME]              ; 03 05: VIPT ALU load
    mov [edi+0x04], eax

    ; ---- C03 control, moffs load, DIFFERENT destination ----
    mov ecx, 0x00000011
    mov eax, 0xDEADBEEF
    mov eax, [DA_MAIN]
    add ecx, [DB_SAME]
    mov [edi+0x08], eax
    mov [edi+0x0C], ecx

    ; ---- C04 control, modrm load, DIFFERENT destination ----
    mov ecx, 0x00000011
    mov eax, 0xDEADBEEF
    db 0x8B, 0x05
    dd DA_MAIN
    add ecx, [DB_SAME]
    mov [edi+0x10], eax
    mov [edi+0x14], ecx

    ; ---- C05 control, moffs load, nop between ----
    mov eax, 0xDEADBEEF
    mov eax, [DA_MAIN]
    nop
    add eax, [DB_SAME]
    mov [edi+0x18], eax

    ; ---- C06 control, modrm load, nop between ----
    mov eax, 0xDEADBEEF
    db 0x8B, 0x05
    dd DA_MAIN
    nop
    add eax, [DB_SAME]
    mov [edi+0x1C], eax

    ; ---- C07 control, unrelated load into another register between ----
    mov eax, 0xDEADBEEF
    mov eax, [DA_MAIN]
    mov ebx, [DC_SEP]
    add eax, [DB_SAME]
    mov [edi+0x20], eax
    mov [edi+0x24], ebx

    ; ---- C08 word moffs load + word modrm add ----
    mov eax, 0xDEADBEEF
    mov ax, [DA_MAIN]               ; 66 A1
    add ax, [DB_SAME]               ; 66 03 05
    mov [edi+0x28], eax

    ; ---- C09 word modrm load + word modrm add ----
    mov eax, 0xDEADBEEF
    db 0x66, 0x8B, 0x05
    dd DA_MAIN                      ; 66 8B 05
    add ax, [DB_SAME]
    mov [edi+0x2C], eax

    ; ---- C10 byte moffs load + byte modrm add ----
    mov eax, 0xDEADBEEF
    mov al, [DA_BYTE]               ; A0
    add al, [DB_BYTE]               ; 02 05
    mov [edi+0x30], eax

    ; ---- C11 byte modrm load + byte modrm add ----
    mov eax, 0xDEADBEEF
    db 0x8A, 0x05
    dd DA_BYTE                      ; 8A 05
    add al, [DB_BYTE]
    mov [edi+0x34], eax

    ; ---- C12 moffs dword load + dword OR ----
    mov eax, 0xDEADBEEF
    mov eax, [DA_MAIN]
    or eax, [DB_SAME]               ; 0B 05
    mov [edi+0x38], eax

    ; ---- C13 modrm dword load + dword SUB ----
    mov eax, 0xDEADBEEF
    db 0x8B, 0x05
    dd DA_MAIN
    sub eax, [DB_SAME]              ; 2B 05
    mov [edi+0x3C], eax

    ; ---- C14 base-register EA pair (mov eax,[ebx] ; add eax,[ebx+4]) ----
    mov ebx, DA_MAIN
    mov eax, 0xDEADBEEF
    mov eax, [ebx]                  ; 8B 03
    add eax, [ebx+4]                ; 03 43 04
    mov [edi+0x40], eax

    ; ---- C15 two ALU loads in a row, same destination ----
    mov eax, 0x00000001
    add eax, [DA_MAIN]
    add eax, [DB_SAME]
    mov [edi+0x44], eax

    ; ---- C16 moffs load + dword add of a DIFFERENT line ----
    mov eax, 0xDEADBEEF
    mov eax, [DA_MAIN]
    add eax, [DA_ALT]               ; 03 05, different 16-byte line
    mov [edi+0x48], eax

    ; ---- C17 modrm ES-override load + ES-override dword add ----
    mov eax, 0xDEADBEEF
    db 0x26, 0x8B, 0x05
    dd DA_MAIN                      ; 26 8B 05
    db 0x26, 0x03, 0x05
    dd DB_SAME                      ; 26 03 05
    mov [edi+0x4C], eax

    ; ---- C18 reverse order: ALU load then plain modrm load ----
    mov eax, 0xDEADBEEF
    add eax, [DA_MAIN]
    db 0x8B, 0x05
    dd DB_SAME
    mov [edi+0x50], eax

    ; ---- C19 moffs load, add, add again ----
    mov eax, 0xDEADBEEF
    mov eax, [DA_MAIN]
    add eax, [DB_SAME]
    add eax, [DB_SAME]
    mov [edi+0x54], eax

    ; ---- C20 modrm load, add, add again ----
    mov eax, 0xDEADBEEF
    db 0x8B, 0x05
    dd DA_MAIN
    add eax, [DB_SAME]
    add eax, [DB_SAME]
    mov [edi+0x58], eax

    ; ---- C25..C27: the older instruction is a POP, which is NOT a VIPT
    ; direct-load candidate (stack_op), so its load commits through the deferred
    ; ROM token -- the same producer as the moffs forms above.  The younger
    ; instruction is a register/immediate ALU op, whose writeback is the EXEC
    ; commit rather than the registered one: THIS is the pairing that does
    ; collide (measured), and the shipped order gives the win to the younger
    ; instruction.  These are the slots that catch an order inversion.
    ; ---- C25 pop eax + add eax,imm32 ----
    mov esp, 0x40000
    mov dword [esp], 0x00001234
    pop eax
    add eax, 0x00001111
    mov esp, ebp
    mov [edi+0x6C], eax

    ; ---- C26 pop ax + add ax,imm16 ----
    mov esp, 0x40000
    mov dword [esp], 0x00001234
    pop ax
    add ax, 0x1111
    mov esp, ebp
    mov [edi+0x70], eax

    ; ---- C27 pop eax + or eax,imm32 ----
    mov esp, 0x40000
    mov dword [esp], 0x00001234
    pop eax
    or eax, 0x0000F000
    mov esp, ebp
    mov [edi+0x74], eax

    ; ---- C28 pop eax + add eax,[mem] (younger is a memory ALU op) ----
    mov esp, 0x40000
    mov dword [esp], 0x00001234
    pop eax
    add eax, [DB_SAME]
    mov esp, ebp
    mov [edi+0x78], eax

    ret

; ---------------------------------------------------------------------------
; Data and result tables.  DA_MAIN and DB_SAME are in the SAME 16-byte line;
; DA_ALT/DB_ALT are the next line.  Addresses come from the labels: DS base is 0
; and the image is assembled at org 0x10000, so a label is its physical address.
; ---------------------------------------------------------------------------
align 16
; Each cold case gets its own pair of 16-byte lines so that neither operand has
; been touched by an earlier case.
CPA1:     dd 0x51515151
          dd 0, 0, 0
CPB1:     dd 0x00000066
          dd 0, 0, 0
CPA2:     dd 0x52525252
          dd 0, 0, 0
CPB2:     dd 0x00000077
          dd 0, 0, 0
CPA3:     dd 0x51515151
          dd 0, 0, 0
CPB3:     dd 0x00000066
          dd 0, 0, 0
CPA4:     dd 0x51515151
          dd 0, 0, 0
CPB4:     dd 0x00000066
          dd 0, 0, 0
align 16
DA_MAIN:  dd 0x11223344       ; +0x00, line A
DB_SAME:  dd 0x00000055       ; +0x04, line A
          dd 0xCAFEF00D       ; +0x08, filler
          dd 0xDEADBEEF       ; +0x0C, filler
DA_ALT:   dd 0x11111111       ; +0x10, line B
DB_ALT:   dd 0x33333333       ; +0x14, line B
DC_SEP:   dd 0x0000AA55       ; +0x18
          dd 0                ; +0x1C
DA_BYTE:  db 0x44             ; +0x20
DB_BYTE:  db 0x11             ; +0x21
          times 2 db 0
          dd 0
          dd 0

align 16
EXPECT:
    ; slots are in RESULT-TABLE OFFSET order (the order the body stores them)
    dd 0x11223399       ; +0x00 C01 moffs dword mov + dword add
    dd 0x11223399       ; +0x04 C02 modrm dword mov + dword add
    dd 0x11223344       ; +0x08 C03 eax, different destination control (moffs)
    dd 0x00000066       ; +0x0C C03 ecx = 0x11 + 0x55
    dd 0x11223344       ; +0x10 C04 eax, different destination control (modrm)
    dd 0x00000066       ; +0x14 C04 ecx = 0x11 + 0x55
    dd 0x11223399       ; +0x18 C05 nop between (moffs)
    dd 0x11223399       ; +0x1C C06 nop between (modrm)
    dd 0x11223399       ; +0x20 C07 unrelated load between
    dd 0x0000AA55       ; +0x24 C07 ebx = DC_SEP
    dd 0xDEAD3399       ; +0x28 C08 word moffs mov + word add
    dd 0xDEAD3399       ; +0x2C C09 word modrm mov + word add
    dd 0xDEADBE55       ; +0x30 C10 byte moffs mov + byte add
    dd 0xDEADBE55       ; +0x34 C11 byte modrm mov + byte add
    dd 0x11223355       ; +0x38 C12 dword mov + OR
    dd 0x112232EF       ; +0x3C C13 dword mov + SUB
    dd 0x11223399       ; +0x40 C14 base-register EA pair
    dd 0x1122339A       ; +0x44 C15 two ALU loads in a row
    dd 0x22334455       ; +0x48 C16 mov + add of the other line
    dd 0x11223399       ; +0x4C C17 ES override pair
    dd 0x00000055       ; +0x50 C18 reverse: ALU load then plain load
    dd 0x112233EE       ; +0x54 C19 mov + add + add
    dd 0x112233EE       ; +0x58 C20 mov + add + add (modrm)
    dd 0x515151B7       ; +0x5C C21 cold-line A1 load + modrm add
    dd 0x00000077       ; +0x60 C22 cold-line A1 load + plain load (younger wins)
    dd 0x51515177       ; +0x64 C23 cold-line A1 load + OR
    dd 0x515151B7       ; +0x68 C24 cold-line modrm load + ALU load
    dd 0x00002345       ; +0x6C C25 pop eax + add eax,imm32
    dd 0x00002345       ; +0x70 C26 pop ax + add ax,imm16 (upper half is C25's)
    dd 0x0000F234       ; +0x74 C27 pop eax + or eax,imm32
    dd 0x00001289       ; +0x78 C28 pop eax + add eax,[DB_SAME]

align 16
R0: times N_SLOTS dd 0xFFFFFFFF     ; pass 0 (cold)
align 16
R1: times N_SLOTS dd 0xFFFFFFFF     ; pass 1 (warm)
