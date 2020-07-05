DATA_REG = 129
CONTROL_REG = 128

RTS_LOW = #16
RTS_HIGH = #56

uart_init:
    ld a, 3, c, CONTROL_REG : out (c), a
    ld a, RTS_HIGH : out (c), a
    ret

uread:
   ld a, RTS_LOW, c, CONTROL_REG : out (c), a
   in a, (c) : and 1 : jr z, .exit

   ld a, RTS_HIGH, c, CONTROL_REG : out (c), a
   in a, (DATA_REG) : scf : ret
.exit
    ld a, RTS_HIGH, c, CONTROL_REG : out (c), a
    or a
    ret

ureadb:
    call uread : jr nc, ureadb
    ret

uwrite:
    in a, (CONTROL_REG) : and 2 : jr z, uwrite
    ld c, DATA_REG, a, e : out (c), a
    ret

w_uwrite:
    FORTH_WORD "UWRITE"
    rst #18
    call uwrite
    jp (iy)

w_ureads:
    FORTH_WORD "UREADS"
    call ureadb
    ld d, 0, e, a
    rst #10
    jp (iy)

w_uread:
    FORTH_WORD "UREAD"
    ld de, #ffff
    call uread
    jr nc, .fine
    ld d, 0, e, a
.fine
    rst #10
    jp (iy)

w_uinit:
    FORTH_WORD "UINIT"
    call uart_init
    jp (iy)