CONTROL_REG:	equ 0x80	; Port addresses for 6850 serial module
DATA_REG:	equ 0x81	; 
RESET:		equ 0x03	; Reset the serial device
RTS_LOW:	equ 0x16 	; Clock div: +64, 8+1-bit
RTS_HIGH:	equ 0x56	; Clock div: +64, 8+1-bit
RECV_RETRY:	equ 0x1000	; Retry count for RECV op
SEND_RETRY:	equ 0x1000	; Retry count for SEND op
	
CR:		equ 0x0d	; Carriage return
LF:		equ 0x0a	; Linefeed

KEYROW_4L:      equ 0xfefe
KEYROW_4R:      equ 0x7ffe

	;; Terminal-input routine spliced into Ace interrupt code
get_key:
	ld a,(0x3c3e)		; FLAGS
	and 0x20		; Check if Bit 5 is set

	jp z, 0x0310		; Continue with KEYBOARD

	call check_break	; Check if BREAK pressed (on Minstrel)

	call RECV		; Otherwise, check for input on UART

	jr c, .error		; If none, error

	;; Check for control character ( 0 ... 26 )
	cp 0x1b			; 0x1b = Escape
	jr nc, .check_escape	; Skip forward if not

	ld e,a
	ld d,0
	ld hl, control_lookup
	add hl, de
	ld a, (hl)
	ret

.check_escape:
	cp 0x1b
	jr nz, .check_normal

	call RECVW		; Receive escape code

	jr c, .error		; Error if no second byte

	cp 65			; Only accept 65, ..., 68
	jr c, .error
	cp 69
	jr nc, .error

	sub 65			; Normalise code

	ld e,a
	ld d,0
	ld hl, escape_lookup
	add hl, de
	ld a, (hl)
	ret

.check_normal:
	cp 0x80			; Only accept values up to 127
	ret c			; If so, done.
	
.error:
	xor a
	ret

control_lookup:
	db 00, 00, 00, 00, 00, 00, 01, 03 ; ASCII 0, .., .7
	db 05, 00, 00, 00, 00, 13, 00, 00 ; ASCII 8, ..., 15
	db 00, 08, 00, 00, 07, 00, 09, 00 ; ASCII 16, ..., 23
	db 10, 00, 04			  ; ASCII 24, ..., 26

escape_lookup:
	db 07, 09, 01, 03	; Up, down, left, right
	
check_break:	
	        ;; Check for BREAK (Shift-SPACE on Minstrel keyboard)
        ld bc, KEYROW_4L        ; Port for bottom left half-row
        in a,(c)                ; Read keyboard
        bit 0,a                 ; Check 'SHIFT'
        ret nz	        	; Can stop test, if not being pressed

        ld bc, KEYROW_4R        ; Port for bottom right half-row
        in a,(c)                ; Read keyboard
        bit 0,a                 ; Check 'SPACE'

        ret nz        		; Can stop test, if not being pressed

        ;; BREAK pressed, so reinstate normal keyboard scan of Minstrel
        res 5,(ix+0x3e)         ; Reinstate usual keyboard routine

        ret                     ; Done
	
	;; Resets UART buffers and set to 115,200 baud, 8N1,
	;; with RTS high (deny to send)
uart_init:
	ld a, RESET
	out (CONTROL_REG),a	; Send reset signal to serial device

	ld a, RTS_HIGH		
	out (CONTROL_REG),a	; +64; 8 bits+1 stop; RTS high; no int

	ret

	;; ========================================================
	;; (Part-blocking) receive byte from serial port
	;;
	;; On entry:
	;;      None
	;;
	;; On exit:
	;;      Carry Set 	- Timed out, no data, A corrupted
	;;     	Carry Clear 	- A = value read
	;;     	Always 		- BC corrupt
	;; ========================================================
RECVW:	ld bc, RECV_RETRY	; Maximum number of read attempts
	
.loop:
	call RECV		; Non-blocking receive
	ret nc			; Indicates success

	dec bc			; Reduce counter
	ld a,b			; Check if out of attempts
	or c

	jr nz, .loop		; Retry, if not out of attempts

	scf			; Indicates time-out

	ret
	
	;; ========================================================
	;; (Non-blocking) receive byte from serial port
	;; 
	;; On entry:
	;; 	None
	;; On exit,
	;;     	Carry Set 	- No data, A corrupted
	;;     	Carry Clear 	- A = value read
	;; ========================================================
	
RECV:	ld a, RTS_LOW		; Set RTS low
	out (CONTROL_REG),a  	; Confirm ready to receive

	in a,(CONTROL_REG)	; Check if byte ready
	and 0x01		; Bit zero set, if so

	jr z, .no_byte		; No data available

	ld a, RTS_HIGH		; Set RTS high
	out (CONTROL_REG),a	; Hold receiver

	in a, (DATA_REG)	; Read byte
	
	and a 			; Reset carry, to indicate success

	ret

.no_byte:	
	ld a, RTS_HIGH		; Set RTS high
	out (CONTROL_REG),a	; Hold receive
	
	scf			; Set carry, to indicate timeout

	ret

	;; ========================================================
	;; Part-blocking send byte to serial port
	;; 
	;; On entry:
	;;     A = byte to send
	;; 
	;; On exit,
	;;     Carry Set 	- Timed out
	;;     Carry Clear 	- Success
	;;     Always 		- AF, BC corrupted
	;; ========================================================

SENDW:	ld bc, SEND_RETRY	; Maximum retries
	
	push af			; Save byte to send

.check:
	xor a			;
	in a,(CONTROL_REG)	; Check if ready to send
	and 0x02		; Bit 1 high, if so

	jr nz, .send_byte	; Ready to send
	
	dec bc			; Try again
	ld a,b
	or c
	jr nz, .check

	pop af			; Balance stack
	
	scf			; Indicates time-out

	ret
	
.send_byte:
	pop af			; Retrieve data to send
	out (DATA_REG),a
	
	and a			; Indicates success	
	
	ret


;;;;;;;;;;;;;;;;;;;;;;; Words section

w_uwrite:
	FORTH_WORD "UWRITE"
	rst 0x18		; Retrieve value from stack to DE
	ld a,e
	
	ld de,0x0000
	
	call SENDW

	jr nc, .cont		; Jump forward if success
	
	dec de			; DE = -1, if failed
	
.cont:	
	rst 0x10
	
	jp (iy)
.word_end:

w_ureads:
    FORTH_WORD "UREADS"
	ld de, 0xffff		; -1 indicates no data read

	call RECVW
	
	jr c, .cont		; No byte received

	ld e,a
	ld d,0
.cont:	
	rst 0x10

	jp (iy)
.word_end:

w_uread:
	FORTH_WORD "UREAD"
	ld de, 0xffff		; -1 indicates no data read

	call RECV		; Non-blocking read
	
	jr c, .cont		; No byte received

	ld e,a			; Transfer byte into DE,
	ld d,0			; ready to push onto Forth stack
.cont:	
	rst 0x10		; Push onto stack

	jp (iy)
.word_end:

w_uinit:
	FORTH_WORD "UINIT"
	call uart_init
	jp (iy)
.word_end:
