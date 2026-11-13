; main.s - EASM page 1: cartridge header, the API jump table for user programs (fixed addresses),
; start-up, the RAM trampolines to page 2, the interrupt hook, running user code (G) and errors.
; The start-up and the trampolines follow EBASIC's genio1.s.
; Copyright (C) 2026 Santiago Crespo
; SPDX-License-Identifier: 0BSD

	.include "shared.inc"
	.area	CODE

	.db	0x55, 0xAA, 0x59, 0x45	; autostart signature
	jp	cold			; 8004
	.ascii	"EASM 1.0 "		; 8007-800F
; API for programs, at fixed addresses (also built-in symbols, expr.s). Page 1 is mapped while a
; program runs. Unless noted, the routines keep BC, DE, HL, IX, IY.
api::	jp	PRINTSTR		; 8010 print the string at HL, ending in 0 (HL ends after the 0; A, F)
	jp	PUTCHAR			; 8013 print A (CR, LF, BS, 7 beep, 12 clear); keeps everything
	jp	GETKEY			; 8016 wait for a key, A = code (F)
	jp	KEYPOLL			; 8019 A = key code or 0, Z if none (F)
	jp	CLS			; 801C clear the screen (A, F)
	jp	SETCUR			; 801F cursor to row D (0-3), column E (0-19) (A, F)
	jp	PRHEX8			; 8022 print A as two hex digits (A, F)
	jp	PRHEX16			; 8025 print HL as four hex digits (A, F)
	jp	PRDEC			; 8028 print HL in decimal, unsigned (A, F)
	jp	BEEP			; 802B 0.1 s beep; keeps everything
	jp	DELAY			; 802E wait about HL ms (A, F, HL)
	jp	EXIT			; 8031 back to EASM, registers kept for R (never returns)
	jp	NEWLINE			; 8034 new line unless at the start of one; keeps everything
api_end::			; (tools/mkcart.py checks that the table is at 0x8010)

cold:	di
	ld	sp, #STACK
	ld	hl, #ramsrc
	ld	de, #RAMCODE
	ld	bc, #ramsrc_end-ramsrc
	ldir
	ld	hl, #VARS		; all variables
	ld	de, #VARS+1
	ld	bc, #VARS_END-VARS-1
	ld	(hl), #0
	ldir
	call	lcdinit
	ld	a, #1
	ld	(CAPS), a		; caps lock on: mnemonics are upper case
	call	accents
	call	setled
	call	txtnew
	ld	a, #10
	ld	(RADIX), a
	ld	hl, (0x0039)		; enable the firmware ISR only if 0038 is JP 0119 and the hook is 0033
	ld	de, #0x0119
	or	a
	sbc	hl, de
	jr	nz, 3$
	ld	hl, (FW_HOOK)
	ld	de, #0x0033
	or	a
	sbc	hl, de
	jr	nz, 3$
	ld	a, #0xFF
	ld	(FW_KEYCODE), a
	ld	a, #0xD0
	ld	(FW_KEYST), a
	ld	hl, #FW_DIRTY
	ld	b, #8
4$:	ld	(hl), #0
	inc	hl
	djnz	4$
	ld	hl, #R_HOOK
	ld	(FW_HOOK), hl
	ld	a, #1
	ld	(ISRON), a
	im	1
	ei
3$:	call	CLS
	ld	hl, #banner
	call	PRINTSTR
	ld	de, #0x0010		; free bytes at the right of the first row
	call	SETCUR
	call	freemem
	call	PRDEC
	ld	de, #0x0300
	call	SETCUR
	jp	cmdloop

banner:	.ascii	"EASM 1.0"
	.db	CR, LF
	.ascii	"Z80 assembler"
	.db	CR, LF
	.ascii	"core: R.T.Russell"
	.db	0

;freemem - HL = bytes free for the text and the symbols. Destroys D,E,F.
freemem::
	ld	hl, #SRCLIM
	ld	de, (TXTEND)
	or	a
	sbc	hl, de
	ret

