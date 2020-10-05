RECV_RETRY:	equ 0x1000	; Retry count for RECV op
SEND_RETRY:	equ 0x1000	; Retry count for SEND op
	
	;; XMODEM protocol parameters
XMODEM_SOH:	equ 0x01
XMODEM_EOT:	equ 0x04
XMODEM_ACK:	equ 0x06
XMODEM_NAK:	equ 0x15
XMODEM_BS:	equ 0x80
XMODEM_MAX_RETRY:	equ 0x08

ERROR_TO:	equ 0xF0	; Indicates timeout
ERROR_PE:	equ 0xF1	; Indicates packet error
	
	;; Minstrel System Variables
EXWRCH:		equ 0x3C29	; Address of alternative print routine
FLAGS:		equ 0x3c3e

	;; Miscellaneous params
CR:	equ 0x0d
LF:	equ 0x0a
	
LAST_PACKET: 	equ 0x2701	; Temporary store for length of last
				; packet in PAD (1 byte)
CURR_PACKET: 	equ 0x2702	; Temporary story for packet number
				; in PAD (2 bytes)
	
	;; ========================================================
	;; (Part-blocking) receive byte from serial port
	;;
	;; On entry:
	;;      None
	;;
	;; On exit:
	;;      Carry Set 	- Timed out, no data, A corrupted
	;;     	Carry Clear 	- A, value read
	;;     	Always 		- BC corrupt
	;; ========================================================
RECVW:	ld bc, RECV_RETRY
	
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
	;;     	Carry Clear 	- A, value read
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

	;; ========================================================
	;; Send packet of 128 bytes, w/ checksum, in line with
	;; XMODEM protocol
	;; 
	;; On entry:
	;;   A  - Packet number to send
	;;   HL - Address of block to send
	;; 
	;; One exit:
	;;   Carry Set 		- Timed out (or other error)
	;;   Carry Clear 	- Send completed and acknowledged
	;; ========================================================

SEND_BLOCK:
	push af			; Store packet number

	;; Send header
	ld a, XMODEM_SOH
	call SENDW
	
	pop af			; Restore packet number
	push af			; Save packet number
	call SENDW
	
	pop af			; Restore Sector number
	cpl			; Work out 0xFF - reg_A
	call SENDW
	
	xor a			; Reset checksum
	ld e,a			; and store in reg_E
	
	ld b, XMODEM_BS		; Size of payload to be sent
	
.loop:
	ld c,(hl)		; Retrieve byte to send
	inc hl			; Advance to next location
	
	ld a,e			; 
	add a,c			; Update checksum
	ld e,a			; 
	
	ld a,c			; 
	push bc			; 
	call SENDW		; Send byte
	pop bc			;
	
	djnz .loop		; Loop to send next byte

	;; Send checksum
	ld a,e
	call SENDW

	;; Get acknowledgement
	ld bc,0x8000

.loop_2:	
	call RECV

	jr nc, .cont		; Byte received

	dec bc			;
	ld a,b			; Try again
	or c			;
	jr nz, .loop_2		;

	scf			; Indicates failure
	
	ret			

.cont:	
	cp XMODEM_ACK		; Check for acknowledgement
	ret z			; If successful, carry flag clear

	scf			; Otherwise, indicate fail
	
	ret

	;; ========================================================
	;; Alternative printing routine to echo screen output to
	;; serial device.
	;;
	;; Accessed from ROM print routine, by setting system variable
	;; EXSRCH to the address of the entry point TEE_KERNEL.
	;; 
	;; On entry, A contains the character to send. Serial card must
	;; previously have been initialised.
	;; ========================================================
	
TEE_KERNEL:
	ld d,a			; Save A
	
	call SENDW
	jr c, .done		; Exit, if serial device not ready

	ld a,d			; Restore A
	cp CR			; Check if carriage return
	jr nz, .done		; Skip forward, if not
	
	ld a, LF		; Otherwise issue line feed
	call SENDW
	ld a, CR		; Restore CR for ROM printing

.done:
	jp 0x03ff		; Continue with ROM printing routine


	;; ========================================================
	;; Print contents of A register as a two-digit hex number
	;; 
	;; On entry:
	;; 	A contains value to be printed
	;; 
	;; On exit:
	;; 	A and alternate registers corrupted
	;; ========================================================

