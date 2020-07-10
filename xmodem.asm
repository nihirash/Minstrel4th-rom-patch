	;; Serial interface parameters
CTRL_PORT:	equ 0x80
DATA_PORT:	equ 0x81
RTS_LOW:	equ 0x16 	; Clock div: +64, 8+1-bit
RTS_HIGH:	equ 0x56	; Clock div: +64, 8+1-bit
RESET:		equ 0x57	; 8+1-bit, interrupt off, RTS low
	
	;; XMODEM protocol parameters
XMODEM_SOH:	equ 0x01
XMODEM_EOT:	equ 0x04
XMODEM_ACK:	equ 0x06
XMODEM_NAK:	equ 0x15
XMODEM_BS:	equ 0x80

	;; Minstrel System Variables
FLAGS:	equ 0x3c3e

	;; Miscellaneous params
CR:		equ 0x0d
	
	OUTPUT "xmodem.bin"
	org 0xf000	      ; Start at 61,440 ( 0xf800 = 63,488d)
	
	;; (Non-blocking) receive byte from serial port
	;; 
	;; On entry:
	;; 	None
	;; On exit,
	;;     	Carry Set 	- No data
	;;     	Carry Clear 	- A, value read
	;;     	Always 		- A' corrupt
	
RECV:	ld a, RTS_LOW		; Set RTS low
	out (CTRL_PORT),a  	; Confirm ready to receive

	in a,(CTRL_PORT)	; Check if byte ready
	and 0x01		; Bit zero set, if so

	jr nz, READ_BYTE

	scf			; Set carry, to indicate timeout
	ret
	
READ_BYTE:
	in a, (DATA_PORT)	; Read byte
	
	push af			; Save character
	ld a, RTS_HIGH		; Set RTS high
	out (CTRL_PORT),a	; Hold receiver
	pop af			; Restore character
	
	and a 			; Reset carry, to indicate success
	ret
	
	;; Send byte to serial port
	;; On entry:
	;;     A = byte to send
	;; On exit,
	;;     Carry Flag Set - Timed out
	;;     Carry Flag Clear - Success
	;;     Always - AF, BC corrupted
	
SEND:	ld bc, 0xBBBB		; Maximum retries
	
	push af			; Save byte to send
	
CHECKS:	xor a			; Check if ready to send
	in a, (CTRL_PORT)
	bit 1,a

	jr nz, SEND_BYTE
	dec bc
	ld a,b
	or c
	jr nz, CHECKS

	pop af			; Balance stack
	scf

	ret			; Set carry, to indicate timeout

SEND_BYTE:
	pop af			; Recover byte to send
	out (DATA_PORT),a	; Send byte
	and a			; Reset carry, to indicate success
	ret

	;; Send block of 128 bytes, w/ checksum, in line with
	;; XMODEM protocol
	;; 
	;; On entry:
	;;   A  - Sector number to send
	;;   HL - Address of block to send
	;; 
	;; One exit:
	;;   Carry Flag Set - Timed out (or other error)
	;;   Carry Flag clear - Send completed and acknowledged
SEND_BLOCK:
	;; Send header information
	push hl			; Save start address
	push af			; Save Sector number

	;; Report send
	ld hl, SECTMSG
	call PRINT_MSG
	pop af			; Retrieve block number
	pop hl			; Restore block address
	push af			; Store block number

	;; Check in VIS mode
	ld a,(FLAGS)
	bit 4,a			; VIS = 0 ; INVIS = 1
	jr nz, SB_CONT_2

	pop af
	push af
	call PRINT_HEX		; Print it

	;; Check in VIS mode
SB_CONT_2:
	ld a,(FLAGS)
	bit 4,a			; VIS = 0 ; INVIS = 1
	jr nz, SB_CONT_3
	
	ld a, CR		; Followed by carriage return
	rst 0x08
	
	;; Send header
SB_CONT_3:
	ld a, XMODEM_SOH
	call SEND
	
	pop af			; Restore Sector number
	push af			; Save Sector number
	call SEND
	
	pop af			; Restore Sector number
	cpl			; Work out 0xFF - reg_A
	call SEND
	
	xor a			; Reset checksum
	ld e,a			; and store in reg_E
	ld b, XMODEM_BS		; Size of payload to be sent
	
SB_LOOP:
	ld c,(hl)		; Retrieve byte to send
	inc hl
	ld a,e
	add a,c			; Update checksum
	ld e,a			; Save it
	ld a,c
	push bc
	call SEND
	pop bc
	djnz SB_LOOP		; Loop to send next byte

	;; Send checksum
	ld a,e
	call SEND

	;; Get acknowledgement
	ld bc,0x8000		; Number of retries

SB_LOOP_2:
	call RECV

	jr nc, SB_CONT

	dec bc
	ld a, b
	or c
	jr nz, SB_LOOP_2

	scf			; Carry set indicates error

	ret  

SB_CONT:	
	cp XMODEM_ACK		; If successful, carry flag clear
	ret z

	scf			; Otherwise, indicate fail
	ret

