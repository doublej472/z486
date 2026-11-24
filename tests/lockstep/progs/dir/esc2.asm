; ESC memory forms, CR0.EM = 0, no x87: which ones make coprocessor I/O cycles
org 0
times 0x100 db 0
  mov di, 0x400
  mov cx, 0x100
  mov al, 0x5a
  rep stosb
  fld tword [0x400]      ; DB /5
  fstp tword [0x410]     ; DB /7
  fld qword [0x420]      ; DD /0
  fstp qword [0x430]     ; DD /3
  fild qword [0x440]     ; DF /5
  fistp qword [0x450]    ; DF /7
  fbld [0x460]           ; DF /4
  fbstp [0x470]          ; DF /6
  fldenv [0x480]         ; D9 /4
  fnstenv [0x4a0]        ; D9 /6
  frstor [0x500]         ; DD /4
  fnsave [0x580]         ; DD /6
  fadd dword [0x600]     ; D8 /0
  fiadd word [0x610]     ; DE /0
  hlt