PRINT_HEX:	
	push af
	srl a			; Shift high nibble into low nibble
	srl a
	srl a
	srl a
	call .print_dgt
	pop af			; Retrieve number
	and 0x0F		; Isolate low nibble
.print_dgt:
	cp 0x0a			; Is it higher than '9'
	jr c, .cont		; If not, skip forward
	add a, 0x07		; Correction for letters
.cont:
	add a, '0'		; Convert to ASCII code
	rst 0x08		; Print it
	ret			; Return to next digit or
				; calling routine

	
	;; ========================================================
	;; Print status message to console
	;; 
	;; On entry:
	;; 	HL points to start of message
	;; 
	;; On exit:
	;; 	A, HL, and alternative registers are corrupt
	;; ========================================================
PRINT_MSG:
	ld a, (hl)		; Retrieve next character
	
	and a			; Null byte indicates end 
	ret z			; of message
	
	inc hl			; Advance to next character

	rst 0x08		; Print it

	jr PRINT_MSG		; Next

	;; ========================================================
	;; Messages
	;; ========================================================
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
PCKMSG:	db "PACKET ERROR", 0x00
NOPMSG:	db "WRONG PACKET", 0X00

	;; ========================================================
	;; Attempt to read an XMODEM packet via serial interface
	;; Packet consists of 132 bytes, as follows:
	;; - SOH
	;; - packet number
	;; - 255-packet number
	;; - 128 bytes of data
	;; - 8-bit checksum
	;;
	;; On entry:
	;; 	A - initiation byte for retrieving packet (ACK/ NAK)
	;;      DE - destination address for payload of packet
	;;
	;; On exit
	;; 	Carry reset 	- success
	;; 			- A=SOH / EOT, indicating packet type
	;;                      - L=packet number
	;; 			- DE=one past last address written to
	;; 	Carry set 	- failure
	;; 			- B = 132 - bytes read
	;; 			- A=error code
	;; ========================================================
GET_BLOCK:
	call SENDW		; Transmit initiation code to 
				; sender (corrupts AF and BC)
	;; Get header
	call RECVW
	jr c, .timeout
	
	cp XMODEM_EOT		; Is it end-of-transmission?
	ret z			; If so, done

	cp XMODEM_SOH		; Is it start-of-header?
	jr nz, .packet_error	; If not, packet error

	;; Read in packet number
	call RECVW
	jr c, .timeout
	
	ld l,a			; Save it for later

	;; Read complement
	call RECVW
	jr c, .timeout

	cpl			; Compute 255-A
	cp l			; Compare to packet number
	jr nz, .packet_error	; If not matching, packet error

	;; Read payload
	push de			; Save original value of DE
	ld b, 0x80		; 128 bytes in XMODEM packet
	ld c, 0			; Zero checksum
.loop:	
	push bc			; Save counter
	call RECVW		; Read next byte (corrupts AF and BC)
	pop bc			; Retrieve counter

	jr nc, .save_byte
	pop de			; Restore start address of block
	jr .timeout		; Exit, if timed out

.save_byte:	
	ld (de),a		; Store byte read
	inc de			; Move to next address
	add a, c		; Update checksum
	ld c,a
	
	djnz .loop		; Repeat if more data expected

	;; At this point, payload is read, so DE correct
	inc sp			; Discard old value of DE
	inc sp			;
	
	;; Get checksum
	push bc			; Save checksum
	call RECVW		; Retrieve sender copy of checksum
	pop bc			; Retrieve checksum

	jr c, .timeout

	cp c			; Compare to computed checksum
	jr nz, .packet_error	; Packet error if no match
	
	;; Done
	ld a, XMODEM_SOH	; Indicates full packet read
	and a			; Reset carry flag
	
	ret
	
	;; Exit with timeout 
.timeout:
	ld A, ERROR_TO		; Indicates timout
	scf			; Indicate error

	ret
	
	;; Exit with packet error
.packet_error:
	ld A, ERROR_PE		; Indicates packet error
	scf

	ret

	;; ========================================================
	;; Discard any stale data in buffer
	;;
	;; On entry
	;;   --
	;;
	;; On exit
	;;   A and BC corrupt
	;; ========================================================
DRAIN_SENDER:
	call RECVW		; Attempt to ready byte
	jr nc, DRAIN_SENDER	; Repeat, if data read

	ret

	;; ========================================================
	;; Enable echoing of screen output to serial device.
	;;
	;; On entry:
	;;   N/A
	;; 
	;; On exit:
	;;   N/A
	;; ========================================================
W_TEE:
	FORTH_WORD "TEE"
	ld hl, TEE_KERNEL
	ld (EXWRCH), hl

	jp (iy)
.word_end:

	;; ========================================================
	;; Disable echoing of screen output to serial device.
	;;
	;; On entry:
	;;   N/A
	;; 
	;; On exit:
	;;   N/A
	;; ========================================================
W_UNTEE:
	FORTH_WORD "UNTEE"
	ld hl, 0x0000
	ld (EXWRCH), hl

	jp (iy)
.word_end:
	
	;; ========================================================
	;; Receive a block of memory via serial interface, using
	;; XMODEM protocol
	;;
	;; On entry:
	;;   TOS 	- address to which to write data
	;; 
	;; On exit:
	;;   TOS 	- error code (0000 indicates success)
	;; ========================================================
w_xbget:
	FORTH_WORD "XBGET"

	ld a,(FLAGS)		; If VIS, move print posn to new line
	bit 4,a
	jr nz, .cont1
	ld a, CR
	rst 0x08

.cont1	
	di 
	
	;; Drain any stale data (transmit initiated by receiver)
	call DRAIN_SENDER
	
	;; Initialise packet number
	ld hl, 0x0000		; First packet is 1, but value
	ld (CURR_PACKET),hl	; incremented before each packet
	
	rst 0x18		; Retrieve TOS destination into DE

	ld a, XMODEM_NAK	; Indicates to sender to start transfer
	
.next_packet	
	ld bc, (CURR_PACKET)	; Expect next packet
	inc bc
	ld (CURR_PACKET), bc

	ld b,XMODEM_MAX_RETRY
.loop
	;; Print block-receive information
	ld l,a			; Save A
	ld a,(FLAGS)
	bit 4,a
	ld a,l			; Restore A
	jr nz, .cont2

	;; Log receive operation
	push af
	push hl
	
	ld hl,RECVMSG
	call PRINT_MSG
	
	ld a,(CURR_PACKET)
	call PRINT_HEX
	
	ld a, CR
	rst 0x08
	
	pop hl
	pop af

.cont2
	push bc
	call GET_BLOCK 
	pop bc

	jr nc, .packet_received	; Skip forward if successful
	
	cp ERROR_PE		; Check for Packet Error
	jr z, .packet_error	; Jump forward if so,

	;; If not packet error, must be timeout
.timeout	
	ld a,(FLAGS)
	bit 4,a
	jr nz, .err

	;; Log timeout error
	ld hl,NORMSG
	call PRINT_MSG
	
	ld a, CR
	rst 0x08
	
	jr .err
	
.packet_error	
	ld a,(FLAGS)
	bit 4,a
	jr nz,.err

	;; Log packet error
	ld hl,PCKMSG
	call PRINT_MSG
	
	ld a, CR
	rst 0x08
	
	jr .err

.wrong_packet	
	ld a,(FLAGS)
	bit 4,a
	jr nz,.err

	;; Log wrong packet
	ld hl,NOPMSG
	call PRINT_MSG
	
	ld a, CR
	rst 0x08
	
	;; jr .err
	
.err
	push bc
	call DRAIN_SENDER
	pop bc
	
	ld a, XMODEM_NAK
	djnz .loop		; If not max retry, try again

	;; Otherwise error
	ld de, 0xFFFF		; Indicates failure
	rst 0x10		; Push onto FORTH stack

	ei
	
	jp (iy)
	
.packet_received	
	;; Check for EOT
	cp XMODEM_EOT
	jr z, .done
	
	;; Check is correct packet
	ld a,(CURR_PACKET)
	cp l

	jr nz, .wrong_packet

	;; Confirm packet received
	ld a, XMODEM_ACK

	jp .next_packet

.done
	ld a, XMODEM_ACK	; Acknowledge receipt
	call SENDW
	
	ld de, 0x0000		; Indicates success
	rst 0x10

	ei
	
	jp (iy)
