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
F_GET_BUFFER_TEXT = 0x05DF
F_CLEAN_WORD = 0x07da
	
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

;;;;;;;;;;;;;;;;;;;;;;; Assembly routines

;; printZ:
;;     ld a, (hl)
;;     and a : ret z
;;     push hl : rst #08 : pop hl
;;     inc hl
;;     jr printZ 

	;; ========================================================
	;; Read filename from input buffer and send as ASCII string
	;;
	;; On entry
	;;   Filename should be next token in input buffer
	;;
	;; On exit
	;;   Carry Set 	- Error
	;; ========================================================
sendFileName:
	call F_GET_BUFFER_TEXT	; Find next word ROM routine

	jr c, .error

	;; DE = address of filename; BC = length
	push de 		
	push bc			; Save for later (to remove word from buffer)

.sendNameLoop:
	;; Transmit word
	ld a, (de)

	push bc 		
	call SENDW
	pop bc

	jr nc, .okay 		; Send succeeded, so continue

	pop bc
	pop de
	jr .error

.okay:
	inc de
	dec bc
	ld a, b
	or c
	jr nz, .sendNameLoop

	pop bc
	pop de
	call F_CLEAN_WORD	; Clean-up word ROM routine

.performReceive:
	;; ld e, 0 : call uwrite (original command)
	xor a
	call SENDW
	ret			; Carry flag correct from SENDW
.error 
	scf			; Indicates error
	ret

	;; ========================================================
	;; Skip filename. Remove next word from input buffer.
	;;
	;; On entry
	;;   Filename should be next token in input buffer
	;;
	;; On exit
	;;   Carry Set 	- Error
	;; ========================================================
justSkipName:
	call F_GET_BUFFER_TEXT
	ret c			; Indicates error
	call F_CLEAN_WORD
	and a			; Indicates success
	ret

	;; Receive from UART block type and name and display it
getBlockTypeAndName:
	call RECVW		; Read character
	ret c			; Indicates error
	ld e, a 		; Save block type for later
	;;    call ureadb : ld e, a ; Save block type
	ld hl, block_dict
	and a
	jr z, .doPrint		; Zero indicates dictionary file
	ld hl, block_bytes	; Otherwise, assume is code block
	
.doPrint
	call PRINT_MSG
	ld b, 10		; Expect 10 characters
.loop
	push bc
	call RECVW		; Read character
	jr nc, .cont		; Continue, if successful
	pop bc			; Balance stack
	ret			; Carry flag is set
.cont:
	rst 0x08		; Print character
	pop bc
	djnz .loop

	ld a, 13
	rst #08			
	ld a, e			; Retrieve block type
	and a			; Indicate success
	
	ret
	
block_dict:	db 13, "Dict: ", 0
block_bytes:	db 13, "Bytes: ", 0

loadVar:
	call RECVW
	ret c			; Indicates timeout
	ld (hl), a
	inc hl
	call RECVW
	ret c			; Indicates timeout
	ld (hl), a
	inc hl
	and a			; Reset carry to indicate success
	ret
	

sendCRC:
	ld e, a			; Save data
	ld a, (CRC_FIELD)	; Retrieve checksum
	xor (hl)		; Update checksum
	ld (CRC_FIELD), a	; Store checksum
	ld a,e			; Retrieve data
	call SENDW		; Send data
	ret			; Carry flag indicates success/ failure

	;; ========================================================
	;; Transmit block of data over serial interface
	;; 
	;; On entry:
	;; 	HL = start of block
	;; 	DE = length of block
	;; On exit:
	;; 	Success - Carry clear
	;; 	Fail    - Carry set
	;; 	Always  - primary and alternate registes corrupted
	;; ========================================================
storeBlock:
	di			; Disable interrupts to get enough speed
	push hl			; Save start and length for later
	push de
	
	;; Send command
	ld a, SAVE_TAP_BLOCK_COMMAND
	call SENDW
	jr c, .error

	;; Check for acknowledgement
	call RECVW
	jr c, .error
	and a
	jr z, .error

	pop de			; Retrieve/ resave block length
	push de

	;; Send (block size+1)
	inc de 
	ld a, e
	call sendCRC
	jr c, .error
	ld a, d
	call sendCRC
	jr c, .error

	;; Blank CRC
	xor a
	ld (CRC_FIELD), a

	pop de
	pop hl
	
