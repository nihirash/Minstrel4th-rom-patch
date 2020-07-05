;
; This is skeleton for Minstrel 4th ROM patch

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

;;;;;;;;;;;;;;;;;;;;;;; Dictionary hack place
    org #1ffd
    LUA PASS3
        _pc("dw " .. link)
    ENDLUA
;;;;;;;;;;;;;;;;;;;;;;; Export binary file
    savebin "patched.rom", 0, 16384