.word_end

	
	;; ========================================================
	;; Send a block of memory via serial interface, using 
	;; XMODEM protocol
	;;
	;; On entry:
	;;   2OS - Address of start of block
	;;   TOS - Length of block
	;; On exit:
	;;   TOS - error code (0000 indicates success)
	;; ========================================================
w_xbput:
	FORTH_WORD "XBPUT"
	
	ld a,(FLAGS)		; If VIS, move print posn to new line
	bit 4,a
	jr nz, .cont0
	ld a, CR
	rst 0x08

.cont0:	
	rst 0x18		; Retrieve length (TOS) into DE

	;; Work out number of packets to send. Instead of dividing
	;; by 128, we multiple by 2 and ignore lowest byte.
	ld a,d			; Check for special case of DE=0
	or e			; which is read as 0x10000
	jr nz, .cont1

	ld a,2			; Two times 0x10000
	jr .cont2
	
.cont1:	xor a			; Multiple DE by 2, leaving
	sla e			; result in ADE
	rl d
	rla

.cont2:
	;; Transfer number of packets to BC
	ld b,a
	ld c,d

	;; Check for remainder
	ld a,e
	srl a			; Divide by 2
	and a
	jr z, .cont3
	inc bc			; One extra packet for remainder

.cont3
	ld (LAST_PACKET),a	; Store for later

	;; Initialise packet number
	ld hl, 0x0000		; XMODEM starts packet count at 1
	                        ; though value incremented at
	                        ; beginning of each send opp
	ld (CURR_PACKET),hl	; Store for later
	
	;;  Retrieve start of block into HL
	rst 0x18
	ld h,d
	ld l,e
	
	;; Move no. blocks to DE
	ld d,b
	ld e,c
	
	;; At this point:
	;;     HL = start
	;;     DE = no packets
	;;     CURR_PACKET = packet number

	;; Wait for NAK (should be 90 seconds, though needs check
	;; for break)
	ld bc, 0x0000
.wait_for_nak:
	call RECV
	jr c, .cont4	; No response
	cp XMODEM_NAK
	jr nz, .cont4
	jr .next_packet

.cont4:	
	dec bc
	ld a,b
	or c
	jr nz, .wait_for_nak
	jr .error
	
.next_packet:
	;; Increase current packet
	ld bc,(CURR_PACKET)
	inc bc
	ld (CURR_PACKET),bc
	
	ld b,XMODEM_MAX_RETRY	; Number of retries
.send_packet:
	push de
	push hl
	push bc

	;; Print block-sending information
	ld a,(FLAGS)		; Check if VIS enabled
	bit 4,a
	jr nz, .cont5

	;; Log send to screen
	push hl
	ld hl, SECTMSG
	call PRINT_MSG
	ld a, (CURR_PACKET)
	call PRINT_HEX
	ld a, CR
	rst 0x08
	pop hl
	
.cont5	
	ld a,(CURR_PACKET)	; Low byte of CURR_PACKET value
	call SEND_BLOCK
	pop bc
	jr nc, .cont7		; Succeeded, so move on
	pop hl			; Otherwise, retry send
	pop de
	djnz .send_packet	; If not at maximum retries

	;; Abandon transfer and report error
.error:	ld a,(FLAGS)
	bit 4,a
	jr nz, .cont6

	ld hl, ERRMSG
	call PRINT_MSG
	ld a, CR
	rst 0x08

.cont6
	ld de, 0xFFFF		; Indicate error
	rst 0x10		; Push onto FORTH stack

	jp (iy)			; Return to FORTH
	
.cont7
	pop de 			; Effectively discard old value of HL
	pop de			; Retrieve no. packets left to transmit

	dec de			; Decrease no. packets to send
	ld a,d			; Check if we are done
	or e
	
	jr nz, .next_packet	; If not, loop back for next packet

	;;  If done, indicate End of Transfer
	ld a, XMODEM_EOT	
	call SENDW

	;; Confirm success
	ld a,(FLAGS)
	bit 4,a
	jr nz, .cont8

	ld hl, OKAYMSG
	call PRINT_MSG
	ld a, CR
	rst 0x08

.cont8:
	ld de,0x0000		; Indicates success
	rst 0x10		; Push onto stack

	jp (iy) 		; Return to FORTH
.word_end:

w_hex:
	FORTH_WORD "HEX"
	ld (IX + 0x3F), 0x10
	jp (iy)	
.word_end:

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


end:	
