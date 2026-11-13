; help.s - EASM page 2: the guide behind the HELP key. An index of entries (the topics first, then
; every mnemonic and directive); ENTER opens one, and on its page ENTER takes its example (the
; editor inserts it as a line, the command line types it). Adapted from EBASIC's help.s.
; The text comes from help.txt through gen_help.py (out/helpdata.s).
; Copyright (C) 2026 Santiago Crespo
; SPDX-License-Identifier: 0BSD

	.include "shared.inc"
	.area	P2

.macro	SLOT	target, n
	.ifne	.-P2TAB-3*n
	.error	1
	.endif
	jp	target
.endm
P2TAB:	SLOT	help, S_HELP

;help - A = 0 from the editor, 1 from the command line. The entry of the word at the cursor in LBUF,
; or the index. Returns carry if an example was taken: it is in WBUF, ending in 0.
help:	ld	(HCTX), a
	ld	a, #1
	ld	(CURSOFF), a
	call	hctx
	jr	c, 2$
1$:	call	hindex
	jr	nc, 3$
2$:	ld	(HSEL), a
	call	hpage
	jr	z, 1$
	jr	nc, 3$
	scf
3$:	push	af
	xor	a
	ld	(CURSOFF), a
	pop	af
	ret

; The index: A = the chosen entry and carry, or no carry to leave
hindex:	call	hdrawidx
	call	hkey
	ld	hl, #HSEL
	cp	#UP
	jr	nz, 1$
	ld	a, (hl)
	or	a
	jr	z, hindex
	dec	(hl)
	ld	a, (HTOP)
	cp	(hl)
	jr	c, hindex
	jr	z, hindex
	ld	a, (hl)
	ld	(HTOP), a
	jr	hindex
1$:	cp	#DOWN
	jr	nz, 2$
	ld	a, (HCOUNT)
	dec	a
	cp	(hl)
	jr	z, hindex
	inc	(hl)
	ld	a, (HTOP)
	add	a, #3
	cp	(hl)
	jr	nc, hindex
	ld	a, (hl)
	sub	#3
	ld	(HTOP), a
	jr	hindex
2$:	cp	#CR
	jr	nz, 3$
	ld	a, (hl)
	scf
	ret
3$:	cp	#ESC
	jr	z, hquit
	cp	#HELP
	jr	z, hquit
	call	hletter
	jr	hindex
hquit:	or	a
	ret

; A letter: select the first mnemonic from it on (NC if A is not a letter)
hletter:
	and	#0xDF
	cp	#0x41
	ccf
	ret	nc
	cp	#0x5B
	ret	nc
	ld	c, a
	ld	a, (HKW)
	ld	b, a
4$:	ld	a, (HCOUNT)
	dec	a
	cp	b
	jr	z, 5$
	ld	a, b
	call	htitle
	ld	a, (hl)
	cp	c
	jr	nc, 5$
	inc	b
	jr	4$
5$:	ld	a, b
	ld	(HSEL), a
	ld	(HTOP), a
	scf
	ret

; A key: U-diaeresis, LEFT, ALT+U-diaeresis are up; ";", RIGHT, ALT+; are down
hkey:	call	GETKEY
	cp	#0x81
	jr	z, 1$
	cp	#0x9A
	jr	z, 1$
	cp	#LEFT
	jr	z, 1$
	cp	#0x3B
	jr	z, 2$
	cp	#RIGHT
	ret	nz
2$:	ld	a, #DOWN
	ret
1$:	ld	a, #UP
	ret

; Draw four titles from HTOP, ">" on the selected one
hdrawidx:
	ld	a, (HTOP)
	ld	c, a
	ld	e, #0
1$:	ld	a, (HSEL)
	cp	c
	ld	a, #0x20
	jr	nz, 2$
	ld	a, #0x3E
2$:	push	bc
	call	putcell
	pop	bc
	inc	e
	ld	hl, #0			; HL = 0: no title (past the last entry)
	ld	a, (HCOUNT)
	cp	c
	jr	z, 3$
	jr	c, 3$
	ld	a, c
	push	de
	call	htitle
	pop	de
