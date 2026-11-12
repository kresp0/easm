; text.s - EASM page 1: the source text in RAM.
; From SRCBEG to TXTEND, one record per line: [length][bytes]. A line that starts with spaces stores
; their count (1-31) as its first byte, so indentation costs one byte. There is always at least one
; line (NLINES >= 1). The symbol table, when there is one, follows at TXTEND.
; Copyright (C) 2026 Santiago Crespo
; SPDX-License-Identifier: GPL-3.0-or-later

	.include "shared.inc"
	.area	CODE


;txtnew - empty text: one empty line. Destroys A,H,L,F.
txtnew::
	ld	hl, #SRCBEG
	ld	(hl), #0
	inc	hl
	ld	(TXTEND), hl
	ld	hl, #1
	ld	(NLINES), hl
	dec	hl
	ld	(CURL), hl
	ld	(TOPL), hl
	xor	a
	ld	(SYMOK), a
	ld	(ERRLN), a
	ld	(ERRLN+1), a
	ret

;lineptr - HL = record of line DE (0-based; DE = NLINES gives TXTEND). Destroys A,B,C,F.
lineptr::
	ld	hl, #SRCBEG
	ld	b, d
	ld	c, e
1$:	ld	a, b
	or	c
	ret	z
	call	nextrec
	dec	bc
	jr	1$

;nextrec - HL = the record after the one at HL. Destroys A,F.
nextrec::
	ld	a, (hl)
	inc	hl
	add	a, l
	ld	l, a
	ret	nc
	inc	h
	ret

;expand - copy the line at record HL to DE, indentation expanded. Returns HL = next record, DE = end
; of the copy, B = its length. Destroys A,C,F.
expand::
	ld	c, (hl)			; bytes left
	inc	hl
	ld	b, #0
	ld	a, c
	or	a
	ret	z
	ld	a, (hl)
	cp	#0x20
	jr	nc, 3$
	inc	hl			; a count of spaces
	dec	c
	ld	b, a
	push	bc
	ld	a, #0x20
1$:	ld	(de), a
	inc	de
	djnz	1$
	pop	bc
	ld	a, c
	or	a
	ret	z
3$:	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	inc	b
	dec	c
	jr	nz, 3$
	ret

;encode - LBUF (LEN characters) as a record in WBUF. Returns BC = record size. Destroys A,D,E,H,L,F.
encode::
	ld	hl, #LBUF
	ld	de, #WBUF+1
	ld	a, (LEN)
	ld	c, a			; C = characters left
	ld	b, #0			; B = leading spaces
1$:	ld	a, c
	or	a
	jr	z, 2$
	ld	a, (hl)
	cp	#0x20
	jr	nz, 2$
	ld	a, b
	cp	#31
	jr	z, 2$
	inc	b
	inc	hl
	dec	c
	jr	1$
2$:	ld	a, b
	or	a
	jr	z, 3$
	ld	(de), a
	inc	de
3$:	ld	a, c
	or	a
	jr	z, 4$
	ld	b, #0
	ldir
4$:	ex	de, hl			; size = end - WBUF
	ld	de, #WBUF
	or	a
	sbc	hl, de
	ld	a, l
	dec	a
	ld	(WBUF), a
	ld	b, h
	ld	c, l
	ret

;splice - replace BC bytes at HL by DE bytes from WBUF (DE = 0 deletes them). "Text full" if the
; text would reach SRCLIM; then nothing changes. Invalidates the symbol table.
; Destroys A,B,C,D,E,H,L,F.
splice::
	xor	a
	ld	(SYMOK), a
	ld	(SPP), hl
	ld	(SPOLD), bc
	ld	(SPNEW), de
	ld	hl, (TXTEND)		; new end = end - old + new
	or	a
	sbc	hl, bc
	add	hl, de
	ld	a, h
	cp	#>SRCLIM		; (SRCLIM is page aligned)
	jr	c, 1$
	ld	a, #E_TXTFULL
	jp	error
1$:	push	hl
	ld	hl, (SPP)		; the tail: from p + old to the end
	ld	bc, (SPOLD)
	add	hl, bc
	ex	de, hl			; DE = source
	ld	hl, (TXTEND)
	or	a
	sbc	hl, de
	ld	b, h
	ld	c, l			; BC = its length
	ld	hl, (SPP)
	push	de
	ld	de, (SPNEW)
	add	hl, de
	ex	de, hl			; DE = destination, p + new
	pop	hl			; HL = source
	ld	a, b
	or	c
	jr	z, 4$
	push	hl
	or	a
	sbc	hl, de
	pop	hl
	jr	nc, 3$
	add	hl, bc			; moving up: copy from the end down
	dec	hl
	ex	de, hl
	add	hl, bc
	dec	hl
	ex	de, hl
	lddr
	jr	4$
3$:	ldir				; moving down
4$:	pop	hl
	ld	(TXTEND), hl
	ld	bc, (SPNEW)
	ld	a, b
	or	c
	ret	z
	ld	de, (SPP)
	ld	hl, #WBUF
	ldir
	ret

;storeline - store LBUF as line CURL if it was changed. Destroys A,B,C,D,E,H,L,F.
storeline::
	ld	a, (MODIF)
	or	a
	ret	z
	call	encode
	push	bc
	ld	de, (CURL)
	call	lineptr
	ld	c, (hl)
	ld	b, #0
	inc	bc			; old record size
	pop	de
	call	splice
	xor	a
	ld	(MODIF), a
	ret

;loadline - LBUF = line CURL; LEN, MODIF = 0, CUR limited to LEN. Destroys A,B,C,D,E,H,L,F.
loadline::
	ld	de, (CURL)
	call	lineptr
	ld	de, #LBUF
	call	expand
	ld	a, b
	ld	(LEN), a
	ld	hl, #CUR
	cp	(hl)
	jr	nc, 1$
	ld	(hl), a
1$:	xor	a
	ld	(MODIF), a
	ld	(HOFS), a
	ret

;insline - insert an empty line before line DE. Destroys A,B,C,D,E,H,L,F.
insline::
	call	lineptr
	xor	a
	ld	(WBUF), a
	ld	bc, #0
	ld	de, #1
	call	splice
	ld	hl, (NLINES)
	inc	hl
	ld	(NLINES), hl
	ret

;delline - delete line DE (the text keeps at least one line). Destroys A,B,C,D,E,H,L,F.
delline::
	ld	hl, (NLINES)
	dec	hl
	ld	a, h
	or	l
	jr	nz, 1$
	ld	hl, #SRCBEG		; the only line: empty it
	ld	c, (hl)
	ld	b, #0
	inc	bc
	ld	de, #1
	xor	a
	ld	(WBUF), a
	jp	splice
1$:	ld	(NLINES), hl
	call	lineptr
	ld	c, (hl)
	ld	b, #0
	inc	bc
	ld	de, #0
	jp	splice
