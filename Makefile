RM=rm
NASM=nasm
BASIC_WRAP=python3 wrap.py
GIT_COMMIT_REF=$(shell git rev-parse --short HEAD)

.PHONY: clean

all: loader.bas pc98shdd.com

clean:
	$(RM) -fv *.bin *.lst *.bas *.com

loader.bas: loader.bin
	$(BASIC_WRAP) $< $@

loader.bin: loader.asm client.bin
	$(NASM) -D GIT_COMMIT_REF=$(GIT_COMMIT_REF) -f bin -o $@ $<

client.bin: client.asm
	$(NASM) -f bin -o $@ $<

pc98shdd.com: pc98shdd.asm
	$(NASM) -f bin -l pc98shdd.lst -o $@ $<