;error - abandon the current operation with error A: the handler at ERRJP runs with SP = ERRSP.
error::	ld	(ERRNO), a
	push	iy			; column of the text pointer
	pop	hl
	ld	a, l
	ld	(ERRCOL), a
	ld	sp, (ERRSP)
	ld	hl, (ERRJP)
	jp	(hl)

;---------------------------------------------------------------- user programs

;rungo - call the program at HL with page 1 mapped and interrupts on. It ends by RET, by EXIT, or
; when ANSWER is pressed (interrupt hook). Afterwards REGS/REGOK say how. Destroys everything but SP.
rungo::	ld	(GOSP), sp
	ld	de, #gret
	push	de
	ld	a, #1
	ld	(RUNNING), a
	jp	(hl)

gret:	ld	(REGS+6), hl		; the program returned
	push	af
	pop	hl
	ld	(REGS), hl
	ld	hl, #0			; no PC to show
	ld	(REGS+14), hl
	ld	a, #1
	jr	gsave

EXIT::	ld	(REGS+6), hl		; the program called EXIT: PC = the CALL
	push	af
	pop	hl
	ld	(REGS), hl
	pop	hl
	dec	hl
	dec	hl
	dec	hl
	ld	(REGS+14), hl
	ld	a, #2
gsave:	ld	(REGS+2), bc
	ld	(REGS+4), de
	ld	(REGS+8), ix
	ld	(REGS+10), iy
	ld	(REGS+12), sp
gend:	ld	(REGOK), a
	ld	sp, (GOSP)
	ld	a, #PAGE1		; whatever the program left
	out	(0x03), a
	xor	a
	ld	(RUNNING), a
	ld	a, (ISRON)
	or	a
	jr	z, 1$
	im	1
	ei
1$:	call	accents
	jp	setled

; ANSWER during a program (from the hook: page 1 mapped, SP = GOSP)
gbreak:	call	waitrel
	ld	a, #3
	jr	gend

;---------------------------------------------------------------- code copied to RAMCODE
; Page switching must run from RAM: the code of the page being left disappears with the OUT.
ramsrc:
; HL = page-2 address to call, the caller's HL on the stack. All other registers pass both ways.
rfar:	ld	(RAMCODE+rfar_t-ramsrc+1), hl
	pop	hl
	push	af
	ld	a, #PAGE2
	out	(0x03), a
	pop	af
rfar_t:	call	0
	push	af
	ld	a, #PAGE1
	out	(0x03), a
	pop	af
	ret
; The same from page 2 to a page-1 routine.
rcall1:	ld	(RAMCODE+rcall1_t-ramsrc+1), hl
	pop	hl
	push	af
	ld	a, #PAGE1
	out	(0x03), a
	pop	af
rcall1_t:	call	0
	push	af
	ld	a, #PAGE2
	out	(0x03), a
	pop	af
	ret
; Interrupt hook, called by the firmware ISR (registers already saved). While a program runs,
; ANSWER (column 7, port 0x10 bit 6) abandons it: back to EASM with the stack of the G command.
; It lives in RAM because either page may be mapped when the interrupt comes.
hook:	ld	a, (RUNNING)
	or	a
	ret	z
	ld	a, #0x80
	out	(0x10), a
	nop
	in	a, (0x10)
	ld	b, a
	xor	a
	out	(0x10), a
	bit	6, b
	ret	nz
	ld	(RUNNING), a
	ld	a, #PAGE1
	out	(0x03), a
	ld	sp, (GOSP)
	jp	gbreak
ramsrc_end:

R_FAR == RAMCODE+rfar-ramsrc
R_CALL1 == RAMCODE+rcall1-ramsrc
R_HOOK == RAMCODE+hook-ramsrc

	.ifgt	VARS_END-VARS-256		; the variables fit in their page
	.error	1
	.endif
	.ifgt	ramsrc_end-ramsrc-0x80		; and the RAM code in its 128 bytes
	.error	1
	.endif

; Entry point that runs slot n of the page-2 jump table
.macro	FAR	name, n
name::	push	hl
	ld	hl, #0x8000+3*n
	jp	R_FAR
.endm
	FAR	help, S_HELP
