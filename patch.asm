;
; This is skeleton for Minstrel 4th ROM patch
LINK = #1D58
  
;;;;;;;;;;;;;;;;;;;;;;; Global macros section
    include "rom-modules/forth-word-macro.asm"

;;;;;;;;;;;;;;;;;;;;;;; Original ROM section
    device zxspectrum48 // Only for using SAVEBIN

    org #0
    incbin "minstrel.rom"
	
;;;;;;;;;;;;;;;;;;;;;;; Additional ROM section
    org #2800

    include "rom-modules/common-uart-ops.asm"
    include "rom-modules/uart-dos.asm"
    include "rom-modules/uart-xmodem.asm"
	
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
    org #1ffd
    dw LINK
    
;;;;;;;;;;;;;;;;;;;;;;; Export binary file
    savebin "patched.rom", 0, 16384

