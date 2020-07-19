	;; Serial interface parameters
CTRL_PORT:	equ 0x80
DATA_PORT:	equ 0x81
RESET:		equ 0x03	; Reset the serial device
RTS_LOW:	equ 0x16 	; Clock div: +64, 8+1-bit
RTS_HIGH:	equ 0x56	; Clock div: +64, 8+1-bit
RECV_RETRY:	equ 0x0100	; Retry could for RECV op
	
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
CR:	equ 0x0d
LF:	equ 0x0a
	
	OUTPUT "xmodem.bin"
	
	org 0xf000	      ; Start at 61,440 ( 0xf800 = 63,488d)
	
	;; (Part-blocking) receive byte from serial port
	;;
	;; On entry:
	;;      None
	;;
	;; On exit:
	;;      Carry Flag	- No data
	;;     	Carry Clear 	- A, value read
	;;     	Always 		- BC corrupt
RECVW:	
	ld bc, RECV_RETRY
RECVW_CONT:
	call RECV
	ret nc

	dec bc
	ld a,b
	or c

	jr nz, RECVW_CONT

	scf
	ret
	
	;; (Non-blocking) receive byte from serial port
	;; 
	;; On entry:
	;; 	None
	;; On exit,
	;;     	Carry Set 	- No data
	;;     	Carry Clear 	- A, value read
	;;     	Otherwise	- A corrupt
	
RECV:	ld a, RTS_LOW		; Set RTS low
	out (CTRL_PORT),a  	; Confirm ready to receive

	in a,(CTRL_PORT)	; Check if byte ready
	and 0x01		; Bit zero set, if so

	jr z, RECV_NO_BYTE	; No data available

	ld a, RTS_HIGH		; Set RTS high
	out (CTRL_PORT),a	; Hold receiver

	in a, (DATA_PORT)	; Read byte
	
	and a 			; Reset carry, to indicate success
	ret

RECV_NO_BYTE:	
	ld a, RTS_HIGH
	out (CTRL_PORT),a
	
	scf			; Set carry, to indicate timeout
	ret
	
	
	;; Send byte to serial port
	;; On entry:
	;;     A = byte to send
	;; On exit,
	;;     Carry Flag Set - Timed out
	;;     Carry Flag Clear - Success
	;;     Always - AF corrupt
SEND:	push af			; Save byte to send
	in a, (CTRL_PORT)	; Check if ready to send
	and 0x02		

	jr z, SEND_NOT_READY	; Jump forward if can not send

	pop af			; Retrieve send data
	out (DATA_PORT),a	; Send
	and a			; Reset carry to indicate success
	ret

SEND_NOT_READY:
	pop af			; Balance stack
	scf			; Indicate no send
	ret
	
	
	;; Blocking Send byte to serial port
	;; On entry:
	;;     A = byte to send
	;; On exit,
	;;     Carry Flag Set - Timed out
	;;     Carry Flag Clear - Success
	;;     Always - AF, BC corrupted
SENDW:	ld bc, 0xBBBB		; Maximum retries

SENDW_CONT:
	call SEND
	ret nc			; Exit if done
	
	dec bc			; Decrement retries
	ld a,b
	or c
	jr nz, SENDW_CONT	; Try again

	scf			; Set carry, to indicate timeout
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
	call SENDW
	
	pop af			; Restore Block number
	push af			; Save Block number
	call SENDW
	
	pop af			; Restore Sector number
	cpl			; Work out 0xFF - reg_A
	call SENDW
	
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
	call SENDW
	pop bc
	djnz SB_LOOP		; Loop to send next byte

	;; Send checksum
	ld a,e
	call SENDW

	;; Get acknowledgement
	call RECVW

	ret c			; Carry set indicates error

SB_CONT:	
	cp XMODEM_ACK		; If successful, carry flag clear
	ret z

	scf			; Otherwise, indicate fail
	ret

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

	;; Attempt to read an XMODEM packet via serial interface
	;; Packet consists of 132 bytes, as follows:
	;; - SOH
	;; - packet number
	;; - 255-packet number
	;; - 128 bytes of data
	;; - 8-bit checksum
	;;
	;; On entry:
	;; 	a - initiation byte for retrieving packet (ACK/ NAK)
	;;      hl - start of 132-byte buffer in which to hold packet
	;;
	;; On exit
	;; 	CF reset - success
	;; 	CF set - timed out (B contains 132 - bytes read)


GET_BLOCK:
	call SENDW		; Transmit initiation code to sender

	ld b, 0x84		; 132 bytes in XMODEM packet
	ret c			; Return if initiation failed

