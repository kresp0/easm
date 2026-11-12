# EASM technical design

## 1. Goal and constraints
A self-contained Z80 development system on the Genio 2000: edit, assemble, run and inspect code on
the machine itself. The constraints that shape everything:

* **8 KiB of RAM** (C000-DFFF), of which the firmware's interrupt routine owns DB00-DFFF. Source text,
  symbol table, object code, stack and EASM's variables share the remaining 6.75 KiB.
* **A 4x20 character LCD** with gaps between cells, and an HD44780 with an unusual DDRAM map.
* **Two 16 KiB cartridge pages** (32 KiB AT28C256 on the RevD board), switched at 8000-BFFF.
* No storage, no serial port: the RAM is lost at power-off.
* Code must run from ROM: no self-modifying code in ROM, page switching from RAM.

## 2. What was taken from EBASIC
EBASIC (https://github.com/kresp0/ebasic, GPL-3.0-or-later, same author) is BBC BASIC (Z80) v5 with a Genio layer. Its
files are either EBASIC's own or R.T. Russell's (zlib). The audit:

| EBASIC component | File | Origin | In EASM |
|---|---|---|---|
| Hardware start-up (RAM code copy, HD44780 init, caps LED) | `genio1.s` | EBASIC | `main.s`, `io.s` (same sequence) |
| Firmware ISR as timer and cursor service, with the DB00/DB01 checks | `genio1.s` | EBASIC | `main.s` (same checks); the hook now watches ANSWER instead of counting TIME |
| Page trampolines in RAM (`rfar`, `rcall1`) | `genio1.s` | EBASIC | `main.s` (same code) |
| LCD: DDRAM map, shadow screen, `putcell`, CGRAM accented capitals, code page 850 | `genio2.s` | EBASIC | `io.s` (graphics window removed) |
| Console: wrap, scroll, BS, beep | `genio2.s` | EBASIC | `io.s` |
| Keyboard: matrix scan, activity panel, auto-repeat, Spanish tables, OFF | `genio1.s`, `genio2.s` | EBASIC | `io.s`; each column is read with interrupts off, because the interrupt hook also drives port 0x10 |
| Screen editor | `genio2.s` | EBASIC | **not reused**: it is built on BASIC's `LIST` output and line numbers. EASM's editor is new (`editor.s`, `text.s`) and reuses only the line-input primitives (insert, delete) |
| Guide viewer and compressor | `help.s`, `gen_help.py` | EBASIC | `help.s`, `tools/gen_help.py`; the coverage check now reads ASMB.Z80's opcode table instead of BASIC's keywords |
| Sound engine, graphics, VDU, statements | `stmt.s`, `gen_sound.py` | EBASIC | not used (only `BEEP`) |
| Interpreter | `bbcz80/*.Z80` | Russell (zlib) | not used, except `ASMB.Z80` (section 3) |
| M80 to sdas converter | `m80_to_sdas.py` | EBASIC | `tools/`, used once to produce `asmb.s` |
| Page-2 stub generator, cartridge image builder | `mksyms.py`, `mkcart.py` | EBASIC | `tools/` (mkcart extended: symbol file, usage report, API check) |
| MAME test driver | `tests/drive.lua`, `run_mame.sh` | EBASIC | `tests/` (extended: `expect`, `expectmem`, `expectpc`, `load`, `loadbin`) |

## 3. Choosing the assembler core
### Candidates
| Assembler | Origin | Size | Passes | Source and licence | Fit |
|---|---|---|---|---|---|
| **ASMB.Z80** (BBC BASIC Z80 v5) | R.T. Russell | 1383 bytes (sdas build in EBASIC), tables included | 1 per call; BASIC's `FOR pass` loop and `OPT` make two | **published, zlib** | ROMable (no self-modifying code), table-driven, already assembled and run on this target by EBASIC |
| ZEAP 1.x/2.0 | Sigma (Nascom), 1978-79 | ~4 KiB editor-assembler; its source "ultimately stretched to 21K" (Nascom newsletter) | 2 | manual (C) 1978 Sigma; no release of the source found | no usable source |
| Z80ASM | SLR Systems (CP/M), 1984 | — | multi | commercial; no release of the source found | no |
| M80 | Microsoft (CP/M) | — | 2 | commercial | no |
| Z80MR | Mitek (CP/M) | — | 2, macros | distributed as a binary; no source or licence terms found | no |
| ZSM | CP/M, public domain | — | 2 | described as public domain with Z80 source (cpcwiki) | file-based CP/M design; would need its I/O, symbol storage and expression code replaced too |
| A new one | — | estimated 3-4 KiB for the encoder alone | 2 | own | the most work and the most risk of encoding errors |

Searches for ZEAP, Z80ASM and Z80MR found manuals and descriptions but no source code or licence terms;
"not found" is the result of those searches, not a proof that none exists.

### ASMB.Z80's dependencies on BASIC
`ASMB.Z80` cannot run alone. Its imports and hidden assumptions:

| Dependency | What BASIC provides | EASM's replacement |
|---|---|---|
| `EXPRI` | BASIC's full expression evaluator (integers, floats, variables, functions): EVAL+MATH, many KiB | `expr.s`: a 16-bit evaluator with symbols, `$`, hex/binary/char literals (1.1 KiB) |
| `EXPRS` + `ACCS` | string expressions, for `DEFM` | `DB "text"` handled by EASM's directive code |
| `VAR`, `ZERO`, `STOREN` | `.label` creates a BASIC variable | removed; EASM's line parser handles `label:` and EQU with its own table |
| `ERROR` | BASIC's error handler | `error` (main.s): back to the current handler with SP restored |
| `PC`, `OC`, `LISTON`, `COUNT` | interpreter variables; `OPT` bits | `PC` is EASM's; `OC`, listing and `OPT` removed |
| `TABIT`, `CRLF`, `OUT` | listing output | removed with the control section |
| tokens `TCALL`, `TAND`, `TOR`, `TDEF` | BASIC tokenises CALL/AND/OR/DEF inside `[ ]` | plain text in EASM; the token table entries kept as never-matching bytes so that the group arithmetic of the table is unchanged |
| two passes | a BASIC `FOR pass=0 TO 2 STEP 2` loop around `[OPT pass ... ]` | `asm.s`: pass 1 and pass 2 over the text |
| forward references | BASIC variables from the previous pass | the symbol table; an undefined name is 0 in pass 1, "Out of range" is not reported in pass 1, and pass 2 checks that every label kept its address ("Phase error") |

### Decision
**Reuse ASMB.Z80's translation section** (`ASMB`, the group decoding, `FIND`, `SKIP`, `DELIM`, the
three opcode tables) and write the rest. It is the only small, complete and licensed encoder; it is
already known to run on this machine; and keeping its tables unchanged means the encodings are
Russell's long-tested ones. The adaptation (`src/asmb.s`, 1096 bytes) is marked as altered in its
header. The test `tests/insn.py` assembles all 697 official instruction forms with it, in MAME, and
compares the bytes with MAME's own disassembler: no differences.

