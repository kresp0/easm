; disasm.s - EASM page 1: Z80 disassembler.
; Decodes an opcode as x = bits 7-6, y = bits 5-3 (p = y/2, q = y odd), z = bits 2-0, the scheme of
; the Zilog opcode tables. All official instructions; the undocumented ones that the CPU executes are
; shown too (SLL, IXH/IXL, IN F,(C), OUT (C),0, the DD CB d op register forms are shown as (IX+d)).
; A DD/FD prefix that changes nothing is shown as "DB DD"; an empty ED slot as "DB ED,nn".
; Numbers are hexadecimal with a "$" ($12, $D000), which the assembler reads in any mode.
; Copyright (C) 2026 Santiago Crespo
; SPDX-License-Identifier: 0BSD

	.include "shared.inc"
	.area	CODE

;disasm - the instruction at HL as text at DE (no terminator). Returns HL = the next instruction,
; DE = the end of the text. Destroys A,B,C,F.
disasm::
	ld	(DPTR), hl
	ld	(DSTART), hl
	push	de
	xor	a
	ld	(DPFX), a
	ld	(DSUB), a
	ld	(DCB), a
	ld	(DNOHX), a
	call	fetchop
	cp	#0xDD
	jr	z, 1$
	cp	#0xFD
	jr	nz, 3$
1$:	ld	(DPFX), a		; an index prefix
	call	fetchop
	cp	#0xDD
	jr	z, 9$
	cp	#0xFD
	jr	z, 9$
	cp	#0xED
	jr	z, 9$
	cp	#0xCB
	jr	nz, 4$
	call	fetch			; DD CB d op
	ld	(DDISP), a
	ld	a, #1
	ld	(DCB), a
	call	fetchop
	call	dcb
	jr	8$
3$:	cp	#0xED
	jr	nz, 5$
	call	fetchop
	call	ded
	jr	8$
5$:	cp	#0xCB
	jr	nz, 4$
	call	fetchop
	call	dcb
	jr	8$
4$:	call	dmain
8$:	ld	a, (DPFX)		; a prefix that substituted nothing
	or	a
	jr	z, 10$
	ld	a, (DSUB)
	or	a
	jr	nz, 10$
9$:	pop	de			; "DB DD": one byte
	push	de
	call	outi
	.ascii	"DB"
	.db	0x20+0x80
	ld	a, (DPFX)
	call	hex8
	ld	hl, (DSTART)
	inc	hl
	ld	(DPTR), hl
10$:	pop	af
	ld	hl, (DPTR)
	ret

; A = the next byte; fetchop also keeps it as the opcode in DOP
fetchop:
	call	fetch
	ld	(DOP), a
	ret
fetch:	push	hl
	ld	hl, (DPTR)
	ld	a, (hl)
	inc	hl
	ld	(DPTR), hl
	pop	hl
	ret

; Fields of the opcode in DOP: A = y, z, p; Z set if q = 0
gety:	ld	a, (DOP)
	rrca
	rrca
	rrca
	and	#7
	ret
getz:	ld	a, (DOP)
	and	#7
	ret
getp:	call	gety
	rrca
	and	#3
	ret
getq:	ld	a, (DOP)
	and	#8
	ret

;---------------------------------------------------------------- output

; The inline string after the call (last character with bit 7) to DE
outi:	ex	(sp), hl
	call	outs
	ex	(sp), hl
	ret
; The string at HL to DE; HL ends after it
outs:	ld	a, (hl)
	and	#0x7F
	ld	(de), a
	inc	de
	bit	7, (hl)
	inc	hl
	jr	z, outs
	ret
; String A of the table at HL
outtab:	or	a
	jr	z, outs
1$:	bit	7, (hl)
	inc	hl
	jr	z, 1$
	dec	a
	jr	outtab
outc:	ld	(de), a
	inc	de
	ret
comma:	ld	a, #',
	jr	outc
; A as "$" and two hex digits; hex16: HL as "$" and four
hex16:	ld	a, #'$
	call	outc
	ld	a, h
	call	hexd
	ld	a, l
	jr	hexd
hex8:	push	af
	ld	a, #'$
	call	outc
	pop	af
hexd:	push	af
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
	jr	outc
; Operands n (a byte) and nn (a word) from the code
outn:	call	fetch
	jr	hex8
outnn:	call	fetch
	push	af
	call	fetch
	ld	h, a
	pop	af
	ld	l, a
	jr	hex16
