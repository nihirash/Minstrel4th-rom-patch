# Minstrel 4th rom patch to support RC2014's UART

To build this patch you're need [sjasmplus](https://github.com/z00m128/sjasmplus).

I'm using GNU Make for build tasks but patched rom can be build just with sjasmplus called on patch.asm. 

If you're using CLI tools for TL866 programmer - you may flash your 28c128 with this firmware using "flash" target.