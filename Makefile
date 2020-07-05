ASM = sjasmplus
AFLAGS = --sym=rom.sym

ifeq ($(OS),Windows_NT)
	ERASE = erase
	MERGECMD = copy patched.rom+secondpart.rom toflash.tom
	else
	ERASE = rm
	MERGECMD = cat patched.rom secondpart.rom >toflash.rom
endif


SRC = patch.asm
OBJS = patched.rom

all: toflash.rom

flash: toflash.rom
		minipro -p "AT28C256"  -E
		minipro -p "AT28C256"  -w toflash.rom

toflash.rom: patched.rom
		$(MERGECMD)

$(OBJS): $(SRC) minstrel.rom
		$(ASM) $(AFLAGS) patch.asm
		
clean:
		$(ERASE) $(OBJS) toflash.rom