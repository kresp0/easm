; asmb.s - the Z80 translation section of R.T. Russell's BBC BASIC (Z80) assembler, ASMB.Z80 v5.0
; (third_party/bbcz80/ASMB.Z80, zlib licence, third_party/bbcz80/licence.txt).
;
; ALTERED SOURCE VERSION, changed for EASM (it is not the original software):
;  * converted to sdasz80 syntax by EBASIC's m80_to_sdas.py;
;  * the language control section (ASSEM, HEX, listing) and the '.label' handling (VAR, ZERO, STOREN)
;    are removed: EASM's own line parser (asm.s) handles labels, directives and passes;
;  * the BASIC token cases are removed (CALL, AND, OR, DEF are plain text here); the TAND/TOR
;    table entries are kept so that the group arithmetic stays the same, with a byte that never
;    matches the start of a mnemonic;
;  * DEFM, DEFB, DEFW and OPT are removed (MISC answers "syntax error");
;  * NUMBER calls EASM's expression evaluator (EXPR, 16-bit value in HL) instead of EXPRI;
;  * "Out of range" goes to EASM's error handler, and is not reported in pass 1.
; The encoder itself and the opcode tables are unchanged.
;
; Entry ASMB: IY = text, IX = output; returns carry for a syntax error, IY after the operands.
;
; Original notice:
	;TITLE	BBC BASIC (C) R.T.RUSSELL 1981-2024
;
;BBC BASIC INTERPRETER - Z80 VERSION
;Z80 CPU ASSEMBLER MODULE - "ASMB"
;(C) COPYRIGHT R.T.RUSSELL 1981-2024
;
;THE NAME BBC BASIC IS USED WITH THE PERMISSION
;OF THE BRITISH BROADCASTING CORPORATION AND IS
;NOT TRANSFERRABLE TO A FORKED OR DERIVED WORK.
;
;VERSION 5.0, 14-05-2024
;

	.include "shared.inc"
	.area	CODE

TAND = 0x80		; EASM: BASIC tokens in the original. FIND matches 0x80 only against 0x80 or 0xA0
TOR = 0x80		; (C cedilla, a acute in code page 850), which never start a mnemonic

;
;PROCESSOR-SPECIFIC TRANSLATION SECTION:
;
;REGISTER USAGE: B - TYPE OF MOST RECENT OPERAND
;                C - OPCODE BEING BUILT
;                D - (IX) OR (IY) FLAG
;                E - OFFSET FROM IX OR IY
;               HL - NUMERIC OPERAND VALUE
;               IX - CODE DESTINATION
;               IY - SOURCE TEXT POINTER
;   Inputs: A = initial character
;  Outputs: Carry set if syntax error.
;
ASMB::	call	SKIP	
	ret	Z	
	ld	HL, #OPCODS	
	call	FIND	
	ret	C	
	ld	C, B	;ROOT OPCODE
	ld	D, #0	;CLEAR IX/IY FLAG
;
;GROUP 0 - TRIVIAL CASES REQUIRING NO COMPUTATION
;GROUP 1 - AS GROUP 0 BUT WITH "ED" PREFIX
;
	sub	#39	
	jr	NC, GROUP2	
	cp	#15-39	
	call	NC, ED	
	jr	BYTE0	
;
;GROUP 2 - BIT, RES, SET
;GROUP 3 - RLC, RRC, RL, RR, SLA, SRA, SRL
;
GROUP2:	sub	#10	
	jr	NC, GROUP4	
	cp	#3-10	
	call	C, BIT	
	ret	C	
	call	REGLO	
	ret	C	
	call	CB	
	jr	BYTE0	
;
;GROUP 4 - PUSH, POP, EX (SP)
;
GROUP4:	sub	#3	
	jr	NC, GROUP5	
G4:	call	PAIR	
	ret	C	
	jr	BYTE0	
;
;GROUP 5 - SUB, AND, XOR, OR, CP
;GROUP 6 - ADD, ADC, SBC
;
GROUP5:	sub	#8+2	
	jr	NC, GROUP7	
	cp	#5-8	
	ld	B, #7	
	call	NC, OPND	
	ld	A, B	
	cp	#7	
	jr	NZ, G6HL	
G6:	call	REGLO	
	ld	A, C	
	jr	NC, BIND1	
	xor	#0x46	
	call	BIND	
DB:	call	NUMBER	
	jr	VAL8	
;
G6HL:	and	#0x3F	
	cp	#12	
	scf		
	ret	NZ	
	ld	A, C	
	cp	#0x80	
	ld	C, #9	
	jr	Z, G4	
	xor	#0x1C	
	rrca		
	ld	C, A	
	call	ED	
	jr	G4	
;
;GROUP 7 - INC, DEC
;
GROUP7:	sub	#2	
	jr	NC, GROUP8	
	call	REGHI	
	ld	A, C	
BIND1:	jp	NC, BIND	
	xor	#0x64	
	rlca		
	rlca		
	rlca		
	ld	C, A	
	call	PAIR1	
	ret	C	
BYTE0:	ld	A, C	
	jr	BYTE2	
;
;GROUP 8 - IN
;GROUP 9 - OUT
;
GROUP8:	sub	#2	
	jr	NC, GROUPA	
	cp	#1-2	
	call	Z, CORN	
	ex	AF, af'	
	call	REGHI	
	ret	C	
	ex	AF, af'	
	call	C, CORN	
	inc	H	
	jr	Z, BYTE0	
	ld	A, B	
	cp	#7	
	scf		
	ret	NZ	
	ld	A, C	
	xor	#3	
	rlca		
	rlca		
	rlca		
	call	BYTE	
	jr	VAL8	
;
;GROUP 10 - JR, DJNZ
;
GROUPA:	sub	#2	
	jr	NC, GROUPB	
	cp	#1-2	
	call	NZ, COND	
	ld	A, C	
	jr	NC, GRPA	
	ld	A, #0x18	
GRPA:	call	BYTE	
	call	NUMBER	
	ld	DE, (PC)	
	inc	DE	
	scf		
	sbc	HL, DE	
	ld	A, L	
	rla		
	sbc	A, A	
	cp	H	
TOOFAR:	jp	NZ, TOOFR1	; EASM: see TOOFR1
VAL8:	ld	A, L	
	jr	BYTE2	
;
;GROUP 11 - JP
;
GROUPB:	ld	B, A	
	jr	NZ, GROUPC	
	call	COND	
	ld	A, C	
	jr	NC, GRPB	
	ld	A, B	
	and	#0x3F	
	cp	#6	
	ld	A, #0x0E9	
	jr	Z, BYTE2	
	ld	A, #0x0C3	
GRPB:	call	BYTE	
	jr	ADDR	
;
;GROUP 12 - CALL
;
GROUPC:	djnz	GROUPD	
GRPC:	call	GRPE	
ADDR:	call	NUMBER	
VAL16:	call	VAL8	
	ld	A, H	
	jr	BYTE2	
;
;GROUP 13 - RST
;
GROUPD:	djnz	GROUPE	
	call	NUMBER	
	and	C	
	or	H	
	jr	NZ, TOOFAR	
	ld	A, L	
	or	C	
BYTE2:	jr	BYTE1	
;
;GROUP 14 - RET
;
GROUPE:	djnz	GROUPF	
GRPE:	call	COND	
	ld	A, C	
	jr	NC, BYTE1	
	or	#9	
	jr	BYTE1	
;
;GROUP 15 - LD
;
GROUPF:	djnz	MISC	
	call	LDOP	
	jr	NC, LDA	
	call	REGHI	
	ex	AF, af'	
	call	SKIP	
	cp	#0x28	
	jr	Z, LDIN	
	ex	AF, af'	
	jp	NC, G6	
	ld	C, #1	
	call	PAIR1	
	ret	C	
	ld	A, #14	
	cp	B	
	ld	B, A	
	call	Z, PAIR	
	ld	A, B	
	and	#0x3F	
	cp	#12	
	ld	A, C	
	jr	NZ, GRPB	
	ld	A, #0x0F9	
	jr	BYTE1	