## 4. Architecture
```
            page 1 (0x80)                                          page 2 (0x83)
 main.s   header, API table 8010, start-up, RAM trampolines,      help.s      guide viewer
          interrupt hook, G/EXIT/break, error()                   helpdata.s  index, dictionary,
 io.s     LCD + shadow screen, console, keyboard, beep, delay                  compressed pages
 text.s   source store: records, splice, load/store a line        p1calls.s   stubs to page 1
 editor.s full-screen editor, activity keys, line editing                      (putcell, GETKEY)
 cmd.s    command line, line input, monitor commands, viewers
 asm.s    line parser, two passes, directives, emit, messages  <-- asmb.s  Russell's encoder
 expr.s   expressions, symbol table, built-in names
 disasm.s disassembler
```
* **Separation**: the assembler core (`asmb.s`) only encodes one instruction; `asm.s` knows lines,
  labels, passes and memory; `expr.s` owns names and numbers; the editor only knows text; the monitor
  only knows memory. The drivers (`io.s`) are the only code that touches ports, apart from `main.s`.
* **Page 2** holds only the guide. It calls page 1 through stubs generated from the page-1 map
  (`tools/mksyms.py`), and page 1 calls it through `R_FAR`: both trampolines live in RAM, because the
  code of the page being left disappears with the `OUT`.
* **Errors** use one mechanism: `error` stores the number and the text pointer, restores SP from
  `ERRSP` and jumps to `ERRJP`. The command line, the editor and the `A` command each install a handler.

### Two pages are enough
Page 1 uses 10849 bytes and page 2 8142: about 13.5 KiB are free. A third page would need a larger
EEPROM and a board decoding another selector bit, which has not been examined. The free space is
enough for the next features (storage, a listing, macros); the guide can also take more text.

## 5. Editor
* **Storage** (`text.s`): one record per line, `[length][bytes]`, leading spaces as a count byte.
  All changes go through `splice` (replace n bytes at p by m bytes), which moves the tail of the text
  and checks the limit. The line being edited is expanded into `LBUF` and stored back when the cursor
  leaves it, only if it changed.
