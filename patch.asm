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
    DISPLAY "Bytes left: ", #3BFF - $

;;;;;;;;;;;;;;;;;;;;;;; Dropout tape routines
    org #1BA1
    dw #166F ;; To list

;;;;;;;;;;;;;;;;;;;;;;; Dictionary hack place
    org #1ffd
    dw LINK
;;;;;;;;;;;;;;;;;;;;;;; Export binary file
    savebin "patched.rom", 0, 16384