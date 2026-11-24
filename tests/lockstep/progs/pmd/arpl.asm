%include "pmhead.inc"
tests:
  mov esi, 0x8000
  xor ebp, ebp
  mov word [0x9650], 0x18b8
  mov word [0xa650], 0x2516
  mov dx, 0x3031
  mov cx, 0xbb3b
  mov [0x9650], cx
  arpl [0x9650], cx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9650]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9098], 0x2c01
  mov word [0xa098], 0xde06
  mov di, 0xd61a
  mov cx, 0x23c4
  mov cx, [0x9098]
  arpl di, cx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9098]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9392], 0x1fac
  mov word [0xa392], 0xcb19
  mov ax, 0x1963
  mov cx, 0x7131
  mov ax, [0x9392]
  nop
  mov ebp, ebp
  arpl ax, cx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9392]
  mov [esi+6], ax
  add esi, 8
  mov word [0x94ee], 0x5c88
  mov word [0xa4ee], 0x34c3
  mov di, 0x6030
  mov ax, 0xbeaa
  mov di, [0x94ee]
  nop
  nop
  arpl di, ax
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x94ee]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9506], 0xee63
  mov word [0xa506], 0xe807
  mov bx, 0xb921
  mov di, 0x997b
  mov di, [0x9506]
  arpl bx, di
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9506]
  mov [esi+6], ax
  add esi, 8
  mov word [0x94cc], 0xfd7f
  mov word [0xa4cc], 0xafdc
  mov cx, 0xe5cd
  mov ax, 0x936c
  mov [0x94cc], ax
  arpl [0x94cc], ax
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x94cc]
  mov [esi+6], ax
  add esi, 8
  mov word [0x92a2], 0xaf21
  mov word [0xa2a2], 0x4dd0
  mov ax, 0xfa59
  mov di, 0xd7e8
  mov ax, [0x92a2]
  nop
  mov ebp, ebp
  arpl ax, di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x92a2]
  mov [esi+6], ax
  add esi, 8
  mov word [0x974c], 0x2334
  mov word [0xa74c], 0x2feb
  mov dx, 0x8a35
  mov di, 0xf2bd
  movzx edx, byte [0x974c]
  arpl dx, di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x974c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x948c], 0xc586
  mov word [0xa48c], 0xb1aa
  mov dx, 0x0b8d
  mov di, 0xec63
  push word [0x948c]
  pop dx
  nop
  mov ebp, ebp
  arpl [0x948c], di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x948c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x93f6], 0xcbb9
  mov word [0xa3f6], 0xc82a
  mov dx, 0xfe36
  mov cx, 0x2941
  mov cx, [0x93f6]
  mov ebp, ebp
  arpl dx, cx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x93f6]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9474], 0xd4a1
  mov word [0xa474], 0xb7b0
  mov cx, 0xc2c9
  mov di, 0x7625
  mov di, [0x9474]
  arpl [0x9474], di
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x9474]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9030], 0xf84d
  mov word [0xa030], 0x5d5c
  mov cx, 0x8686
  mov dx, 0x9059
  mov cx, [0x9030]
  arpl cx, dx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x9030]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9202], 0x1ba4
  mov word [0xa202], 0xe9cd
  mov dx, 0xc8e5
  mov bx, 0xcbcf
  add bx, ax
  mov ebp, ebp
  arpl [0x9202], bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9202]
  mov [esi+6], ax
  add esi, 8
  mov word [0x970c], 0x5319
  mov word [0xa70c], 0x3848
  mov ax, 0xae1b
  mov dx, 0x1aeb
  mov ax, [0x970c]
  arpl ax, dx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x970c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x95d0], 0x0d0e
  mov word [0xa5d0], 0x2400
  mov di, 0x6a78
  mov ax, 0xc0a1
  mov ax, [0x95d0]
  mov ebp, ebp
  mov ebp, ebp
  arpl di, ax
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x95d0]
  mov [esi+6], ax
  add esi, 8
  mov word [0x91d8], 0xf9e4
  mov word [0xa1d8], 0xee96
  mov bx, 0xf5f6
  mov ax, 0xf7b9
  push word [0x91d8]
  pop bx
  arpl [0x91d8], ax
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x91d8]
  mov [esi+6], ax
  add esi, 8
  mov word [0x97a8], 0x52a8
  mov word [0xa7a8], 0x0bd3
  mov dx, 0x6911
  mov bx, 0xb937
  mov bx, [0x97a8]
  nop
  mov ebp, ebp
  arpl dx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x97a8]
  mov [esi+6], ax
  add esi, 8
  mov word [0x95de], 0x5586
  mov word [0xa5de], 0xb61d
  mov ax, 0x7211
  mov bx, 0xa8c9
  movzx eax, byte [0x95de]
  nop
  nop
  arpl ax, bx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x95de]
  mov [esi+6], ax
  add esi, 8
  mov word [0x97e2], 0xb60c
  mov word [0xa7e2], 0x0ed6
  mov cx, 0x0e4d
  mov dx, 0x8f0f
  add dx, cx
  mov ebp, ebp
  mov ebp, ebp
  arpl cx, dx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x97e2]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9148], 0x70e0
  mov word [0xa148], 0x344d
  mov dx, 0x7425
  mov bx, 0xf0ae
  mov bx, [0x9148]
  nop
  arpl dx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9148]
  mov [esi+6], ax
  add esi, 8
  mov word [0x97aa], 0xb021
  mov word [0xa7aa], 0x2b68
  mov di, 0x3d64
  mov ax, 0xc6ee
  movzx edi, byte [0x97aa]
  nop
  arpl di, ax
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x97aa]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9654], 0xed23
  mov word [0xa654], 0xcd82
  mov dx, 0x2b7a
  mov ax, 0x5155
  mov ax, [0x9654]
  arpl [0x9654], ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9654]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9256], 0xf2de
  mov word [0xa256], 0xb368
  mov di, 0x4fd3
  mov bx, 0x4310
  mov di, [0x9256]
  arpl di, bx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9256]
  mov [esi+6], ax
  add esi, 8
  mov word [0x96f0], 0x63bd
  mov word [0xa6f0], 0x6c0d
  mov ax, 0x0e55
  mov dx, 0x80f0
  mov dx, [0x96f0]
  nop
  arpl ax, dx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x96f0]
  mov [esi+6], ax
  add esi, 8
  mov word [0x96b4], 0x431c
  mov word [0xa6b4], 0x1f2e
  mov dx, 0xb523
  mov bx, 0xea94
  movzx ebx, byte [0x96b4]
  nop
  nop
  arpl dx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x96b4]
  mov [esi+6], ax
  add esi, 8
  mov word [0x92ee], 0x0203
  mov word [0xa2ee], 0x4cb2
  mov ax, 0x583d
  mov di, 0x487a
  add ax, di
  arpl ax, di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x92ee]
  mov [esi+6], ax
  add esi, 8
  mov word [0x91b2], 0x1d17
  mov word [0xa1b2], 0x7f3a
  mov di, 0x61f2
  mov bx, 0x8dc8
  mov di, [0x91b2]
  arpl di, bx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x91b2]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9102], 0xe2f1
  mov word [0xa102], 0xa6b6
  mov di, 0x6618
  mov ax, 0x8deb
  add ax, di
  arpl di, ax
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9102]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9728], 0x4636
  mov word [0xa728], 0xd551
  mov dx, 0x3e45
  mov cx, 0xc8e3
  add cx, ax
  nop
  mov ebp, ebp
  arpl [0x9728], cx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9728]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9278], 0xbb7c
  mov word [0xa278], 0x4934
  mov dx, 0x8197
  mov ax, 0x4646
  add dx, ax
  mov ebp, ebp
  arpl [0x9278], ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9278]
  mov [esi+6], ax
  add esi, 8
  mov word [0x96e6], 0xcec0
  mov word [0xa6e6], 0xada0
  mov cx, 0xd7b1
  mov dx, 0x6438
  push word [0x96e6]
  pop dx
  arpl cx, dx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x96e6]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9756], 0xe183
  mov word [0xa756], 0x0942
  mov ax, 0xc4c8
  mov bx, 0xa9ba
  mov [0x9756], bx
  mov ebp, ebp
  nop
  arpl [0x9756], bx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9756]
  mov [esi+6], ax
  add esi, 8
  mov word [0x91ac], 0x2b0a
  mov word [0xa1ac], 0x87f8
  mov ax, 0x8b39
  mov dx, 0x1444
  mov dx, [0x91ac]
  nop
  arpl ax, dx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x91ac]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9262], 0xfd3d
  mov word [0xa262], 0xa772
  mov dx, 0x2dcd
  mov di, 0x8ee1
  mov dx, [0x9262]
  nop
  mov ebp, ebp
  arpl dx, di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9262]
  mov [esi+6], ax
  add esi, 8
  mov word [0x916a], 0x8567
  mov word [0xa16a], 0x2ae0
  mov dx, 0x71df
  mov ax, 0x221c
  push word [0x916a]
  pop dx
  nop
  arpl dx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x916a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9448], 0x4229
  mov word [0xa448], 0x161f
  mov di, 0x7a14
  mov bx, 0x380a
  mov bx, [0x9448]
  nop
  arpl [0x9448], bx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9448]
  mov [esi+6], ax
  add esi, 8
  mov word [0x934a], 0x9475
  mov word [0xa34a], 0xe431
  mov dx, 0x5b15
  mov bx, 0x8a81
  push word [0x934a]
  pop dx
  nop
  arpl [0x934a], bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x934a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9798], 0x7dc9
  mov word [0xa798], 0xe4e4
  mov di, 0x366a
  mov cx, 0xdd46
  movzx ecx, byte [0x9798]
  mov ebp, ebp
  mov ebp, ebp
  arpl di, cx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9798]
  mov [esi+6], ax
  add esi, 8
  mov word [0x932c], 0x4789
  mov word [0xa32c], 0xcf34
  mov cx, 0xb1f2
  mov bx, 0x1bd8
  mov bx, [0x932c]
  arpl [0x932c], bx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x932c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x929c], 0x1c5d
  mov word [0xa29c], 0x2b41
  mov dx, 0xc302
  mov di, 0x9059
  mov [0x929c], di
  arpl [0x929c], di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x929c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9758], 0x5ee6
  mov word [0xa758], 0x50a8
  mov dx, 0x89bf
  mov ax, 0xe443
  mov dx, [0x9758]
  mov ebp, ebp
  arpl dx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9758]
  mov [esi+6], ax
  add esi, 8
  mov word [0x93e8], 0x11a3
  mov word [0xa3e8], 0x9e7d
  mov di, 0x6f8c
  mov dx, 0xb692
  mov dx, [0x93e8]
  arpl di, dx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x93e8]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9476], 0x66e6
  mov word [0xa476], 0x7f11
  mov ax, 0x0288
  mov di, 0x2e84
  push word [0x9476]
  pop ax
  arpl ax, di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9476]
  mov [esi+6], ax
  add esi, 8
  mov word [0x905c], 0x996b
  mov word [0xa05c], 0x9bc5
  mov ax, 0x7732
  mov di, 0x2b41
  mov [0x905c], di
  nop
  mov ebp, ebp
  arpl [0x905c], di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x905c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9264], 0x917f
  mov word [0xa264], 0x4a1c
  mov dx, 0x166b
  mov di, 0xdbc5
  movzx edx, byte [0x9264]
  nop
  nop
  arpl [0x9264], di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9264]
  mov [esi+6], ax
  add esi, 8
  mov word [0x95c4], 0x35b7
  mov word [0xa5c4], 0xc0d4
  mov ax, 0xe71c
  mov dx, 0x19ff
  movzx eax, byte [0x95c4]
  nop
  mov ebp, ebp
  arpl [0x95c4], dx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x95c4]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9178], 0x21d1
  mov word [0xa178], 0xf29d
  mov bx, 0x811f
  mov ax, 0x261e
  push word [0x9178]
  pop bx
  nop
  nop
  arpl bx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9178]
  mov [esi+6], ax
  add esi, 8
  mov word [0x961e], 0x274a
  mov word [0xa61e], 0xf540
  mov bx, 0x931b
  mov di, 0x17ef
  mov [0x961e], di
  nop
  nop
  arpl [0x961e], di
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x961e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x954e], 0x8204
  mov word [0xa54e], 0x9bdc
  mov di, 0x4452
  mov cx, 0x0662
  add di, bx
  nop
  arpl di, cx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x954e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9490], 0xede8
  mov word [0xa490], 0xee8a
  mov bx, 0xeec4
  mov dx, 0x3cac
  mov [0x9490], dx
  arpl [0x9490], dx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9490]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9790], 0x08f6
  mov word [0xa790], 0x9444
  mov dx, 0xeafe
  mov ax, 0x2726
  mov [0x9790], ax
  mov ebp, ebp
  arpl [0x9790], ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9790]
  mov [esi+6], ax
  add esi, 8
  mov word [0x935e], 0x2633
  mov word [0xa35e], 0x2e3c
  mov bx, 0x4892
  mov cx, 0x860b
  push word [0x935e]
  pop bx
  mov ebp, ebp
  nop
  arpl bx, cx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x935e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x97c6], 0xc9c4
  mov word [0xa7c6], 0x0cb7
  mov cx, 0x5171
  mov di, 0x01d6
  add di, bx
  nop
  arpl cx, di
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x97c6]
  mov [esi+6], ax
  add esi, 8
  mov word [0x91ee], 0xa9a3
  mov word [0xa1ee], 0x00e4
  mov bx, 0xa62b
  mov dx, 0xad32
  add bx, cx
  nop
  mov ebp, ebp
  arpl [0x91ee], dx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x91ee]
  mov [esi+6], ax
  add esi, 8
  mov word [0x963e], 0x271d
  mov word [0xa63e], 0xb8ae
  mov ax, 0xdb29
  mov di, 0x8ce1
  mov ax, [0x963e]
  nop
  arpl [0x963e], di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x963e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x93fc], 0x880d
  mov word [0xa3fc], 0xdf5a
  mov dx, 0xa196
  mov cx, 0x6133
  push word [0x93fc]
  pop cx
  arpl dx, cx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x93fc]
  mov [esi+6], ax
  add esi, 8
  mov word [0x914a], 0x1954
  mov word [0xa14a], 0xd25f
  mov bx, 0xe6d7
  mov cx, 0x46f2
  movzx ecx, byte [0x914a]
  nop
  arpl bx, cx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x914a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x92ba], 0xf1c2
  mov word [0xa2ba], 0xd469
  mov di, 0xaff4
  mov cx, 0x9041
  push word [0x92ba]
  pop cx
  mov ebp, ebp
  mov ebp, ebp
  arpl di, cx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x92ba]
  mov [esi+6], ax
  add esi, 8
  mov word [0x964e], 0x3d4e
  mov word [0xa64e], 0x55ac
  mov dx, 0x52c4
  mov di, 0x267c
  mov di, [0x964e]
  mov ebp, ebp
  nop
  arpl dx, di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x964e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x96d6], 0x4779
  mov word [0xa6d6], 0x6283
  mov dx, 0x7cf8
  mov di, 0x2e72
  mov di, [0x96d6]
  nop
  arpl dx, di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x96d6]
  mov [esi+6], ax
  add esi, 8
  mov word [0x933a], 0x0a48
  mov word [0xa33a], 0xd358
  mov dx, 0xc403
  mov bx, 0xd3e8
  movzx edx, byte [0x933a]
  mov ebp, ebp
  arpl dx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x933a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9470], 0xb864
  mov word [0xa470], 0x4072
  mov ax, 0x6e92
  mov di, 0x2f69
  push word [0x9470]
  pop ax
  mov ebp, ebp
  arpl ax, di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9470]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9058], 0x4126
  mov word [0xa058], 0x1082
  mov bx, 0xd9b3
  mov dx, 0xf250
  mov [0x9058], dx
  nop
  arpl [0x9058], dx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9058]
  mov [esi+6], ax
  add esi, 8
  mov word [0x977c], 0xe5dc
  mov word [0xa77c], 0x7f36
  mov ax, 0x37d4
  mov di, 0x7295
  mov di, [0x977c]
  arpl ax, di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x977c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x915c], 0x143f
  mov word [0xa15c], 0x00b3
  mov ax, 0x4055
  mov di, 0x7714
  mov [0x915c], di
  arpl [0x915c], di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x915c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9406], 0xdff6
  mov word [0xa406], 0x3969
  mov dx, 0x32ea
  mov cx, 0x2405
  push word [0x9406]
  pop dx
  mov ebp, ebp
  arpl [0x9406], cx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9406]
  mov [esi+6], ax
  add esi, 8
  mov word [0x902a], 0x9a60
  mov word [0xa02a], 0xebdf
  mov di, 0x8ea5
  mov ax, 0xa1f9
  movzx edi, byte [0x902a]
  nop
  arpl di, ax
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x902a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x94ea], 0x1c51
  mov word [0xa4ea], 0x0b27
  mov ax, 0x6363
  mov di, 0xff22
  movzx edi, byte [0x94ea]
  arpl [0x94ea], di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x94ea]
  mov [esi+6], ax
  add esi, 8
  mov word [0x93a0], 0xfc63
  mov word [0xa3a0], 0x1175
  mov bx, 0xad15
  mov dx, 0xd753
  push word [0x93a0]
  pop dx
  arpl [0x93a0], dx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x93a0]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9348], 0xfdcb
  mov word [0xa348], 0x669c
  mov dx, 0x9f99
  mov ax, 0x634b
  mov ax, [0x9348]
  nop
  arpl [0x9348], ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9348]
  mov [esi+6], ax
  add esi, 8
  mov word [0x97ee], 0x5fe7
  mov word [0xa7ee], 0x7257
  mov dx, 0xf858
  mov ax, 0xd584
  movzx edx, byte [0x97ee]
  nop
  mov ebp, ebp
  arpl [0x97ee], ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x97ee]
  mov [esi+6], ax
  add esi, 8
  mov word [0x96a4], 0x1a8a
  mov word [0xa6a4], 0x1eca
  mov ax, 0x5e42
  mov dx, 0xc961
  add dx, ax
  arpl ax, dx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x96a4]
  mov [esi+6], ax
  add esi, 8
  mov word [0x92f6], 0xef6b
  mov word [0xa2f6], 0x1054
  mov dx, 0x9fa7
  mov cx, 0xc1da
  push word [0x92f6]
  pop cx
  nop
  arpl [0x92f6], cx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x92f6]
  mov [esi+6], ax
  add esi, 8
  mov word [0x914a], 0xb3f3
  mov word [0xa14a], 0xd722
  mov ax, 0x3f56
  mov bx, 0x6a30
  add bx, dx
  nop
  arpl [0x914a], bx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x914a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x95f6], 0xe487
  mov word [0xa5f6], 0x62d4
  mov bx, 0xa588
  mov cx, 0xba7e
  movzx ecx, byte [0x95f6]
  arpl bx, cx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x95f6]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90a6], 0xc04a
  mov word [0xa0a6], 0x11d8
  mov cx, 0xed98
  mov di, 0x200a
  mov cx, [0x90a6]
  nop
  arpl cx, di
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x90a6]
  mov [esi+6], ax
  add esi, 8
  mov word [0x95ce], 0x8b6c
  mov word [0xa5ce], 0xab81
  mov di, 0x1650
  mov dx, 0x863b
  movzx edx, byte [0x95ce]
  mov ebp, ebp
  arpl [0x95ce], dx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x95ce]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9062], 0x77bd
  mov word [0xa062], 0x36ea
  mov di, 0xf34b
  mov ax, 0xee75
  add ax, bx
  nop
  arpl di, ax
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9062]
  mov [esi+6], ax
  add esi, 8
  mov word [0x94da], 0x4d79
  mov word [0xa4da], 0x78e7
  mov cx, 0xa7d5
  mov ax, 0xa39b
  add ax, di
  arpl cx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x94da]
  mov [esi+6], ax
  add esi, 8
  mov word [0x93f4], 0xd0c5
  mov word [0xa3f4], 0x2124
  mov bx, 0x1156
  mov cx, 0xf6a0
  mov [0x93f4], cx
  mov ebp, ebp
  nop
  arpl [0x93f4], cx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x93f4]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9126], 0x879f
  mov word [0xa126], 0x2b0c
  mov bx, 0x6aab
  mov ax, 0x315e
  add ax, bx
  arpl [0x9126], ax
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9126]
  mov [esi+6], ax
  add esi, 8
  mov word [0x93c2], 0x3e09
  mov word [0xa3c2], 0x967d
  mov bx, 0x966a
  mov di, 0x8f0d
  mov [0x93c2], di
  mov ebp, ebp
  arpl [0x93c2], di
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x93c2]
  mov [esi+6], ax
  add esi, 8
  mov word [0x932e], 0xe0f8
  mov word [0xa32e], 0x7eaf
  mov dx, 0x5f18
  mov bx, 0x7d9d
  mov bx, [0x932e]
  arpl [0x932e], bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x932e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9538], 0x212e
  mov word [0xa538], 0xcac9
  mov di, 0x80d8
  mov cx, 0x7ded
  mov [0x9538], cx
  nop
  nop
  arpl [0x9538], cx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9538]
  mov [esi+6], ax
  add esi, 8
  mov word [0x91a2], 0x024c
  mov word [0xa1a2], 0xf314
  mov bx, 0x7654
  mov ax, 0xe587
  push word [0x91a2]
  pop bx
  nop
  arpl [0x91a2], ax
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x91a2]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9132], 0xbe95
  mov word [0xa132], 0x5b03
  mov cx, 0xe5f2
  mov dx, 0x8517
  movzx ecx, byte [0x9132]
  arpl cx, dx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x9132]
  mov [esi+6], ax
  add esi, 8
  mov word [0x937a], 0x132d
  mov word [0xa37a], 0xbcc7
  mov di, 0xae16
  mov dx, 0x4861
  mov di, [0x937a]
  arpl di, dx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x937a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x902e], 0xa78d
  mov word [0xa02e], 0xd167
  mov ax, 0xbe5d
  mov dx, 0x5ecb
  mov [0x902e], dx
  nop
  arpl [0x902e], dx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x902e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x97ee], 0xf78e
  mov word [0xa7ee], 0x2065
  mov cx, 0xd0fb
  mov ax, 0x33e9
  add cx, di
  arpl cx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x97ee]
  mov [esi+6], ax
  add esi, 8
  mov word [0x968e], 0x910c
  mov word [0xa68e], 0x9d7d
  mov bx, 0xd5ef
  mov dx, 0x1a4b
  push word [0x968e]
  pop dx
  mov ebp, ebp
  arpl [0x968e], dx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x968e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9640], 0xcf58
  mov word [0xa640], 0x6847
  mov dx, 0x0302
  mov cx, 0xde4a
  mov cx, [0x9640]
  nop
  arpl dx, cx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9640]
  mov [esi+6], ax
  add esi, 8
  mov word [0x975e], 0x5339
  mov word [0xa75e], 0x428c
  mov bx, 0x0798
  mov dx, 0x1a77
  mov [0x975e], dx
  arpl [0x975e], dx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x975e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x95ee], 0x57e7
  mov word [0xa5ee], 0x4ab1
  mov bx, 0xb225
  mov ax, 0x910c
  mov ax, [0x95ee]
  nop
  nop
  arpl [0x95ee], ax
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x95ee]
  mov [esi+6], ax
  add esi, 8
  mov word [0x94d2], 0x40d8
  mov word [0xa4d2], 0x1645
  mov bx, 0xf729
  mov cx, 0xa109
  mov bx, [0x94d2]
  mov ebp, ebp
  nop
  arpl bx, cx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x94d2]
  mov [esi+6], ax
  add esi, 8
  mov word [0x938c], 0xcf18
  mov word [0xa38c], 0x6468
  mov di, 0xf227
  mov cx, 0x5dad
  mov [0x938c], cx
  arpl [0x938c], cx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x938c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9280], 0xc464
  mov word [0xa280], 0xb7ea
  mov ax, 0x3f01
  mov di, 0x4c86
  mov di, [0x9280]
  nop
  nop
  arpl ax, di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9280]
  mov [esi+6], ax
  add esi, 8
  mov word [0x91e2], 0xc798
  mov word [0xa1e2], 0xe955
  mov ax, 0x9cc8
  mov bx, 0xd713
  push word [0x91e2]
  pop ax
  mov ebp, ebp
  arpl ax, bx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x91e2]
  mov [esi+6], ax
  add esi, 8
  mov word [0x92dc], 0x0bf7
  mov word [0xa2dc], 0x01cb
  mov bx, 0xfa9f
  mov di, 0xee38
  mov di, [0x92dc]
  mov ebp, ebp
  arpl bx, di
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x92dc]
  mov [esi+6], ax
  add esi, 8
  mov word [0x91b6], 0x225d
  mov word [0xa1b6], 0x41c4
  mov bx, 0xb797
  mov di, 0xdc77
  push word [0x91b6]
  pop bx
  nop
  arpl [0x91b6], di
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x91b6]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9504], 0x28f1
  mov word [0xa504], 0x1bc8
  mov cx, 0xc177
  mov ax, 0x45ba
  mov cx, [0x9504]
  arpl cx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x9504]
  mov [esi+6], ax
  add esi, 8
  mov word [0x921a], 0xfbd6
  mov word [0xa21a], 0x9365
  mov ax, 0x5489
  mov dx, 0x7137
  mov ax, [0x921a]
  mov ebp, ebp
  arpl [0x921a], dx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x921a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x974c], 0x4982
  mov word [0xa74c], 0x8221
  mov di, 0xf5d0
  mov dx, 0x6aa9
  mov [0x974c], dx
  nop
  arpl [0x974c], dx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x974c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9096], 0x65db
  mov word [0xa096], 0x5d3b
  mov dx, 0xce93
  mov bx, 0x528c
  movzx ebx, byte [0x9096]
  mov ebp, ebp
  mov ebp, ebp
  arpl [0x9096], bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9096]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90c6], 0xb834
  mov word [0xa0c6], 0xe7f4
  mov dx, 0x358f
  mov ax, 0x810a
  mov [0x90c6], ax
  mov ebp, ebp
  mov ebp, ebp
  arpl [0x90c6], ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x90c6]
  mov [esi+6], ax
  add esi, 8
  mov word [0x95e6], 0x4ada
  mov word [0xa5e6], 0xb872
  mov dx, 0xa962
  mov di, 0x29ab
  add dx, cx
  nop
  mov ebp, ebp
  arpl dx, di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x95e6]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9500], 0x00ea
  mov word [0xa500], 0x114d
  mov dx, 0x717a
  mov bx, 0x4c79
  push word [0x9500]
  pop bx
  mov ebp, ebp
  arpl dx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9500]
  mov [esi+6], ax
  add esi, 8
  mov word [0x93a2], 0x1756
  mov word [0xa3a2], 0x0b69
  mov cx, 0x1bd9
  mov di, 0x0156
  mov [0x93a2], di
  mov ebp, ebp
  arpl [0x93a2], di
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x93a2]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9396], 0xd393
  mov word [0xa396], 0x9a30
  mov ax, 0x4477
  mov bx, 0x688a
  push word [0x9396]
  pop bx
  arpl [0x9396], bx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9396]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9736], 0x310d
  mov word [0xa736], 0x2099
  mov cx, 0x4a15
  mov dx, 0x8a1e
  add dx, ax
  arpl cx, dx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x9736]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9718], 0xfc57
  mov word [0xa718], 0x7f3b
  mov di, 0x5487
  mov dx, 0x0034
  mov di, [0x9718]
  arpl di, dx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9718]
  mov [esi+6], ax
  add esi, 8
  mov word [0x93cc], 0x5184
  mov word [0xa3cc], 0x1de3
  mov bx, 0x35b7
  mov cx, 0x0652
  mov [0x93cc], cx
  nop
  nop
  arpl [0x93cc], cx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x93cc]
  mov [esi+6], ax
  add esi, 8
  mov word [0x96a4], 0x596a
  mov word [0xa6a4], 0x9e67
  mov bx, 0x20a6
  mov cx, 0x99bc
  movzx ebx, byte [0x96a4]
  mov ebp, ebp
  nop
  arpl bx, cx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x96a4]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9148], 0xe7ac
  mov word [0xa148], 0x59cc
  mov bx, 0x73af
  mov di, 0x35e7
  push word [0x9148]
  pop bx
  nop
  nop
  arpl bx, di
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9148]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9440], 0xdf42
  mov word [0xa440], 0x87d4
  mov dx, 0x975b
  mov ax, 0x6f1a
  mov dx, [0x9440]
  nop
  nop
  arpl [0x9440], ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9440]
  mov [esi+6], ax
  add esi, 8
  mov word [0x928c], 0xa75b
  mov word [0xa28c], 0x6245
  mov cx, 0xc704
  mov dx, 0xa838
  mov [0x928c], dx
  arpl [0x928c], dx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x928c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x978c], 0x0344
  mov word [0xa78c], 0x0d93
  mov bx, 0xdfda
  mov di, 0x77b8
  mov [0x978c], di
  nop
  arpl [0x978c], di
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x978c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x92be], 0x4a08
  mov word [0xa2be], 0x10da
  mov bx, 0x0dc6
  mov ax, 0x394a
  mov bx, [0x92be]
  nop
  mov ebp, ebp
  arpl bx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x92be]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90aa], 0x46dc
  mov word [0xa0aa], 0x15d5
  mov ax, 0x22ba
  mov cx, 0x17e7
  mov ax, [0x90aa]
  mov ebp, ebp
  nop
  arpl ax, cx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x90aa]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9624], 0x36d7
  mov word [0xa624], 0x7e3f
  mov di, 0x6954
  mov ax, 0x6804
  mov di, [0x9624]
  arpl [0x9624], ax
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9624]
  mov [esi+6], ax
  add esi, 8
  mov word [0x97a2], 0x3323
  mov word [0xa7a2], 0x43eb
  mov ax, 0x321a
  mov bx, 0x68f4
  push word [0x97a2]
  pop bx
  mov ebp, ebp
  arpl [0x97a2], bx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x97a2]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9484], 0x18c8
  mov word [0xa484], 0xbc6d
  mov dx, 0xa443
  mov bx, 0xf3c1
  push word [0x9484]
  pop dx
  nop
  arpl dx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9484]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9780], 0x18a2
  mov word [0xa780], 0x6ee2
  mov ax, 0x2e89
  mov bx, 0x9300
  mov bx, [0x9780]
  nop
  arpl ax, bx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9780]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9010], 0xb213
  mov word [0xa010], 0xfb4d
  mov dx, 0x30fe
  mov ax, 0xfba3
  movzx edx, byte [0x9010]
  mov ebp, ebp
  arpl dx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9010]
  mov [esi+6], ax
  add esi, 8
  mov word [0x928a], 0x9145
  mov word [0xa28a], 0x6def
  mov di, 0x768a
  mov dx, 0xff23
  mov dx, [0x928a]
  arpl di, dx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x928a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x91ac], 0xa73d
  mov word [0xa1ac], 0xb613
  mov ax, 0x30b7
  mov di, 0xcd73
  add ax, bx
  nop
  mov ebp, ebp
  arpl [0x91ac], di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x91ac]
  mov [esi+6], ax
  add esi, 8
  mov word [0x92bc], 0xc234
  mov word [0xa2bc], 0x7797
  mov dx, 0xebfc
  mov di, 0x40f6
  mov [0x92bc], di
  nop
  mov ebp, ebp
  arpl [0x92bc], di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x92bc]
  mov [esi+6], ax
  add esi, 8
  mov word [0x927c], 0xe68e
  mov word [0xa27c], 0xa58c
  mov di, 0x56cf
  mov dx, 0xed22
  add dx, di
  arpl [0x927c], dx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x927c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9310], 0x88f3
  mov word [0xa310], 0x9a5f
  mov bx, 0x4f26
  mov cx, 0x4fdd
  mov cx, [0x9310]
  mov ebp, ebp
  mov ebp, ebp
  arpl [0x9310], cx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9310]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9422], 0x341f
  mov word [0xa422], 0x5446
  mov dx, 0x3409
  mov cx, 0x640f
  add dx, cx
  mov ebp, ebp
  arpl dx, cx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9422]
  mov [esi+6], ax
  add esi, 8
  mov word [0x91b4], 0x8fc5
  mov word [0xa1b4], 0x69b3
  mov cx, 0xc6d4
  mov ax, 0xed86
  mov cx, [0x91b4]
  arpl cx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x91b4]
  mov [esi+6], ax
  add esi, 8
  mov word [0x94bc], 0xed32
  mov word [0xa4bc], 0x0b52
  mov bx, 0x489b
  mov cx, 0x83b1
  mov [0x94bc], cx
  mov ebp, ebp
  nop
  arpl [0x94bc], cx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x94bc]
  mov [esi+6], ax
  add esi, 8
  mov word [0x96bc], 0x7506
  mov word [0xa6bc], 0x750b
  mov cx, 0x5cee
  mov di, 0x3f99
  add di, dx
  nop
  arpl cx, di
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x96bc]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9280], 0x8007
  mov word [0xa280], 0xd8df
  mov cx, 0xf72a
  mov di, 0xe90f
  mov cx, [0x9280]
  mov ebp, ebp
  nop
  arpl cx, di
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x9280]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9638], 0xfacc
  mov word [0xa638], 0x3677
  mov dx, 0x1387
  mov ax, 0x80a0
  mov [0x9638], ax
  arpl [0x9638], ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9638]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9592], 0x33c1
  mov word [0xa592], 0xe9df
  mov cx, 0x68f3
  mov dx, 0xf393
  mov [0x9592], dx
  arpl [0x9592], dx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x9592]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9690], 0xe9f0
  mov word [0xa690], 0x6b90
  mov dx, 0x5e1b
  mov bx, 0xc8f4
  mov [0x9690], bx
  arpl [0x9690], bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9690]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90e6], 0x8142
  mov word [0xa0e6], 0x8c78
  mov di, 0xc380
  mov dx, 0xcca3
  mov di, [0x90e6]
  arpl [0x90e6], dx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x90e6]
  mov [esi+6], ax
  add esi, 8
  mov word [0x943e], 0x37f0
  mov word [0xa43e], 0x72e8
  mov bx, 0x9b63
  mov dx, 0xcd0b
  mov [0x943e], dx
  arpl [0x943e], dx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x943e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9364], 0x543d
  mov word [0xa364], 0x4233
  mov bx, 0x2346
  mov di, 0x62e7
  add bx, cx
  mov ebp, ebp
  arpl bx, di
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9364]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9782], 0xb5a1
  mov word [0xa782], 0x75fe
  mov dx, 0x88eb
  mov cx, 0xc096
  movzx ecx, byte [0x9782]
  nop
  arpl dx, cx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9782]
  mov [esi+6], ax
  add esi, 8
  mov word [0x93ea], 0x9a88
  mov word [0xa3ea], 0xa401
  mov dx, 0xf587
  mov bx, 0xf847
  add dx, dx
  arpl dx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x93ea]
  mov [esi+6], ax
  add esi, 8
  mov word [0x915c], 0xa63f
  mov word [0xa15c], 0x47e2
  mov bx, 0xb0b7
  mov ax, 0x07ac
  movzx ebx, byte [0x915c]
  arpl bx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x915c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x919e], 0x4914
  mov word [0xa19e], 0x779f
  mov dx, 0x5f0f
  mov bx, 0xe767
  push word [0x919e]
  pop dx
  arpl dx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x919e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9172], 0x9816
  mov word [0xa172], 0x650d
  mov di, 0xfd2a
  mov cx, 0x6d1b
  mov [0x9172], cx
  arpl [0x9172], cx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9172]
  mov [esi+6], ax
  add esi, 8
  mov word [0x91e4], 0x876b
  mov word [0xa1e4], 0xd68c
  mov bx, 0x77e5
  mov ax, 0x4757
  add ax, di
  arpl bx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x91e4]
  mov [esi+6], ax
  add esi, 8
  mov word [0x93f0], 0xff10
  mov word [0xa3f0], 0x5448
  mov cx, 0x0361
  mov di, 0x521a
  push word [0x93f0]
  pop di
  mov ebp, ebp
  mov ebp, ebp
  arpl cx, di
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x93f0]
  mov [esi+6], ax
  add esi, 8
  mov word [0x96b2], 0x269a
  mov word [0xa6b2], 0x5c6c
  mov dx, 0xb883
  mov di, 0x0e9b
  mov dx, [0x96b2]
  nop
  mov ebp, ebp
  arpl dx, di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x96b2]
  mov [esi+6], ax
  add esi, 8
  mov word [0x97c0], 0x49fa
  mov word [0xa7c0], 0x115a
  mov ax, 0x6d3d
  mov di, 0xd4c8
  movzx eax, byte [0x97c0]
  nop
  arpl ax, di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x97c0]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9796], 0x6be4
  mov word [0xa796], 0x917c
  mov dx, 0xded1
  mov bx, 0xaf14
  add bx, di
  arpl dx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9796]
  mov [esi+6], ax
  add esi, 8
  mov word [0x97e6], 0xceb5
  mov word [0xa7e6], 0xaadd
  mov dx, 0x8b1b
  mov bx, 0xb08a
  mov bx, [0x97e6]
  mov ebp, ebp
  nop
  arpl dx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x97e6]
  mov [esi+6], ax
  add esi, 8
  mov word [0x920a], 0x2cd6
  mov word [0xa20a], 0x1481
  mov dx, 0xcc39
  mov bx, 0xcfe3
  mov [0x920a], bx
  nop
  mov ebp, ebp
  arpl [0x920a], bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x920a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9018], 0x17c1
  mov word [0xa018], 0x613f
  mov dx, 0xf33a
  mov ax, 0x1ecb
  mov [0x9018], ax
  mov ebp, ebp
  nop
  arpl [0x9018], ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9018]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9366], 0x1435
  mov word [0xa366], 0xea6f
  mov di, 0x5909
  mov ax, 0x33e5
  movzx edi, byte [0x9366]
  arpl di, ax
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9366]
  mov [esi+6], ax
  add esi, 8
  mov word [0x95e6], 0x4703
  mov word [0xa5e6], 0x9e62
  mov ax, 0x8418
  mov cx, 0x9aa5
  mov cx, [0x95e6]
  nop
  arpl ax, cx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x95e6]
  mov [esi+6], ax
  add esi, 8
  mov word [0x97f6], 0x1429
  mov word [0xa7f6], 0x3cd9
  mov bx, 0xd796
  mov ax, 0xcf2e
  add bx, ax
  mov ebp, ebp
  nop
  arpl bx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x97f6]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9152], 0xf1c3
  mov word [0xa152], 0x6caf
  mov bx, 0x4db4
  mov ax, 0x07f3
  add bx, ax
  nop
  nop
  arpl [0x9152], ax
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9152]
  mov [esi+6], ax
  add esi, 8
  mov word [0x978e], 0x091a
  mov word [0xa78e], 0x8d07
  mov ax, 0x7c0a
  mov dx, 0xe6cc
  movzx eax, byte [0x978e]
  arpl ax, dx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x978e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x94b0], 0xff06
  mov word [0xa4b0], 0xebd1
  mov cx, 0x8212
  mov ax, 0x1af6
  movzx ecx, byte [0x94b0]
  arpl [0x94b0], ax
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x94b0]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9638], 0x9f43
  mov word [0xa638], 0x9fff
  mov di, 0x54fd
  mov ax, 0xf900
  mov [0x9638], ax
  arpl [0x9638], ax
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9638]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9704], 0xf089
  mov word [0xa704], 0x553b
  mov dx, 0x4a31
  mov bx, 0x3bc0
  push word [0x9704]
  pop dx
  mov ebp, ebp
  mov ebp, ebp
  arpl dx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9704]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9556], 0x95b3
  mov word [0xa556], 0x8f4f
  mov bx, 0x1f0b
  mov dx, 0xaa01
  mov [0x9556], dx
  nop
  nop
  arpl [0x9556], dx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9556]
  mov [esi+6], ax
  add esi, 8
  mov word [0x96da], 0x7e02
  mov word [0xa6da], 0xc0db
  mov di, 0xc653
  mov dx, 0xc09d
  mov [0x96da], dx
  arpl [0x96da], dx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x96da]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9006], 0xa49f
  mov word [0xa006], 0x86ad
  mov bx, 0x893a
  mov dx, 0xd851
  mov dx, [0x9006]
  nop
  mov ebp, ebp
  arpl bx, dx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9006]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9460], 0xfffc
  mov word [0xa460], 0xb196
  mov di, 0x2b8d
  mov cx, 0xf832
  add di, cx
  nop
  arpl di, cx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9460]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9412], 0x04cc
  mov word [0xa412], 0xc51b
  mov bx, 0xeb60
  mov cx, 0x2ce7
  mov [0x9412], cx
  nop
  arpl [0x9412], cx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9412]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9426], 0xa459
  mov word [0xa426], 0xf403
  mov cx, 0x675b
  mov di, 0x60d8
  mov di, [0x9426]
  arpl [0x9426], di
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x9426]
  mov [esi+6], ax
  add esi, 8
  mov word [0x95be], 0xce13
  mov word [0xa5be], 0x4c4a
  mov dx, 0x7e1b
  mov bx, 0x16d5
  add bx, ax
  mov ebp, ebp
  arpl dx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x95be]
  mov [esi+6], ax
  add esi, 8
  mov word [0x907c], 0xb099
  mov word [0xa07c], 0x8fa3
  mov cx, 0x0a88
  mov bx, 0x302b
  mov cx, [0x907c]
  arpl cx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x907c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x936a], 0x85f0
  mov word [0xa36a], 0x8f45
  mov di, 0xda16
  mov bx, 0x31b8
  add di, dx
  arpl di, bx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x936a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9156], 0x0e17
  mov word [0xa156], 0x1a1c
  mov cx, 0x11d2
  mov di, 0xbd40
  movzx edi, byte [0x9156]
  nop
  arpl cx, di
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x9156]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9170], 0x83ae
  mov word [0xa170], 0xa32e
  mov bx, 0x7767
  mov ax, 0x2df8
  movzx eax, byte [0x9170]
  arpl bx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9170]
  mov [esi+6], ax
  add esi, 8
  mov word [0x93c2], 0x7185
  mov word [0xa3c2], 0x5820
  mov cx, 0x13c7
  mov bx, 0x8300
  push word [0x93c2]
  pop cx
  nop
  nop
  arpl [0x93c2], bx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x93c2]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90e4], 0x33bd
  mov word [0xa0e4], 0x4a22
  mov di, 0xa2a7
  mov bx, 0x02f5
  mov bx, [0x90e4]
  mov ebp, ebp
  mov ebp, ebp
  arpl di, bx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x90e4]
  mov [esi+6], ax
  add esi, 8
  mov word [0x952e], 0xbe4d
  mov word [0xa52e], 0x8396
  mov ax, 0xc7b4
  mov di, 0x3f8f
  push word [0x952e]
  pop di
  nop
  arpl ax, di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x952e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x977c], 0x63e4
  mov word [0xa77c], 0x1270
  mov cx, 0x505c
  mov ax, 0x70ec
  mov cx, [0x977c]
  mov ebp, ebp
  nop
  arpl cx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x977c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9058], 0x267a
  mov word [0xa058], 0xe798
  mov ax, 0xadf7
  mov di, 0xa527
  mov di, [0x9058]
  nop
  arpl ax, di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9058]
  mov [esi+6], ax
  add esi, 8
  mov word [0x938a], 0x1d0b
  mov word [0xa38a], 0x5c48
  mov cx, 0xe71a
  mov bx, 0x4a17
  add cx, dx
  mov ebp, ebp
  arpl [0x938a], bx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x938a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x94be], 0xab44
  mov word [0xa4be], 0x55e9
  mov ax, 0x8576
  mov bx, 0xfb65
  mov ax, [0x94be]
  mov ebp, ebp
  arpl ax, bx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x94be]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90e8], 0x6c1c
  mov word [0xa0e8], 0xf475
  mov ax, 0x928d
  mov dx, 0x3d06
  push word [0x90e8]
  pop ax
  mov ebp, ebp
  arpl ax, dx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x90e8]
  mov [esi+6], ax
  add esi, 8
  mov word [0x918e], 0xc7c1
  mov word [0xa18e], 0x942f
  mov cx, 0xd4ce
  mov dx, 0x530b
  mov cx, [0x918e]
  mov ebp, ebp
  nop
  arpl cx, dx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x918e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9574], 0x47c0
  mov word [0xa574], 0xe2d1
  mov ax, 0x00fc
  mov di, 0x92a2
  mov di, [0x9574]
  mov ebp, ebp
  arpl [0x9574], di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9574]
  mov [esi+6], ax
  add esi, 8
  mov word [0x946c], 0x5c82
  mov word [0xa46c], 0x46b1
  mov bx, 0x5c39
  mov cx, 0x75f9
  movzx ebx, byte [0x946c]
  arpl bx, cx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x946c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9460], 0x59c3
  mov word [0xa460], 0x697d
  mov ax, 0x462a
  mov di, 0x6265
  mov [0x9460], di
  nop
  arpl [0x9460], di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9460]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9686], 0x1c59
  mov word [0xa686], 0xb1fe
  mov ax, 0xaba1
  mov cx, 0x9042
  movzx ecx, byte [0x9686]
  arpl [0x9686], cx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9686]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9442], 0x7f26
  mov word [0xa442], 0x5f42
  mov bx, 0xbbf4
  mov cx, 0x12c6
  mov cx, [0x9442]
  mov ebp, ebp
  nop
  arpl bx, cx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9442]
  mov [esi+6], ax
  add esi, 8
  mov word [0x91ee], 0xb6a3
  mov word [0xa1ee], 0x7d4c
  mov bx, 0xa457
  mov ax, 0xc345
  mov [0x91ee], ax
  arpl [0x91ee], ax
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x91ee]
  mov [esi+6], ax
  add esi, 8
  mov word [0x97ea], 0xe493
  mov word [0xa7ea], 0x0d20
  mov dx, 0x44cc
  mov ax, 0x0a97
  mov ax, [0x97ea]
  arpl [0x97ea], ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x97ea]
  mov [esi+6], ax
  add esi, 8
  mov word [0x91a4], 0x9fb3
  mov word [0xa1a4], 0x803c
  mov cx, 0x0f65
  mov dx, 0x09f5
  mov cx, [0x91a4]
  nop
  mov ebp, ebp
  arpl [0x91a4], dx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x91a4]
  mov [esi+6], ax
  add esi, 8
  mov word [0x93d0], 0xe36f
  mov word [0xa3d0], 0x34aa
  mov di, 0xb38e
  mov bx, 0x3014
  movzx edi, byte [0x93d0]
  arpl [0x93d0], bx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x93d0]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9478], 0x3857
  mov word [0xa478], 0x3e7b
  mov bx, 0x3e3a
  mov di, 0xcfb1
  mov di, [0x9478]
  nop
  nop
  arpl [0x9478], di
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9478]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9658], 0x5422
  mov word [0xa658], 0x0979
  mov di, 0xc709
  mov bx, 0xd749
  mov [0x9658], bx
  nop
  mov ebp, ebp
  arpl [0x9658], bx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9658]
  mov [esi+6], ax
  add esi, 8
  mov word [0x956a], 0xcd29
  mov word [0xa56a], 0x7b12
  mov ax, 0xab8f
  mov bx, 0xdf04
  mov [0x956a], bx
  mov ebp, ebp
  arpl [0x956a], bx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x956a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9532], 0x4b12
  mov word [0xa532], 0xb4f3
  mov di, 0x7fa2
  mov ax, 0xd822
  movzx edi, byte [0x9532]
  nop
  arpl di, ax
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9532]
  mov [esi+6], ax
  add esi, 8
  mov word [0x96ec], 0x66cd
  mov word [0xa6ec], 0x0aa9
  mov ax, 0x7371
  mov bx, 0x4760
  add bx, bx
  nop
  nop
  arpl [0x96ec], bx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x96ec]
  mov [esi+6], ax
  add esi, 8
  mov word [0x945e], 0x1251
  mov word [0xa45e], 0x3375
  mov di, 0x804c
  mov dx, 0x3e4f
  mov [0x945e], dx
  arpl [0x945e], dx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x945e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90a0], 0x9336
  mov word [0xa0a0], 0x39e0
  mov bx, 0x9c5e
  mov cx, 0xb1f2
  movzx ebx, byte [0x90a0]
  arpl [0x90a0], cx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x90a0]
  mov [esi+6], ax
  add esi, 8
  mov word [0x915a], 0xeece
  mov word [0xa15a], 0x4bfc
  mov di, 0xe144
  mov dx, 0x3f72
  mov [0x915a], dx
  arpl [0x915a], dx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x915a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x949c], 0x8c58
  mov word [0xa49c], 0x7c9f
  mov dx, 0x2cfa
  mov di, 0x9307
  add dx, bx
  arpl dx, di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x949c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x94da], 0xf4a9
  mov word [0xa4da], 0xf01c
  mov dx, 0x9efa
  mov di, 0x0fda
  mov di, [0x94da]
  nop
  arpl [0x94da], di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x94da]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9656], 0x0614
  mov word [0xa656], 0xb48e
  mov di, 0x5318
  mov bx, 0x7a22
  push word [0x9656]
  pop bx
  mov ebp, ebp
  arpl [0x9656], bx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9656]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90e8], 0x0b27
  mov word [0xa0e8], 0x512f
  mov cx, 0x2233
  mov bx, 0xb22c
  add cx, di
  mov ebp, ebp
  arpl cx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x90e8]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9278], 0xd560
  mov word [0xa278], 0xac8d
  mov ax, 0xb474
  mov dx, 0x47d8
  movzx eax, byte [0x9278]
  mov ebp, ebp
  nop
  arpl ax, dx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9278]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9208], 0xd379
  mov word [0xa208], 0x34eb
  mov bx, 0x0236
  mov dx, 0xd222
  mov [0x9208], dx
  nop
  mov ebp, ebp
  arpl [0x9208], dx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9208]
  mov [esi+6], ax
  add esi, 8
  mov word [0x96ae], 0x8f01
  mov word [0xa6ae], 0x38d8
  mov bx, 0xc255
  mov cx, 0xe791
  movzx ecx, byte [0x96ae]
  mov ebp, ebp
  arpl [0x96ae], cx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x96ae]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9526], 0x0376
  mov word [0xa526], 0xffc4
  mov bx, 0xc2e7
  mov di, 0xe358
  push word [0x9526]
  pop bx
  mov ebp, ebp
  nop
  arpl bx, di
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9526]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9168], 0xa900
  mov word [0xa168], 0xa5d1
  mov bx, 0x7c3c
  mov cx, 0xa6d1
  mov cx, [0x9168]
  nop
  arpl [0x9168], cx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9168]
  mov [esi+6], ax
  add esi, 8
  mov word [0x94cc], 0x9ff5
  mov word [0xa4cc], 0xdfd3
  mov dx, 0xdc30
  mov di, 0xc76e
  add di, ax
  mov ebp, ebp
  mov ebp, ebp
  arpl dx, di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x94cc]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9194], 0xd1ac
  mov word [0xa194], 0xbfb3
  mov ax, 0xcd41
  mov dx, 0x4ef5
  mov dx, [0x9194]
  mov ebp, ebp
  arpl ax, dx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9194]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9178], 0x5768
  mov word [0xa178], 0xb9b6
  mov di, 0xa2db
  mov dx, 0xbbba
  mov di, [0x9178]
  nop
  arpl [0x9178], dx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9178]
  mov [esi+6], ax
  add esi, 8
  mov word [0x96ba], 0x5013
  mov word [0xa6ba], 0x9471
  mov dx, 0x6a64
  mov bx, 0x604f
  add dx, ax
  nop
  mov ebp, ebp
  arpl dx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x96ba]
  mov [esi+6], ax
  add esi, 8
  mov word [0x902a], 0x016c
  mov word [0xa02a], 0x9d0d
  mov ax, 0x0200
  mov di, 0x9be1
  add ax, di
  arpl ax, di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x902a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x97f6], 0x8833
  mov word [0xa7f6], 0x4995
  mov cx, 0x65a7
  mov dx, 0xd27b
  mov [0x97f6], dx
  arpl [0x97f6], dx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x97f6]
  mov [esi+6], ax
  add esi, 8
  mov word [0x91b4], 0x0edd
  mov word [0xa1b4], 0x3340
  mov cx, 0x26fa
  mov dx, 0x5750
  mov [0x91b4], dx
  mov ebp, ebp
  arpl [0x91b4], dx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x91b4]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90fe], 0x0665
  mov word [0xa0fe], 0xa548
  mov di, 0x49b0
  mov bx, 0x79fd
  push word [0x90fe]
  pop bx
  arpl [0x90fe], bx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x90fe]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9594], 0x6220
  mov word [0xa594], 0xe651
  mov ax, 0xc574
  mov cx, 0x0a02
  mov ax, [0x9594]
  arpl ax, cx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9594]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9708], 0x1bf2
  mov word [0xa708], 0x7a01
  mov di, 0x7fa8
  mov ax, 0x721f
  mov di, [0x9708]
  arpl di, ax
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9708]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9018], 0xe92f
  mov word [0xa018], 0x9b7b
  mov cx, 0xd635
  mov bx, 0x8101
  add cx, cx
  mov ebp, ebp
  nop
  arpl cx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x9018]
  mov [esi+6], ax
  add esi, 8
  mov word [0x905a], 0x7c9d
  mov word [0xa05a], 0x2cc8
  mov bx, 0x58d0
  mov di, 0x5700
  push word [0x905a]
  pop di
  arpl [0x905a], di
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x905a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x95ce], 0x3ad2
  mov word [0xa5ce], 0xab87
  mov dx, 0xc56d
  mov di, 0xabf8
  add dx, ax
  mov ebp, ebp
  arpl dx, di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x95ce]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9778], 0x9132
  mov word [0xa778], 0xb05f
  mov bx, 0x796e
  mov cx, 0xdf03
  mov bx, [0x9778]
  nop
  arpl bx, cx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9778]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9212], 0x2f6d
  mov word [0xa212], 0x6480
  mov cx, 0x8a11
  mov dx, 0x416e
  mov [0x9212], dx
  mov ebp, ebp
  arpl [0x9212], dx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x9212]
  mov [esi+6], ax
  add esi, 8
  mov word [0x95e2], 0xb4b1
  mov word [0xa5e2], 0x6ed5
  mov cx, 0xcf70
  mov dx, 0xc0f8
  movzx ecx, byte [0x95e2]
  mov ebp, ebp
  arpl cx, dx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x95e2]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9218], 0x8582
  mov word [0xa218], 0xe175
  mov cx, 0xbc69
  mov di, 0x7e14
  add cx, cx
  arpl cx, di
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x9218]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9628], 0x0eb3
  mov word [0xa628], 0x4a46
  mov ax, 0x9f1f
  mov bx, 0x07ae
  add ax, cx
  arpl ax, bx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9628]
  mov [esi+6], ax
  add esi, 8
  mov word [0x95c8], 0x980a
  mov word [0xa5c8], 0x62b9
  mov ax, 0x21bf
  mov cx, 0x9f5f
  mov ax, [0x95c8]
  arpl [0x95c8], cx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x95c8]
  mov [esi+6], ax
  add esi, 8
  mov word [0x95b0], 0xce87
  mov word [0xa5b0], 0xedce
  mov bx, 0x43ab
  mov dx, 0x8d94
  mov dx, [0x95b0]
  arpl bx, dx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x95b0]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9066], 0xecd7
  mov word [0xa066], 0x7f31
  mov dx, 0xcd11
  mov di, 0xb448
  movzx edx, byte [0x9066]
  arpl [0x9066], di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9066]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90a4], 0xcf2f
  mov word [0xa0a4], 0x147a
  mov dx, 0x52f3
  mov cx, 0xdc85
  mov cx, [0x90a4]
  nop
  arpl dx, cx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x90a4]
  mov [esi+6], ax
  add esi, 8
  mov word [0x92de], 0x748f
  mov word [0xa2de], 0xfeeb
  mov ax, 0x8269
  mov bx, 0xdeaf
  movzx ebx, byte [0x92de]
  arpl [0x92de], bx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x92de]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90c0], 0x7d29
  mov word [0xa0c0], 0x38ed
  mov dx, 0x1302
  mov ax, 0xa319
  mov ax, [0x90c0]
  nop
  arpl dx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x90c0]
  mov [esi+6], ax
  add esi, 8
  mov word [0x947e], 0x2e0b
  mov word [0xa47e], 0xb2b4
  mov bx, 0xd913
  mov cx, 0xe296
  push word [0x947e]
  pop cx
  nop
  nop
  arpl bx, cx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x947e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x97d4], 0x60eb
  mov word [0xa7d4], 0x165e
  mov di, 0x85bb
  mov cx, 0x595c
  mov [0x97d4], cx
  arpl [0x97d4], cx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x97d4]
  mov [esi+6], ax
  add esi, 8
  mov word [0x93fe], 0x1e67
  mov word [0xa3fe], 0x560a
  mov cx, 0xb734
  mov bx, 0xb1c8
  add cx, cx
  mov ebp, ebp
  nop
  arpl [0x93fe], bx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x93fe]
  mov [esi+6], ax
  add esi, 8
  mov word [0x93ce], 0x7bc1
  mov word [0xa3ce], 0x0302
  mov bx, 0xe3db
  mov di, 0x4425
  movzx edi, byte [0x93ce]
  mov ebp, ebp
  nop
  arpl bx, di
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x93ce]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9556], 0x3c66
  mov word [0xa556], 0xd969
  mov cx, 0x56a2
  mov dx, 0x4f40
  mov [0x9556], dx
  mov ebp, ebp
  arpl [0x9556], dx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x9556]
  mov [esi+6], ax
  add esi, 8
  mov word [0x94a0], 0x0655
  mov word [0xa4a0], 0xb890
  mov cx, 0xf924
  mov ax, 0x69b1
  mov cx, [0x94a0]
  arpl cx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x94a0]
  mov [esi+6], ax
  add esi, 8
  mov word [0x91c4], 0x9e2a
  mov word [0xa1c4], 0xe562
  mov dx, 0x39d9
  mov cx, 0x5298
  push word [0x91c4]
  pop cx
  mov ebp, ebp
  arpl [0x91c4], cx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x91c4]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90ba], 0x0589
  mov word [0xa0ba], 0xefe0
  mov di, 0xf896
  mov ax, 0x2afe
  movzx eax, byte [0x90ba]
  mov ebp, ebp
  nop
  arpl di, ax
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x90ba]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9308], 0xa4c4
  mov word [0xa308], 0x0440
  mov bx, 0xb7f5
  mov di, 0x2e93
  movzx edi, byte [0x9308]
  mov ebp, ebp
  nop
  arpl [0x9308], di
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9308]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9652], 0x4a4f
  mov word [0xa652], 0x97b6
  mov ax, 0xbc5b
  mov cx, 0x5f18
  movzx eax, byte [0x9652]
  arpl ax, cx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9652]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9610], 0x5e7c
  mov word [0xa610], 0xb665
  mov dx, 0xa3eb
  mov bx, 0x75e0
  push word [0x9610]
  pop dx
  mov ebp, ebp
  mov ebp, ebp
  arpl [0x9610], bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9610]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9672], 0x19e1
  mov word [0xa672], 0x6ed1
  mov ax, 0xfd1f
  mov cx, 0xd890
  add ax, dx
  nop
  nop
  arpl ax, cx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9672]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9716], 0xcd82
  mov word [0xa716], 0x2de8
  mov cx, 0x1473
  mov dx, 0xe106
  add cx, cx
  mov ebp, ebp
  nop
  arpl [0x9716], dx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x9716]
  mov [esi+6], ax
  add esi, 8
  mov word [0x924a], 0x9107
  mov word [0xa24a], 0x24dc
  mov di, 0x1c50
  mov bx, 0xd7a8
  push word [0x924a]
  pop di
  nop
  arpl di, bx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x924a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x960e], 0x976b
  mov word [0xa60e], 0x0225
  mov cx, 0xe2e5
  mov dx, 0xb23a
  mov [0x960e], dx
  arpl [0x960e], dx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x960e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x952c], 0xebc3
  mov word [0xa52c], 0xdb53
  mov bx, 0x4f08
  mov ax, 0xcd7f
  mov [0x952c], ax
  nop
  nop
  arpl [0x952c], ax
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x952c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x96bc], 0xbcbe
  mov word [0xa6bc], 0xf622
  mov dx, 0x4611
  mov bx, 0x993f
  push word [0x96bc]
  pop dx
  arpl [0x96bc], bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x96bc]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9258], 0xbe78
  mov word [0xa258], 0xd52f
  mov bx, 0xb852
  mov ax, 0x7b00
  mov [0x9258], ax
  mov ebp, ebp
  arpl [0x9258], ax
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9258]
  mov [esi+6], ax
  add esi, 8
  mov word [0x93a2], 0x5c6a
  mov word [0xa3a2], 0x67d8
  mov dx, 0x397b
  mov ax, 0x7148
  push word [0x93a2]
  pop dx
  arpl dx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x93a2]
  mov [esi+6], ax
  add esi, 8
  mov word [0x93a0], 0xea93
  mov word [0xa3a0], 0x73fe
  mov dx, 0x39dd
  mov di, 0x2913
  add dx, bx
  arpl dx, di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x93a0]
  mov [esi+6], ax
  add esi, 8
  mov word [0x91a2], 0xeb83
  mov word [0xa1a2], 0xc8af
  mov di, 0x57ae
  mov ax, 0x621f
  mov [0x91a2], ax
  nop
  arpl [0x91a2], ax
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x91a2]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90ea], 0xcf07
  mov word [0xa0ea], 0x794b
  mov cx, 0x182d
  mov bx, 0xbea4
  mov cx, [0x90ea]
  arpl cx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x90ea]
  mov [esi+6], ax
  add esi, 8
  mov word [0x94cc], 0x3db7
  mov word [0xa4cc], 0x456c
  mov cx, 0xda19
  mov di, 0x2ce7
  mov [0x94cc], di
  arpl [0x94cc], di
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x94cc]
  mov [esi+6], ax
  add esi, 8
  mov word [0x95ac], 0x5604
  mov word [0xa5ac], 0xbbe5
  mov di, 0xaecb
  mov ax, 0x05f6
  push word [0x95ac]
  pop di
  arpl di, ax
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x95ac]
  mov [esi+6], ax
  add esi, 8
  mov word [0x97d2], 0x1646
  mov word [0xa7d2], 0xb4f6
  mov di, 0x3304
  mov dx, 0xb623
  mov [0x97d2], dx
  nop
  arpl [0x97d2], dx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x97d2]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9412], 0xb56d
  mov word [0xa412], 0x62e4
  mov ax, 0xe4be
  mov dx, 0x0ae5
  mov [0x9412], dx
  nop
  arpl [0x9412], dx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9412]
  mov [esi+6], ax
  add esi, 8
  mov word [0x91c4], 0x25c3
  mov word [0xa1c4], 0x844f
  mov ax, 0x5edb
  mov di, 0x4cec
  mov [0x91c4], di
  mov ebp, ebp
  arpl [0x91c4], di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x91c4]
  mov [esi+6], ax
  add esi, 8
  mov word [0x944c], 0xe35f
  mov word [0xa44c], 0x0710
  mov cx, 0x0cad
  mov bx, 0xaf4a
  mov bx, [0x944c]
  mov ebp, ebp
  arpl cx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x944c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x92ea], 0xc8fe
  mov word [0xa2ea], 0xf396
  mov ax, 0x510a
  mov cx, 0xe5ad
  add ax, di
  nop
  mov ebp, ebp
  arpl ax, cx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x92ea]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9218], 0x165a
  mov word [0xa218], 0x6c3a
  mov cx, 0x56e6
  mov bx, 0xb8d3
  movzx ebx, byte [0x9218]
  mov ebp, ebp
  arpl cx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x9218]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9018], 0xabc7
  mov word [0xa018], 0xf785
  mov dx, 0xaae5
  mov bx, 0x7407
  mov dx, [0x9018]
  arpl dx, bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9018]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9254], 0x498c
  mov word [0xa254], 0x8b9a
  mov di, 0xc4d4
  mov ax, 0x8bf2
  mov di, [0x9254]
  mov ebp, ebp
  mov ebp, ebp
  arpl di, ax
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9254]
  mov [esi+6], ax
  add esi, 8
  mov word [0x908a], 0x30c4
  mov word [0xa08a], 0x6603
  mov di, 0xda3d
  mov cx, 0x32af
  push word [0x908a]
  pop cx
  arpl di, cx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x908a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x94dc], 0xaed9
  mov word [0xa4dc], 0xb9ad
  mov cx, 0x7d8b
  mov ax, 0xb36b
  mov [0x94dc], ax
  mov ebp, ebp
  mov ebp, ebp
  arpl [0x94dc], ax
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x94dc]
  mov [esi+6], ax
  add esi, 8
  mov word [0x952a], 0xf682
  mov word [0xa52a], 0xbc0c
  mov ax, 0x7ca1
  mov bx, 0x7839
  push word [0x952a]
  pop ax
  arpl [0x952a], bx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x952a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9720], 0xcaca
  mov word [0xa720], 0x9ad5
  mov bx, 0x567c
  mov di, 0x21f5
  mov di, [0x9720]
  mov ebp, ebp
  arpl [0x9720], di
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9720]
  mov [esi+6], ax
  add esi, 8
  mov word [0x912c], 0x6166
  mov word [0xa12c], 0x28f9
  mov di, 0x5b84
  mov dx, 0x9bc4
  mov [0x912c], dx
  mov ebp, ebp
  arpl [0x912c], dx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x912c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9114], 0xf812
  mov word [0xa114], 0xa375
  mov dx, 0x59b8
  mov di, 0x8d3f
  push word [0x9114]
  pop dx
  arpl dx, di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9114]
  mov [esi+6], ax
  add esi, 8
  mov word [0x937e], 0x186b
  mov word [0xa37e], 0xcc94
  mov cx, 0xe555
  mov ax, 0x6693
  mov [0x937e], ax
  nop
  arpl [0x937e], ax
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x937e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90e8], 0x420e
  mov word [0xa0e8], 0x18e2
  mov cx, 0x289b
  mov dx, 0x259a
  mov [0x90e8], dx
  nop
  arpl [0x90e8], dx
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x90e8]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9454], 0x07ae
  mov word [0xa454], 0xa552
  mov ax, 0x0e1e
  mov dx, 0x6ca8
  push word [0x9454]
  pop dx
  nop
  mov ebp, ebp
  arpl ax, dx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9454]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90ea], 0xd41b
  mov word [0xa0ea], 0x1747
  mov dx, 0x2ca5
  mov cx, 0xab46
  add cx, dx
  nop
  arpl [0x90ea], cx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x90ea]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90e4], 0xd48c
  mov word [0xa0e4], 0xa888
  mov dx, 0x5038
  mov bx, 0x2fd8
  mov dx, [0x90e4]
  arpl [0x90e4], bx
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x90e4]
  mov [esi+6], ax
  add esi, 8
  mov word [0x95b8], 0xb934
  mov word [0xa5b8], 0xd8b1
  mov di, 0xb02e
  mov ax, 0x4e8b
  movzx eax, byte [0x95b8]
  arpl di, ax
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x95b8]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9080], 0x9e56
  mov word [0xa080], 0xe804
  mov dx, 0x8e78
  mov di, 0xb903
  mov [0x9080], di
  mov ebp, ebp
  nop
  arpl [0x9080], di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9080]
  mov [esi+6], ax
  add esi, 8
  mov word [0x979c], 0x3317
  mov word [0xa79c], 0xb999
  mov dx, 0x4d1a
  mov ax, 0x74d2
  add dx, ax
  nop
  nop
  arpl [0x979c], ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x979c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x92e8], 0x84aa
  mov word [0xa2e8], 0xbb31
  mov di, 0x4c73
  mov cx, 0x5ad8
  movzx edi, byte [0x92e8]
  nop
  mov ebp, ebp
  arpl di, cx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x92e8]
  mov [esi+6], ax
  add esi, 8
  mov word [0x97fa], 0x6d20
  mov word [0xa7fa], 0xb03e
  mov cx, 0xc72e
  mov di, 0xeb92
  mov di, [0x97fa]
  nop
  arpl [0x97fa], di
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x97fa]
  mov [esi+6], ax
  add esi, 8
  mov word [0x966c], 0xb38c
  mov word [0xa66c], 0x1eb6
  mov ax, 0x74cb
  mov cx, 0xc082
  add cx, cx
  arpl [0x966c], cx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x966c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x93de], 0x7677
  mov word [0xa3de], 0xb567
  mov dx, 0x680a
  mov di, 0xa6ef
  add di, dx
  nop
  arpl dx, di
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x93de]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9446], 0x45e6
  mov word [0xa446], 0x99a4
  mov cx, 0x90ac
  mov di, 0x2d47
  push word [0x9446]
  pop cx
  nop
  arpl [0x9446], di
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x9446]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9364], 0x1ab0
  mov word [0xa364], 0x6b6d
  mov di, 0xb881
  mov bx, 0x17a6
  add di, bx
  arpl di, bx
  pushfd
  pop dword [esi]
  mov [esi+4], di
  mov ax, [0x9364]
  mov [esi+6], ax
  add esi, 8
  mov word [0x91c8], 0x4dc9
  mov word [0xa1c8], 0x04d3
  mov dx, 0x444a
  mov ax, 0x9afc
  mov ax, [0x91c8]
  mov ebp, ebp
  nop
  arpl dx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x91c8]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9170], 0xd412
  mov word [0xa170], 0xadd8
  mov bx, 0xcb19
  mov di, 0xabdc
  mov bx, [0x9170]
  nop
  nop
  arpl bx, di
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9170]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9228], 0x7698
  mov word [0xa228], 0xdc6a
  mov ax, 0x35b1
  mov cx, 0x0a34
  mov ax, [0x9228]
  nop
  arpl ax, cx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9228]
  mov [esi+6], ax
  add esi, 8
  mov word [0x922c], 0xdb61
  mov word [0xa22c], 0x0150
  mov ax, 0x5ba3
  mov di, 0x72a4
  movzx eax, byte [0x922c]
  nop
  mov ebp, ebp
  arpl ax, di
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x922c]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9370], 0x72aa
  mov word [0xa370], 0x2510
  mov ax, 0x8bc3
  mov bx, 0x5abc
  mov ax, [0x9370]
  mov ebp, ebp
  arpl [0x9370], bx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x9370]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90c4], 0xd0f5
  mov word [0xa0c4], 0xb9a8
  mov ax, 0x88cf
  mov dx, 0x056c
  push word [0x90c4]
  pop ax
  mov ebp, ebp
  mov ebp, ebp
  arpl ax, dx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x90c4]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9662], 0xd80b
  mov word [0xa662], 0xa2f3
  mov bx, 0xd69a
  mov dx, 0xc415
  mov dx, [0x9662]
  mov ebp, ebp
  arpl bx, dx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x9662]
  mov [esi+6], ax
  add esi, 8
  mov word [0x93d2], 0x8263
  mov word [0xa3d2], 0xc101
  mov cx, 0x7b45
  mov ax, 0x6597
  movzx ecx, byte [0x93d2]
  arpl cx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x93d2]
  mov [esi+6], ax
  add esi, 8
  mov word [0x967e], 0xa614
  mov word [0xa67e], 0xe285
  mov ax, 0xa198
  mov cx, 0xe936
  mov [0x967e], cx
  arpl [0x967e], cx
  pushfd
  pop dword [esi]
  mov [esi+4], ax
  mov ax, [0x967e]
  mov [esi+6], ax
  add esi, 8
  mov word [0x957a], 0xc281
  mov word [0xa57a], 0x7807
  mov bx, 0xc1f6
  mov di, 0xb5dd
  movzx ebx, byte [0x957a]
  mov ebp, ebp
  arpl bx, di
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x957a]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9392], 0x87a4
  mov word [0xa392], 0x8649
  mov dx, 0xf251
  mov ax, 0xb20f
  mov [0x9392], ax
  mov ebp, ebp
  nop
  arpl [0x9392], ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9392]
  mov [esi+6], ax
  add esi, 8
  mov word [0x95d2], 0x68e0
  mov word [0xa5d2], 0x5698
  mov cx, 0xbb49
  mov ax, 0x7a2f
  movzx ecx, byte [0x95d2]
  arpl cx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], cx
  mov ax, [0x95d2]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90b0], 0xa4d8
  mov word [0xa0b0], 0xc334
  mov bx, 0xb938
  mov cx, 0xdb2a
  mov bx, [0x90b0]
  nop
  arpl bx, cx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x90b0]
  mov [esi+6], ax
  add esi, 8
  mov word [0x95d6], 0xb69a
  mov word [0xa5d6], 0x9ad4
  mov bx, 0xe7d6
  mov ax, 0x2d0e
  push word [0x95d6]
  pop ax
  mov ebp, ebp
  arpl bx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x95d6]
  mov [esi+6], ax
  add esi, 8
  mov word [0x92ca], 0x4cbd
  mov word [0xa2ca], 0x0307
  mov bx, 0x42d3
  mov di, 0xbbdd
  add bx, di
  mov ebp, ebp
  arpl bx, di
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x92ca]
  mov [esi+6], ax
  add esi, 8
  mov word [0x9336], 0x0069
  mov word [0xa336], 0x84f3
  mov dx, 0x1d8f
  mov ax, 0x5b5b
  push word [0x9336]
  pop ax
  mov ebp, ebp
  arpl [0x9336], ax
  pushfd
  pop dword [esi]
  mov [esi+4], dx
  mov ax, [0x9336]
  mov [esi+6], ax
  add esi, 8
  mov word [0x97e4], 0x2d7b
  mov word [0xa7e4], 0x6742
  mov bx, 0x41b0
  mov ax, 0xd8a6
  push word [0x97e4]
  pop ax
  arpl bx, ax
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x97e4]
  mov [esi+6], ax
  add esi, 8
  mov word [0x90aa], 0x972a
  mov word [0xa0aa], 0xd0db
  mov bx, 0xdca7
  mov dx, 0x837a
  push word [0x90aa]
  pop bx
  nop
  arpl bx, dx
  pushfd
  pop dword [esi]
  mov [esi+4], bx
  mov ax, [0x90aa]
  mov [esi+6], ax
  add esi, 8
  hlt
align 8
idt: times 256*8 db 0