* **Display**: four rows; each shows a line, the current one from its sideways offset `HOFS`, the
  others from column 0. Line numbers take 4 columns. The whole screen is redrawn from the shadow
  screen after each key (80 cells, about 20 ms).
* **Indentation**: ENTER copies the indentation; after a line with something in column 0 the next one
  starts with two spaces, so that `START:` ENTER is ready for an instruction.
* **Modes**: the editor and the command line share `LBUF`; switching stores the edited line and saves
  or restores the command-line screen (`SCRSAVE`, with its cursor).

## 6. Assembler
* **Line parser** (`asmline`): a name followed by `:` is a label; `name EQU expr` or `name = expr` a
  constant; a name in column 0 that is neither a mnemonic (`FIND` on Russell's table) nor a directive
  is a label. Then statements separated by `:`, each a directive (`finddir`) or an instruction (`ASMB`
  into `OBUF`, then `emit`).
* **Passes**: pass 1 builds the symbol table after the text (`TXTEND`..`SYMEND`) and computes sizes;
  undefined names are 0 and range errors are not reported. Pass 2 evaluates everything again, writes
  the code, checks ranges, and checks that each label has its pass-1 address. `EQU` is updated in pass
  2, so a constant may be defined after its use (when that does not change a size).
* **Safety**: `emit` writes only into D000-DAFF ("Outside user RAM"), so a mistaken `ORG` cannot
  overwrite the text, the stack, EASM's variables or the firmware's RAM.
* **Errors**: the number, the line (`ASMLN`) and the column (the text pointer) are kept; the editor's
  "last error" key goes there.
* **Speed**: symbols are found by a linear search. A 552-line text assembles within the 3 s that `t07_limits` waits in MAME; this has not been timed more closely.

## 7. Monitor, disassembler and running code
* **Disassembler** (`disasm.s`): the x/y/z/p/q decomposition of the opcode, with the DD/FD
  substitutions of HL, H, L and (HL), and DD CB d op. It shows every official instruction; the
  undocumented ones are shown too, and a prefix that changes nothing is `DB $DD`. Numbers have a `$`
  so that they are not read as registers (`LD A,$DE`). `tests/opsweep.py` compares it with MAME's
  `unidasm` on every opcode after every prefix: no difference in documented opcodes.
* **G / RUN** (`rungo`): saves SP in `GOSP`, pushes a return address and jumps, with page 1 mapped and
  interrupts on. Ways back:
  * the program's `RET`: the registers are saved (`R`), SP restored;
  * `EXIT` (API 8031) from any depth: registers and the address of the CALL saved, SP restored;
  * **ANSWER**: the interrupt hook in RAM reads the keyboard column of ANSWER at each interrupt while
    `RUNNING` is set; if it is pressed it maps page 1, restores SP from `GOSP` and jumps to EASM. This
    works whenever the program leaves interrupts on.
  Afterwards EASM sets page 1, `IM 1`, `EI`, reloads its CGRAM glyphs and the caps LED.
* **What is not offered, and why**:
  * **Single step and breakpoints**: every `RST` vector and the interrupt vector are in the Genio's ROM,
    so EASM cannot place a trap instruction that comes back to it; the only maskable interrupt is the
    firmware's 46.76 Hz tick, too coarse to step instructions; whether NMI is wired is not known. A
    breakpoint can be written by hand as `CALL EXIT`.
  * **Registers after a break with ANSWER**: they are on the stack below the firmware routine's own
    pushes, in an order that has not been verified, so they are not shown.
  * **Protection against the program itself**: a program can write anywhere, disable interrupts,
    switch the cartridge page or power the unit off (port 0x12 bit 0). Only switching off and on
    recovers from a hang, and the text is lost.

## 8. Guide
The viewer is EBASIC's (an index, pages wrapped to 20 columns, a page per entry, an example per page).
`tools/gen_help.py` checks that every mnemonic of ASMB.Z80's table and every directive has an entry,
compresses the text with a 128-piece dictionary (8623 -> 5637 bytes plus an 816-byte dictionary),
and lays every page out as the viewer does, failing if one does not fit. 99 entries: 22 topics and
77 mnemonics and directives. The example of a page goes into the editor as a new line; at the command
prompt only an example that is a command is typed there (code goes to the editor), and in `A` it is
typed as the line to assemble.

## 9. Build and tests
`make` assembles the nine page-1 modules and links them at 0x8000, generates the guide data and the
page-1 stubs, links page 2, and `tools/mkcart.py` writes both images, the symbol file and the usage
report, checking the signature and that the API table is at 8010-8036.

The MAME tests (`tests/run_tests.sh`) run the cartridge headless with `tests/drive.lua`, which presses
keys on the emulated matrix and checks the shadow screen, memory and the CPU's PC:

| Test | Covers |
|---|---|
| `t00_smoke` | start-up screen, free memory, calculator |
| `t01_demo` | the demonstration program typed key by key, ASM, bytes, RUN, output, R, back to the editor |
| `t02_directives` | labels, forward references, EQU and `=`, ORG, DB/DW/DS, END entry, every operator, SYM |
| `t03_errors` | 15 error cases with line, text and message; the editor at the error, cursor column |
| `t04_editor` | split, join (both ways), DEL, long lines, line numbers, insert/delete line, activity keys, context help and its example (page 2), FIND, LINE |
| `t05_monitor` | A (with an error), D, M, E (both forms), F, C, user-RAM protection, G, R, the API, EXIT, ANSWER break |
| `t06_keys` | ASM and RUN keys, the guide from the command line (index, letters, example run as a command), NEW |
| `t07_limits` | a full text ("Text full", delete-line escape), "Symbol table full", BYE to the firmware |
| `insn.py` | 697 instruction forms: EASM's bytes and EASM's disassembly against `unidasm` |
| `opsweep.py` | every opcode after every prefix through EASM's disassembler against `unidasm` |

## 10. Interfaces for later (not implemented)
The core is complete and tested; these are designs, kept out of the ROM until there is hardware to
test them on.

### Storage driver
A table of entry points in RAM (so that a later page or a RAM-loaded driver can fill it), called with
the same conventions as the API:
```
DRV_OPEN   HL = name (0-terminated), A = 0 read / 1 write   -> carry on error, A = error
DRV_READ   DE = buffer, BC = max                             -> BC = bytes read
DRV_WRITE  DE = buffer, BC = count
DRV_CLOSE
DRV_DIR    HL = callback per name
```
* **SAVE / LOAD of sources**: the text area is already a byte image (`SRCBEG`..`TXTEND`); SAVE writes a
  small header (magic, version, length) and the records; LOAD checks the header and the length against
  `SRCLIM` and sets `TXTEND` and `NLINES`. The format is exactly what `tests/drive.lua` writes.
* **SAVE / LOAD of binaries**: `SAVEB name,from,to` and `LOADB name[,addr]`, with the header holding the
  load address and the entry point; LOADB keeps the user-RAM check.
* **Include files** would read another source through `DRV_READ` line by line in both passes; the
  line numbers of errors would then need the file too.

### Software UART on the printer port
The DB25's lines ([hardware/HARDWARE.md](https://github.com/kresp0/vtech-genio2000/blob/main/docs/hardware/HARDWARE.md), from VGLDK `printer.h`): data on
port 0x10 (the keyboard column latch), BUSY on port 0x11 bit 5, STROBE on port 0x12 bit 2. The ROM
dumper (https://github.com/kresp0/vtech-genio2000-rom-dumper) sent data at 9600 baud on DATA0 with a
timed loop ([hardware/CLOCK_AND_SOUND.md](https://github.com/kresp0/vtech-genio2000/blob/main/docs/hardware/CLOCK_AND_SOUND.md)). A two-way link could use DATA0 (TX) and BUSY (RX), with these
constraints:
* port 0x10 is shared with the keyboard scan: a transfer must run with interrupts off and the keyboard
  not scanned, and between transfers the keyboard scan leaves DATA0 low, which a UART sees as a break;
  the far side (or a transistor) must accept or invert that;
* the timing loops must be counted in T-states for 6.13 MHz (the measured clock,
  [hardware/HARDWARE.md](https://github.com/kresp0/vtech-genio2000/blob/main/docs/hardware/HARDWARE.md)) and checked on the unit.

### ESP32 as storage and link to a PC
An ESP32 on the printer port, speaking a framed protocol over the UART: `[cmd][len][data][checksum]`,
commands OPEN/READ/WRITE/CLOSE/DIR mapping onto the storage driver; files on its flash or SD; a PC
could reach the same files over Wi-Fi. Remote debugging would add PEEK/POKE/GO commands answered by a
small resident loop, using the same `EXIT` mechanism to come back.

### Macros and multi-file projects
Macros need a definition store (they could live after the symbol table in pass 1, as text) and
parameter substitution in `asmline` before `ASMB` is called; the cost is RAM, which is the scarce
resource. Libraries of routines can already be built as sources that use the API; with storage they
would be included or loaded at fixed addresses.