; "(nn)"
outmnn:	ld	a, #'(
	call	outc
	call	outnn
	ld	a, #')
	jr	outc
; Relative jump: the target address
outrel:	call	fetch
	ld	l, a
	rla
	sbc	a, a
	ld	h, a
	push	de
	ld	de, (DPTR)
	add	hl, de
	pop	de
	jr	hex16

; HL, or IX/IY with a prefix
outhl:	ld	a, (DPFX)
	or	a
	jr	nz, 1$
	call	outi
	.ascii	"H"
	.db	'L+0x80
	ret
1$:	ld	(DSUB), a
	ld	a, #'I
	call	outc
	ld	a, (DPFX)
	cp	#0xDD
	ld	a, #'X
	jr	z, outc
	ld	a, #'Y
	jr	outc

; Register A of r: B C D E H L (HL) A; (HL) is (IX+d) with a prefix, H and L are IXH/IXL there
; unless DNOHX is set
outr:	cp	#6
	jr	z, outm
	cp	#4
	jr	c, 1$
	cp	#6
	jr	nc, 1$
	ld	b, a			; H or L
	ld	a, (DPFX)
	or	a
	jr	z, 2$
	ld	a, (DNOHX)
	or	a
	jr	nz, 2$
	call	outhl
	ld	a, b
1$:	ld	hl, #RTAB
	jp	outtab
2$:	ld	a, b
	jr	1$
; (HL) or (IX+d)
outm:	ld	a, (DPFX)
	or	a
	jr	nz, 1$
	call	outi
	.ascii	"(HL"
	.db	')+0x80
	ret
1$:	ld	a, #'(
	call	outc
	call	outhl
	ld	a, (DCB)
	or	a
	ld	a, (DDISP)
	call	z, fetch
	ld	b, a
	ld	a, #'+
	bit	7, b
	jr	z, 2$
	ld	a, b
	neg
	ld	b, a
	ld	a, #'-
2$:	call	outc
	ld	a, b
	call	hex8
	ld	a, #')
	jr	outc0
outc0:	jp	outc

; Register pair A of rp (BC DE HL SP) or rp2 (BC DE HL AF)
outrp:	cp	#2
	jp	z, outhl
	ld	hl, #RPTAB
	jp	outtab
outrp2:	cp	#3
	jr	nz, outrp
	call	outi
	.ascii	"A"
	.db	'F+0x80
	ret

; Condition A
outcc:	ld	hl, #CCTAB
	jp	outtab

RTAB:	.db	'B+0x80, 'C+0x80, 'D+0x80, 'E+0x80, 'H+0x80, 'L+0x80, 0x80, 'A+0x80
RPTAB:	.ascii	"B"
	.db	'C+0x80
	.ascii	"D"
	.db	'E+0x80
	.ascii	"H"
	.db	'L+0x80
	.ascii	"S"
	.db	'P+0x80
CCTAB:	.ascii	"N"
	.db	'Z+0x80
	.db	'Z+0x80
	.ascii	"N"
	.db	'C+0x80
	.db	'C+0x80
	.ascii	"P"
	.db	'O+0x80
	.ascii	"P"
	.db	'E+0x80
	.db	'P+0x80
	.db	'M+0x80
ALUTAB:	.ascii	"ADD A"
	.db	',+0x80
	.ascii	"ADC A"
	.db	',+0x80
	.ascii	"SUB"
	.db	0x20+0x80
	.ascii	"SBC A"
	.db	',+0x80
	.ascii	"AND"
	.db	0x20+0x80
	.ascii	"XOR"
	.db	0x20+0x80
	.ascii	"OR"
	.db	0x20+0x80
	.ascii	"CP"
	.db	0x20+0x80
ROTTAB:	.ascii	"RL"
	.db	'C+0x80
	.ascii	"RR"
	.db	'C+0x80
	.ascii	"R"
	.db	'L+0x80
	.ascii	"R"
	.db	'R+0x80
	.ascii	"SL"
	.db	'A+0x80
	.ascii	"SR"
	.db	'A+0x80
	.ascii	"SL"
	.db	'L+0x80
	.ascii	"SR"
	.db	'L+0x80
