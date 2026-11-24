; INTR withdrawn before an instruction boundary (interrupt_controller.sv intr_pending suspect).
; OUT E2h, n raises INTR for n clocks (testbench port).  A 486 samples INTR at instruction
; boundaries (level-sensitive): a request that is gone at the boundary is not acknowledged.
org 0
times 0x100 db 0
  xor ax, ax
  mov es, ax
  mov word [es:0x40*4], h40
  mov word [es:0x40*4+2], 0x1000
  mov al, 0x40
  out 0xe1, al
  xor bx, bx            ; counts acknowledged interrupts
  ; case 1: IF = 0, INTR high for 3 clocks, then STI much later: nothing pending
  cli
  mov al, 3
  out 0xe2, al
  times 20 nop
  sti
  times 20 nop
  ; case 2: IF = 1, INTR high for 2 clocks inside a long instruction (DIV)
  mov cx, 7
  mov ax, 1000
  xor dx, dx
  mov al, 2
  out 0xe2, al
  div cx
  times 20 nop
  ; case 3: INTR held high, acknowledged normally
  mov al, 1
  out 0xe0, al
  nop
  nop
  mov al, 0
  out 0xe0, al
  times 10 nop
  mov cx, bx
  hlt
h40:
  inc bx
  push ax
  mov al, 0
  out 0xe0, al          ; (the device drops INTR once serviced)
  pop ax
  iret
