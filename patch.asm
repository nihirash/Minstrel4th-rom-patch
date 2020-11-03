;
; This is skeleton for Minstrel 4th ROM patch

	;; LINK is used to keep track of address of name-length
	;; field in most recently defined word. Needed to ensure
	;; dictionary (a linked list) is defined correctly.
LINK = #1D58			; Addr of name-length field of UFLOAT

  
;;;;;;;;;;;;;;;;;;;;;;; Global macros section
	include "rom-modules/forth-word-macro.asm"

;;;;;;;;;;;;;;;;;;;;;;; Original ROM section
	device zxspectrum48 // Only for using SAVEBIN

	;; Choose base ROM: "ace.rom" is original, 3.25 MHz ROM from
	;; Ace; "minstrel.rom" is modified version of Ace ROM for 6.5MHz
	;; clock speed.
	org 0x0000
	incbin "ace.rom" ; "ace.rom" = 3.25 MHz / "minstrel.rom" = 6.5MHz
	
;;;;;;;;;;;;;;;;;;;;;;; Additional ROM section
	;; Uncomment lines corresponding to functionality you wish to
	;; include. Note that "uart-dos.asm" and "uart-xmodem.asm" both
	;; require "common-uart-ops.asm".
	org #2800

	include "rom-modules/clock_check.asm"	  ; Check and record clock speed
	include "rom-modules/common-uart-ops.asm" ; Basic UART ops
	include "rom-modules/case.asm" 	      ; CASE construct (Optional)
	include "rom-modules/uart-dos.asm"    ; UART support for PC file
					      ; server
	include "rom-modules/uart-xmodem.asm" ; UART support for XMODEM
	include "rom-modules/devtools.asm"    ; Additional tools for
					      ; developers (needs uart-xmodem.asm)
	
	DISPLAY "Bytes left: ", #3BFF - $
	
;;;;;;;;;;;;;;;;;;;;;;; Rename tape routines
	org 0x1930 ; SAVE header
	db 'T'+0x80 
	org 0x1940 ; BSAVE header
	db 'T'+0x80 
	org 0x1950 ; BLOAD header
	db 'T'+0x80 
	org 0x1986 ; LOAD header
	db 'T'+0x80 

;;;;;;;;;;;;;;;;;;;;;;; Dictionary hack place
	;; Update link field address used to create word "FORTH", to
	;; point to name-length field in last word of extended
	;; dictionary.

	org #1ffd
	dw LINK

	;; Update QUIT command, so that clock-speed is checked and
	;; system variables are updated
	org 0x00a0
	jp CHECK_CLOCK

	org 0x014b		; KEYBOARD check
	call get_key		; Splice in custom routine.
	
	org 0x0ba9	      ; Modified beep routine
	jp beeper	      ;
	
;;;;;;;;;;;;;;;;;;;;;;; Export binary file
	savebin "patched.rom", 0, 16384