3$:	ld	b, #19
4$:	ld	a, h
	or	l
	jr	z, 5$
	ld	a, (hl)
	inc	hl
	or	a
	jr	nz, 6$
	ld	hl, #0
5$:	ld	a, #0x20
6$:	push	hl
	push	bc
	call	putcell
	pop	bc
	pop	hl
	inc	e
	djnz	4$
	inc	c
	ld	a, e
	cp	#80
	jr	c, 1$
	ret

; HL = title of entry A
htitle:	add	a, a
	ld	e, a
	ld	d, #0
	ld	hl, #HIDX
	add	hl, de
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	ret

; The page of entry HSEL: Z to go back to the index; NZ to leave, with carry if the example was taken
hpage:	call	hexpand
	call	hwrap
	xor	a
	ld	(HLINE), a
1$:	call	hdrawpg
	call	hkey
	ld	hl, #HLINE
	cp	#UP
	jr	nz, 2$
	ld	a, (hl)
	or	a
	jr	z, 1$
	dec	(hl)
	jr	1$
2$:	cp	#DOWN
	jr	nz, 3$
	ld	a, (hl)
	add	a, #4
	ld	b, a
	ld	a, (HNL)
	cp	b
	jr	z, 1$
	jr	c, 1$
	inc	(hl)
	jr	1$
3$:	cp	#ESC
	jr	nz, 4$
	xor	a			; Z: the index
	ret
4$:	cp	#HELP
	jr	nz, 5$
	or	a			; NZ, NC: leave
	ret
5$:	cp	#CR
	jr	z, 6$
	call	hletter			; a letter: the index, from that letter
	jr	nc, 1$
	xor	a
	ret
6$:	ld	hl, (HEX)		; ENTER: the example to WBUF
	ld	a, h
	or	l
	jr	z, 1$
	ld	de, #WBUF
	call	hdec
	xor	a
	ld	(de), a
	inc	a			; NZ
	scf
	ret

; WBUF = title, LF, body, and "LF e.g. example" if there is one
hexpand:
	ld	a, (HSEL)
	call	htitle
	ld	de, #WBUF
1$:	ld	a, (hl)			; title
	inc	hl
	or	a
	jr	z, 2$
	ld	(de), a
	inc	e
	jr	1$
2$:	ld	a, #LF
	ld	(de), a
	inc	e
	call	hdec			; body
	ld	(HEX), hl
	ld	a, (hl)
	or	a
	jr	nz, 3$
	ld	hl, #0			; no example
	ld	(HEX), hl
	jr	4$
3$:	push	hl
	ld	hl, #egtxt
	ld	b, #6
5$:	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	e
	djnz	5$
	pop	hl
	call	hdec			; example
4$:	ld	a, e
	ld	(HLEN), a
	ret

