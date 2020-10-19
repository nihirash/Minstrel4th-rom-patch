CONTROL_REG:	equ 0x80	; Port addresses for 6850 serial module
DATA_REG:	equ 0x81	; 
RESET:		equ 0x03	; Reset the serial device
RTS_LOW:	equ 0x16 	; Clock div: +64, 8+1-bit
RTS_HIGH:	equ 0x56	; Clock div: +64, 8+1-bit
RECV_RETRY:	equ 0x1000	; Retry count for RECV op
SEND_RETRY:	equ 0x1000	; Retry count for SEND op
	
CR:		equ 0x0d	; Carriage return
LF:		equ 0x0a	; Linefeed
	
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
