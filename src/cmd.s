; cmd.s - EASM page 1: the command line (a scrolling console with a ">" prompt) and the monitor.
;   ASM            assemble the text           RUN          assemble, then run from the entry point
;   EDIT [n] / LINE n   the editor (at line n)  FIND text    the next line containing text
;   NEW            erase the text              SYM          list the symbols
;   ? expr         value of an expression      BYE          back to the Genio menu
;   A addr  assemble line by line   D [addr]  disassemble   M [addr]  memory   E addr [bytes]  edit
;   R  registers after the last program   G [addr]  run   F from,to,byte  fill   C from,to,with  compare
; Monitor numbers are hexadecimal (a word made of hex digits is a number); ASM syntax applies otherwise.
; Copyright (C) 2026 Santiago Crespo
; SPDX-License-Identifier: GPL-3.0-or-later

	.include "shared.inc"
	.area	CODE

;cmdloop - the command line. Entered by a jump; the stack is reset.
cmdloop::
	xor	a
	ld	(LEN), a
	ld	(CUR), a
cmdnext::
	ld	sp, #STACK
	ld	(ERRSP), sp
	ld	hl, #cmderr
	ld	(ERRJP), hl
	xor	a
	ld	(INASM), a
	ld	(HOFS), a
	ld	(CURSOFF), a
	call	NEWLINE
	ld	a, #'>
	call	PUTCHAR
	ld	a, (PRUN)		; a command given by an editor key runs at once
	or	a
	jr	z, 1$
	xor	a
	ld	(PRUN), a
	ld	hl, #LBUF
	ld	a, (LEN)
	ld	l, a
	ld	(hl), #CR
	ld	l, #0
	call	PRINTSTRCR
	call	NEWLINE
	jr	2$
1$:	call	readline
	jr	nc, 2$
	ld	a, (CY)			; ANSWER: the prompt row is cleared, the editor comes
	ld	e, a
	add	a, a
	add	a, a
	add	a, e
	add	a, a
	add	a, a
	ld	e, a
	ld	d, #0
	ld	hl, #SCR
	add	hl, de
	ld	b, #20
3$:	ld	(hl), #0x20
	inc	hl
	djnz	3$
	xor	a
	ld	(CX), a
	jp	toedit
2$:	call	docmd
	jr	cmdloop

; Print LBUF up to CR
PRINTSTRCR:
	ld	a, (hl)
	cp	#CR
	ret	z
	call	PUTCHAR
	inc	hl
	jr	PRINTSTRCR

; Error handler of the command line: the message (with the line, during ASM), then the prompt
cmderr:	ld	a, (RUNNING)
	or	a
	jr	z, 1$
	xor	a
	ld	(RUNNING), a
1$:	call	NEWLINE
	ld	a, (INASM)
	or	a
	jr	z, 2$
	xor	a			; during ASM: "Line n:" and the line, kept for the editor
	ld	(INASM), a
	ld	(SYMOK), a
	ld	hl, (ASMLN)
	inc	hl
	ld	(ERRLN), hl
	ld	hl, #ltxt
	call	PRINTSTR
	ld	hl, (ERRLN)
	call	PRDEC
	ld	a, #':
	call	PUTCHAR
	call	NEWLINE
	ld	hl, #WBUF
	ld	b, #20
3$:	ld	a, (hl)
	cp	#CR
	jr	z, 4$
	call	PUTCHAR
	inc	hl
	djnz	3$
4$:	call	NEWLINE
2$:	ld	a, (ERRNO)
	call	errmsg
	call	prmsg
	call	BEEP
	jp	cmdloop

ltxt:	.asciz	"Line "

; Execute the command in LBUF
docmd:	ld	iy, #LBUF
	ld	a, #16
	ld	(RADIX), a
	call	skipsp
	cp	#CR
	ret	z
	cp	#'?
	jp	z, c_calc
	call	getname
	jr	nc, 9$
	ld	hl, #CMDS
	ld	c, #0
1$:	ld	a, (hl)			; compare NAMBUF with each name of the table
	or	a
	jr	z, 9$
	ld	de, #NAMBUF
	ld	a, (de)
	ld	b, a
	push	hl
2$:	inc	de
	ld	a, (de)
	xor	(hl)
	and	#0x7F
	jr	nz, 4$
	bit	7, (hl)
	inc	hl
	jr	nz, 3$
	djnz	2$
	jr	4$			; the name is shorter
3$:	dec	b
	jr	nz, 4$
	pop	hl
	ld	a, c
	add	a, a
	ld	e, a
	ld	d, #0
	ld	hl, #CMDTAB
	add	hl, de
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	jp	(hl)
4$:	pop	hl
5$:	bit	7, (hl)
	inc	hl
	jr	z, 5$
	inc	c
	jr	1$
9$:	ld	a, #E_CMD
	jp	error

.macro	NAME	text, last
	.ascii	text
	.db	last+0x80
.endm
CMDS:	NAME	"AS", 'M
	NAME	"RU", 'N
	NAME	"NE", 'W
	NAME	"EDI", 'T
	NAME	"LIN", 'E
	NAME	"FIN", 'D
	NAME	"SY", 'M
	NAME	"BY", 'E
	NAME	"", 'A
	NAME	"", 'D
	NAME	"", 'M
	NAME	"", 'E
	NAME	"", 'R
	NAME	"", 'G
	NAME	"", 'F
	NAME	"", 'C
	.db	0
CMDTAB:	.dw	c_asm, c_run, c_new, c_edit, c_edit, c_find, c_sym, c_bye
	.dw	c_a, c_d, c_m, c_e, c_r, c_g, c_f, c_c

;---------------------------------------------------------------- argument helpers

; HL = optional argument; carry if there is one
argopt:	call	skipsp
	call	isend
	ret	z			; (NC)
	cp	#',
	ret	z
	call	EXPR
	scf
	ret

; HL = argument, required
argreq:	call	argopt
	ret	c
synerr:	ld	a, #E_SYNTAX
	jp	error

; A comma, then HL = argument
argcom:	call	skipsp
	cp	#',
	jr	nz, synerr
	inc	iy
	jr	argreq

; Nothing more on the line
argend:	call	skipsp
	call	isend
	ret	z
	jr	synerr

;---------------------------------------------------------------- commands

c_asm:	call	argend
	call	asmsrc
; The result of ASM: "D000-D00C 13 bytes", "Entry D000"
report:	ld	hl, (HIADR)
	ld	de, (LOADR)
	or	a
	sbc	hl, de
	jr	nc, 1$
	ld	hl, #nocode
	jp	PRINTSTR
1$:	ex	de, hl
	call	PRHEX16
	ld	a, #'-
	call	PUTCHAR
	ld	hl, (HIADR)
	call	PRHEX16
	ld	a, #0x20
	call	PUTCHAR
	ld	hl, (HIADR)
	ld	de, (LOADR)
	or	a
	sbc	hl, de
	inc	hl
	call	PRDEC
	ld	hl, #bytes
	call	PRINTSTR
	call	NEWLINE
	ld	hl, #entry
	call	PRINTSTR
	ld	hl, (ENTRY)
	jp	PRHEX16

nocode:	.asciz	"OK, no code"
bytes:	.asciz	" bytes"
entry:	.asciz	"Entry "

c_run:	call	argend
	call	asmsrc
	ld	a, (ENTOK)
	or	a
	ld	a, #E_NOCODE
	jp	z, error
	ld	hl, (ENTRY)
; Run the program at HL, then say how it ended
run:	ld	(MADDR), hl
	call	rungo
	call	NEWLINE
	ld	a, (REGOK)
	cp	#2
	ret	c			; RET: nothing to add
	ld	hl, #brktxt
	jr	nz, 1$
	ld	hl, #exittxt
	call	PRINTSTR
	ld	hl, (REGS+14)
	jp	PRHEX16
1$:	jp	PRINTSTR

brktxt:	.asciz	"Break"
exittxt:
	.asciz	"EXIT at "

c_g:	call	argopt
	jr	c, 1$
	ld	a, (ENTOK)
	or	a
	ld	a, #E_NOCODE
	jp	z, error
	ld	hl, (ENTRY)
1$:	push	hl
	call	argend
	pop	hl
	jr	run

c_new:	call	argend
	ld	hl, #suretxt
	call	PRINTSTR
	call	GETKEY
	and	#0xDF
	cp	#'Y
	ret	nz
	call	txtnew
	xor	a
	ld	(ECUR), a
	ld	hl, #newtxt
	jp	PRINTSTR

suretxt:
	.asciz	"Erase the text? Y/N"
newtxt:	.asciz	" erased"

c_bye:	di				; the firmware's "no key" state, as on entry
	ld	a, #0xC0
	ld	(FW_KEYST), a
	jp	0x0030

; ? expr: hexadecimal and decimal value (assembler syntax: decimal by default)
c_calc:	inc	iy
	ld	a, #10
	ld	(RADIX), a
	call	argreq
	push	hl
	call	argend
	pop	hl
	ld	a, #'=
	call	PUTCHAR
	call	PRHEX16
	ld	a, #'H
	call	PUTCHAR
	ld	a, #0x20
	call	PUTCHAR
	jp	PRDEC

; EDIT [n], LINE n: to the editor at line n (1-based, decimal)
c_edit:	ld	a, #10
	ld	(RADIX), a
	call	argopt
	jr	nc, 2$
	push	hl
	call	argend
	pop	hl
	ld	a, h
	or	l
	jr	z, 1$
	dec	hl
1$:	ex	de, hl
	call	clampl
	ld	(CURL), de
	xor	a
	ld	(ECUR), a
2$:	jp	toedit

; DE = a line number limited to the text (0 to NLINES-1). Destroys A,F,H,L.
clampl::
	ld	hl, (NLINES)
	dec	hl
	or	a
	sbc	hl, de
	ret	nc
	ld	de, (NLINES)
	dec	de
	ret

; FIND text: the next line (after the current one, round to it) containing the text, any case
c_find:	call	skipsp
	cp	#CR
	jp	z, synerr
	push	iy
	pop	hl
	ld	(LABPOS), hl		; the text to find, ending in CR
	ld	de, (CURL)
	ld	hl, (NLINES)		; lines to try
	ld	(FCOUNT), hl
1$:	inc	de
	ld	hl, (NLINES)
	or	a
	sbc	hl, de
	jr	nz, 2$
	ld	de, #0
2$:	push	de
	call	lineptr
	ld	de, #WBUF
	call	expand
	ld	a, #CR
	ld	(de), a
	call	fmatch
	pop	de
	jr	nc, 3$
	ld	hl, (FCOUNT)
	dec	hl
	ld	(FCOUNT), hl
	ld	a, h
	or	l
	jr	nz, 1$
	ld	hl, #nftxt
	jp	PRINTSTR
3$:	ld	(CURL), de
	ld	(ECUR), a
	jp	toedit

nftxt:	.asciz	"Not found"

; NC and A = the column where the text at LABPOS appears in WBUF, else carry
fmatch:	ld	hl, #WBUF
1$:	ld	a, (hl)
	cp	#CR
	scf
	ret	z
	push	hl
	ld	de, (LABPOS)
2$:	ld	a, (de)
	cp	#CR
	jr	z, 4$			; all of it matched
	call	upper
	ld	c, a
	ld	a, (hl)
	call	upper
	cp	c
	jr	nz, 3$
	inc	hl
	inc	de
	jr	2$
3$:	pop	hl
	inc	hl
	jr	1$
4$:	pop	hl
	ld	a, l
	or	a
	ret

; A in upper case (ASCII letters)
upper::	cp	#'a
	ret	c
	cp	#'z+1
	ret	nc
	sub	#0x20
	ret

; R: the registers at the end of the last program
;   AF=0044 -Z-P-- 8031     flags S Z H P/V N C, then PC (after EXIT; "----" after RET or a break)
;   BC=0000 DE=0000 / HL=0000 IX=0000 / IY=0000 SP=C4FE
c_r:	call	argend
	ld	a, (REGOK)
	or	a
	jr	nz, 1$
	ld	hl, #noregs
	jp	PRINTSTR
1$:	call	savescr
	ld	hl, #ROWBUF		; 80 spaces
	ld	b, #80
2$:	ld	(hl), #0x20
	inc	hl
	djnz	2$
	ld	hl, #rnames		; pairs: name, offset in REGS, offset in ROWBUF
	ld	b, #7
3$:	ld	a, (hl)
	add	a, #<ROWBUF
	ld	e, a
	inc	hl
	ld	d, #>ROWBUF
	ld	a, (hl)
	inc	hl
	ld	(de), a
	inc	de
	ld	a, (hl)
	inc	hl
	ld	(de), a
	inc	de
	ld	a, #'=
	ld	(de), a
	inc	de
	ld	a, (hl)
	inc	hl
	push	hl
	ld	hl, #REGS
	add	a, l
	ld	l, a
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	call	bhex16
	pop	hl
	djnz	3$
	ld	a, (REGS)		; flags: S Z H P/V N C, "-" when clear
	ld	c, a
	ld	hl, #flagch
	ld	de, #ROWBUF+8
	ld	b, #8
4$:	ld	a, (hl)
	inc	hl
	rl	c
	jr	c, 5$
	cp	#'x
	jr	z, 6$
	ld	a, #'-
5$:	cp	#'x			; bits 5 and 3 are not shown
	jr	z, 6$
	ld	(de), a
	inc	de
6$:	djnz	4$
	ld	de, #ROWBUF+15		; PC
	ld	hl, (REGS+14)
	ld	a, h
	or	l
	jr	z, 8$
	call	bhex16
	jr	9$
8$:	ld	a, #'-
	ld	b, #4
10$:	ld	(de), a
	inc	de
	djnz	10$
9$:	ld	hl, #ROWBUF
	ld	e, #0
11$:	ld	a, (hl)
	inc	hl
	push	hl
	call	putcell
	pop	hl
	inc	e
	ld	a, e
	cp	#80
	jr	c, 11$
	call	GETKEY
	jp	restscr

; register name, offset in REGS, then the column (offset in ROWBUF) first
rnames:	.db	0
	.ascii	"AF"
	.db	0, 20
	.ascii	"BC"
	.db	2, 28
	.ascii	"DE"
	.db	4, 40
	.ascii	"HL"
	.db	6, 48
	.ascii	"IX"
	.db	8, 60
	.ascii	"IY"
	.db	10, 68
	.ascii	"SP"
	.db	12
flagch:	.ascii	"SZxHxPNC"
noregs:	.asciz	"No program run yet"

; F from,to,byte (user RAM only)
c_f:	call	range
	call	argcom
	push	hl
	call	argend
	pop	hl
	ld	a, l
	ld	hl, (FFROM)
	ld	bc, (FCOUNT)
1$:	ld	(hl), a
	inc	hl
	dec	bc
	ld	d, a
	ld	a, b
	or	c
	ld	a, d
	jr	nz, 1$
	ret

; FFROM, FCOUNT = range "from,to" (to >= from, both in user RAM)
range:	call	argreq
	ld	(FFROM), hl
	call	argcom
	ld	de, (FFROM)
	or	a
	sbc	hl, de
	jp	c, synerr
	inc	hl
	ld	(FCOUNT), hl
	add	hl, de
	dec	hl
	call	usrchk
	ex	de, hl
	jp	usrchk

; C from,to,with: the first differences (up to three), or "Same"
c_c:	call	argreq
	ld	(FFROM), hl
	call	argcom
	ld	de, (FFROM)
	or	a
	sbc	hl, de
	jp	c, synerr
	inc	hl
	ld	(FCOUNT), hl
	call	argcom
	push	hl
	call	argend
	pop	de			; DE = with
	ld	hl, (FFROM)
	ld	bc, (FCOUNT)
	ld	a, #3
	ld	(LABPOS), a		; differences left to show
1$:	ld	a, (de)
	cp	(hl)
	jr	z, 2$
	push	af
	call	NEWLINE
	call	PRHEX16
	ld	a, #0x20
	call	PUTCHAR
	ld	a, (hl)
	call	PRHEX8
	ld	a, #0x20
	call	PUTCHAR
	pop	af
	call	PRHEX8
	ld	a, (LABPOS)
	dec	a
	ld	(LABPOS), a
	ret	z
2$:	inc	hl
	inc	de
	dec	bc
	ld	a, b
	or	c
	jr	nz, 1$
	ld	a, (LABPOS)
	cp	#3
	ret	nz
	ld	hl, #sametxt
	jp	PRINTSTR

sametxt:
	.asciz	"Same"

; E addr [byte...]: write bytes; with none, ask for each one ("D000 3E " then a value, ENTER keeps it)
c_e:	call	argreq
	ld	(MADDR), hl
	call	skipsp
	cp	#',
	jr	nz, 5$
	inc	iy
5$:	call	argopt
	jr	nc, 2$
1$:	call	poke			; the bytes given
	call	argopt
	jr	c, 1$
	ret
2$:	call	NEWLINE
	ld	hl, (MADDR)
	call	PRHEX16
	ld	a, #0x20
	call	PUTCHAR
	ld	a, (hl)
	call	PRHEX8
	ld	a, #0x20
	call	PUTCHAR
	xor	a
	ld	(LEN), a
	ld	(CUR), a
	ld	(HOFS), a
	call	readline
	ret	c
	ld	iy, #LBUF
	call	argopt
	jr	nc, 3$
4$:	call	poke
	call	argopt
	jr	c, 4$
	jr	2$
3$:	ld	hl, (MADDR)		; ENTER alone: the next byte
	inc	hl
	ld	(MADDR), hl
	jr	2$

; Store L at MADDR (user RAM only) and advance; a comma may follow
poke:	ld	e, l
	ld	hl, (MADDR)
	call	usrchk
	ld	(hl), e
	inc	hl
	ld	(MADDR), hl
	call	skipsp
	cp	#',
	ret	nz
	inc	iy
	ret

; A addr: assemble line by line. ENTER alone or ANSWER ends.
c_a:	call	argreq
	ld	(MADDR), hl
	call	argend
	ld	(ERRSP), sp
	ld	hl, #aerr
	ld	(ERRJP), hl
a_loop:	call	NEWLINE
	ld	hl, (MADDR)
	call	PRHEX16
	ld	a, #0x20
	call	PUTCHAR
	xor	a
	ld	(LEN), a
	ld	(CUR), a
	ld	(HOFS), a
	call	readline
	ret	c
	ld	a, (LEN)
	or	a
	ret	z
	ld	a, #16
	ld	(RADIX), a
	ld	hl, (MADDR)
	push	hl
	call	asmone
	ld	(MADDR), hl
	pop	de			; show the bytes: "  3E 05"
	or	a
	sbc	hl, de
	ld	b, l
	ld	a, b
	or	a
	jr	z, a_loop
	call	NEWLINE
	ex	de, hl
	ld	a, #0x20
	call	PUTCHAR
2$:	ld	a, #0x20
	call	PUTCHAR
	ld	a, (hl)
	call	PRHEX8
	inc	hl
	djnz	2$
	jr	a_loop
aerr:	call	NEWLINE			; an error: say it and stay at the same address
	ld	a, (ERRNO)
	call	errmsg
	call	prmsg
	call	BEEP
	ld	hl, #aerr
	ld	(ERRJP), hl
	jr	a_loop

;---------------------------------------------------------------- viewers

; A key for the viewers: U-diaeresis is UP and ';' DOWN (as ALT+U-diaeresis and ALT+;), ENTER is ESC
vkey::	call	GETKEY
	cp	#0x81			; u-diaeresis, upper case too
	jr	z, 1$
	cp	#0x9A
	jr	z, 1$
	cp	#0x3B
	jr	z, 2$
	cp	#CR
	ret	nz
	ld	a, #ESC
	ret
1$:	ld	a, #UP
	ret
2$:	ld	a, #DOWN
	ret

; M [addr]: four rows of four bytes. UP/DOWN: a row, LEFT/RIGHT: four rows.
c_m:	call	argopt
	jr	nc, 1$
	ld	(MADDR), hl
1$:	call	argend
	call	savescr
2$:	ld	hl, (MADDR)
	ld	e, #0
3$:	push	de			; "D000 00 11 22 33"
	ld	de, #ROWBUF
	call	bhex16
	ld	b, #4
4$:	ld	a, #0x20
	ld	(de), a
	inc	de
	ld	a, (hl)
	inc	hl
	call	bhex8
	djnz	4$
	xor	a
	ld	(de), a
	pop	de
	push	hl
	ld	hl, #ROWBUF
	call	putrow
	pop	hl
	ld	a, e
	cp	#80
	jr	c, 3$
	call	vkey
	ld	hl, (MADDR)
	ld	de, #4
	cp	#DOWN
	jr	z, 5$
	ld	de, #-4
	cp	#UP
	jr	z, 5$
	ld	de, #16
	cp	#RIGHT
	jr	z, 5$
	ld	de, #-16
	cp	#LEFT
	jr	z, 5$
	cp	#ESC
	jr	nz, 2$
	jp	restscr
5$:	add	hl, de
	ld	(MADDR), hl
	jr	2$

; D [addr]: four instructions. DOWN: the next one, UP: back, RIGHT/LEFT: four.
c_d:	call	argopt
	jr	nc, 1$
	ld	(MADDR), hl
1$:	call	argend
	call	savescr
	xor	a
	ld	(HISTN), a
2$:	ld	hl, (MADDR)
	ld	e, #0
3$:	push	de
	ld	de, #ROWBUF
	call	bhex16
	ld	a, #0x20
	ld	(de), a
	inc	de
	call	disasm			; HL = next address
	xor	a
	ld	(de), a
	pop	de
	push	hl
	ld	hl, #ROWBUF
	call	putrow
	pop	hl
	ld	a, e
	cp	#80
	jr	c, 3$
	call	vkey
	ld	b, #1
	cp	#DOWN
	jr	z, 5$
	cp	#UP
	jr	z, 6$
	ld	b, #4
	cp	#RIGHT
	jr	z, 5$
	cp	#LEFT
	jr	z, 6$
	cp	#ESC
	jr	nz, 2$
	jp	restscr
5$:	push	bc			; forward B instructions, remembering where they started
	ld	hl, (MADDR)
	call	hpush
	push	hl
	ld	de, #ROWBUF
	call	disasm
	ld	(MADDR), hl
	pop	hl
	pop	bc
	djnz	5$
	jr	2$
6$:	push	bc			; back B instructions (one byte when there is no history)
	call	hpop
	ld	(MADDR), hl
	pop	bc
	djnz	6$
	jr	2$

; The history of D: up to 16 start addresses
hpush:	ld	a, (HISTN)
	cp	#16
	jr	c, 1$
	push	hl			; full: forget the oldest
	ld	hl, #HIST+2
	ld	de, #HIST
	ld	bc, #30
	ldir
	pop	hl
	ld	a, #15
