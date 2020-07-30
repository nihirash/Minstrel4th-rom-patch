# Minstrel 4th rom patch to support RC2014's UART

To build this patch you're need [sjasmplus](https://github.com/z00m128/sjasmplus).

I'm using GNU Make for build tasks but patched rom can be build just with sjasmplus called on patch.asm. 

If you're using CLI tools for TL866 programmer - you may flash your 28c128 with this firmware using "flash" target.

Development server placed in 'devserver' directory. 

It requires Python 3 and PySerial, before usage please correct your UART in `port` variable.

Current supported operations:
 * uinit - init UART
 * uwrite - write byte to UART
 * uread - non blocking UART reading(if there no byte in buffer will be returned -1)
 * ureads - blocking UART reading.
 * ubget - download plain binary from dev. server. Syntax is: `ADDRESS ubget FILENAME`, for example `16384 ubget game.bin` will downloads `game.bin` from dev.server to memory, starting from 16384 address.
 * ubput - upload plain binary to dev.server. Syntax is: `ADDRESS SIZE ubput FILENAME`, for example `0 16384 ubput dump.bin` will upload 16384 bytes starting from 0 address  
 * ls - get current directory files listing
 * tapin - select tape image to load from
 * tapout - select tape image for storing. If file exists - new files will be appended.
 * load/bload works like with tape but with image. Optionally you can skip file name, for example: `tapin tetris.tap load` and `tapin tetris.tap load tetris` makes same result.
 * save/bsave works in pure way as on original ROM but saves to TAP-file

## XMODEM

Implementation of XMODEM protocol for Minstrel 4th, using the Tynemouth Software 6850 serial port for RC2014.

Current version is intended to be loaded into memory at address 0xF000, using command sequence such as:

`61440 15384 ! ( MOVE RAMTOP DOWN TO MAKE SPACE FOR CODE )`

`QUIT ( RESET MINSTREL 4TH WITH NEW RAMTOP )`

`16 BASE C!`

`F000 0 BLOAD xmodem ( LOAD M/CODE )`

Both transmit and receive operations are implemented, via machine-code calls with required parameters on the stack, as follows:

- Reset card: `F0E8 CALL`

- Receive data `<start add> F10E CALL`

- Send data `<start addr> <legngth> F1B6 CALL`

For send and receive, on exit, stack contains value to indicate outcome: '0' for success; '-1' for failure (timeout). Routine will also display progress on-screen, unless INVIS is enabled to surpress screen output.

### Notes

Current version of send routine has some deviations from the standard in that it will pad the transfer size to the next 128-byte boundary, without putting in padding. For example, if you run the command:

`0000 10 F10E CALL`

--the routine will transfer the first 128 bytes of memory, rather than the first 16 plus 112 bytes of padding.

Received data is written directly to memory. If receive routine fails mid-way through transfer, there will be a partially complete copy of the transfer in memory. 

### Known issues

- Routines should be created a proper FORTH words.

- Screen logging for receive operation will report receiving one more packet than you might expect. The EOT at the end of the transfer is counted as a packet, which might confuse the user.

- Transfer routines require a small amount of RAM to hold temporary variables. It would be better to reuse existing Minstrel system variables, to make it easier to move the routines into ROM.

