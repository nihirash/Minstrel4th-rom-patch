# Minstrel 4th rom patch to support RC2014's UART

To build this patch you're need [sjasmplus](https://github.com/z00m128/sjasmplus).

I'm using GNU Make for build tasks but patched rom can be build just with sjasmplus called on patch.asm. 

If you're using CLI tools for TL866 programmer - you may flash your 28c128 with this firmware using "flash" target.

## XMODEM

Implementation of XMODEM protocol for Minstrel 4th, using the Tynemouth Software 6850 serial port for RC2014.

Current version is intended to be loaded into memory at address 0xF800, using command sequence such as:

`63488 15384 ! ( MOVE RAMTOP DOWN TO MAKE SPACE FOR CODE )`

`51 CALL ( RESET MINSTREL 4TH WITH NEW RAMTOP )`

`63488 0 BLOAD xmodem ( LOAD M/CODE )`

`87 128 OUT 22 128 OUT ( INITIALISE SERIAL CARD )`

`63676 CALL ( RUN TEST (N.B. 63676 = 0xF8BC) )`

Current version is test code which transmits the first 16kB of memory.
