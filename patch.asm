;
; This is skeleton for Minstrel 4th ROM patch
LINK = #1D58
;;;;;;;;;;;;;;;;;;;;;;; Global macros section
    include "rom-modules/forth-word-macro.asm"

;;;;;;;;;;;;;;;;;;;;;;; Original ROM section
    device zxspectrum48 // Only for using SAVEBIN

    IFDEF INRAM
    OUTPUT "serialtools.bin"
    ENDIF
	
    IFNDEF INRAM
      org #0
      incbin "minstrel.rom"
    ENDIF
	
;;;;;;;;;;;;;;;;;;;;;;; Additional ROM section
    IFDEF INRAM
    org 0x3c51			; Immediately follows defn of FORTH
    ELSE
    org #2800
    ENDIF

    include "rom-modules/common-uart-ops.asm"
    include "rom-modules/uart-dos.asm"
	
    IFDEF INRAM
      DISPLAY "Set STACKBOT to be", end
      DISPLAY "Set 0x3C4C to be", w_ubget + 9

      OUTEND
    ELSE
      DISPLAY "Bytes left: ", #3BFF - $
	
;;;;;;;;;;;;;;;;;;;;;;; Dropout tape routines
      org #1BA1
      dw #166F ;; To list

;;;;;;;;;;;;;;;;;;;;;;; Dictionary hack place
      org #1ffd
      dw LINK
;;;;;;;;;;;;;;;;;;;;;;; Export binary file
      savebin "patched.rom", 0, 16384
    ENDIF

