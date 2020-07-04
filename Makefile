all: toflash.rom

flash: toflash.rom
		minipro -p "AT28C256"  -E
		minipro -p "AT28C256"  -w toflash.rom

toflash.rom: patched.rom
		cat patched.rom secondpart.rom >toflash.rom

patched.rom: patch.asm minstrel.rom
		sjasmplus patch.asm
		
clean:
		rm patched.rom toflash.rom