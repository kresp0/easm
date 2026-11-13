; io.s - EASM page 1: the 4x20 LCD (shadow screen, console with scrolling), the keyboard matrix
; (Spanish layout, activity panel, auto-repeat, OFF key), the speaker and the caps-lock LED.
; Taken from EBASIC's genio1.s and genio2.s (same author and licence) with the graphics window removed,
; and with interrupts held off around each keyboard column so that the break check of the interrupt
; hook can share port 0x10.
; Copyright (C) 2026 Santiago Crespo
; SPDX-License-Identifier: 0BSD

	.include "shared.inc"
	.area	CODE

; Glyphs of A I O U with acute accent for CGRAM 0-3 (design 0 of vgldk-genio's cgram_accents.h)
ACCGLY:	.db	0x01,0x02,0x0E,0x11,0x1F,0x11,0x11,0x00
	.db	0x01,0x02,0x0E,0x04,0x04,0x04,0x0E,0x00
	.db	0x01,0x02,0x0E,0x11,0x11,0x11,0x0E,0x00
	.db	0x01,0x02,0x11,0x11,0x11,0x11,0x0E,0x00

; DDRAM set-address command for the three column groups (0-3, 4-11, 12-19) of each row; the cell's
; column is added. Same map as the firmware table B0:07EE, which puts row 1, column 0 at A8.
ROWADR:	.db	0x80,0x84,0x8C, 0xC0,0xC4,0xCC, 0x84,0x8C,0x94, 0xC4,0xCC,0xD4

; Text is code page 850 (the firmware's own internal codes); these are drawn at another LCD code
LCDTAB:	.db	0xA4,0x9B, 0xA5,0x9C, 0xAD,0xA9, 0xA8,0x9F, 0xA7,0x9E	; n~ N~ inverted ! ? ordinal
	.db	0xB5,0, 0xD6,1, 0xE0,2, 0xE9,3, 0			; A I O U acute: CGRAM

;---------------------------------------------------------------- LCD

; HD44780 set-up: 8-bit, display on, about 2.5 ms per command
lcdinit::
	ld	hl, #lcdini
	ld	b, #lcdini_end-lcdini
1$:	ld	a, (hl)
	out	(0x0A), a
	ld	de, #600
2$:	dec	de
	ld	a, d
	or	e
	jr	nz, 2$
	inc	hl
	djnz	1$
	ret
lcdini:	.db	0x38, 0x38, 0x38, 0x38, 0x01, 0x02, 0x0C, 0x06
lcdini_end:

; ~70 us, more than the 37 us an HD44780 write needs (the busy flag is not read)
lcd_delay:
	push	bc
	ld	b, #32
1$:	djnz	1$
	pop	bc
	ret

; A = DDRAM set-address command of cell E (0-79). Destroys B,H,L,F.
ddaddr:	ld	a, e
	ld	hl, #ROWADR
1$:	cp	#20
	jr	c, 2$
	sub	#20
	inc	hl
	inc	hl
	inc	hl
	jr	1$
2$:	ld	b, a
	cp	#4
	jr	c, 3$
	inc	hl
	cp	#12
	jr	c, 3$
	inc	hl
3$:	add	a, (hl)
	cp	#0xC0
	ret	nz
	ld	a, #0xA8
	ret

; Write character A to cell E (0-79) and to the shadow screen. Destroys A,B,C,H,L,F.
putcell::
	push	de
	ld	d, #0
	ld	hl, #SCR
	add	hl, de
	pop	de
	ld	(hl), a
	ld	hl, #LCDTAB
	call	look
	ld	c, a
	call	ddaddr
	ld	b, a
	ld	a, i			; P/V = IFF2
	di
	push	af
	ld	a, b
	out	(0x0A), a
	call	lcd_delay
	ld	a, c
	out	(0x0B), a
	call	lcd_delay
	pop	af
	ret	po
	ei
	ret

; Rewrite the LCD from the shadow screen. Destroys A,B,C,H,L,F.
redraw::
	push	de
	ld	e, #0
1$:	ld	hl, #SCR
	ld	d, #0
	add	hl, de
	ld	a, (hl)
	call	putcell
	inc	e
	ld	a, e
	cp	#80
	jr	c, 1$
	pop	de
	ret

; Save the console / put it back (viewers and the guide draw over it). Destroy B,C,D,E,H,L.
savescr::
	ld	hl, (CX)		; and CY
	ld	(SAVCXY), hl
	ld	hl, #SCR
	ld	de, #SCRSAVE
	ld	bc, #80
	ldir
	ret
restscr::
	ld	hl, (SAVCXY)
	ld	(CX), hl
	ld	hl, #SCRSAVE
	ld	de, #SCR
	ld	bc, #80
	ldir
	jp	redraw

; The accented capitals into CGRAM 0-3. Interrupts stay off: the firmware's interrupt routine moves
; the LCD address to its cursor. Destroys A,B,H,L,F.
accents::
	ld	hl, #ACCGLY
	ld	b, #32
	ld	a, i
	di
	push	af
	ld	a, #0x40
	out	(0x0A), a
	call	lcd_delay
1$:	ld	a, (hl)
	out	(0x0B), a
	call	lcd_delay
	inc	hl
	djnz	1$
	pop	af
	ret	po
	ei
	ret

;CLS - clear the console. Destroys A,F.
CLS::	push	bc
	push	de
	push	hl
	ld	hl, #SCR
	ld	b, #80
1$:	ld	(hl), #0x20
	inc	hl
	djnz	1$
	call	redraw
	xor	a
	ld	(CX), a
	ld	(CY), a
	pop	hl
	pop	de
	pop	bc
	ret

;SETCUR - D = row (0-3), E = column (0-19). Destroys A,F.
SETCUR::
	ld	a, e
	cp	#20
	jr	c, 1$
	ld	a, #19
1$:	ld	(CX), a
	ld	a, d
	cp	#4
	jr	c, 2$
	ld	a, #3
2$:	ld	(CY), a
	ret

; E = cell of the cursor (column 20 shows on column 19). Destroys A,F.
curcell::
	ld	a, (CY)
	ld	e, a
	add	a, a
	add	a, a
	add	a, e			; 5*row
	add	a, a
	add	a, a			; 20*row
	ld	e, a
	ld	a, (CX)
	cp	#20
	jr	c, 1$
	dec	a
1$:	add	a, e
	ld	e, a
	ret

; Underline cursor at CX,CY, drawn by the firmware ISR's LCD service (none without the ISR). Destroys A,F.
showcur::
	ld	a, (CURSOFF)
	or	a
	ret	nz
	ld	a, (CX)
	cp	#20
	jr	c, 1$
	dec	a
1$:	ld	(FW_DIRTY+4), a
	ld	a, (CY)
	ld	(FW_DIRTY+5), a
	ld	a, #1
	jr	setcur
hidecur::
	xor	a
setcur:	ld	(FW_DIRTY+7), a
	ret

;PUTCHAR - write character A to the console: printing characters, CR, LF, BS, 12 (clear), 7 (beep).
; Destroys nothing.
PUTCHAR::
	push	af
	push	bc
	push	de
	push	hl
	call	wrch
	pop	hl
	pop	de
	pop	bc
	pop	af
	ret

wrch:	cp	#0x20
	jr	c, wctrl
	cp	#0x7F
	ret	z
	push	af
	ld	a, (CX)
	cp	#20
	call	nc, newline		; deferred wrap: the line breaks on the next character
	call	curcell
	pop	af
	call	putcell
	ld	hl, #CX
	inc	(hl)
	ret

wctrl:	cp	#CR
	jr	z, wcr
	cp	#LF
	jr	z, wlf
	cp	#BS
	jr	z, wbs
	cp	#12
	jp	z, CLS
	cp	#7
	jp	z, BEEP
	ret

newline::
	xor	a
	ld	(CX), a
wlf:	ld	a, (CY)
	cp	#3
	jr	z, scroll
	inc	a
	ld	(CY), a
	ret

wcr:	xor	a
	ld	(CX), a
	ret

wbs:	ld	hl, #CX
	ld	a, (hl)
	cp	#20			; past column 19 (deferred wrap): back onto column 19
	jr	nc, 3$
	or	a
	jr	z, 1$
	dec	(hl)
	ret
1$:	ld	a, (CY)
	or	a
	ret	z
	dec	a
	ld	(CY), a
3$:	ld	(hl), #19
	ret

scroll:	ld	hl, #SCR+20
	ld	de, #SCR
	ld	bc, #60
	ldir
	ex	de, hl			; HL = start of the last row
	ld	b, #20
1$:	ld	(hl), #0x20
	inc	hl
	djnz	1$
	jp	redraw

;NEWLINE - CR LF on the console unless the cursor is already at the start of a line. Destroys nothing.
NEWLINE::
	push	af
	ld	a, (CX)
	or	a
	jr	z, 1$
	ld	a, #CR
	call	PUTCHAR
	ld	a, #LF
	call	PUTCHAR
1$:	pop	af
	ret

;PRINTSTR - print the string at HL, ending in 0. HL ends after the 0. Destroys A,F.
PRINTSTR::
	ld	a, (hl)
	inc	hl
	or	a
	ret	z
	call	PUTCHAR
	jr	PRINTSTR

;PRHEX16 - HL as four hex digits. PRHEX8 - A as two. Destroy A,F.
PRHEX16::
	ld	a, h
	call	PRHEX8
	ld	a, l
PRHEX8::
	push	af
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
	jp	PUTCHAR

;PRDEC - HL as an unsigned decimal number. Destroys A,F.
PRDEC::	push	bc
	push	de
	push	hl
	ld	b, #0			; digits printed
	ld	de, #-10000
	call	1$
	ld	de, #-1000
	call	1$
	ld	de, #-100
	call	1$
	ld	de, #-10
	call	1$
	ld	a, l
	add	a, #0x30
	call	PUTCHAR
	pop	hl
	pop	de
	pop	bc
	ret
1$:	ld	a, #0x2F
2$:	inc	a
	add	hl, de
	jr	c, 2$
	sbc	hl, de
	cp	#0x30
	jr	nz, 3$
	inc	b
	dec	b
	ret	z			; no leading zeros
3$:	inc	b
	jp	PUTCHAR

;BEEP - about 1 kHz for 0.1 s on the speaker (port 0x12 bit 3), interrupts off. Destroys nothing.
BEEP::	push	af
	push	bc
	push	de
	ld	a, i
	di
	push	af
	ld	de, #200
1$:	ld	a, (P12)
	xor	#0x08
	ld	(P12), a
	out	(0x12), a
	ld	b, #234
2$:	djnz	2$
	dec	de
	ld	a, d
	or	e
	jr	nz, 1$
	call	setled
	pop	af
	jp	po, 3$
	ei
3$:	pop	de
	pop	bc
	pop	af
	ret

; Caps-lock LED (port 0x12 bit 5); bit 0 (power off) is never set here
setled::
	ld	a, (CAPS)
	rrca
	rrca
	rrca
	and	#0x20
	ld	(P12), a
	out	(0x12), a
	ret

;DELAY - wait about HL milliseconds (busy loop at 6.13 MHz; interrupts make it a little longer).
; Destroys A,F,H,L.
DELAY::	ld	a, h
	or	l
	ret	z
	push	bc
	ld	bc, #236
1$:	dec	bc			; 6 T
	ld	a, b			; 4
	or	c			; 4
	jr	nz, 1$			; 12: 26 T per turn, 236 turns = 6136 T = 1.0 ms
	pop	bc
	dec	hl
	jr	DELAY

;---------------------------------------------------------------- keyboard

; Scan the keyboard (matrix 1, then the activity panel). Returns D = first non-modifier scancode
; (bit*8+column, or 64+ for the panel) or FF, E bit 0 = SHIFT, bit 1 = ALT. Destroys A,B,C,D,E,H,L,F.
kscan::	ld	bc, #0x0100		; B = column mask, C = column
	ld	de, #0xFF00
1$:	ld	a, i			; the interrupt hook also drives port 0x10
	di
	push	af
	ld	a, b
	out	(0x10), a
	nop
	in	a, (0x10)
	cpl
	ld	l, a
	in	a, (0x11)		; activity panel: rows 8-12 on port 0x11
	cpl
	ld	h, a
	xor	a
	out	(0x10), a
	pop	af
	jp	po, 9$
	ei
9$:	ld	a, c
	cp	#1
	jr	nz, 2$
	bit	5, l			; ALT
	res	5, l
	jr	z, 3$
	set	1, e
	jr	3$
2$:	cp	#6
	jr	nz, 3$
	bit	6, l			; SHIFT
	res	6, l
	jr	z, 3$
	set	0, e
3$:	ld	a, d
	inc	a
	jr	nz, 5$			; already found one
	ld	a, l
	or	a
	jr	z, 6$
	ld	d, c
4$:	rrca
	jr	c, 5$
	ld	l, a
	ld	a, d
	add	a, #8
	ld	d, a
	ld	a, l
	jr	4$
6$:	ld	a, h			; activity panel (not OFF, column 7 row 9)
	and	#0x1F
	ld	h, a
	ld	a, c
	cp	#7
	ld	a, h
	jr	nz, 7$
	and	#0x1C
7$:	or	a
	jr	z, 5$
	ld	h, a
	ld	a, c			; D = 64 + column*5 + row
	add	a, a
	add	a, a
	add	a, c
	add	a, #64
	ld	d, a
8$:	srl	h
	jr	c, 5$
	inc	d
	jr	8$
5$:	sla	b
	inc	c
	bit	3, c
	jr	z, 1$
	ret

; OFF key: column mask 0x80, port 0x11 bit 1 low (the routine verified on the unit). Z = pressed.
offscan:
	ld	a, i
	di
	push	af
	ld	a, #0x80
	out	(0x10), a
	nop
	in	a, (0x11)
	and	#0x02
	ld	b, a
	xor	a
	out	(0x10), a
	pop	af
	jp	po, 1$
	ei
1$:	ld	a, b
	or	a
	ret

; Power off when OFF is pressed (held ~20 ms against bounce); ignored until seen released once.
offpoll:
	call	offscan
	jr	z, 1$
	ld	a, #1
	ld	(OFFARM), a
	ret
1$:	ld	a, (OFFARM)
	or	a
	ret	z
	ld	de, #0x0300
2$:	call	offscan
	ret	nz
	dec	de
	ld	a, d
	or	e
	jr	nz, 2$
	di
	ld	a, #0x01
	out	(0x12), a
3$:	halt				; the firmware's own power-off sequence
	jr	3$

;KEYPOLL - one keyboard poll with auto-repeat. Returns A = key code or 0. Destroys A,F.
KEYPOLL::
	push	bc
	push	de
	push	hl
	call	kpoll
	pop	hl
	pop	de
	pop	bc
	or	a
	ret

kpoll:	call	offpoll
	call	kscan
	ld	hl, #RELCNT		; a release counts after two empty scans (contact bounce)
	ld	a, d
	inc	a
	jr	z, 7$
	ld	(hl), #0
	jr	8$
7$:	inc	(hl)
	ld	a, (hl)
	cp	#2
	ld	a, #0
	ret	c
8$:	ld	hl, #LASTSC
	ld	a, d
	cp	(hl)
	ld	(hl), a
	inc	hl			; REPCNT
	jr	z, 1$
	ld	(hl), #50		; first repeat after ~0.5 s of polls
	jr	2$
1$:	inc	a
	ret	z			; no key
	dec	(hl)
	ld	a, #0
	ret	nz
	ld	(hl), #8
2$:	ld	a, d
	inc	a
	ret	z
	ld	a, d			; activity key: codes 192-213, 240-255 in panel order
	sub	#64
	jr	c, 10$
	cp	#35
	jr	c, 11$
	sub	#2
11$:	cp	#22
	jr	c, 12$
	add	a, #0x1A
12$:	add	a, #0xC0
	ret
10$:	ld	hl, #KTAB
	ld	c, d
	ld	b, #0
	add	hl, bc
	ld	a, (hl)
	or	a
	ret	z
	cp	#1			; caps lock
	jr	nz, 3$
	ld	hl, #CAPS
	xor	(hl)
	ld	(hl), a
	call	setled
	xor	a
	ld	(REPCNT), a		; no repeat for caps lock (next one after 256 polls)
	ret
3$:	ld	c, a
	ld	a, (CAPS)
	xor	e
	and	#1
	ld	d, a			; D = 1 for upper case (SHIFT xor caps lock)
	ld	a, c
	bit	1, e
	jr	z, 4$
	ld	hl, #ACCLO		; ALT+vowel: accented, ALT+digit: the red legend
	dec	d
	jr	nz, 9$
	ld	hl, #ACCUP
9$:	call	look
	ret	c
	ld	hl, #ALTTAB
	jr	look
4$:	sub	#'a
	cp	#26
	ld	a, c
	jr	nc, 5$
	dec	d
	ret	nz
	sub	#0x20
	ret
5$:	dec	d
	jr	nz, 6$
	ld	hl, #CASETAB
	call	look
	ret	c
6$:	bit	0, e
	ret	z
	ld	hl, #SHFTAB
; Pairs (from, to) ending in 0 at HL: A = the pair's "to" and carry if A is found, else A unchanged. Destroys C,H,L,F.
look::	ld	c, a
1$:	ld	a, (hl)
	or	a
	ld	a, c
	ret	z
	cp	(hl)
	inc	hl
	jr	nz, 2$
	ld	a, (hl)
	scf
	ret
2$:	inc	hl
	jr	1$

; Scancode (bit*8+column) -> code. 0 = ignored, 1 = caps lock. Matrix as mapped on the unit.
KTAB:	.db	HELP, 1,    '2,   '4,   '6,   '8,   '0,   0	; AYUDA (SHIFT: TAB)
	.db	0x5E, '1,   '3,   '5,   '7,   '9,   BS,   0	; PAUSA, BORRAR
	.db	0,    'q,   'e,   't,   'u,   'o,   0x81, LEFT	; u-diaeresis
	.db	0,    'a,   's,   'f,   'h,   'k,   0xA4, RIGHT	; n-tilde
	.db	0,    'z,   'd,   'g,   'j,   'l,   0x3B, CR	; INTRO
	.db	0,    0,    'x,   'v,   'n,   0x2C, 0x27, DEL	; JUGADOR DERECHA/DEL
	.db	0,    0x20, 'c,   'b,   'm,   0x2E, 0,    ESC	; RESPUESTA
	.db	0,    0,    'w,   'r,   'y,   'i,   'p,   0

; Pairs (from, to) for SHIFT, upper case, ALT; code page 850
SHFTAB:	.db	'1,0xAD, '2,0xA8, '3,0x23, '4,0x24, '5,0x25, '6,0x2F, '7,0x26, '8,0x2A, '9,0x28, '0,0x29
	.db	0x2C,0x3F, 0x2E,0x21, 0x27,0x22, 0x3B,0x3A, LEFT,0x3C, RIGHT,0x3E, HELP,TAB, 0
CASETAB:	.db	0xA4,0xA5, 0x81,0x9A, 0
ACCLO:	.db	'a,0xA0, 'e,0x82, 'i,0xA1, 'o,0xA2, 'u,0xA3, 0
ACCUP:	.db	'a,0xB5, 'e,0x90, 'i,0xD6, 'o,0xE0, 'u,0xE9, 0
ALTTAB:	.db	'1,0x5C, '2,0x40, '3,0x2D, '4,0x5F, '5,0x2B, '6,0x5B, '7,0x5D, '8,0x3D, '9,0x7C, '0,0x7E, 0x81,UP, 0x3B,DOWN, LEFT,HOME, RIGHT,END, 0

; ~10 ms between keyboard polls
pause::	push	bc
	ld	bc, #2300
1$:	dec	bc
	ld	a, b
	or	c
	jr	nz, 1$
	pop	bc
	ret

;GETKEY - wait for a key, with the cursor shown at CX,CY. Returns A. Destroys F.
GETKEY::
	call	showcur
1$:	call	KEYPOLL
	jr	nz, 2$
	call	pause
	jr	1$
2$:	push	af
	call	hidecur
	pop	af
	ret

; Wait until no key is held (after a break with ANSWER). Destroys A,B,C,D,E,H,L,F.
waitrel::
	call	pause
	call	kscan
	ld	a, d
	inc	a
	jr	nz, waitrel
	ld	(LASTSC), a		; 0: no repeat state
	ret
