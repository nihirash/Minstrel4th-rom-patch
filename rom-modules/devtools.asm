	;; Additional words that are useful for developers

STKBOT:	equ 0x3c37
SPARE:	equ 0x3c3b

	;; Switch to hexidecimal mode (analogue of built-in DECIMAL)
w_hex:
	FORTH_WORD "HEX"
	ld (IX + 0x3F), 0x10
	jp (iy)	
.word_end:

	;; Definer word to allow small m/code routines to be stored in
	;; (and called from) FORTH words (see Jupiter Ace manual,
	;; Ch 25, p.147)
w_code:
.name:  ABYTEC 0 "CODE"
.name_end:
	dw LINK                 ; Link field 
	SET_VAR LINK, $         
	db .name_end - .name    ; Name-length field
	dw 0x1085               ; Code field
	dw .entry               ; Parameter field
	db 0xe8, 0x10, 0xf0, 0xff
.entry:	db 0xcd, 0xf0, 0x0f
	db 0xa7, 0x10
	db 0xb6, 0x04
.word_end:

w_dots:
	FORTH_WORD ".S"

	call .get_depth

	ld a,b			; Check if any values on stack
	or c
	jr z, .done		; If not, then we are done

.loop:	inc de			; Move to high byte first
	ld a, (de)		; Retrieve it
	dec de			; Back to low byte
	and a			; Check if non-zero
	jr z, .cont		; Skip if not
	call PRINT_HEX
.cont:
	ld a,(de)		; Retrieve low byte
	call PRINT_HEX		; Print it
	
	inc de			; Advance to next value on stack
	inc de
	
	dec bc			; See if we are done
	dec bc
	ld a, b
	or c
	jr z, .done

	ld a, 0x20		; Print 'space'
	rst 0x08

	jr .loop
	
.done:  jp (iy)
	
.get_depth:
	ld hl, (STKBOT)		; End of dictionary
	ld de, 0x000c		; Minstrel leaves 12 bytes for padding
	add hl, de		; to prevent stack-underflow problems
	ex hl, de		; DE = bottom of stack
	ld hl, (SPARE)		; HL = top of stack
	and a			; Clear carry flag
	sbc hl, de		; HL = length of stack
	ld b,h			; Move to BC
	ld c,l

	ret
.word_end:
