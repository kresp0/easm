; editor.s - EASM page 1: the full-screen source editor (4 rows of 20 columns).
; Every row shows a line; the line with the cursor is edited in LBUF and scrolls sideways, the
; others show their first characters. Optional line numbers take 4 columns.
; Keys: LEFT/RIGHT, ALT+LEFT/RIGHT (start/end), ALT+U-diaeresis / ALT+; (line up/down), DELETE and DEL,
; ENTER (split the line; the new line keeps the indentation), SHIFT+HELP (TAB: to the next column
; multiple of 4), HELP (the guide; on a word, its page), ANSWER (the command line).
; The activity panel types mnemonics and directives, and has the editor's commands (see ACTS).
; Copyright (C) 2026 Santiago Crespo
; SPDX-License-Identifier: 0BSD

	.include "shared.inc"
	.area	CODE

; Activity keys, in panel order (column by column, top to bottom). Text keys first, then actions.
A_ACT = 26			; first action
A_PGUP = 26
A_PGDN = 27
A_LINE = 28
A_ERR = 29
A_ASM = 30
A_RUN = 31
A_CMD = 32
A_CALC = 33
A_FIND = 34
A_NUMS = 35
A_INS = 36
A_DELL = 37
	.globl	A_ACT, A_ASM, A_RUN

ACTS:	.asciz	"LD "		; BUSCA LA LETRA
	.asciz	"CALL "		; RECUERDA LA PALABRA
	.asciz	"JP "		; PLURALES
	.asciz	"JR "		; VERBOS
	.asciz	"RET"		; REVOLTIJO DE LETRAS
	.asciz	"PUSH "		; LA PALABRA MISTERIOSA
	.asciz	"POP "		; DERIVADOS
	.asciz	"INC "		; SINONIMOS
	.asciz	"DEC "		; ANTONIMOS
	.asciz	"DJNZ "		; LA LETRA LOCA
	.asciz	"ADD "		; LA NUEVA PALABRA
	.asciz	"SUB "		; TRUEQUE DE LETRAS
	.asciz	"AND "		; ALFAPUZZLE
	.asciz	"OR "		; REVOLTIJO
	.asciz	"XOR "		; ACERTIJO GRAMATICAL
	.asciz	"CP "		; SUMA
	.asciz	"EX "		; RESTA
	.asciz	"OUT "		; MULTIPLICACION
	.asciz	"IN "		; DIVISION
	.asciz	"(HL)"		; FRACCIONES / DECIMALES
	.asciz	"ORG "		; FRACCIONES / PORCENTAJES
	.asciz	"EQU "		; RATIOS
	.asciz	"DB "		; ALGEBRA
	.asciz	"DW "		; REPASO A LAS MATEMATICAS
	.asciz	"DS "		; EL SIGNO PERDIDO
	.asciz	"END"		; CIENCIAS
	.asciz	""		; CINE Y TELEVISION: page up
	.asciz	""		; HISTORIA Y GEOGRAFIA: page down
	.asciz	"LINE "		; GENERAL: go to line (command line)
	.asciz	""		; QUE SOY?: to the line of the last error
	.asciz	"ASM"		; EL NUMERO RELAMPAGO: assemble
	.asciz	"RUN"		; BASIC: assemble and run
	.asciz	""		; IMPRIMIR TEXTO: the command line
	.asciz	"? "		; CALCULADORA: calculator (command line)
	.asciz	"FIND "		; CARTUCHOS ADICIONALES: find (command line)
	.asciz	""		; NIVEL: line numbers on/off
	.asciz	""		; 1 JUGADOR: insert a line
	.asciz	""		; 2 JUGADORES: delete the line

;actkey - carry and A = 0-37 if A is the code of an activity key
actkey::
	cp	#0xF0
	jr	c, 1$
	sub	#0xDA
	scf
	ret
1$:	sub	#0xC0
	cp	#22
	ret	c
	add	a, #0xC0
	or	a
	ret

;acttext - HL = the text of activity key A. Destroys A,F.
acttext::
	ld	hl, #ACTS
1$:	or	a
	ret	z
	push	af
2$:	ld	a, (hl)
	inc	hl
	or	a
	jr	nz, 2$
	pop	af
	dec	a
	jr	1$

;instext - insert the text at HL (ending in 0) at the cursor. Destroys A,B,C,H,L,F.
instext::
	ld	a, (hl)
	or	a
	ret	z
	push	hl
	call	insch
	pop	hl
	inc	hl
	jr	instext

;insch - insert A at the cursor (up to MAXLEN characters). Destroys A,B,C,H,L,F.
insch::	ld	c, a
	ld	a, (LEN)
	cp	#MAXLEN
	ret	nc
	ld	hl, #LBUF
	ld	l, a
	ld	a, (CUR)
	ld	b, a
1$:	ld	a, l
	cp	b
	jr	z, 2$
	dec	l
	ld	a, (hl)
	inc	l
	ld	(hl), a
	dec	l
	jr	1$
2$:	ld	(hl), c
	ld	hl, #LEN
	inc	(hl)
	ld	hl, #CUR
	inc	(hl)
	ld	a, #1
	ld	(MODIF), a
	ret

;delat - delete the character at A. Destroys A,B,H,L,F.
delat::	ld	hl, #LBUF
	ld	l, a
	ld	a, (LEN)
	ld	b, a
1$:	ld	a, l
	inc	a
	cp	b
	jr	nc, 2$
	inc	l
	ld	a, (hl)
	dec	l
	ld	(hl), a
	inc	l
	jr	1$
2$:	ld	hl, #LEN
	dec	(hl)
	ld	a, #1
	ld	(MODIF), a
	ret

;edkey - the keys that edit LBUF in place (shared with the command line): characters, LEFT,
; RIGHT, HOME, END, DELETE (only within the line), DEL (only within the line), TAB.
; Returns carry if the key was not one of them. Destroys A,B,C,H,L,F.
edkey::	ld	hl, #CUR
	cp	#LEFT
	jr	nz, 1$
	ld	a, (hl)
	or	a
	ret	z
	dec	(hl)
	ret
1$:	cp	#RIGHT
	jr	nz, 2$
	ld	a, (LEN)
	cp	(hl)
	ret	z
	inc	(hl)
	ret
2$:	cp	#HOME
	jr	nz, 3$
	ld	(hl), #0
	ret
3$:	cp	#END
	jr	nz, 4$
	ld	a, (LEN)
	ld	(hl), a
	ret
4$:	cp	#BS
	jr	nz, 5$
	ld	a, (hl)
	or	a
	scf
	ret	z			; at the start: not handled here
	dec	a
	ld	(hl), a
	call	delat
	or	a
	ret
5$:	cp	#DEL
	jr	nz, 6$
	ld	a, (LEN)
	cp	(hl)
	scf
	ret	z			; at the end: not handled here
	ld	a, (hl)
	call	delat
	or	a
	ret
6$:	cp	#TAB
	jr	nz, 8$
7$:	ld	a, #0x20		; spaces up to the next multiple of 4
	call	insch
	ld	a, (CUR)
	and	#3
	jr	nz, 7$
	ret
8$:	cp	#0x20			; printable: ASCII and code page 850, not the key codes
	ret	c
	cp	#DEL
	jr	z, 9$
	cp	#LEFT
	jr	c, 10$
	cp	#HELP+1
	jr	c, 9$
	push	af
	call	actkey
	pop	bc
	jr	c, 9$
	ld	a, b
10$:	call	insch
	or	a
	ret
9$:	scf
	ret

;exline - LBUF = the guide's example (in WBUF, ending in 0). Destroys A,B,C,H,L,F.
exline::
	xor	a
	ld	(LEN), a
	ld	(CUR), a
	ld	hl, #WBUF
	jp	instext

;---------------------------------------------------------------- the editor

;toedit - leave the command line for the editor (jumped to)
toedit::
	call	savescr
edstart:
	ld	sp, #STACK
	ld	(ERRSP), sp
	ld	hl, #ederr
	ld	(ERRJP), hl
	call	edfix
	call	loadline
	ld	a, (ECUR)
	ld	hl, #LEN
	cp	(hl)
	jr	c, 1$
	ld	a, (hl)
1$:	ld	(CUR), a
	ld	hl, #EXEDIT		; the guide's example, taken at the command prompt
	ld	a, (hl)
	ld	(hl), #0
	or	a
	jp	nz, ed_insex
ed_loop:
	call	drawed
	call	GETKEY
	cp	#ESC
	jp	z, ed_cmd
	cp	#CR
	jp	z, ed_enter
	cp	#HELP
	jp	z, ed_help
	cp	#UP
	jp	z, ed_up
	cp	#DOWN
	jp	z, ed_down
	push	af
	call	actkey
	jp	c, ed_act
	pop	af
	push	af
	call	edkey
	jr	nc, 2$			; done
	pop	af
	cp	#BS			; DELETE at the start: join with the line above
	jp	z, ed_join
	cp	#DEL			; DEL at the end: join the line below
	jp	z, ed_joinb
	jr	ed_loop
2$:	pop	af
	jr	ed_loop

; An error in the editor (text full): beep, the message on the top row until a key; the line
; being edited is kept as it is
ederr:	ld	sp, #STACK
	call	BEEP
	ld	a, (ERRNO)
	call	errmsg
	ld	de, #ROWBUF
1$:	ld	a, (hl)
	and	#0x7F
	ld	(de), a
	inc	de
	bit	7, (hl)
	inc	hl
	jr	z, 1$
	xor	a
	ld	(de), a
	ld	hl, #ROWBUF
	ld	e, #0
	call	putrow
	call	GETKEY
	jp	ed_loop

; ANSWER: the command line
ed_cmd:	call	storeline
	ld	a, (CUR)
	ld	(ECUR), a
	xor	a
	ld	(LEN), a
	ld	(CUR), a
	call	restscr
	jp	cmdnext

; Keep CURL in the text and TOPL so that CURL is on the screen
edfix:	ld	de, (CURL)
	call	clampl
	ld	(CURL), de
	ld	hl, (TOPL)
	ex	de, hl			; DE = TOPL, HL = CURL
	or	a
	sbc	hl, de
	jr	nc, 1$
	ld	de, (CURL)		; above the window
	ld	(TOPL), de
	ret
1$:	ld	a, h			; more than 3 below
	or	a
	jr	nz, 2$
	ld	a, l
	cp	#4
	ret	c
2$:	ld	hl, (CURL)
	ld	de, #3
	or	a
	sbc	hl, de
	ld	(TOPL), hl
	ret

; Draw the four rows; the cursor goes to the current line
drawed:	call	edfix
	ld	a, (NUMSHOW)
	or	a
	ld	a, #19			; width - 1
	jr	z, 1$
	ld	a, #15
1$:	call	hscroll
	ld	de, (TOPL)
	call	lineptr
	ld	(LINEPTR), hl
	ld	e, #0			; cell
	ld	bc, (TOPL)
2$:	push	bc
	ld	a, (NUMSHOW)		; "nnn " (the line number, 1-based)
	or	a
	jr	z, 3$
	call	drnum
3$:	ld	hl, (CURL)
	or	a
	sbc	hl, bc
	jr	nz, 4$
	ld	a, (HOFS)		; the current line, from HOFS
	ld	hl, #LBUF
	ld	l, a
	ld	a, (LEN)
	sub	l
	jr	nc, 5$
	xor	a
5$:	ld	b, a			; characters left
	jr	6$
4$:	ld	hl, (NLINES)		; another line: its start (or nothing past the end)
	or	a
	sbc	hl, bc
	ld	b, #0
	jr	z, 6$
	jr	c, 6$
	ld	hl, (LINEPTR)
	push	de
	ld	de, #WBUF
	call	expand
	pop	de
	ld	hl, #WBUF
6$:	ld	a, b			; B characters at HL, then spaces up to the end of the row
	or	a
	ld	a, #0x20
	jr	z, 7$
	ld	a, (hl)
	inc	hl
	dec	b
7$:	push	hl
	push	bc
	call	putcell
	pop	bc
	pop	hl
	inc	e
	ld	a, e
	cp	#20
	jr	z, 8$
	cp	#40
	jr	z, 8$
	cp	#60
	jr	z, 8$
	cp	#80
	jr	nz, 6$
8$:	pop	bc			; the next line
	ld	hl, (NLINES)
	or	a
	sbc	hl, bc
	jr	z, 9$
	jr	c, 9$
	ld	hl, (LINEPTR)
	call	nextrec
	ld	(LINEPTR), hl
9$:	inc	bc
	ld	a, e
	cp	#80
	jr	c, 2$
	ld	hl, (CURL)		; the cursor
	ld	de, (TOPL)
	or	a
	sbc	hl, de
	ld	a, l
	ld	(CY), a
	ld	a, (HOFS)
	ld	b, a
	ld	a, (CUR)
	sub	b
	ld	b, a
	ld	a, (NUMSHOW)
	or	a
	jr	z, 10$
	ld	a, #4
10$:	add	a, b
	ld	(CX), a
	ret

; "nnn " for line BC (0-based) at cell E, blank past the end
drnum:	push	bc
	ld	hl, (NLINES)
	or	a
	sbc	hl, bc
	ld	h, b
	ld	l, c
	inc	hl
	ld	b, #3
	jr	z, 5$
	jr	c, 5$
	ld	a, #0x2F		; hundreds (modulo 1000)
	ld	bc, #-1000
1$:	add	hl, bc
	jr	c, 1$
	ld	bc, #1000
	add	hl, bc
	ld	bc, #-100
	call	2$
	ld	bc, #-10
	call	2$
	ld	a, l
	add	a, #0x30
	call	6$
	jr	4$
2$:	ld	a, #0x2F
3$:	inc	a
	add	hl, bc
	jr	c, 3$
	sbc	hl, bc
6$:	push	hl
	push	bc
	call	putcell
	pop	bc
	pop	hl
	inc	e
	ret
5$:	ld	a, #0x20		; past the end
	call	6$
	djnz	5$
4$:	ld	a, #0x20
	call	6$
	pop	bc
	ret

; UP and DOWN: the line above / below (the changed line is stored first)
ed_up:	ld	hl, (CURL)
	ld	a, h
	or	l
	jp	z, ed_loop
	dec	hl
	jr	ed_go
ed_down:
	ld	hl, (CURL)
	inc	hl
	ld	de, (NLINES)
	or	a
	sbc	hl, de
	add	hl, de
	jp	nc, ed_loop
; To line HL, the cursor in the same column
ed_go:	push	hl
	call	storeline
	pop	hl
	ld	(CURL), hl
	call	loadline
	jp	ed_loop

; ENTER: split the line at the cursor; the new line starts with the indentation of this one
; (two spaces after something in column 0, such as a label)
ed_enter:
	call	freemem			; room for the new line?
	ld	a, (LEN)
	add	a, #40
	ld	e, a
	ld	d, #0
	or	a
	sbc	hl, de
	ld	a, #E_TXTFULL
	jp	c, error
	ld	hl, #LBUF		; B = indentation of this line
	ld	b, #0
1$:	ld	a, (LEN)
	cp	b
	jr	z, 2$
	ld	a, (hl)
	cp	#0x20
	jr	nz, 2$
	inc	hl
	inc	b
	jr	1$