1$:	ld	e, a
	inc	a
	ld	(HISTN), a
	ld	d, #0
	ex	de, hl
	add	hl, hl
	ld	bc, #HIST
	add	hl, bc
	ld	(hl), e
	inc	hl
	ld	(hl), d
	ex	de, hl
	ret
hpop:	ld	a, (HISTN)
	or	a
	jr	nz, 1$
	ld	hl, (MADDR)
	dec	hl
	ret
1$:	dec	a
	ld	(HISTN), a
	add	a, a
	ld	l, a
	ld	h, #0
	ld	bc, #HIST
	add	hl, bc
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	ret

; SYM: the symbols, four per screen, "NAME          D000"
c_sym:	call	argend
	ld	a, (SYMOK)
	or	a
	jr	nz, 1$
	ld	hl, #asmfirst
	jp	PRINTSTR
1$:	call	savescr
	ld	hl, #0
	ld	(FFROM), hl		; first entry shown
2$:	ld	de, (FFROM)
	call	symnth
	ld	e, #0
3$:	push	de
	ld	de, (SYMEND)
	or	a
	sbc	hl, de
	add	hl, de
	pop	de
	jr	nc, 4$			; past the end: blank rows
	push	de
	ld	de, #ROWBUF
	ld	b, (hl)
	inc	hl
	ld	c, #16
5$:	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	c
	djnz	5$
6$:	ld	a, #0x20
	ld	(de), a
	inc	de
	dec	c
	jr	nz, 6$
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	inc	hl
	push	hl
	ld	h, b
	ld	l, c
	call	bhex16
	xor	a
	ld	(de), a
	pop	hl
	pop	de
	push	hl
	ld	hl, #ROWBUF
	call	putrow
	pop	hl
	jr	7$
4$:	push	hl
	ld	hl, #ROWBUF
	ld	(hl), #0
	call	putrow
	pop	hl
7$:	ld	a, e
	cp	#80
	jr	c, 3$
	call	vkey
	ld	hl, (FFROM)
	ld	de, #1
	cp	#DOWN
	jr	z, 8$
	ld	de, #4
	cp	#RIGHT
	jr	z, 8$
	ld	de, #-1
	cp	#UP
	jr	z, 9$
	ld	de, #-4
	cp	#LEFT
	jr	z, 9$
	cp	#ESC
	jr	nz, 2$
	jp	restscr
8$:	add	hl, de			; forward only while there is an entry there
	push	hl
	ex	de, hl
	call	symnth
	ld	bc, (SYMEND)
	or	a
	sbc	hl, bc
	pop	hl
	jp	nc, 2$
	jr	10$
9$:	add	hl, de
	jr	c, 10$			; (wrapped below 0: stay at 0)
	ld	hl, #0
10$:	ld	(FFROM), hl
	jp	2$

asmfirst:
	.asciz	"Assemble first (ASM)"

; HL = entry DE of the symbol table (or past its end)
symnth:	ld	hl, (TXTEND)
1$:	ld	a, d
	or	e
	ret	z
	push	de
	ld	de, (SYMEND)
	or	a
	sbc	hl, de
	add	hl, de
	pop	de
	ret	nc
	ld	a, (hl)
	add	a, #3
	add	a, l
	ld	l, a
	jr	nc, 2$
	inc	h
2$:	dec	de
	jr	1$

;---------------------------------------------------------------- output helpers

; Row: the text at HL (ending in 0) padded to 20 cells from cell E. E ends at the next row.
; Destroys A,B,C,H,L,F.
putrow::
	ld	b, #20
1$:	ld	a, (hl)
	or	a
	jr	z, 2$
	inc	hl
	jr	3$
2$:	ld	a, #0x20
3$:	push	hl
	push	bc
	call	putcell
	pop	bc
	pop	hl
	inc	e
	djnz	1$
	ret

; HL as four hex digits at DE (DE advances). bhex8: A as two. Destroy A,F.
bhex16::
	ld	a, h
	call	bhex8
	ld	a, l
bhex8::	push	af
	rrca
	rrca
	rrca
	rrca
	call	1$
	pop	af
1$:	and	#0x0F
	add	a, #0x90
	daa
	adc	a, #0x40
	daa
	ld	(de), a
	inc	de
	ret

;---------------------------------------------------------------- line input

;readline - edit LBUF (LEN, CUR) on the console row from the current column to the end of the row,
; scrolling sideways. ENTER: carry clear, LBUF ends in CR, new line. ANSWER: carry set.
readline::
	ld	a, #0xFF
	ld	(RLCOL), a
1$:	call	rldraw
	call	GETKEY
	cp	#CR
	jr	z, 8$
	cp	#ESC
	jr	z, 9$
	cp	#HELP
	jr	nz, 2$
	call	savescr
	ld	a, #1
	call	help			; the guide; an example comes back in WBUF (carry)
	push	af
	call	restscr
	pop	af
	jr	nc, 1$
	call	exline			; the example replaces the line
	jr	1$
2$:	call	actkey
	jr	nc, 3$
	cp	#A_ACT
	jr	nc, 5$
	call	acttext			; a text key: its text
	call	instext
	jr	1$
5$:	cp	#A_ASM			; ASM and RUN keys: that command; the others do nothing here
	jr	z, 4$
	cp	#A_RUN
	jr	nz, 1$
4$:	call	acttext
	xor	a
	ld	(LEN), a
	ld	(CUR), a
	call	instext
	jr	8$
3$:	call	edkey			; editing keys and characters
	jr	1$
8$:	call	rldraw
	ld	hl, #LBUF
	ld	a, (LEN)
	ld	l, a
	ld	(hl), #CR
	call	newline
	or	a
	ret
9$:	call	rldraw
	scf
	ret

; Draw LBUF from HOFS on the row, from RLCOL; the cursor at CUR
rldraw:	ld	a, (CX)
	cp	#20
	jr	c, 1$
	call	newline			; no room on this row
	xor	a
1$:	ld	b, a
	ld	a, (RLCOL)
	cp	#0xFF
	jr	nz, 2$
	ld	a, b
	ld	(RLCOL), a
2$:	ld	c, a			; C = first column
	ld	a, #19			; width - 1
	sub	c
	call	hscroll
	ld	a, (CY)
	ld	e, a
	add	a, a
	add	a, a
	add	a, e
	add	a, a
	add	a, a
	add	a, c
	ld	e, a			; cell
	ld	a, #20
	sub	c
	ld	b, a
	ld	a, (HOFS)
	ld	d, a
3$:	ld	a, (LEN)
	cp	d
	ld	a, #0x20
	jr	z, 4$
	jr	c, 4$
	ld	hl, #LBUF
	ld	l, d
	ld	a, (hl)
4$:	push	bc
	push	de
	call	putcell
	pop	de
	pop	bc
	inc	e
	inc	d
	djnz	3$
	ld	a, (HOFS)
	ld	b, a
	ld	a, (CUR)
	sub	b
	add	a, c
	ld	(CX), a
	ret

;hscroll - keep CUR within HOFS .. HOFS+A (A = shown width - 1); moving left, four characters
; before the cursor stay in view. Destroys A,B,F.
hscroll::
	ld	b, a
	ld	a, (CUR)
	push	hl
	ld	hl, #HOFS
	cp	(hl)
	jr	nc, 1$
	sub	#4			; left of the window
	jr	nc, 3$
	xor	a
3$:	ld	(hl), a
	pop	hl
	ret
1$:	sub	(hl)
	cp	b
	jr	c, 2$
	jr	z, 2$
	sub	b			; right of it
	add	a, (hl)
	ld	(hl), a
2$:	pop	hl
	ret