;
LDIN:	ex	AF, af'	
	push	BC	
	call	NC, REGLO	
	ld	A, C	
	pop	BC	
	jr	NC, BIND	
	ld	C, #0x0A	
	call	PAIR1	
	call	LD16	
	jr	NC, GRPB	
	call	NUMBER	
	ld	C, #2	
	call	PAIR	
	call	LD16	
	ret	C	
	call	BYTE	
	jr	VAL16	
;
LDA:	cp	#4	
	call	C, ED	
	ld	A, B	
BYTE1:	jr	BYTE	
;
;MISC - EASM: DEFM, DEFB, OPT, DEFW are not here (directives are in asm.s)
;
MISC:	scf	
	ret	
;
;SUBROUTINES:
;
LD16:	ld	A, B	
	jr	C, LD8	
	ld	A, B	
	and	#0x3F	
	cp	#12	
	ld	A, C	
	ret	Z	
	call	ED	
	ld	A, C	
	or	#0x43	
	ret		
;
LD8:	cp	#7	
	scf		
	ret	NZ	
	ld	A, C	
	or	#0x30	
	ret		
;
CORN:	push	BC	
	call	OPND	
	bit	5, B	
	pop	BC	
	jr	Z, NUMBER	
	ld	H, #-1	
ED:	ld	A, #0x0ED	
	jr	BYTE	
;
CB:	ld	A, #0x0CB	
BIND:	cp	#0x76	
	scf		
	ret	Z	;REJECT LD (HL),(HL)
	call	BYTE	
	inc	D	
	ret	P	
	ld	A, E	
	jr	BYTE	
;
OPND:	push	HL	
	ld	HL, #OPRNDS	
	call	FIND	
	pop	HL	
	ret	C	
	bit	7, B	
	ret	Z	
	bit	3, B	
	push	HL	
	call	Z, OFFSET	
	ld	E, L	
	pop	HL	
	ld	A, #0x0DD	
	bit	6, B	
	jr	Z, OP1	
	ld	A, #0x0FD	
OP1:	or	A	
	inc	D	
	ld	D, A	
	ret	M	
BYTE:	ld	0(IX), A	
	inc	IX	
	or	A	
	ret		
;
OFFSET:	ld	A, 0(IY)	
	cp	#0x29	
	ld	HL, #0	
	ret	Z	
NUMBER:	call	SKIP	
	push	BC	
	push	DE	
	push	IX	
	call	EXPR		; EASM: our evaluator, the value in HL
	pop	IX	
	pop	DE	
	pop	BC	
	ld	A, L	
	or	A	
	ret		
;
REG:	call	OPND	
	ret	C	
	ld	A, B	
	and	#0x3F	
	cp	#8	
	ccf		
	ret		
;
REGLO:	call	REG	
	ret	C	
	jr	ORC	
;
REGHI:	call	REG	
	ret	C	
	jr	SHL3	
;
COND:	call	OPND	
	ret	C	
	ld	A, B	
	and	#0x1F	
	sub	#16	
	jr	NC, SHL3	
	cp	#-15	
	scf		
	ret	NZ	
	ld	A, #3	
	jr	SHL3	
;
PAIR:	call	OPND	
	ret	C	
PAIR1:	ld	A, B	
	and	#0x0F	
	sub	#8	
	ret	C	
	jr	SHL3	
;
BIT:	call	NUMBER	
	cp	#8	
	ccf		
	ret	C	
SHL3:	rlca		
	rlca		
	rlca		
ORC:	or	C	
	ld	C, A	
	ret		
;
LDOP:	ld	HL, #LDOPS	
FIND::	call	SKIP	
EXIT:	ld	B, #0	
	scf		
	ret	Z	
FIND0:	ld	A, (HL)	
	or	A	
	jr	Z, EXIT	
	xor	0(IY)	
	and	#0b01011111	
	jr	Z, FIND2	
FIND1:	bit	7, (HL)	
	inc	HL	
	jr	Z, FIND1	
	inc	HL	
	inc	B	
	jr	FIND0	
;
FIND2:	push	IY	
FIND3:	bit	7, (HL)	
	inc	IY	
	inc	HL	
	jr	NZ, FIND5	
	cp	(HL)	
	call	Z, SKIP0	
	ld	A, (HL)	
	xor	0(IY)	
	and	#0b01011111	
	jr	Z, FIND3	
FIND4:	pop	IY	
	jr	FIND1	
;
FIND5:	call	DELIM	
	call	NZ, SIGN	
	jr	NZ, FIND4	
FIND6:	ld	A, B	
	ld	B, (HL)	
	pop	HL	
	ret		
;
SKIP0:	inc	HL	
SKIP::	call	DELIM	
	ret	NZ	
	call	TERM	
	ret	Z	
	inc	IY	
	jr	SKIP	
;
SIGN:	cp	#0x2B	
	ret	Z	
	cp	#0x2D	
	ret		
;
DELIM:	ld	A, 0(IY)	;ASSEMBLER DELIMITER
	cp	#0x20	
	ret	Z	
	cp	#0x2C	
	ret	Z	
	cp	#0x29	
	ret	Z	
TERM:	cp	#0x3B	;ASSEMBLER TERMINATOR
	ret	Z	
	cp	#0x5C	
	ret	Z	
TERM0:	cp	#0x3A	;ASSEMBLER SEPARATOR
	ret	NC	
	cp	#CR	
	ret		
;
OPCODS::	.db	0x4E, 0x4F	
	.db	0x50+0x80	
	.db	0	
	.db	0x52, 0x4C, 0x43	
	.db	0x41+0x80	
	.db	7	
	.db	0x45, 0x58	
	.db	0	
	.db	0x41, 0x46	
	.db	0	
	.db	0x41, 0x46	
	.db	0x27+0x80	
	.db	8	
	.db	0x52, 0x52, 0x43	
	.db	0x41+0x80	
	.db	0x0F	
	.db	0x52, 0x4C	
	.db	0x41+0x80	
	.db	0x17	
	.db	0x52, 0x52	
	.db	0x41+0x80	
	.db	0x1F	
	.db	0x44, 0x41	
	.db	0x41+0x80	
	.db	0x27	
	.db	0x43, 0x50	
	.db	0x4C+0x80	
	.db	0x2F	
	.db	0x53, 0x43	
	.db	0x46+0x80	
	.db	0x37	
	.db	0x43, 0x43	
	.db	0x46+0x80	
	.db	0x3F	
	.db	0x48, 0x41, 0x4C	
	.db	0x54+0x80	
	.db	0x76	
	.db	0x45, 0x58	
	.db	0x58+0x80	
	.db	0x0D9	
	.db	0x45, 0x58	
	.db	0	
	.db	0x44, 0x45	
	.db	0	
	.db	0x48	
	.db	0x4C+0x80	
	.db	0x0EB	
	.db	0x44	
	.db	0x49+0x80	
	.db	0x0F3	
	.db	0x45	
	.db	0x49+0x80	
	.db	0x0FB	
;
	.db	0x4E, 0x45	
	.db	0x47+0x80	
	.db	0x44	
	.db	0x49, 0x4D	
	.db	0	
	.db	0x30+0x80	
	.db	0x46	
	.db	0x52, 0x45, 0x54	
	.db	0x4E+0x80	
	.db	0x45	
	.db	0x52, 0x45, 0x54	
	.db	0x49+0x80	
	.db	0x4D	
	.db	0x49, 0x4D	
	.db	0	
	.db	0x31+0x80	
	.db	0x56	
	.db	0x49, 0x4D	
	.db	0	
	.db	0x32+0x80	
	.db	0x5E	
	.db	0x52, 0x52	
	.db	0x44+0x80	
	.db	0x67	
	.db	0x52, 0x4C	
	.db	0x44+0x80	
	.db	0x6F	
	.db	0x4C, 0x44	
	.db	0x49+0x80	
	.db	0x0A0	
	.db	0x43, 0x50	
	.db	0x49+0x80	
	.db	0x0A1	
	.db	0x49, 0x4E	
	.db	0x49+0x80	
	.db	0x0A2	
	.db	0x4F, 0x55, 0x54	
	.db	0x49+0x80	
	.db	0x0A3	
	.db	0x4C, 0x44	
	.db	0x44+0x80	
	.db	0x0A8	
	.db	0x43, 0x50	
	.db	0x44+0x80	
	.db	0x0A9	
	.db	0x49, 0x4E	
	.db	0x44+0x80	
	.db	0x0AA	
	.db	0x4F, 0x55, 0x54	
	.db	0x44+0x80	
	.db	0x0AB	
	.db	0x4C, 0x44, 0x49	
	.db	0x52+0x80	
	.db	0x0B0	
	.db	0x43, 0x50, 0x49	
	.db	0x52+0x80	
	.db	0x0B1	
	.db	0x49, 0x4E, 0x49	
	.db	0x52+0x80	
	.db	0x0B2	
	.db	0x4F, 0x54, 0x49	
	.db	0x52+0x80	
	.db	0x0B3	
	.db	0x4C, 0x44, 0x44	
	.db	0x52+0x80	
	.db	0x0B8	
	.db	0x43, 0x50, 0x44	
	.db	0x52+0x80	
	.db	0x0B9	
	.db	0x49, 0x4E, 0x44	
	.db	0x52+0x80	
	.db	0x0BA	
	.db	0x4F, 0x54, 0x44	
	.db	0x52+0x80	
	.db	0x0BB	
;
	.db	0x42, 0x49	
	.db	0x54+0x80	
	.db	0x40	
	.db	0x52, 0x45	
	.db	0x53+0x80	
	.db	0x80	
	.db	0x53, 0x45	
	.db	0x54+0x80	
	.db	0x0C0	
;
	.db	0x52, 0x4C	
	.db	0x43+0x80	
	.db	0	
	.db	0x52, 0x52	
	.db	0x43+0x80	
	.db	8	
	.db	0x52	
	.db	0x4C+0x80	
	.db	0x10	
	.db	0x52	
	.db	0x52+0x80	
	.db	0x18	
	.db	0x53, 0x4C	
	.db	0x41+0x80	
	.db	0x20	
	.db	0x53, 0x52	
	.db	0x41+0x80	
	.db	0x28	
	.db	0x53, 0x52	
	.db	0x4C+0x80	
	.db	0x38	
;
	.db	0x50, 0x4F	
	.db	0x50+0x80	
	.db	0x0C1	
	.db	0x50, 0x55, 0x53	
	.db	0x48+0x80	
	.db	0x0C5	
	.db	0x45, 0x58	
	.db	0	
	.db	0x28, 0x53	
	.db	0x50+0x80	
	.db	0x0E3	
;
	.db	0x53, 0x55	
	.db	0x42+0x80	
	.db	0x90	
	.db	0x41, 0x4E	
	.db	0x44+0x80	
	.db	0x0A0	
	.db	0x58, 0x4F	
	.db	0x52+0x80	
	.db	0x0A8	
	.db	0x4F	
	.db	0x52+0x80	
	.db	0x0B0	
	.db	0x43	
	.db	0x50+0x80	
	.db	0x0B8	
	.db	TAND	
	.db	0x0A0	
	.db	TOR	
	.db	0x0B0	
;
	.db	0x41, 0x44	
	.db	0x44+0x80	
	.db	0x80	
	.db	0x41, 0x44	
	.db	0x43+0x80	
	.db	0x88	
	.db	0x53, 0x42	
	.db	0x43+0x80	
	.db	0x98	
;
	.db	0x49, 0x4E	
	.db	0x43+0x80	
	.db	4	
	.db	0x44, 0x45	
	.db	0x43+0x80	
	.db	5	
;
	.db	0x49	
	.db	0x4E+0x80	
	.db	0x40	
	.db	0x4F, 0x55	
	.db	0x54+0x80	
	.db	0x41	
;
	.db	0x4A	
	.db	0x52+0x80	
	.db	0x20	
	.db	0x44, 0x4A, 0x4E	
	.db	0x5A+0x80	
	.db	0x10	
;
	.db	0x4A	
	.db	0x50+0x80	
	.db	0x0C2	
;
	.db	0x43, 0x41, 0x4C	
	.db	0x4C+0x80	
	.db	0x0C4	
;
	.db	0x52, 0x53	
	.db	0x54+0x80	
	.db	0x0C7	
;
	.db	0x52, 0x45	
	.db	0x54+0x80	
	.db	0x0C0	
;
	.db	0x4C	
	.db	0x44+0x80	
	.db	0x40	
;
;	(EASM: DEFM, DEFB, OPT, DEFW removed)
	.db	0	
;
OPRNDS:	.db	0x42+0x80	
	.db	0	
	.db	0x43+0x80	
	.db	1	
	.db	0x44+0x80	
	.db	2	
	.db	0x45+0x80	
	.db	3	
	.db	0x48+0x80	
	.db	4	
	.db	0x4C+0x80	
	.db	5	
	.db	0x28, 0x48	
	.db	0x4C+0x80	
	.db	6	
	.db	0x41+0x80	
	.db	7	
	.db	0x28, 0x49	
	.db	0x58+0x80	
	.db	0x86	
	.db	0x28, 0x49	
	.db	0x59+0x80	
	.db	0x0C6	
;
	.db	0x42	
	.db	0x43+0x80	
	.db	8	
	.db	0x44	
	.db	0x45+0x80	
	.db	10	
	.db	0x48	
	.db	0x4C+0x80	
	.db	12	
	.db	0x49	
	.db	0x58+0x80	
	.db	0x8C	
	.db	0x49	
	.db	0x59+0x80	
	.db	0x0CC	
	.db	0x41	
	.db	0x46+0x80	
	.db	14	
	.db	0x53	
	.db	0x50+0x80	
	.db	14	
;
	.db	0x4E	
	.db	0x5A+0x80	
	.db	16	
	.db	0x5A+0x80	
	.db	17	
	.db	0x4E	
	.db	0x43+0x80	
	.db	18	
	.db	0x50	
	.db	0x4F+0x80	
	.db	20	
	.db	0x50	
	.db	0x45+0x80	
	.db	21	
	.db	0x50+0x80	
	.db	22	
	.db	0x4D+0x80	
	.db	23	
;
	.db	0x28	
	.db	0x43+0x80	
	.db	0x20	
;
	.db	0	
;
LDOPS:	.db	0x49	
	.db	0	
	.db	0x41+0x80	
	.db	0x47	
	.db	0x52	
	.db	0	
	.db	0x41+0x80	
	.db	0x4F	
	.db	0x41	
	.db	0	
	.db	0x49+0x80	
	.db	0x57	
	.db	0x41	
	.db	0	
	.db	0x52+0x80	
	.db	0x5F	
	.db	0x28, 0x42, 0x43	
	.db	0	
	.db	0x41+0x80	
	.db	2	
	.db	0x28, 0x44, 0x45	
	.db	0	
	.db	0x41+0x80	
	.db	0x12	
	.db	0x41	
	.db	0	
	.db	0x28, 0x42	
	.db	0x43+0x80	
	.db	0x0A	
	.db	0x41	
	.db	0	
	.db	0x28, 0x44	
	.db	0x45+0x80	
	.db	0x1A	
;
	.db	0	
;


; EASM: "Out of range" goes to EASM's error handler, except in pass 1, where forward references are
; not known yet (their value is 0)
TOOFR1:	ld	A, (PASS)
	dec	A
	jp	Z, VAL8
	ld	A, #E_RANGE
	jp	error