2$:	ld	a, b
	or	a
	jr	nz, 3$
	ld	a, (LEN)
	or	a
	jr	z, 3$
	ld	b, #2
3$:	ld	hl, #LBUF		; the rest of the line after the cursor, without leading spaces
	ld	a, (CUR)
	ld	l, a
4$:	ld	a, (LEN)
	cp	l
	jr	z, 5$
	ld	a, (hl)
	cp	#0x20
	jr	nz, 5$
	inc	l
	jr	4$
5$:	ld	a, l
	ld	(LABPOS), a		; T: where it starts
	ld	a, (LEN)
	sub	l
	ld	(FCOUNT), a		; N: its length
	add	a, b
	cp	#MAXLEN+1
	jr	c, 6$
	ld	b, #0			; (too long with the indentation)
6$:	ld	a, b
	ld	(LABPOS+1), a		; B
	ld	a, (CUR)		; this line ends at the cursor
	ld	(LEN), a
	ld	a, #1
	ld	(MODIF), a
	call	storeline
	ld	de, (CURL)
	inc	de
	ld	(CURL), de
	call	insline
	ld	a, (FCOUNT)		; move the rest from T to B
	or	a
	jr	z, 9$
	ld	c, a
	ld	b, #0
	ld	hl, #LBUF
	ld	a, (LABPOS)
	ld	l, a
	ld	de, #LBUF
	ld	a, (LABPOS+1)
	ld	e, a
	cp	l
	jr	z, 9$
	jr	c, 7$
	add	hl, bc			; to the right: from the end down
	dec	hl
	ex	de, hl
	add	hl, bc
	dec	hl
	ex	de, hl
	lddr
	jr	9$
7$:	ldir
9$:	ld	hl, #LBUF		; the indentation
	ld	a, (LABPOS+1)
	ld	b, a
	ld	(CUR), a
	or	a
	jr	z, 11$
10$:	ld	(hl), #0x20
	inc	hl
	djnz	10$
11$:	ld	a, (LABPOS+1)
	ld	b, a
	ld	a, (FCOUNT)
	add	a, b
	ld	(LEN), a
	ld	a, #1
	ld	(MODIF), a
	call	storeline
	jp	ed_loop

; A = the column of the first character that is not a space in LBUF (or LEN)
firstnb:
	ld	hl, #LBUF
	ld	a, (LEN)
	ld	b, a
	xor	a
1$:	cp	b
	ret	z
	ld	c, a
	ld	a, (hl)
	cp	#0x20
	ld	a, c
	ret	nz
	inc	hl
	inc	a
	jr	1$

; DELETE at the start of a line: append it to the line above
ed_join:
	ld	hl, (CURL)
	ld	a, h
	or	l
	jp	z, ed_loop
	call	storeline
	ld	de, (CURL)		; this line to WBUF
	call	lineptr
	ld	de, #WBUF
	call	expand
	ld	a, b
	ld	(FCOUNT), a
	ld	de, (CURL)
	call	delline
	ld	hl, (CURL)
	dec	hl
	ld	(CURL), hl
	call	loadline
	jr	ed_app

; DEL at the end of a line: append the line below
ed_joinb:
	ld	hl, (CURL)
	inc	hl
	ld	de, (NLINES)
	or	a
	sbc	hl, de
	jp	nc, ed_loop
	call	storeline
	ld	de, (CURL)
	inc	de
	push	de
	call	lineptr
	ld	de, #WBUF
	call	expand
	ld	a, b
	ld	(FCOUNT), a
	pop	de
	call	delline
; Append FCOUNT characters from WBUF to LBUF (as far as they fit), store it; the cursor at the joint
ed_app:	ld	a, (LEN)
	ld	(CUR), a
	push	af
	ld	hl, #WBUF
	ld	a, (FCOUNT)
	ld	b, a
	or	a
	jr	z, 2$
1$:	ld	a, (hl)
	push	hl
	push	bc
	call	insch
	pop	bc
	pop	hl
	inc	hl
	djnz	1$