X0Z7:	.ascii	"RLC"
	.db	'A+0x80
	.ascii	"RRC"
	.db	'A+0x80
	.ascii	"RL"
	.db	'A+0x80
	.ascii	"RR"
	.db	'A+0x80
	.ascii	"DA"
	.db	'A+0x80
	.ascii	"CP"
	.db	'L+0x80
	.ascii	"SC"
	.db	'F+0x80
	.ascii	"CC"
	.db	'F+0x80
EDZ7:	.ascii	"LD I,"
	.db	'A+0x80
	.ascii	"LD R,"
	.db	'A+0x80
	.ascii	"LD A,"
	.db	'I+0x80
	.ascii	"LD A,"
	.db	'R+0x80
	.ascii	"RR"
	.db	'D+0x80
	.ascii	"RL"
	.db	'D+0x80
	.ascii	"NO"
	.db	'P+0x80
	.ascii	"NO"
	.db	'P+0x80
BLKTAB:	.ascii	"LD"
	.db	'I+0x80
	.ascii	"CP"
	.db	'I+0x80
	.ascii	"IN"
	.db	'I+0x80
	.ascii	"OUT"
	.db	'I+0x80
	.ascii	"LD"
	.db	'D+0x80
	.ascii	"CP"
	.db	'D+0x80
	.ascii	"IN"
	.db	'D+0x80
	.ascii	"OUT"
	.db	'D+0x80
	.ascii	"LDI"
	.db	'R+0x80
	.ascii	"CPI"
	.db	'R+0x80
	.ascii	"INI"
	.db	'R+0x80
	.ascii	"OTI"
	.db	'R+0x80
	.ascii	"LDD"
	.db	'R+0x80
	.ascii	"CPD"
	.db	'R+0x80
	.ascii	"IND"
	.db	'R+0x80
	.ascii	"OTD"
	.db	'R+0x80

;---------------------------------------------------------------- unprefixed (and DD/FD) opcodes

dmain:	ld	a, (DOP)
	cp	#0x40
	jp	c, dx0
	cp	#0x80
	jp	c, dx1
	cp	#0xC0
	jp	nc, dx3
; x = 2: ALU A,r
	call	gety
	ld	hl, #ALUTAB
	call	outtab
	call	getz
	jp	outr

; x = 1: LD r,r' (76 is HALT); with (IX+d) the other register is plain H/L
dx1:	cp	#0x76
	jr	nz, 1$
	call	outi
	.ascii	"HAL"
	.db	'T+0x80
	ret
1$:	call	gety
	cp	#6
	jr	z, 2$
	call	getz
	cp	#6
	jr	nz, 3$
2$:	ld	a, #1
	ld	(DNOHX), a
3$:	call	outi
	.ascii	"LD"
	.db	0x20+0x80
	call	gety
	call	outr
	call	comma
	call	getz
	jp	outr

dx0:	call	getz
	or	a
	jr	nz, dx0z1
	call	gety			; z = 0: NOP, EX AF,AF', DJNZ, JR, JR cc
	or	a
	jr	nz, 1$
	call	outi
	.ascii	"NO"
	.db	'P+0x80
	ret
1$:	dec	a
	jr	nz, 2$
	call	outi
	.ascii	"EX AF,AF"
	.db	0x27+0x80
	ret
2$:	dec	a
	jr	nz, 3$
	call	outi
	.ascii	"DJNZ"
	.db	0x20+0x80
	jp	outrel
3$:	call	outi
	.ascii	"JR"
	.db	0x20+0x80
	call	gety
	sub	#4
	jp	c, outrel
	call	outcc
	call	comma
	jp	outrel

dx0z1:	dec	a
	jr	nz, dx0z2
	call	getq			; LD rp,nn / ADD HL,rp
	jr	nz, 1$
	call	outi
	.ascii	"LD"
	.db	0x20+0x80
	call	getp
	call	outrp
	call	comma
	jp	outnn
1$:	call	outi
	.ascii	"ADD"
	.db	0x20+0x80
	call	outhl
	call	comma
	call	getp
	jp	outrp

dx0z2:	dec	a
	jr	nz, dx0z3
	call	outi			; the indirect loads
	.ascii	"LD"
	.db	0x20+0x80
	call	getp
	ld	b, a
	call	getq
	jr	nz, 5$
	ld	a, b			; q = 0: stores
	cp	#2
	jr	c, 1$
	call	outmnn
	call	comma
	ld	a, b
	cp	#2
	jp	z, outhl
	ld	a, #'A
	jp	outc
1$:	call	outbcde
	call	comma
	ld	a, #'A
	jp	outc
5$:	ld	a, b			; q = 1: loads
	cp	#2
	jr	nz, 6$
	call	outhl
	call	comma
	jp	outmnn
6$:	ld	a, #'A
	call	outc
	call	comma
	ld	a, b
	cp	#3
	jp	z, outmnn
; "(BC)" or "(DE)" for p = 0 or 1 (in B)
outbcde:
	ld	a, #'(
	call	outc
	ld	a, b
	ld	hl, #RPTAB
	call	outtab
	ld	a, #')
	jp	outc

dx0z3:	dec	a
	jr	nz, dx0z4
	call	getq			; INC rp / DEC rp
	ld	hl, #incdec
	jr	z, 1$
	ld	hl, #incdec+4
1$:	call	outs
	call	getp
	jp	outrp
incdec:	.ascii	"INC"
	.db	0x20+0x80
	.ascii	"DEC"
	.db	0x20+0x80

dx0z4:	dec	a
	jr	nz, dx0z5
	ld	hl, #incdec		; INC r
	jr	dincr
dx0z5:	dec	a
	jr	nz, dx0z6
	ld	hl, #incdec+4		; DEC r
dincr:	call	outs
	call	gety
	jp	outr

dx0z6:	dec	a
	jr	nz, dx0z7
	call	outi			; LD r,n
	.ascii	"LD"
	.db	0x20+0x80
	call	gety
	call	outr
	call	comma
	jp	outn

dx0z7:	call	gety			; RLCA ... CCF
	ld	hl, #X0Z7
	jp	outtab

; x = 3
dx3:	call	getz
	or	a
	jr	nz, dx3z1
	call	outi			; RET cc
	.ascii	"RET"
	.db	0x20+0x80
	call	gety
	jp	outcc

dx3z1:	dec	a
	jr	nz, dx3z2
	call	getq
	jr	nz, 1$
	call	outi			; POP rp2
	.ascii	"POP"
	.db	0x20+0x80
	call	getp
	jp	outrp2
1$:	call	getp
	or	a
	jr	nz, 2$
	call	outi
	.ascii	"RE"
	.db	'T+0x80
	ret
2$:	dec	a
	jr	nz, 3$
	call	outi
	.ascii	"EX"
	.db	'X+0x80
	ret
3$:	dec	a
	jr	nz, 4$
	call	outi
	.ascii	"JP "
	.db	'(+0x80
	call	outhl
	ld	a, #')
	jp	outc
4$:	call	outi
	.ascii	"LD SP"
	.db	',+0x80
	jp	outhl

dx3z2:	dec	a
	jr	nz, dx3z3
	call	outi			; JP cc,nn
	.ascii	"JP"
	.db	0x20+0x80
	call	gety
	call	outcc
	call	comma
	jp	outnn

dx3z3:	dec	a
	jr	nz, dx3z4
	call	gety
	or	a
	jr	nz, 1$
	call	outi			; JP nn
	.ascii	"JP"
	.db	0x20+0x80
	jp	outnn
1$:	sub	#2			; (y = 1 is CB, decoded before)
	jr	nz, 2$
	call	outi
	.ascii	"OUT "
	.db	'(+0x80
	call	outn
	call	outi
	.ascii	"),"
	.db	'A+0x80
	ret
2$:	dec	a
	jr	nz, 3$
	call	outi
	.ascii	"IN A,"
	.db	'(+0x80
	call	outn
	ld	a, #')
	jp	outc
3$:	dec	a
	jr	nz, 4$
	call	outi
	.ascii	"EX (SP)"
	.db	',+0x80
	jp	outhl
4$:	dec	a
	jr	nz, 5$
	call	outi
	.ascii	"EX DE,H"
	.db	'L+0x80
	ret
5$:	dec	a
	jr	nz, 6$
	call	outi
	.ascii	"D"
	.db	'I+0x80
	ret
6$:	call	outi
	.ascii	"E"
	.db	'I+0x80
	ret

dx3z4:	dec	a
	jr	nz, dx3z5
	call	outi			; CALL cc,nn
	.ascii	"CALL"
	.db	0x20+0x80
	call	gety
	call	outcc
	call	comma
	jp	outnn

dx3z5:	dec	a
	jr	nz, dx3z6
	call	getq
	jr	nz, 1$
	call	outi			; PUSH rp2
	.ascii	"PUSH"
	.db	0x20+0x80
	call	getp
	jp	outrp2
1$:	call	outi			; CALL nn (the other q = 1 opcodes are prefixes)
	.ascii	"CALL"
	.db	0x20+0x80
	jp	outnn

dx3z6:	dec	a
	jr	nz, dx3z7
	call	gety			; ALU A,n
	ld	hl, #ALUTAB
	call	outtab
	jp	outn

dx3z7:	call	outi			; RST y*8
	.ascii	"RST"
	.db	0x20+0x80
	ld	a, (DOP)
	and	#0x38
	jp	hex8

;---------------------------------------------------------------- CB and ED

dcb:	ld	a, (DOP)
	cp	#0x40
	jr	nc, 1$
	call	gety			; rotations and shifts
	ld	hl, #ROTTAB
	call	outtab
	ld	a, #0x20
	call	outc
	jr	3$
1$:	rlca				; BIT, RES, SET y,r
	rlca
	and	#3
	dec	a
	ld	hl, #BRS
	call	outtab
	call	gety
	add	a, #'0
	call	outc
	call	comma
3$:	ld	a, (DCB)		; DD CB d op: always (IX+d)
	or	a
	ld	a, #6
	jp	nz, outr
	call	getz
	jp	outr
BRS:	.ascii	"BIT"
	.db	0x20+0x80
	.ascii	"RES"
	.db	0x20+0x80
	.ascii	"SET"
	.db	0x20+0x80

ded:	ld	a, (DOP)
	cp	#0x40
	jr	c, 1$
	cp	#0x80
	jr	c, ded1
	cp	#0xC0
	jr	nc, 1$
	call	getz			; x = 2: the block instructions (z <= 3, y >= 4)
	cp	#4
	jr	nc, 1$
	ld	b, a
	call	gety
	sub	#4
	jr	c, 1$
	add	a, a
	add	a, a
	add	a, b
	ld	hl, #BLKTAB
	jp	outtab
1$:	call	outi			; empty slot: "DB ED,nn"
	.ascii	"DB ED"
	.db	',+0x80
	ld	a, (DOP)
	jp	hex8

ded1:	call	getz
	or	a
	jr	nz, 2$
	call	outi			; IN r,(C)
	.ascii	"IN"
	.db	0x20+0x80
	call	gety
	cp	#6
	jr	nz, 1$
	ld	a, #'F
	call	outc
	jr	3$
1$:	call	outr
3$:	call	outi
	.ascii	",(C"
	.db	')+0x80
	ret
2$:	dec	a
	jr	nz, 5$
	call	outi			; OUT (C),r
	.ascii	"OUT (C)"
	.db	',+0x80
	call	gety
	cp	#6
	jp	nz, outr
	ld	a, #'0
	jp	outc
5$:	dec	a
	jr	nz, 7$
	call	getq			; SBC HL,rp / ADC HL,rp
	ld	hl, #sbcadc
	jr	z, 6$
	ld	hl, #sbcadc+7
6$:	call	outs
	call	getp
	jp	outrp
7$:	dec	a
	jr	nz, 9$
	call	outi			; LD (nn),rp / LD rp,(nn)
	.ascii	"LD"
	.db	0x20+0x80
	call	getq
	jr	nz, 8$
	call	outmnn
	call	comma
	call	getp
	jp	outrp
8$:	call	getp
	call	outrp
	call	comma
	jp	outmnn
9$:	dec	a
	jr	nz, 10$
	call	outi
	.ascii	"NE"
	.db	'G+0x80
	ret
10$:	dec	a
	jr	nz, 12$
	call	gety
	cp	#1
	jr	nz, 11$
	call	outi
	.ascii	"RET"
	.db	'I+0x80
	ret
11$:	call	outi
	.ascii	"RET"
	.db	'N+0x80
	ret
12$:	dec	a
	jr	nz, 13$
	call	outi			; IM 0/1/2
	.ascii	"IM"
	.db	0x20+0x80
	call	gety
	ld	hl, #imtab
	add	a, l
	ld	l, a
	jr	nc, 14$
	inc	h
14$:	ld	a, (hl)
	jp	outc
13$:	call	gety
	ld	hl, #EDZ7
	jp	outtab

sbcadc:	.ascii	"SBC HL"
	.db	',+0x80
	.ascii	"ADC HL"
	.db	',+0x80
imtab:	.ascii	"00120012"
