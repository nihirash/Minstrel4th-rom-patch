DATA_REG = 129
CONTROL_REG = 128
RTS_LOW = #16
RTS_HIGH = #56
LAST_WORD = #1D58

    device zxspectrum48 // Only for using SAVEBIN
    org #0
    incbin "minstrel.rom"

    org #1ffd
    dw uinit_w.link ; Here you should put new link to words

    org #2800

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


ubget:
.name db "UBGE", 'T' + #80
.name_end
    dw LAST_WORD
.link
    db .name_end - .name
    dw $ + 2
    di
    call uart_init
    ld e, 'p' : call uwrite
    call #05df
    jr c, .error
    push de
    push bc
.sendNameLoop
    push bc
    push de
    ld a, (de)
    ld e, a : call uwrite
    pop de
    inc de
    pop bc
    dec bc
    ld a, b : or c : jr nz, .sendNameLoop
    pop bc
    pop de
    call #07da
.performReceive
    ld e, '?' : call uwrite
    call ureadb : ld l, a
    call ureadb : ld h, a
    or l : jr z, .error
    push hl
    rst #18
    pop bc
.downloop
    push bc
    call ureadb
    ld (de), a
    inc de
    pop bc
    dec bc
    ld a, b : or c : jr nz, .downloop
.exit   
    ei
    jp (iy)
.error
    ei 
    rst #10 : db #0a
    jp (iy)
;
; Here goes word definitions. Format dead easy:
; n-bytes word name with last char ored to #80

uwrite_w:
.name db "UWRIT", 'E' + #80
.name_end
    dw ubget.link
.link
    db .name_end - .name
    dw $ + 2

    rst #18
    call uwrite
    jp (iy)

ureads_w:
.name db "UREAD", 'S' + #80
.name_end 
    dw uwrite_w.link
.link
    db .name_end - .name
    dw $ + 2
    call ureadb
    ld d, 0, e, a
    rst #10
    jp (iy)

uread_w:
.name db "UREA", 'D' + #80
.name_end 
    dw ureads_w.link
.link 
    db .name_end - .name
    dw $ + 2
    ld de, #ffff
    call uread
    jr nc, .fine
    ld d, 0, e, a
.fine
    rst #10
    jp (iy)

uinit_w:
.name db "UINI", 'T' + #80
.name_end
    dw uread_w.link
.link
    db .name_end - .name
    dw $ + 2
    call uart_init
    jp (iy)
.end

    savebin "patched.rom", 0, 16384