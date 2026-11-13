; asm.s - EASM page 1: the two-pass assembler around Russell's translation section (asmb.s).
; A line is:  [label[:]] [statement [: statement]...] [; comment]
;   * a label is a name followed by ':', or a name in column 0 that is not a mnemonic or directive;
;   * "name EQU expr" (or "name = expr") defines a constant;
;   * statements are Z80 instructions or the directives ORG, DB/DEFB/DEFM, DW/DEFW, DS/DEFS, END.
; Pass 1 sizes everything and builds the symbol table; pass 2 writes the code (into user RAM only)
; and checks that every label kept its pass-1 address.
; Copyright (C) 2026 Santiago Crespo
; SPDX-License-Identifier: 0BSD

	.include "shared.inc"
	.area	CODE

;asmsrc - assemble the whole text. Errors leave through error(). Destroys everything but SP.
asmsrc::
	ld	a, #1
	ld	(INASM), a
	ld	(PASS), a
	ld	a, #10
	ld	(RADIX), a
	xor	a
	ld	(SYMOK), a
	ld	(ERRLN), a
	ld	(ERRLN+1), a
	ld	hl, (TXTEND)
	ld	(SYMEND), hl
1$:	ld	hl, #USRBEG
	ld	(PC), hl
	ld	hl, #0
	ld	(HIADR), hl
	dec	hl
	ld	(LOADR), hl		; LOADR > HIADR: nothing written
	xor	a
	ld	(ENTOK), a
	ld	(ENDF), a
	ld	hl, #0
	ld	(ASMLN), hl
	ld	hl, #SRCBEG
2$:	ld	de, #WBUF		; the line, expanded, ending in CR
	call	expand
	ld	a, #CR
	ld	(de), a
	ld	(LINEPTR), hl
	call	asmline
	ld	a, (ENDF)
	or	a
	jr	nz, 3$
	ld	hl, (ASMLN)
	inc	hl
	ld	(ASMLN), hl
	ld	de, (NLINES)
	or	a
	sbc	hl, de
	ld	hl, (LINEPTR)
	jr	c, 2$
3$:	ld	hl, #PASS
	ld	a, (hl)
	inc	(hl)
	dec	a
	jr	z, 1$
	xor	a
	ld	(INASM), a
	inc	a
	ld	(SYMOK), a
	ret

;asmline - assemble the line in WBUF (IY is set here)
asmline::
	ld	iy, #WBUF
	xor	a
	ld	(UNDEF), a
	call	skipsp
	call	isend
	ret	z
	call	isnam0
	jr	nc, stmts
	push	iy
	call	getname
	call	skipsp
	cp	#':
	jr	nz, 1$
	inc	iy			; "name:"
	pop	af
	jr	label
1$:	cp	#'=
	jr	z, 2$
	push	iy			; "name EQU"?
	ld	hl, #DIRS
	call	finddir
	pop	iy
	jr	c, 3$
	ld	a, c
	cp	#D_EQU
	jr	nz, 3$
	ld	hl, #DIRS		; skip the EQU
	call	finddir
	jr	4$
2$:	inc	iy			; "name = expr"
4$:	pop	af
	call	EXPR
	ld	b, #1
	call	symdef
	jp	endst
3$:	pop	iy			; column 0 and not a mnemonic or directive: a label
	push	iy
	pop	hl
	ld	a, l
	or	a			; (WBUF is page aligned)
	jr	nz, stmts
	call	ismnem
	jr	c, stmts
	call	getname
label:	ld	hl, (PC)
	ld	b, #0
	call	symdef
; Statements up to the end of the line
stmts:	ld	hl, (PC)		; $ is the address of the statement
	ld	(STPC), hl
	call	skipsp
	call	isend
	ret	z
	ld	hl, #DIRS
	call	finddir
	jr	c, 1$
	ld	hl, #dirjp
	push	hl
	ld	a, c			; handler of the directive
	add	a, a
	ld	e, a
	ld	d, #0
	ld	hl, #DIRTAB
	add	hl, de
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	jp	(hl)
1$:	ld	ix, #OBUF
	call	ASMB
	ld	a, #E_SYNTAX
	jp	c, error
	push	ix			; emit OBUF up to IX
	pop	hl
	ld	de, #OBUF
	or	a
	sbc	hl, de
	ld	b, l
	ld	hl, #OBUF
	ld	a, b
	or	a
	jr	z, endst
2$:	ld	a, (hl)
	inc	hl
	call	emit
	djnz	2$
dirjp:
; After a statement: the end of the line, or ':' and another statement
endst:	call	SKIP
	ld	a, #E_SYNTAX
	jp	nz, error
	ld	a, 0(iy)
	cp	#':
	ret	nz
	inc	iy
	jr	stmts

; Z if A ends the line (CR, ';', '\')
isend::	cp	#CR
	ret	z
	cp	#';
	ret	z
	cp	#0x5C
	ret

; Carry if the word at IY is a mnemonic or directive (IY unchanged). Destroys A,B,C,H,L,F.
ismnem:	push	iy
	ld	hl, #DIRS
	call	finddir
	pop	iy
	ccf
	ret	c
	push	iy
	ld	hl, #OPCODS
	call	FIND
	pop	iy
	ccf
	ret

;finddir - the directive at IY in the table at HL: NC, C = its number, IY after it; carry if none.
; A directive must be followed by a space or the end of the line. Destroys A,B,H,L,F.
finddir::
	ld	c, #0
1$:	ld	a, (hl)
	or	a
	scf
	ret	z
	push	iy
2$:	ld	a, 0(iy)
	cp	#'a
	jr	c, 3$
	sub	#0x20
3$:	ld	b, (hl)
	res	7, b
	cp	b
	jr	nz, 5$
	inc	iy
	bit	7, (hl)
	inc	hl
	jr	z, 2$
	ld	a, 0(iy)		; whole word?
	cp	#0x20
	jr	z, 4$
	call	isend
	jr	z, 4$
	cp	#':
	jr	nz, 6$
4$:	pop	af
	or	a
	ret
5$:	bit	7, (hl)			; skip the rest of the entry
	inc	hl
	jr	z, 5$
6$:	pop	iy
	inc	c
	jr	1$

D_EQU = 9
DIRS:	.ascii	"OR"
	.db	'G+0x80
	.ascii	"DEF"
	.db	'B+0x80
	.ascii	"DEF"
	.db	'M+0x80
	.ascii	"D"
	.db	'B+0x80
	.ascii	"DEF"
	.db	'W+0x80
	.ascii	"D"
	.db	'W+0x80
	.ascii	"DEF"
	.db	'S+0x80
	.ascii	"D"
	.db	'S+0x80
	.ascii	"EN"
	.db	'D+0x80
	.ascii	"EQ"
	.db	'U+0x80
	.db	0
DIRTAB:	.dw	d_org, d_db, d_db, d_db, d_dw, d_dw, d_ds, d_ds, d_end, d_equ

d_equ:	ld	a, #E_SYNTAX		; EQU without a name
	jp	error

d_org:	call	EXPR
	ld	(PC), hl
	ret

d_end:	call	skipsp
	call	isend
	ret	z
	cp	#':
	ret	z
	call	EXPR
	ld	(ENTRY), hl
	ld	a, #2
	ld	(ENTOK), a
	ld	(ENDF), a
	ret

; DB: expressions (bytes) and strings, separated by commas
d_db:	call	skipsp
	cp	#0x22
	jr	z, 1$
	cp	#0x27
	jr	nz, 4$
	ld	b, a
	ld	a, 2(iy)		; 'c' alone is an expression ('A'+1)
	cp	b
	ld	a, b
	jr	nz, 1$
4$:	call	EXPR
	call	byteok
	ld	a, l
	call	emit
	jr	3$
1$:	ld	b, a			; a string up to the same quote
	inc	iy
2$:	ld	a, 0(iy)
	cp	#CR
	ld	a, #E_STRING
	jp	z, error
	ld	a, 0(iy)
	inc	iy
	cp	b
	jr	z, 3$
	call	emit
	jr	2$
3$:	call	skipsp
	cp	#',
	ret	nz
	inc	iy
	jr	d_db

; HL must fit in a byte (-256 to 255), checked in pass 2
byteok:	ld	a, (PASS)
	dec	a
	ret	z
	ld	a, h
	or	a
	ret	z
	inc	a
	ret	z
	ld	a, #E_RANGE
	jp	error

d_dw:	call	EXPR
	ld	a, l
	call	emit
	ld	a, h
	call	emit
	call	skipsp
	cp	#',
	ret	nz
	inc	iy
	jr	d_dw

; DS n[,fill]
d_ds:	call	EXPR
	push	hl
	ld	c, #0
	call	skipsp
	cp	#',
	jr	nz, 1$
	inc	iy
	call	EXPR
	ld	c, l
1$:	pop	hl
2$:	ld	a, h
	or	l
	ret	z
	ld	a, c
	call	emit
	dec	hl
	jr	2$

;emit - byte A at PC: written in pass 2 (only into user RAM), PC + 1. Destroys A,F.
emit::	push	hl
	push	de
	ld	hl, (PC)
	ld	e, a
	ld	a, (PASS)
	dec	a
	jr	z, 9$
	call	usrchk
	ld	(hl), e
	ld	a, (ENTOK)		; the first byte is the entry point unless END names one
	or	a
	jr	nz, 1$
	inc	a
	ld	(ENTOK), a
	ld	(ENTRY), hl
1$:	ex	de, hl
	ld	hl, (LOADR)		; lowest and highest addresses written
	or	a
	sbc	hl, de
	jr	c, 2$
	ld	(LOADR), de
2$:	ld	hl, (HIADR)
	or	a
	sbc	hl, de
	jr	nc, 3$
	ld	(HIADR), de
3$:	ex	de, hl
9$:	inc	hl
	ld	(PC), hl
	pop	de
	pop	hl
	ret

;usrchk - "Outside user RAM" unless HL is in USRBEG-USREND. Destroys A,F.
usrchk::
	ld	a, h
	cp	#>USRBEG
	jr	c, 1$
	cp	#>USREND+1		; (USREND ends a page)
	ret	c
1$:	ld	a, #E_USRRAM
	jp	error

;asmone - assemble one line in LBUF at address HL into memory (the monitor's A command, pass-2
; rules, no labels). Returns HL = the address after it. Destroys everything but SP.
asmone::
	ld	(PC), hl
	ld	a, #2
	ld	(PASS), a
	ld	a, #1
	ld	(ENTOK), a		; (no entry point here)
	ld	iy, #LBUF
	call	stmts
	ld	hl, (PC)
	ret

;---------------------------------------------------------------- errors

;errmsg - HL = the message of error A (1-n). Destroys A,F.
errmsg::
	ld	hl, #ERRTXT
1$:	dec	a
	ret	z
2$:	bit	7, (hl)
	inc	hl
	jr	z, 2$
	jr	1$

;prmsg - print the message at HL (last character with bit 7). Destroys A,F,H,L.
prmsg::	ld	a, (hl)
	and	#0x7F
	call	PUTCHAR
	bit	7, (hl)
	inc	hl
	jr	z, prmsg
	ret

; Messages, the last character with bit 7
ERRTXT:
	.ascii	"Out of rang"	; 1
	.db	0xE5
	.ascii	"Syntax erro"	; 2
	.db	0xF2
	.ascii	"Unknown symbo"	; 3
	.db	0xEC
	.ascii	"Duplicate labe"	; 4
	.db	0xEC
	.ascii	"Bad numbe"	; 5
	.db	0xF2
	.ascii	"Missing "	; 6
	.db	0xA9
	.ascii	"Outside user RA"	; 7
	.db	0xCD
	.ascii	"Symbol table ful"	; 8
	.db	0xEC
	.ascii	"Division by zer"	; 9
	.db	0xEF
	.ascii	"Phase erro"	; 10
	.db	0xF2
	.ascii	"Name too lon"	; 11
	.db	0xE7
	.ascii	"Text ful"	; 12
	.db	0xEC
	.ascii	"Bad comman"	; 13
	.db	0xE4
	.ascii	"Bad strin"	; 14
	.db	0xE7
	.ascii	"No cod"	; 15
	.db	0xE5
	.ascii	"Line too lon"	; 16
	.db	0xE7
	.ascii	"Escap"	; 17
	.db	0xE5
