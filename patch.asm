;
; This is skeleton for Minstrel 4th ROM patch
  IFDEF INRAM
LINK = #3c49
  ELSE
LINK = #1D58
  ENDIF
  
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
    include "rom-modules/uart-xmodem.asm"
	
    IFDEF INRAM
      DISPLAY "1. Set SPARE (0x3C3B) to be ", end + 0x0c
      DISPLAY "2. Set STACKBOT (0x3C37) to be ", end
      DISPLAY "3. Load code block to 0x3C51"	
      DISPLAY "4. Set 0x3C4C to be ", w_xbput + 0x09
      DISPLAY "5. Set DICT (0x3C39) to be ", w_xbput + 0x05
      DISPLAY "6. Set ", w_xbput + 0x05, " to be 0x0000"
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

