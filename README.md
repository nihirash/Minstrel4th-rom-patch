# Minstrel 4th rom patch to support RC2014's UART

To build this patch you need [sjasmplus](https://github.com/z00m128/sjasmplus).

I'm using GNU Make for build tasks, but patched rom can be built just with sjasmplus called on patch.asm. 

If you're using CLI tools for TL866 programmer - you may flash your 28c128 with this firmware using "flash" target.

Development server placed in 'devserver' directory. 

It requires Python 3 and PySerial, before usage please correct your UART in `port` variable.

Current supported operations:
 * uinit - init UART
 * uwrite - write byte to UART
 * uread - non-blocking UART reading (if there no byte in buffer will be returned -1)
 * ureads - blocking UART reading.
 * ubget - download plain binary from dev. server. Syntax is: `ADDRESS ubget FILENAME`, for example `16384 ubget game.bin` will downloads `game.bin` from dev.server to memory, starting from 16384 address.
 * ubput - upload plain binary to dev.server. Syntax is: `ADDRESS SIZE ubput FILENAME`, for example `0 16384 ubput dump.bin` will upload 16384 bytes starting from 0 address  
 * ls - get current directory files listing
 * tapin - select tape image to load from
 * tapout - select tape image for storing. If file exists - new files will be appended.
 * load/bload works like with tape but with image. Optionally you can skip file name, for example: `tapin tetris.tap load` and `tapin tetris.tap load tetris` makes same result.
 * save/bsave works in pure way as on original ROM but saves to TAP-file
 * xbput ( addr size -- flag ) - upload block of memory using XMODEM protocol. Syntax is `ADDRESS SIZE xbput`. On exit, TOS contains 0, if transfer succeeded and -1 otherwise.
 * xbget ( addr -- flag )- download block of memory using XMODEM protocol. Syntax is `ADDRESS xbget`. On exit, TOS contains 0, if transfer succeeded and -1 otherwise.
 * `tee ( -- )` - echo screen output to serial interface. Useful for capturing FORTH word listings or the transcript of an adventure game, for example.
 * `untee ( -- )` - disable echoing of screen output to the serial interface.
 * `hex ( -- )` - change BASE to hexidecimal (analogue of DECIMAL).
 * `code ( -- )` - create simple machine code routine. See Jupiter Ace user manual, Chapter 25, for details.
 

Real tape support is available using variants of the original Jupiter Ace/ Minstrel words, named SAVT (e.g., for SAVE), BSAVT, LOAT, and BLOAT. 