RX:
	call RECV
	
	jr c, RX_NO_BYTE

	ld e,a
	ld d,0
	rst 0x10

	jp (iy)
	
RX_NO_BYTE:
	ld de, 0xffff
	
	rst 0x10

	jp (iy)

TX:
	rst 0x18		; Retrieve value from stack
	ld a,e
	
	ld de,0x0000
	
	call SEND

	jr c,TX_NO_SEND

	rst 0x10
	jp (iy)

TX_NO_SEND:
	dec DE

	rst 0x10
	jp (iy)
	
	;; Print contents of A register as a two-digit hex number
	;; On entry:
	;; 	A contains value to be printed
	;; On exit:
	;; 	A and alternate registers corrupted
PRINT_HEX:	
	push af
	srl a			; Shift high nibble into low nibble
	srl a
	srl a
	srl a
	call PRINT_DGT
	pop af			; Retrieve number
	and 0x0F		; Isolate low nibble
PRINT_DGT:
	cp 0x0a			; Is it higher than '9'
	jr c, PRINT_CNT		; If not, skip forward
	add a, 0x07		; Correction for letters
PRINT_CNT:
	add a, '0'		; Convert to ASCII code
	rst 0x08		; Print it
	ret			; Return to next digit or calling routine

	;; Print status message to console
	;; On entry:
	;; 	HL points to start of message
	;; On exit:
	;; 	A, HL, and alternative registers are corrupt
	;; 
PRINT_MSG:
	;; Check in VIS mode
	ld a,(FLAGS)
	bit 4,a			; VIS = 0 ; INVIS = 1
	ret nz

	;; Print Message
	ld a, (hl)
	and a			; Null byte indicates end of message
	ret z
	inc hl
	push hl
	rst 0x08
	pop hl
	jr PRINT_MSG

	;; Send a block of memory via serial interface, using XMODEM
	;; protocol
	;;
	;; On entry:
	;;   2OS - Address of start of block
	;;   TOS - Length of block
	;; On exit:
	;;   TOS - error code (0000 indicates success)
TRANSMIT:	
	rst 0x18		; Retrieve TOS into DE

	;; Work out number of packets to send. Instead of dividing
	;; by 128, we multiple by 2 and ignore lowest byte.

	xor a			; Multiple DE by 2, leaving
	sla e			; result in ADE
	rl d
	rla

	;; Transfer number of packets to BC
	ld b,a
	ld c,d

	;; Check for remainder
	ld a,e
	srl a			; Divide by 2
	and a
	jr z, TRANS_CONT_1
	inc bc			; One extra packet for remainder

TRANS_CONT_1:
	
	ld (LAST_PACKET),a	; Store for later

	;; Initialise packet number
	ld hl, 0x0000		; XMODEM starts packet count at 1
	                        ; though value increased at beginning
	                        ; of each send opp
	ld (CURR_PACKET),hl	; Store for later
	
	;;  Retrieve start of block into HL
	rst 0x18
	ld h,d
	ld l,e

	;; Make transmission
	ld d,b			; Move no. blocks to DE
	ld e,c
	
	;; At this point:
	;;     HL = start
	;;     DE = no packets
	;;     CURR_PACKET = packet number

TRANS_LOOP:
	;; Increase current packet
	ld bc,(CURR_PACKET)
	inc bc
	ld (CURR_PACKET),bc
	
	ld b,5			; Number of retries
TRANS_LOOP_2:
	push de
	push hl
	push bc
	ld a,(CURR_PACKET)	; Low byte of CURR_PACKET value
	call SEND_BLOCK
	pop bc
	jr nc, TRANS_CONT_2
	pop hl		
	pop de
	djnz TRANS_LOOP_2

	;; Abandon transfer and report error
	ld hl, ERRMSG
	call PRINT_MSG
	ld a, CR
	rst 0x08

	ld de, 0xFFFF		; Indicate error
	rst 0x10		; Push onto FORTH stack

	jp (iy)			; Return to FORTH
	
TRANS_CONT_2:
	pop de 			; Effectively discard old value of HL
	pop de			; Retrieve no. block left to transmit

	dec de			; Decrease no. packets to send
	ld a,d			; Check if we are done
	or e
	
	jr nz, TRANS_LOOP
	
	ld a, XMODEM_EOT
	call SEND

	;; Confirm success
	ld hl, OKAYMSG
	call PRINT_MSG
	ld a, CR
	rst 0x08

	ld de,0x0000		; Indicates success
	rst 0x10		; Push onto stack

	jp (iy) 		; Return to FORTH

LAST_PACKET:
	db 0x00			; Temporary store for length of last
				; packet
CURR_PACKET:
	dw 0x0000		; Temporary story for packet number
	
SECTMSG:
	db "SENDING SECTOR ", 0x00
ERRMSG:	
	db "SEND FAILED ", 0x00
OKAYMSG:
	db "SEND COMPLETE ", 0x00
	
END:	
	OUTEND
