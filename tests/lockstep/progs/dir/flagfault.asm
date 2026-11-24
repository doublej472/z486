; a flag-producing instruction right before an instruction that faults: the fault frame's
; FLAGS image must be the producer's result (faults leave no state of the faulting instruction)
org 0
times 0x100 db 0
  xor ax, ax
  mov es, ax
  mov word [es:13*4], h13
  mov word [es:13*4+2], 0x1000
  mov word [es:12*4], h13
  mov word [es:12*4+2], 0x1000
  mov ax, 0x2000
  mov ds, ax
  mov di, 0x1000          ; log of the pushed FLAGS
%macro fcase 2
  mov al, 0x5a
  mov word [cs:resume], %%r
  %1
  %2
%%r:
%endmacro
  fcase {sub al, 0xa5}, {adc word [0xffff], 5}
  fcase {add al, 0xa6}, {adc word [0xffff], 5}
  fcase {sub al, 0xa5}, {sbb byte [0xffff+1], 5}
  fcase {stc}, {adc word [0xffff], 1}
  fcase {clc}, {adc word [0xffff], 1}
  fcase {cmp al, 0x7f}, {inc word [0xffff]}
  fcase {sub al, 0xa5}, {mov word [0xffff], 1}
  fcase {sub al, 0xa5}, {add word [0xffff], ax}
  fcase {xor al, al}, {adc dword [0xfffe], 1}
  fcase {sub al, 0xa5}, {push word [0xffff]}
  mov cx, di
  hlt
h13:
  push bp
  mov bp, sp
  mov ax, [bp+6]          ; pushed FLAGS
  mov [es:di+0x500], ax    ; (es = 0: log at 0:1500 + ...)
  add di, 2
  mov ax, [cs:resume]
  mov [bp+2], ax
  pop bp
  iret
resume: dw 0