.loop:
	push hl
	push de
	ld a, (hl)
	call sendCRC
	jr c, .error
	pop de
	pop hl
	inc hl
	dec de
	ld a, d
	or e
	jr z, .fin
	jr .loop

.fin:
	ld a, (CRC_FIELD)
	call SENDW
	jr c, .error2
	ei
	ret
.error:
	pop de
	pop hl
.error2:
	ei

	rst #20			; Abort, tape error
	db #0a

	ret

;;;;;;;;;;;;;;;;;;;;;;; Words section
hw_store_data: ; Hidden word
    dw .code
.code
	call uart_init
	ld a, (#2302) 		; length of word in pad
	and a			; Check is nonzero
	jp z, #1AB6		; Tape error, if zero
	ld hl, (#230c)		; Retrieve length of block
	ld a, h			; Check is nonzero
	or l
	jp z, #1AB6		; Tape error, if zero
	
	push hl			; Save block length
	
	ld de, #19		; Length of header
	ld hl, #2301		; Start of header
	call storeBlock		; Send header
	
	pop de			; Retrieve block length
	ld hl, (#230e)		; Start of block
	call storeBlock		; Send block
	
	jp (iy)			; End of Word

w_bsave:
	FORTH_WORD_ADDR "BSAVE", FORTH_MODE
	dw F_PREPARE_BSAVE_HEADER  
	dw hw_store_data
	dw F_EXIT
    
w_save:
	FORTH_WORD_ADDR "SAVE", FORTH_MODE
	dw F_WORD_TO_PAD              
	dw hw_store_data
	dw F_EXIT

w_tapout:
	FORTH_WORD "TAPOUT"
	di
	call uart_init
	ld a, TAP_OUT_COMMAND
	call SENDW
	jr c, .error
	jr w_tapin.common
.error:
	ei
	rst #20			; Abort, tape error
	db #0a
	ret

w_tapin:
	FORTH_WORD "TAPIN"
	di
	call uart_init
	ld a, TAP_IN_COMMAND
	call SENDW
	jr c, .error
.common
	call sendFileName
	jr c, .error
	call RECVW
	jr c, .error
	and a
	jr z, .error ; Is file found?
	ei
	jp (iy)
	
.error
	ei
	xor a
	call SENDW
	
	rst #20
	db #0a

	jp (iy)

w_bload:
	FORTH_WORD "BLOAD"
	di
	call justSkipName
	call uart_init
	ld a, GET_TAP_BLOCK_COMMAND
	call SENDW
	jp c, w_load.error

	call RECVW
	jp c, w_load.error
	and a
	jp z, w_load.error

	call getBlockTypeAndName
	jp c, w_load.error

	and a
	jp z, w_load.error

	ld a, 1
	call SENDW
	jp c, w_load.error
	
	ld hl, TMP_CURRENT 
	ld b, 10 
	
	;; Skip variables
.varsloop:
	push bc
	call RECVW ;; IGNORE VARS
	pop bc
	jp c, w_load.error
	djnz .varsloop
	
	;; Retrieve block length into HL
	call RECVW
	jp c, w_load.error
	ld l, a

	call RECVW
	jp c, w_load.error
	ld h, a

	;; Retrieve start of block into DE
	call RECVW
	jp c, w_load.error
	ld e, a

	call RECVW
	jp c, w_load.error
	ld d, a

	ld (TMP_CURRENT), hl
	ld (TMP_CONTEXT), de

	;; Retrieve expected size from input buffer
	rst #18			; Pop Forth stack to DE
	ld hl, TMP_CURRENT 	; Retrieve value from header
	ld a, d			; Skip, if user specified zero length
	or e
	call nz, .save

	;; Retrieve user-specified start address
	rst #18			; Por Forth stack to DE
	ld hl, TMP_CONTEXT	; Retrieve value from header
	;; ld a, d		; Commented, as user can
	;; or e                 ; specify 0 for this.
	call .save
    
	ld hl, (TMP_CURRENT)	; Retrieve final values
	ld de, (TMP_CONTEXT)

.loop:
	call RECVW
	jp c, w_load.error	; Check for time-out

	ld (de), a		; Store value
	inc de			; Advance to next byte
	dec hl
	ld a, l			; Unless we are done
	or h
	jr nz, .loop

.exit:
	ei
	jp (iy)

.save:
	ld (hl), de
	ret

w_load:
	FORTH_WORD "LOAD"
	call justSkipName
	call uart_init
	ld a, GET_TAP_BLOCK_COMMAND
	call SENDW
	jr c, .error

	call RECVW		; Get acknowledgement
	jr c, .error		; Exit, if timed out
	and a
	jr z, .error		; Exit if not acknowledged
	
	call getBlockTypeAndName
	jr c, .error		; Exit, if timeout
	and a
	jr nz, .error		; Exit, if not Dictionary

	ld a, 1
	call SENDW 		; Send confirm byte 
	jr c, .error		; Exit, if time-out
	
	;; Loading vars
	di

	ld hl, TMP_DICT
	call loadVar
	jr c, .error
	
	ld hl, TMP_CURRENT 
	dup 4
	call loadVar
	jr c, .error
	edup 

	;; Retrieve block length into HL
	call RECVW
	jr c, .error
	ld l, a

	call RECVW
	jr c, .error
	ld h, a

	;; Retrieve start of block into DE
	call RECVW
	jr c, .error
	ld e, a

	call RECVW
	jr c, .error
	ld d, a

	push hl
	ld hl, (TMP_STKBOT)
	ld bc, #0c 		; Leave 12 bytes for stack underflow
	add hl, bc
	ld (VAR_SPARE), hl
	pop hl
	
.loop:
	call RECVW		; Retrieve next byte
	jr c, .error
	
	ld (de), a		; Store byte
	inc de			; Advance to next byte
	dec hl
	ld a, h			; Unless done
	or l
	jr z, .exit
	jr .loop

	;; Update system variables
.exit
	ld hl, TMP_CURRENT	
	ld de, VAR_CURRENT
	ld bc, 8
	ldir ; moving vars 
	ld hl, (TMP_DICT)
	ld (VAR_DICT), hl 
    
	ei
	jp (iy)

.error
	xor a
	call SENDW ; Send cancel byte

	ei 
	rst #20	   ; Abort, tape error
	db #0a

	jp (iy)

w_ls:
	FORTH_WORD "LS"
	di
	call uart_init
	ld a, GET_CATALOG_COMMAND
	call SENDW
	jr c, .error
	ld a, 13
	rst #08
.loop
	call RECVW
	jr c, .error
	cp #ff			; Check if terminator
	jr z, .exit		; Exit, if so
	rst #08			; Otherwise print character
	jr .loop
.exit
	ld a, 13		; Print new line
	rst #08
	ei 
	jp (iy)
.error:
	ld a, 13 		; Send carriage return
	rst #08

	ei 
	rst #20	  		 ; Abort, tape error
	db #0a

	jp (iy)
	
	
w_ubput:
	FORTH_WORD "UBPUT"
	di
	call uart_init

	ld a, BINARY_PUT_COMMAND
	call SENDW
	jr c, .error		; Time-out

	call sendFileName
	jr c, .error	

	;; Retrieve block length
	rst #18 		; Pop top of Forth stack into DE

	ld a, e
	call SENDW
	jr c, .error		; Time-out
	ld a, d
	call SENDW
	jr c, .error		; Time-out
	push de

	;; Retrieve start of block
	rst #18			; Pop top of Forth stack into DE
	ex hl, de		; Move to HL
	pop de			; DE contains block length

.sendLoop:
	ld a, (hl)
	
	call SENDW
	jr c, .error

	inc hl
	dec de
	ld a, d
	or e
	jr nz, .sendLoop

.exit:
	ei
	jp (iy)	

.error:
	ei

	rst #20			; Abort, tape error
	db #0a

	jp (iy)

w_ubget:
	FORTH_WORD "UBGET"
	di
	call uart_init
	ld a, BINARY_GET_COMMAND
	call SENDW
	jr c, .error
	
	call sendFileName
	jr c, .error
	
	;; Read block length into HL
	call RECVW
	jr c, .error
	ld l, a

	call RECVW
	jr c, .error
	ld h, a

	;; Check length is non-zero
	or l			; A contains copy of H
	jr z, .error

	;; Retrieve start address from input buffer into DE
	push hl
	rst #18			; Retrieve top of stack into DE
	pop hl
	
.downloop:
	call RECVW
	jr c, .error
	
	ld (de), a
	inc de

	dec hl
	ld a, h
	or l
	jr nz, .downloop

.exit:   
	ei
	jp (iy)

.error:
	ei
	
	rst #20			; Abort, tape error
	db #0a
	
	jp (iy)