2$:	ld	a, #1
	ld	(MODIF), a
	call	storeline
	pop	af
	ld	(CUR), a
	jp	ed_loop

; HELP: the guide, on the word at the cursor; an example chosen there becomes a new line below
ed_help:
	call	storeline
	xor	a
	call	help
	jp	nc, ed_loop
; The example in WBUF: an empty line takes it; otherwise a new line below
ed_insex:
	ld	a, (LEN)
	push	af
	xor	a			; LBUF = two spaces and the example (WBUF is needed by insline)
	ld	(LEN), a
	ld	(CUR), a
	ld	a, #0x20
	call	insch
	ld	a, #0x20
	call	insch
	ld	hl, #WBUF
	call	instext
	pop	af
	or	a
	jr	z, 1$
	ld	de, (CURL)
	inc	de
	ld	(CURL), de
	call	insline
1$:	ld	a, #1
	ld	(MODIF), a
	call	storeline
	jp	ed_loop

;---------------------------------------------------------------- activity keys

ed_act:	pop	bc			; (the key)
	cp	#A_ACT
	jr	nc, 2$
	push	af			; a text: on an empty line, indented
	ld	a, (LEN)
	or	a
	jr	nz, 1$
	ld	a, #0x20
	call	insch
	ld	a, #0x20
	call	insch
1$:	pop	af
	call	acttext
	call	instext
	jp	ed_loop
2$:	cp	#A_LINE			; commands typed in the command line
	jr	z, 3$
	cp	#A_CALC
	jr	z, 3$
	cp	#A_FIND
	jr	z, 3$
	cp	#A_ASM			; commands run at once
	jr	z, 4$
	cp	#A_RUN
	jr	z, 4$
	cp	#A_CMD
	jp	z, ed_cmd
	cp	#A_PGUP
	jr	z, ed_pgup
	cp	#A_PGDN
	jr	z, ed_pgdn
	cp	#A_ERR
	jr	z, ed_err
	cp	#A_NUMS
	jr	z, ed_nums
	cp	#A_INS
	jr	z, ed_ins
	xor	a			; A_DELL: delete this line (unsaved changes are dropped, so
	ld	(MODIF), a		; that a line too long for the text can always go)
	ld	de, (CURL)
	call	delline
	call	loadline
	jp	ed_loop
4$:	push	af
	ld	a, #1
	ld	(PRUN), a
	pop	af
3$:	push	af
	call	storeline
	ld	a, (CUR)
	ld	(ECUR), a
	pop	af
	call	acttext
	xor	a
	ld	(LEN), a
	ld	(CUR), a
	call	instext
	xor	a			; (the editor's line was stored above)
	ld	(MODIF), a
	call	restscr
	jp	cmdnext

ed_ins:	call	storeline		; an empty line before this one
	ld	de, (CURL)
	call	insline
	call	loadline
	jp	ed_loop

ed_nums:
	ld	hl, #NUMSHOW
	ld	a, (hl)
	xor	#1
	ld	(hl), a
	jp	ed_loop

ed_pgup:
	ld	hl, (CURL)
	ld	de, #-4
	add	hl, de
	jp	c, ed_go
	ld	hl, #0
	jp	ed_go
ed_pgdn:
	ld	hl, (CURL)
	ld	de, #4
	add	hl, de
	ex	de, hl
	call	clampl
	ex	de, hl
	jp	ed_go

; To the line of the last assembly error, the cursor where it was found
ed_err:	ld	hl, (ERRLN)
	ld	a, h
	or	l
	jp	z, ed_loop
	dec	hl
	push	hl
	call	storeline
	pop	hl
	ld	(CURL), hl
	call	loadline
	ld	a, (ERRCOL)
	ld	hl, #LEN
	cp	(hl)
	jr	c, 1$
	ld	a, (hl)
1$:	ld	(CUR), a
	jp	ed_loop
