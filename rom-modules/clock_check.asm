	;; Routine to check clock speed of system. Should be run
	;; at end of QUIT word (which needs to be patched)
	;; Outcome is recorded in bit 7 of FLAGS (0 = 3.25 MHz; 1 = 6.5 MHz)
	;; 
	;; Works by running counter loop until an interrupt is detected
	;; (based on a change in value of FRAMES). An iteration of 
	;; the loop takes 25 T states (plus 7 T states for
	;; initialisation so (allowing 300 T-states for interrupt service
	;; routine), a 3.25 MHz clock should return around 2,500
	;; iterations, whereas a 6.5 MHz clock should return around 5,300
	;; iterations on a 50 Hz set-up.
	;;
	;; CHECKCLOCK ( -- ITERS )
	
FRAMES:	equ 0x3c2b		; Lowest byte of clock in Sys Variables
	
CHECK_CLOCK:
	ld de, 0x0000		; Reset counter
	ld hl, FRAMES		
	halt			; Synchronise to interrupt
	ld a, (hl)		; Save initial FRAMES value
.loop:	inc de			; Increment counter
	cp (hl)			; See if FRAMES has changed
	jr z, .loop		; It not, loop again

	ex hl, de		; Move final count to HL
	ld de, 3500		; Compare to 3,500 (somewhere between
				; 3.25MHz and 6.5 MHz)
	and a			; Reset carry
	sbc hl, de
	jr c, .cont		; Carry set indicates is 3.25 MHz
	set 7, (IX + 0x3e)	; Update FLAGS bit for 6.5 MZh

.cont:
	
	jp 0x04F2		; Continue with main execution routine
END:	
