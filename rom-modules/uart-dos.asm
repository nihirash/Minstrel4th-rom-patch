;;;;;;;;;;;;;;;;;;;;;;; Constants section
BINARY_GET_COMMAND = 'p'
BINARY_PUT_COMMAND = 'P'
GET_CATALOG_COMMAND = 'C'
GET_TAP_BLOCK_COMMAND = 'D'
SAVE_TAP_BLOCK_COMMAND = 'U'
TAP_IN_COMMAND = 'T'
TAP_OUT_COMMAND = 't'

;;;;;;;;;;;;;;;;;;;;;;; Forth's words used
F_WORD_TO_PAD = #1A10
F_PREPARE_BSAVE_HEADER = #1A3D
F_EXIT = #04B6 

;;;;;;;;;;;;;;;;;;;;;;; Forth's vars section
FORTH_MODE = #0ec3

CRC_FIELD = #27fe

TMP_CURRENT = #2701
TMP_CONTEXT = #2703
TMP_VOCLINK = #2705
TMP_STKBOT = #2707
TMP_DICT = #2709

VAR_CURRENT = #3C31
VAR_CONTEXT = #3C33
VAR_VOCLNK = #3C35 
VAR_STKBOT = #3C37
VAR_DICT = #3C4C ;; ACTUAL
VAR_SPARE = #3C3B

    IFDEF INRAM
.name
        ABYTEC 0 "UARTDOS"
.name_end
        dw UART_DOS_END - .name_end
        dw LINK
        SET_VAR LINK, $
        db .name_end - .name
        dw 0x0fec
    ENDIF

;;;;;;;;;;;;;;;;;;;;;;; Assembly routines

printZ:
    ld a, (hl)
    and a : ret z
    push hl : rst #08 : pop hl
    inc hl
    jr printZ 

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

justSkipName:
     call #05df
     ret c
     call #07da
     ret

; Receive from UART block type and name and display it
getBlockTypeAndName:
    call ureadb : ld e, a ; Save block type
    ld hl, block_dict
    and a : jr z, .doPrint
    ld hl, block_bytes
.doPrint
    call printZ
    ld b, 10
.loop
    push bc
    call ureadb : rst #08
    pop bc
    djnz .loop

    ld a, 13 : rst #08
    ld a, e
    ret

block_dict db 13, "Dict: ", 0
block_bytes db 13, "Bytes: ", 0

loadVar:
    call ureadb : ld (hl), a : inc hl : call ureadb : ld (hl), a : inc hl
    ret

sendCRC:
    ld e, a
    ld a, (CRC_FIELD)
    xor (hl) : ld (CRC_FIELD), a
    call uwrite
    ret

storeBlock:
    di
    push hl, de
    ;; Send command
    ld e, SAVE_TAP_BLOCK_COMMAND : call uwrite
    call ureadb : and a : jr z, .error

    pop de : push de
    ;; Send chunk size
    inc de 
    ld a, e
    call sendCRC : ld a, d : call sendCRC

    ; Blank crc
    xor a : ld (CRC_FIELD), a

    pop de, hl
.loop

    push hl, de
    ld a, (hl)
    call sendCRC
    pop de, hl
    inc hl : dec de
    ld a, d : or e : jr z, .fin
    jr .loop
.fin
    ld a, (CRC_FIELD), e, a : call uwrite
    ei
    ret
.error
    pop de, hl
    ei
    rst #20 : db #0a
    ret

;;;;;;;;;;;;;;;;;;;;;;; Words section
hw_store_data: ; Hidden word
    dw .code
.code
    call uart_init
    ld a, (#2302) ; length of word in pad
    and a : jp z, #1AB6 ; Tape error
    ld hl, (#230c), a, h  : or l : jp z, #1AB6
    push hl
    ld de, #19, hl, #2301
    call storeBlock
    pop de
    ld hl, (#230e)
    call storeBlock
    jp (iy)

    IFDEF INRAM
UART_DOS_END:
    ENDIF

w_bsave:
    FORTH_WORD_ADDR "UBSAVE", FORTH_MODE
    dw F_PREPARE_BSAVE_HEADER  
    dw hw_store_data
    dw F_EXIT
.word_end
	
w_save:
    FORTH_WORD_ADDR "USAVE", FORTH_MODE
    dw F_WORD_TO_PAD              
    dw hw_store_data
    dw F_EXIT
.word_end

w_tapout:
    FORTH_WORD "TAPOUT"
    di
    call uart_init
    ld e, TAP_OUT_COMMAND : call uwrite
    jr w_tapin.common
.word_end

w_tapin:
    FORTH_WORD "TAPIN"
    di
    call uart_init
    ld e, TAP_IN_COMMAND : call uwrite
.common
    call sendFileName : jr c, .error
    call ureadb : and a : jr z, .error ; Is file found?
    ei
    jp (iy)
.error
    ei
    ld e, 0 : call uwrite
    rst #20 : db #0a
    jp (iy)
.word_end

w_bload:
    FORTH_WORD_ADDR "UBLOAD", FORTH_MODE
    di
    call justSkipName
    call uart_init
    ld e, GET_TAP_BLOCK_COMMAND : call uwrite
    call ureadb : and a : jp z, w_load.error
    call getBlockTypeAndName : and a : jp z, w_load.error
    ld e, 1 : call uwrite
    ld hl, TMP_CURRENT 
    ld b, 10 
.varsloop
    push bc
    call ureadb ;; IGNORE VARS
    pop bc
    djnz .varsloop
    call ureadb : ld l, a : call ureadb : ld h, a ; Data len
    call ureadb : ld e, a : call ureadb : ld d, a ; Org
    ld (TMP_CURRENT), hl, (TMP_CONTEXT), de

    ;; size
    rst #18
    ld hl, TMP_CURRENT, a, d : or e : call nz, .save
    ;; org
    rst #18
    ld hl, TMP_CONTEXT, a, d: or e : call nz, .save
    
    ld hl, (TMP_CURRENT), de, (TMP_CONTEXT)
.loop
    push hl, de
    call ureadb
    ld (de), a
    pop de, hl
    inc de : dec hl : ld a, l : or h : jr nz, .loop

.exit
    ei
    jp (iy)
.save
    ld (hl), de
    ret
.word_end

w_load:
    FORTH_WORD_ADDR "ULOAD", FORTH_MODE
    call justSkipName
    call uart_init
    ld e, GET_TAP_BLOCK_COMMAND : call uwrite
    call ureadb : and a : jr z, .error
    call getBlockTypeAndName : and a : jr nz, .error

    ld e, 1 : call uwrite ; Send confirm byte 
    di
    ;; Loading vars

    ld hl, TMP_DICT : call loadVar
    ld hl, TMP_CURRENT 
    dup 4
    call loadVar 
    edup 

    call ureadb : ld l, a : call ureadb : ld h, a ; Data len
    call ureadb : ld e, a : call ureadb : ld d, a ; Org
    push hl
    ld hl, (TMP_STKBOT)
    ld bc, #0c : add hl, bc
    ld (VAR_SPARE), hl
    pop hl
.loop
    push hl, de
    call ureadb : ld (de), a
    pop de, hl
    inc de
    dec hl : ld a, h : or l : jr z, .exit
    jp .loop
    
.exit
    ld hl, TMP_CURRENT, de, VAR_CURRENT, bc, 8 : ldir ; moving vars 
    ld hl, (TMP_DICT), (VAR_DICT), hl 
    
    ei
    jp (iy)

.error
    ld e, 0 : call uwrite ; Send cancel byte
    rst #20 : db #0a
    ei 
    jp (iy)
.word_end

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
.word_end

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
.word_end

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
.word_end

end:	
