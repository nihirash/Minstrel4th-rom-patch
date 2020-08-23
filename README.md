# Minstrel 4th rom patch to support RC2014's UART

To build this patch you're need [sjasmplus](https://github.com/z00m128/sjasmplus).

I'm using GNU Make for build tasks but patched rom can be built just with sjasmplus called on patch.asm. 

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
 * uxput - upload block of memory using XMODEM protocol. Syntax is `ADDRESS SIZE xbput`. On exit, TOS contains 0, if transfer succeeded and -1 otherwise.
 * uxget - download block of memory using XMODEM protocol. Syntax is `ADDRESS xbget`. On exit, TOS contains 0, if transfer succeeded and -1 otherwise.
 * `TEE ( -- )` - echo screen output to serial interface. Useful for capturing FORTH word listings or the transcript of an adventure game, for example.
 * `UNTEE ( -- )` - disable echoing of screen output to the serial interface.

## Version of patch that can be loaded into RAM

By defining INRAM variable in Makefile, you can instruct 'make' to build a version of the patch suitable for loading into RAM (in a freshly booted Minstrel). The process for loading the extra words is a bit convoluted, though the output of Make will explain the key steps. They are, as follows (for correct values, check make ouput):

1. `3FF7 3C3B ! ( MOVE STACK UP IN MEMORY ) `

2. `3FEB 3C37 ! ( MOVE END OF DICTIONARY POINTER ) `

3. `3C51 0 BLOAD SERIALB ( LOAD EXTRA WORDS )`

4. `3FB8 3C4C ! ( UPDATE FORTH VOCAB TO POINT TO NEWEST WORD ) `

5. `3FB4 3C39 ! ( UPDATE DICT TO POINT TO LENGTH FIELD ON NEWEST WORD ) `

6. `0 3FB4 ! ( SET LENGTH FIELD OF NEWEST WORD TO 0 )`

The ULOAD and USAVE commands cannot be used with RAM version of patch file, as the relinking of the dictionary will fail.
