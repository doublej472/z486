.PHONY: all clean

all: blink.hex

blink.hex: blink.asm build.sh
	./build.sh

clean:
	rm -f blink.bin blink.hex
