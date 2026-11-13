# EASM, a Z80 assembler cartridge for the VTech Genio 2000. Usage: make   (needs sdasz80, sdldz80, python3)
# Page 1 (port 0x03 = 0x80): EASM itself. Page 2 (0x83): the guide. Page 2 calls page-1 routines through
# stubs that tools/mksyms.py writes from the page-1 map.
# Copyright (C) 2026 Santiago Crespo
# SPDX-License-Identifier: 0BSD
NAME = easm_gl2000
P1SRC = main io text editor cmd asm expr asmb disasm
RELS1 = $(P1SRC:%=out/%.rel)
RELS2 = out/help.rel out/helpdata.rel out/p1calls.rel
# page-1 routines that page 2 calls through a stub, and page-1 addresses it uses
P1CALL = putcell GETKEY
P1ADDR = R_CALL1

all: $(NAME)_AT28C256_32K.bin

out/%.rel: src/%.s src/shared.inc
	@mkdir -p out
	sdasz80 -g -l -o $@ $<

out/page1.ihx: $(RELS1)
	sdldz80 -n -m -w -i $@ -b CODE=0x8000 $(RELS1)
	@if grep -q "Undefined Global" out/page1.map; then grep -A3 "Undefined Global" out/page1.map; exit 1; fi

out/p1calls.s: out/page1.ihx tools/mksyms.py
	python3 tools/mksyms.py out/page1.map $@ --addr $(P1ADDR) --call $(P1CALL)

out/helpdata.s: help.txt tools/gen_help.py third_party/bbcz80/ASMB.Z80
	@mkdir -p out
	python3 tools/gen_help.py help.txt third_party/bbcz80/ASMB.Z80 $@

out/helpdata.rel out/p1calls.rel: out/%.rel: out/%.s
	sdasz80 -g -l -o $@ $<

out/page2.ihx: $(RELS2)
	sdldz80 -n -m -w -i $@ -b P2=0x8000 $(RELS2)
	@if grep -q "Undefined Global" out/page2.map; then grep -A3 "Undefined Global" out/page2.map; exit 1; fi

# ROM images, symbol file and the usage report
$(NAME)_AT28C256_32K.bin: out/page1.ihx out/page2.ihx tools/mkcart.py
	python3 tools/mkcart.py out/page1.ihx out/page2.ihx $@ $(NAME)_mame_64K.bin out/page1.map out/page2.map out/easm.sym out/usage.txt
	@cat out/usage.txt

test: all
	tests/run_tests.sh

clean:
	rm -rf out $(NAME)_AT28C256_32K.bin $(NAME)_mame_64K.bin
.PHONY: all clean test
.SECONDARY:
