RM=rm
NASM=nasm
BASIC_WRAP=python3 wrap.py
GIT_COMMIT_REF=$(shell git rev-parse --short HEAD)

.PHONY: clean

all: loader.bas

clean:
	$(RM) -fv *.bin *.lst *.bas

%.bas: %.bin
	$(BASIC_WRAP) $< $@

%.bin: %.asm
	$(NASM) -D GIT_COMMIT_REF=$(GIT_COMMIT_REF) -f bin -o $@ $<

