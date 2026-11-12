; expr.s - EASM page 1: expression evaluator and symbol table.
;
; EXPR reads an expression at IY and returns its 16-bit value in HL (arithmetic is modulo 65536).
;   operators, lowest precedence first:   | ^    &    + -    * / % << >>    unary - + ~
;   operands: ( expr ), numbers, 'c' or "c" (a character), $ (the address of the statement), symbols
;   numbers: 123 (decimal), 0x1F $1F &1F 1FH (hex), %1010 1010B (binary). With RADIX = 16 (the
;   monitor) a word made only of hex digits is a hex number.
; Symbols: up to 15 characters (letters, digits, _ . ?; not starting with a digit), case-insensitive.
; The table follows the source text: [length][name][value lo][value hi] ..., from TXTEND to SYMEND.
; The API names (PRINTSTR, ...) are built in.
; Copyright (C) 2026 Santiago Crespo
; SPDX-License-Identifier: GPL-3.0-or-later

	.include "shared.inc"
	.area	CODE

NAMLEN = 15

; A = (IY) after spaces. Destroys F.
skipsp::
	ld	a, 0(iy)
	cp	#0x20
	ret	nz
	inc	iy
	jr	skipsp

;EXPR - value of the expression at IY in HL. IY ends after it. Destroys A,B,C,D,E,F.
EXPR::
e_or:	call	e_and
1$:	call	skipsp
	cp	#'|
	jr	z, 2$
	cp	#'^
	ret	nz
2$:	push	af
	inc	iy
	push	hl
	call	e_and
	pop	de
	pop	af
	cp	#'|
	jr	z, 3$
	ld	a, h			; xor
	xor	d
	ld	h, a
	ld	a, l
	xor	e
	ld	l, a
	jr	1$
3$:	ld	a, h
	or	d
	ld	h, a
	ld	a, l
	or	e
	ld	l, a
	jr	1$

e_and:	call	e_add
1$:	call	skipsp
	cp	#'&
	ret	nz
	inc	iy
	push	hl
	call	e_add
	pop	de
	ld	a, h
	and	d
	ld	h, a
	ld	a, l
	and	e
	ld	l, a
	jr	1$

e_add:	call	e_mul
1$:	call	skipsp
	cp	#'+
	jr	z, 2$
	cp	#'-
	ret	nz
2$:	push	af
	inc	iy
	push	hl
	call	e_mul
	pop	de
	pop	af
	ex	de, hl			; HL = left, DE = right
	cp	#'+
	jr	z, 3$
	or	a
	sbc	hl, de
	jr	1$
3$:	add	hl, de
	jr	1$

e_mul:	call	e_un
1$:	call	skipsp
	cp	#'*
	jr	z, 2$
	cp	#'/
	jr	z, 2$
	cp	#'%
	jr	z, 2$
	cp	#'<
	jr	z, 5$
	cp	#'>
	ret	nz
5$:	cp	1(iy)			; << or >>
	ret	nz
	inc	iy
2$:	push	af
	inc	iy
	push	hl
	call	e_un
	pop	de
	pop	af
	ex	de, hl			; HL = left, DE = right
	cp	#'*
	jr	nz, 3$
	call	mul16
	jr	1$
3$:	cp	#'<
	jr	nz, 6$
	ld	a, e
	call	shcount
	jr	z, 1$
7$:	add	hl, hl
	djnz	7$
	jr	1$
6$:	cp	#'>
	jr	nz, 8$
	call	shcount
	jr	z, 1$
9$:	srl	h
	rr	l
	djnz	9$
	jr	1$
8$:	push	af
	call	div16			; HL = quotient, DE = remainder
	pop	af
	cp	#'/
	jr	z, 1$
	ex	de, hl
	jr	1$

; B = shift count from DE (a count above 15 gives 0); Z if no shift
shcount:
	ld	a, d
	or	a
	jr	nz, 1$
	ld	a, e
	cp	#16
	jr	nc, 1$
	ld	b, a
	or	a
	ret
1$:	ld	hl, #0
	xor	a
	ret

; HL = HL * DE. Destroys A,B,C,D,E.
mul16::	ld	b, h
	ld	c, l
	ld	hl, #0
	ld	a, #16
1$:	add	hl, hl
	sla	c
	rl	b
	jr	nc, 2$
	add	hl, de
2$:	dec	a
	jr	nz, 1$
	ret

; HL = HL / DE, DE = HL mod DE (unsigned); "Division by zero". Destroys A,B,C.
div16:	ld	a, d
	or	e
	ld	a, #E_DIV0
	jp	z, error
	ld	b, h
	ld	c, l
	ld	hl, #0
	ld	a, #16
1$:	sla	c
	rl	b
	adc	hl, hl
	jr	c, 4$			; 17 bits: larger than any divisor
	sbc	hl, de			; (carry is clear)
	jr	nc, 2$
	add	hl, de
	jr	3$
4$:	or	a
	sbc	hl, de
2$:	inc	c
3$:	dec	a
	jr	nz, 1$
	ex	de, hl			; DE = remainder
	ld	h, b
	ld	l, c
	ret

e_un:	call	skipsp
	cp	#'-
	jr	nz, 1$
	inc	iy
	call	e_un
	xor	a
	sub	l
	ld	l, a
	sbc	a, a
	sub	h
	ld	h, a
	ret
1$:	cp	#'+
	jr	nz, 2$
	inc	iy
	jr	e_un
2$:	cp	#'~
	jr	nz, primary
	inc	iy
	call	e_un
	ld	a, h
	cpl
	ld	h, a
	ld	a, l
	cpl
	ld	l, a
	ret

primary:
	cp	#'(
	jr	nz, 1$
	inc	iy
	call	EXPR
	call	skipsp
	cp	#')
	ld	a, #E_PAREN
	jp	nz, error
	inc	iy
	ret
1$:	cp	#0x27			; 'c' or "c"
	jr	z, 2$
	cp	#0x22
	jr	nz, 3$
2$:	cp	2(iy)
	ld	a, #E_STRING
	jp	nz, error
	ld	l, 1(iy)
	ld	h, #0
	inc	iy
	inc	iy
	inc	iy
	ret
3$:	cp	#'$
	jr	nz, 4$
	inc	iy
	ld	a, 0(iy)
	call	ishex
	jr	c, hexnum
	ld	hl, (STPC)
	ret
4$:	cp	#'&
	jr	nz, 5$
	inc	iy
	jr	hexnum
5$:	cp	#'%
	jr	nz, 6$
	inc	iy
	ld	b, #2
	jr	numrad
6$:	call	isdigit
	jr	c, number
	ld	a, (RADIX)		; monitor: a word of hex digits is a number
	cp	#16
	jr	nz, symval
	push	iy
	pop	hl
7$:	ld	a, (hl)
	inc	hl
	call	ishex
	jr	c, 7$
	call	isname
	jr	nc, number		; only hex digits: a number
; A symbol: its value
symval:	call	getname
	ld	a, #E_SYNTAX
	jp	nc, error
	call	symget
	ret	nc
	ld	a, (INASM)		; not defined: 0 in pass 1 (a forward reference), else an error
	or	a
	jr	z, 1$
	ld	a, (PASS)
	dec	a
	jr	nz, 1$
	inc	a
	ld	(UNDEF), a
	ld	hl, #0
	ret
1$:	ld	a, #E_UNDEF
	jp	error

hexnum:	ld	b, #16
; Digits at IY in base B (2 or 16) up to the first character that is not one. Value in HL.
; numrad fails if a letter or digit follows; numrad0 stops there (C = digits read).
numrad:	call	numrad0
	ld	a, 0(iy)		; a letter or digit left over is a bad number
	call	isname
	jr	c, 4$
	inc	c
	dec	c
	ret	nz
4$:	ld	a, #E_NUMBER
	jp	error
numrad0:
	ld	hl, #0
	ld	c, #0			; digits seen
1$:	ld	a, 0(iy)
	call	digval
	jr	c, 2$
	cp	b
	jr	nc, 2$
	push	af
	ld	a, b
	cp	#16
	add	hl, hl
	jr	nz, 3$
	add	hl, hl
	add	hl, hl
	add	hl, hl
3$:	pop	af
	or	l
	ld	l, a
	inc	iy
	inc	c
	jr	1$
2$:	ret

; A number at IY starting with a digit (or, in the monitor, a hex letter): 0x.., ..H, ..B, decimal
number:	ld	a, 0(iy)
	cp	#'0
	jr	nz, 1$
	ld	a, 1(iy)
	and	#0xDF
	cp	#'X
	jr	nz, 1$
	inc	iy
	inc	iy
	jr	hexnum
1$:	push	iy			; find the last character of the word
	pop	hl
2$:	ld	a, (hl)
	call	isname
	inc	hl
	jr	c, 2$
	dec	hl
	dec	hl
	ld	a, (hl)			; last character
	and	#0xDF
	ld	e, l			; E = low byte of its address (the word ends there)
	cp	#'H
	jr	z, 3$
	ld	a, (RADIX)
	cp	#16
	jr	z, hexnum
	ld	a, (hl)
	and	#0xDF
	cp	#'B
	jr	nz, 5$
	ld	b, #2			; ...B: binary, if all the digits are 0 and 1
	push	iy
	pop	hl
4$:	ld	a, l
	cp	e
	jr	z, 6$
	ld	a, (hl)
	inc	hl
	cp	#'2
	jr	nc, 5$			; not binary: decimal (fails on the B)
	jr	4$
3$:	ld	b, #16
6$:	call	numrad0			; must stop at the H or B, after a digit
	ld	a, c
	or	a
	jr	z, 10$
	push	iy			; low byte of IY (no undocumented opcodes)
	ex	(sp), hl
	ld	a, l
	ex	(sp), hl
	inc	sp
	inc	sp
	cp	e
	jr	nz, 10$
	inc	iy
	ret
10$:	ld	a, #E_NUMBER
	jp	error
5$:	ld	hl, #0			; decimal
7$:	ld	a, 0(iy)
	call	isdigit
	jr	nc, 8$
	push	de
	ld	d, h
	ld	e, l
	add	hl, hl
	add	hl, hl
	add	hl, de
	add	hl, hl
	pop	de
	sub	#'0
	add	a, l
	ld	l, a
	jr	nc, 9$
	inc	h
9$:	inc	iy
	jr	7$
8$:	call	isname
	ret	nc
	ld	a, #E_NUMBER
	jp	error

; A = value of digit/letter A, carry if it is neither
digval:	call	isdigit
	jr	nc, 1$
	sub	#'0
	ret
1$:	and	#0xDF
	cp	#'A
	ret	c
	cp	#'Z+1
	ccf
	ret	c
	sub	#'A-10
	ret

; Carry if A is a decimal digit
isdigit::
	cp	#'0
	ccf
	ret	nc
	cp	#'9+1
	ret

; Carry if A is a hex digit
ishex:	call	isdigit
	ret	c
	push	bc
	ld	b, a
	and	#0xDF
	sub	#'A
	cp	#6
	ld	a, b
	pop	bc
	ret

; Carry if A can be part of a name (letter, digit, _ . ?)
isname::
	call	isdigit
	ret	c
; Carry if A can start a name (letter, _ . ?)
isnam0::
	cp	#'_
	scf
	ret	z
	cp	#'.
	scf
	ret	z
	cp	#'?
	scf
	ret	z
	push	bc
	ld	b, a
	and	#0xDF
	cp	#'A
	jr	c, 1$
	cp	#'Z+1
	jr	2$
1$:	or	a
2$:	ld	a, b
	pop	bc
	ret

;getname - read the name at IY into NAMBUF (length first, upper case). Carry if there is one.
; "Name too long" past 15 characters. Destroys A,B,H,L,F.
getname::
	ld	a, 0(iy)
	call	isnam0
	ret	nc
	ld	hl, #NAMBUF+1
	ld	b, #0
1$:	ld	a, 0(iy)
	call	isname
	jr	nc, 2$
	cp	#'a
	jr	c, 3$
	cp	#'z+1
	jr	nc, 3$
	sub	#0x20
3$:	ld	(hl), a
	inc	hl
	inc	iy
	inc	b
	ld	a, b
	cp	#NAMLEN+1
	jr	c, 1$
	ld	a, #E_NAME
	jp	error
2$:	ld	a, b
	ld	(NAMBUF), a
	scf
	ret

;symfind - look NAMBUF up in the table from HL to DE. NC and HL = its value field if found, else carry.
; Destroys A,B,C,F.
symfind::
1$:	ld	a, l			; end of the table?
	cp	e
	jr	nz, 2$
	ld	a, h
	cp	d
	scf
	ret	z
2$:	push	hl
	push	de
	ld	de, #NAMBUF
	ld	a, (de)
	ld	b, a
	inc	b			; compare the length and the name
3$:	ld	a, (de)
	cp	(hl)
	jr	nz, 4$
	inc	hl
	inc	de
	djnz	3$
	pop	de
	pop	bc			; found: HL = value field
	or	a
	ret
4$:	pop	de
	pop	hl
	ld	c, (hl)			; next entry: length + name + value
	ld	b, #0
	add	hl, bc
	inc	hl
	inc	hl
	inc	hl
	jr	1$

;symget - HL = value of the symbol in NAMBUF, NC if it is defined (the user's table only while it
; belongs to the text), else carry. Destroys A,B,C,D,E,F.
symget::
	call	usrtab
	jr	c, 1$
	call	symfind
	jr	nc, 2$
1$:	ld	hl, #BUILTIN
	ld	de, #BUILTIN_END
	call	symfind
	ret	c
2$:	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	ret

; HL, DE = bounds of the user's table; carry if it cannot be used
usrtab::
	ld	hl, (TXTEND)
	ld	de, (SYMEND)
	ld	a, (INASM)
	or	a
	ret	nz
	ld	a, (SYMOK)
	sub	#1			; carry if 0
	ret

;symdef - define NAMBUF = HL in the user's table (pass 1: a new entry, "Duplicate label" if it
; exists; pass 2: HL must equal the pass-1 value unless B = 1 (EQU: the value is updated)).
; Destroys A,B,C,D,E,H,L,F.
symdef::
	push	bc
	push	hl
	ld	hl, (TXTEND)
	ld	de, (SYMEND)
	call	symfind
	pop	de			; DE = value
	pop	bc
	jr	c, 3$
	ld	a, (PASS)		; it exists
	dec	a
	ld	a, #E_DUP
	jp	z, error
	djnz	1$
	ld	(hl), e			; EQU: update
	inc	hl
	ld	(hl), d
	ret
1$:	ld	a, (hl)			; a label: the same address as in pass 1
	cp	e
	jr	nz, 2$
	inc	hl
	ld	a, (hl)
	cp	d
	ret	z
2$:	ld	a, #E_PHASE
	jp	error
3$:	ld	hl, (SYMEND)		; new: room for length, name, value?
	ld	a, (NAMBUF)
	add	a, #3
	ld	c, a
	ld	b, #0
	push	hl
	add	hl, bc
	ld	bc, #SRCLIM+1
	or	a
	sbc	hl, bc
	pop	hl
	ld	a, #E_SYMFULL
	jp	nc, error
	push	de
	ex	de, hl			; DE = SYMEND
	ld	hl, #NAMBUF
	ld	a, (hl)
	inc	a
	ld	c, a
	ld	b, #0
	ldir
	pop	hl
	ex	de, hl
	ld	(hl), e
	inc	hl
	ld	(hl), d
	inc	hl
	ld	(SYMEND), hl
	ret

; The API, at fixed addresses in page 1 (main.s checks them), and the user RAM
BUILTIN::
	.db	8
	.ascii	"PRINTSTR"
	.dw	0x8010
	.db	7
	.ascii	"PUTCHAR"
	.dw	0x8013
	.db	6
	.ascii	"GETKEY"
	.dw	0x8016
	.db	7
	.ascii	"KEYPOLL"
	.dw	0x8019
	.db	3
	.ascii	"CLS"
	.dw	0x801C
	.db	6
	.ascii	"SETCUR"
	.dw	0x801F
	.db	6
	.ascii	"PRHEX8"
	.dw	0x8022
	.db	7
	.ascii	"PRHEX16"
	.dw	0x8025
	.db	5
	.ascii	"PRDEC"
	.dw	0x8028
	.db	4
	.ascii	"BEEP"
	.dw	0x802B
	.db	5
	.ascii	"DELAY"
	.dw	0x802E
	.db	4
	.ascii	"EXIT"
	.dw	0x8031
	.db	7
	.ascii	"NEWLINE"
	.dw	0x8034
	.db	7
	.ascii	"USERRAM"
	.dw	USRBEG
	.db	7
	.ascii	"USEREND"
	.dw	USREND
BUILTIN_END::