; Expand the text at HL (ending in 0) to DE: bytes 0x80-0xFF are dictionary pieces, 1 escapes the next
; byte. HL ends after the 0.
hdec:	ld	a, (hl)
	inc	hl
	or	a
	ret	z
	bit	7, a
	jr	nz, 2$
	dec	a
	jr	nz, 1$
	ld	a, (hl)			; escaped
	inc	hl
	.db	0xFE			; (cp #n: skips the inc a)
1$:	inc	a
	ld	(de), a
	inc	e
	jr	hdec
2$:	push	hl
	and	#0x7F
	ld	b, a
	ld	hl, #HDICT
	inc	b
	jr	4$
3$:	ld	a, (hl)
	inc	a
	add	a, l
	ld	l, a
	jr	nc, 4$
	inc	h
4$:	djnz	3$
	ld	b, (hl)
5$:	inc	hl
	ld	a, (hl)
	ld	(de), a
	inc	e
	djnz	5$
	pop	hl
	jr	hdec

egtxt:	.db	LF
	.ascii	"e.g. "

; Lines of at most 20 characters, broken after a space where possible (gen_help.py does the same)
hwrap:	ld	hl, #HLINES
	ld	c, #0			; position
	ld	b, #0			; lines
1$:	ld	a, (HLEN)
	cp	c
	jr	z, 9$
	ld	(hl), c			; start
	inc	hl
	push	hl
	ld	d, #0xFF		; last space seen
	ld	e, #0			; k
2$:	ld	a, c
	add	a, e
	ld	l, a
	ld	a, (HLEN)
	cp	l
	jr	z, 5$			; end of the text: the line ends there
	ld	h, #>WBUF
	ld	a, (hl)
	cp	#LF
	jr	z, 6$
	cp	#0x20
	jr	nz, 3$
	ld	d, l
3$:	inc	e
	ld	a, e
	cp	#20
	jr	c, 2$
	ld	a, c			; 20 fit: does a space or the end follow?
	add	a, #20
	ld	l, a
	ld	a, (HLEN)
	cp	l
	jr	z, 5$
	ld	a, (hl)
	cp	#0x20
	jr	z, 7$
	cp	#LF
	jr	z, 6$
	ld	a, d			; break at the last space, or hard at 20
	inc	a
	ld	a, l
	jr	z, 5$
	ld	l, d
	jr	7$
5$:	pop	hl			; end = L, next = L
	ld	(hl), a
	ld	c, a
	jr	8$
6$:	ld	a, l			; LF at L: end = L, next = L+1
	pop	hl
	ld	(hl), a
	inc	a
	ld	c, a
	jr	8$
7$:	ld	a, l			; space at L: end = L, next = L+1
	pop	hl
	ld	(hl), a
	inc	a
	ld	c, a
8$:	inc	hl
	inc	b
	jr	1$
9$:	ld	a, b
	ld	(HNL), a
	ret

; Four lines from HLINE
hdrawpg:
	ld	e, #0
	ld	a, (HLINE)
	ld	c, a
1$:	ld	a, (HNL)
	cp	c
	ld	b, #0			; empty row
	jr	z, 2$
	jr	c, 2$
	ld	a, c
	add	a, a
	ld	l, a
	ld	h, #0
	push	de
	ld	de, #HLINES
	add	hl, de
	pop	de
	ld	a, (hl)			; start
	inc	hl
	ld	b, (hl)			; end
	ld	l, a
	ld	a, b
	sub	l
	ld	b, a			; length
	ld	h, #>WBUF
2$:	ld	d, #20
3$:	ld	a, b
	or	a
	ld	a, #0x20
	jr	z, 4$
	ld	a, (hl)
	inc	hl
	dec	b
4$:	push	hl
	push	bc
	call	putcell
	pop	bc
	pop	hl
	inc	e
	dec	d
	jr	nz, 3$
	inc	c
	ld	a, e
	cp	#80
	jr	c, 1$
	ret

; Carry and A = the entry whose title is the word at the cursor (letters around CUR in LBUF, any case)
hctx:	ld	hl, #LBUF
	ld	a, (CUR)
	ld	l, a
1$:	ld	a, l			; back to the start of the word
	or	a
	jr	z, 2$
	dec	l
	ld	a, (hl)
	call	hword
	jr	c, 1$
	inc	l
2$:	ld	a, (hl)
	call	hword
	ret	nc			; no word here
	ld	a, (HKW)
	ld	b, a
3$:	ld	a, (HCOUNT)
	cp	b
	ret	z			; NC: not found
	push	hl
	ld	a, b
	push	bc
	call	htitle
	ex	de, hl
	pop	bc
	pop	hl
	push	hl
4$:	ld	a, (de)			; title against the word
	or	a
	jr	z, 5$
	ld	c, a
	ld	a, (hl)
	and	#0xDF
	cp	c
	jr	nz, 6$
	inc	de
	inc	l
	jr	4$
5$:	ld	a, (hl)			; title ended: so must the word
	call	hword
	jr	c, 6$
	pop	hl
	ld	a, b
	scf
	ret
6$:	pop	hl
	inc	b
	jr	3$

; Carry if A is a letter
hword:	push	bc
	ld	b, a
	and	#0xDF
	sub	#0x41
	cp	#26
	ld	a, b
	pop	bc
	ret
