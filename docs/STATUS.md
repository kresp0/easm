# EASM status: implemented and pending

All "implemented" items are tested in MAME (see [COMPATIBILITY.md](COMPATIBILITY.md)); none on the
real unit.

## Implemented
**Environment**
* Autostart cartridge, two 16 KiB pages (EASM, guide), start-up screen with the free memory.
* Editor and command line, switched with ANSWER; the command line keeps its screen.
* OFF switches off; `BYE` returns to the Genio menu.

**Editor**
* Insert, delete, split and join lines; insert and delete whole lines; long lines scroll sideways.
* Up/down, page up/down, start/end of line, go to a line (`LINE n`, `EDIT n`), find text (`FIND`).
* Optional line numbers; automatic indentation; TAB.
* Mnemonics and directives on the activity panel; ASM, RUN, calculator, find and line keys.
* Context help on the word at the cursor; the example of a page inserted as a line.
* Go to the last assembly error, cursor at the column where it was found.

**Assembler**
* All official Z80 instructions (697 forms checked against MAME's disassembler), IX/IY indexed forms,
  relative and absolute jumps.
* Two passes: labels (with or without `:`), forward references, `EQU`/`=`, phase check.
* Decimal, hex (`0FFH $FF 0xFF &FF`), binary (`%1010 1010B`), characters, `$`.
* Expressions with `+ - * / % << >> & | ^ ~` and parentheses.
* `ORG`, `EQU`, `DB/DEFB/DEFM`, `DW/DEFW`, `DS/DEFS`, `END [entry]`, comments, `:` between statements.
* 15 error messages with the line number and the line; code confined to the user RAM.
* Symbol list (`SYM`), built-in names for the API and the user RAM.

**Monitor**
* `A` line assembler, `D` disassembler (all opcodes), `M` memory viewer, `E` memory editor, `F` fill,
  `C` compare, `G` run, `R` registers, `?` calculator.
* Return by `RET`, by `EXIT` (with the registers and the address), or by ANSWER (interrupts on).

**API**: 13 routines at fixed addresses 8010-8036 (print, keys, cursor, numbers, beep, delay, exit).

**Guide**: 99 pages (22 topics, every mnemonic and directive), compressed, with examples.

**Build and tests**: `make` (EEPROM image, MAME image, symbol file, maps, usage report), `make test`
(8 scripted MAME tests, the instruction-set test and the disassembler sweep).

## Pending
| Item | Notes |
|---|---|
| Running on a real Genio 2000 | the first thing to do; see the risks in COMPATIBILITY.md |
| Storage: SAVE/LOAD of sources and binaries | needs a link; driver interface designed (DESIGN.md §10) |
| Software UART on the printer port, ESP32 storage, PC transfers, remote debugging | designed, not implemented (DESIGN.md §10) |
| Macros, INCLUDE, conditional assembly, multi-file projects | RAM is the limit; notes in DESIGN.md §10 |
| A listing (address, bytes, line) | possible on the printer once the port is used |
| Single step, breakpoints, registers after a break | not technically viable as designed (DESIGN.md §7); `CALL EXIT` serves as a breakpoint |
| `HIGH`/`LOW`, relational operators, local labels | small additions to `expr.s` / `asm.s` |
| Undocumented instructions in the assembler | the disassembler shows them already |
| Undo in the editor | — |
