; ESC instructions with CR0.EM = 0 / MP = 0 on a core without x87 (486SX model)
org 0
times 0x100 db 0
  mov ax, 0x1234
  mov [0x200], ax
  fninit                 ; DB E3
  fnstsw [0x200]         ; DD 3E
  mov ax, 0x5555
  fnstsw ax              ; DF E0
  fnstcw [0x202]         ; D9 3E
  fld dword [0x204]      ; D9 06
  wait
  mov bx, [0x200]
  hlt