GET_BLOCK_LOOP:	
	push bc			; Save counter
	call RECVW		; Read next byte
	pop bc			; Retrieve counter

	jr c, GET_BLOCK_TO	; Exit, if timed out
	ld (hl),a		; Store byte read
	inc hl			; Move to next address
	djnz GET_BLOCK_LOOP	; Repeat if more data expected

	and a			; Reset carry flag
	ret
	
GET_BLOCK_TO:
	scf			; Indicate error
	ret

	;; Check that packet in memory is valid XMODEM packet
	;;
	;; On entry:
	;;     HL - address of start of packet
	;;
	;; On exit
	;;   Carry flag reset - valid packet
	;;     A = SOH, E = packet number, or
	;;     A = EOT - EOT received
	;;   Carry flag set - invalid packet
CHECK_BLOCK:
	ld e, a			; Save packet number for later

	ld a,(hl)		; Check first byte

	cp XMODEM_EOT		; Check for end of transmission

	ret z			; A contains EOT and carry reset

	cp XMODEM_SOH

	jr z, CHECK_BLOCK_CONT_01

	scf			; Indicates invalid packet
	ret

CHECK_BLOCK_CONT_01:
	inc hl			; Check packet number
	ld e,(hl)
	
	inc hl
	ld a,(hl)

	cpl			; Calculate 255-a
	cp e			; Should be same

	jr z, CHECK_BLOCK_CONT_02

	scf			; Indicates invalid packet
	ret

CHECK_BLOCK_CONT_02:
	ld bc,0x8000		; 128 bytes; checksum 0

CHECK_BLOCK_LOOP:	
	inc hl
	ld a,(hl)		; Read byte
	add a,c			; Update checksum
	ld c,a
	djnz CHECK_BLOCK_LOOP

	inc hl
	ld a,(hl)		; Read checksum from packet
	cp c			; Check it is consistent

	ret z			; Carry flag reset

	scf			; Indicates invalid packet
	ret

	;;  Discard any stale data in buffer
DRAIN_SENDER:
	call RECVW
	jr nc, DRAIN_SENDER	; Read whole packet

	ret

FORTH_RESET:
	ld a, RESET
	out (CTRL_PORT),a	; Reset serial device

	ld a, RTS_HIGH
	out (CTRL_PORT),a	; +64; 8 bits+1 stop; RTS high; no int

	jp (iy)			; Return to FORTH
	
FORTH_RX:
	ld de, 0xffff

	call RECV
	
	jr c, RX_CONT		; No byte received

	ld e,a
	ld d,0
RX_CONT:	
	rst 0x10

	jp (iy)
	
FORTH_TX:
	rst 0x18		; Retrieve value from stack to DE
	ld a,e
	
	ld de,0x0000
	
	call SENDW

	jr nc,TX_CONT		; Jump forward if success
	dec de			; DE = -1, if failed
TX_CONT:	
	rst 0x10
	jp (iy)

	
	;; Receive a block of memory via serial interface, using XMODEM
	;; protocol
	;;
	;; On entry:
	;;   TOS - address to which to write data
	;; On exit:
	;;   TOS - error code (0000 indicates success)
FORTH_RECEIVE:	
	ld a,(FLAGS)		; If VIS, move print posn to new line
	bit 4,a
	jr nz, RECV_CONT_0
	ld a, CR
	rst 0x08

	;; Initialise packet number
RECV_CONT_0:	
	ld hl, 0x0000
	ld (CURR_PACKET),hl
	
	rst 0x18		; Retrieve TOS into DE

	;; Transfer to HL, as will track where to store next value read
	ld h,d
	ld l,e

	;; Send initiation string
	ld a, XMODEM_NAK
	call SEND
	
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
	call GET_BLOCK
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

REC_TEST:
	call DRAIN_SENDER

	rst 0x18		; Retrieve acknowledge string
	ld a,e
	
	rst 0x18
	ld h,d
	ld l,e
	
	ld hl, PACKET_BUFFER
	
	call GET_BLOCK

	jr c, REC_ERR

	ld hl, PACKET_BUFFER

	call CHECK_BLOCK
	
	jr c, REC_ERR

	ld d,0
	rst 0x10
	jp (iy)
	
REC_ERR:	
	ld de, 0xffff
	rst 0x10
	jp (iy)
	
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
EOTMSG:	db "EOT RECEIVED", 0x00
SOHMSG:	db "SOH RECEIVED", 0x00
NORMSG:	db "NO RESPONSE", 0x00
BOKMSG:	db "PACKETID OKAY", 0x00

PACKET_BUFFER:	ds 0x86
END:	
	OUTEND
