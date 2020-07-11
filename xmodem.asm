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
XMODEM_MAX_RETRY:	equ 5
	
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
	push af			; Store block number

	;; Send header
SB_CONT_3:
	ld a, XMODEM_SOH
	call SEND
	
	pop af			; Restore Block number
	push af			; Save Block number
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
	ld a,(FLAGS)		; If VIS, move print posn to new line
	bit 4,a
	jr nz, TRANS_CONT_0
	ld a, CR
	rst 0x08

TRANS_CONT_0:	
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
	
	ld b,XMODEM_MAX_RETRY	; Number of retries
TRANS_LOOP_2:
	push de
	push hl
	push bc

	;; Print block-sending information
	ld a,(FLAGS)		; Check if VIS enabled
	bit 4,a
	jr nz, TRANS_CONT_2

	;; Report send
	push hl
	ld hl, SECTMSG
	call PRINT_MSG
	ld a, (CURR_PACKET)
	call PRINT_HEX
	ld a, CR
	rst 0x08
	pop hl
	
TRANS_CONT_2:	
	ld a,(CURR_PACKET)	; Low byte of CURR_PACKET value
	call SEND_BLOCK
	pop bc
	jr nc, TRANS_CONT_4	; Succeeded, so move on
	pop hl			; Otherwise, retry send
	pop de
	djnz TRANS_LOOP_2	; If not at maximum retries

	;; Abandon transfer and report error
	ld a,(FLAGS)
	bit 4,a
	jr nz, TRANS_CONT_3

	ld hl, ERRMSG
	call PRINT_MSG
	ld a, CR
	rst 0x08

TRANS_CONT_3:
	ld de, 0xFFFF		; Indicate error
	rst 0x10		; Push onto FORTH stack

	jp (iy)			; Return to FORTH
	
TRANS_CONT_4:
	pop de 			; Effectively discard old value of HL
	pop de			; Retrieve no. block left to transmit

	dec de			; Decrease no. packets to send
	ld a,d			; Check if we are done
	or e
	
	jr nz, TRANS_LOOP	; Look back for next packet
	
	ld a, XMODEM_EOT	; Indicate end of transfer
	call SEND

	;; Confirm success
	ld a,(FLAGS)
	bit 4,a
	jr nz, TRANS_CONT_5

	ld hl, OKAYMSG
	call PRINT_MSG
	ld a, CR
	rst 0x08

TRANS_CONT_5:	
	ld de,0x0000		; Indicates success
	rst 0x10		; Push onto stack

	jp (iy) 		; Return to FORTH

	;; Receive block of 128 bytes, w/ checksum, in line with
	;; XMODEM protocol
	;; 
	;; On entry:
	;;   HL - Address to which to write block
	;; 
	;; One exit:
	;;   Carry Flag Set - Timed out (or other error)
	;;   Carry Flag clear - Send completed and acknowledged
	;;   HL - First address beyond block read
	;;   D - non-zero if EOT; zero otherwise
	;;   E - packet number read
RECV_BLOCK
	ld de, 0x0080
	add hl, de
	ld d,0
	ld a,(CURR_PACKET)
	cp 0x10
	jr nz, RECV_BLOCK_CONT
	inc d
RECV_BLOCK_CONT:
	ld e,a
	and a			; Reset carry flag
	
	ret

	;; Receive a block of memory via serial interface, using XMODEM
	;; protocol
	;;
	;; On entry:
	;;   TOS - address to which to write data
	;; On exit:
	;;   TOS - error code (0000 indicates success)
RECEIVE:	
	ld a,(FLAGS)		; If VIS, move print posn to new line
	bit 4,a
	jr nz, RECV_CONT_0
	ld a, CR
	rst 0x08

	;; Initialise packet number
	ld hl, 0x0000
	ld (CURR_PACKET),hl
	
RECV_CONT_0:	
	rst 0x18		; Retrieve TOS into DE

	;; Transfer to HL, as will track where to store next value read
	ld h,d
	ld l,e

	
RECV_LOOP:
	ld bc,(CURR_PACKET) 	; Advance to next packet
	inc bc
	ld (CURR_PACKET),bc

	ld b,XMODEM_MAX_RETRY	; Number of retry
RECV_LOOP_2:
	push hl
	push bc

	;; Print block-receive information
	ld a,(FLAGS)
	bit 4,a
	jr nz,RECV_CONT_2

	;; Log receive
	push hl
	ld hl,RECVMSG
	call PRINT_MSG
	ld a,(CURR_PACKET)
	call PRINT_HEX
	ld a, CR
	rst 0x08
	pop hl

RECV_CONT_2:	
	call RECV_BLOCK
	pop bc

	jr nc, RECV_CONT_4	; Succeeded, so move on

	pop hl
	djnz RECV_LOOP_2	; Try again, if not maximum retries

	ld de, 0xFFFF		; Indicate error
	rst 0x10		; Push onto FORTH stack

	jp (iy) 		; Return to FORTH

RECV_CONT_4:
	ld a,d			; D non-zero if EOT
	and a

	jr nz, RECV_CONT_6	; Jump to wrap-up

	ld a,(CURR_PACKET)	; Check is packet we expect
	cp e

	jr z, RECV_CONT_5	; Jump forward if is

	pop hl			; Retry, if not maximum retry
	djnz RECV_LOOP_2
	
	ld de, 0xFFFF		; Indicate error
	rst 0x10		; Push onto FORTH stack

	jp (iy) 		; Return to FORTH

RECV_CONT_5:
	inc sp			; Discard old value of HL
	inc sp			
	jr RECV_LOOP		; Move to next block

RECV_CONT_6:
	inc sp			; Discard old value of HL
	inc sp			

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
RECVMSG:
	db "RECEIVE SECTOR ", 0x00
ERRMSG:	
	db "SEND FAILED ", 0x00
OKAYMSG:
	db "SEND COMPLETE ", 0x00
	
END:	
	OUTEND
