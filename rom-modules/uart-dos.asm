;;;;;;;;;;;;;;;;;;;;;;; Constants section
BINARY_GET_COMMAND = 'p'
BINARY_PUT_COMMAND = 'P'
GET_CATALOG_COMMAND = 'C'

;;;;;;;;;;;;;;;;;;;;;;; Assembly routines

; Routine that sends file name by uart as ASCIIZ string
; Filename goes after(SIC!) your word. Like usual load/bload
sendFileName:
    call #05df ; Find next word ROM routine
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
    call #07da ; Clean word ROM routine
.performReceive
    ld e, 0 : call uwrite
    or a
    ret
.error 
    scf
    ret


;;;;;;;;;;;;;;;;;;;;;;; Words section
w_ls:
    FORTH_WORD "LS"
    di
    call uart_init
    ld e, GET_CATALOG_COMMAND : call uwrite
    ld a, 13 : rst #08
.loop
    call ureadb
    cp #ff : jr z, .exit
    rst #08
    jp .loop
.exit
    ld a, 13 : rst #08
    ei 
    jp (iy)

w_ubput:
    FORTH_WORD "UBPUT"
    di
    call uart_init

    ld e, BINARY_PUT_COMMAND : call uwrite
    call sendFileName : jr c, .error
    
    rst #18 ; File size
    push de
    call uwrite : ld e, d : call uwrite

    rst #18
    ex hl, de
    pop bc
.sendLoop
    push bc
    ld a, (hl), e, a : call uwrite
    inc hl
    pop bc
    dec bc
    ld a, b : or c
    jr nz, .sendLoop

.exit
    ei
    jp (iy)
.error
    ei
    rst #20 : db #0a
    jp (iy)

w_ubget:
    FORTH_WORD "UBGET"
    di
    call uart_init
    ld e, BINARY_GET_COMMAND : call uwrite
    call sendFileName : jr c, .error
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
    rst #20 : db #0a
    jp (iy)
