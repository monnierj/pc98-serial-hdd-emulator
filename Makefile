RM=rm
NASM=nasm
BASIC_WRAP=python3 wrap.py
GIT_COMMIT_REF=$(shell git rev-parse --short HEAD)

.PHONY: clean

all: loader.bas

clean:
	$(RM) -fv *.bin *.lst *.bas

loader.bas: loader.bin
	$(BASIC_WRAP) $< $@

loader.bin: loader.asm client.bin
	$(NASM) -D GIT_COMMIT_REF=$(GIT_COMMIT_REF) -f bin -o $@ $<

client.bin: client.asm
	$(NASM) -f bin -o $@ -l client.lst $<
