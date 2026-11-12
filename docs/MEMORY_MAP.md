# EASM memory map

The hardware facts are the ones EBASIC measured or took from the firmware; EASM adds none. The
numbers of EASM's own use come from `out/usage.txt` (written by `make`) and `src/shared.inc`.

## CPU address space
| Range | What | Source |
|---|---|---|
| 0000-3FFF | Genio ROM bank 0: reset, `RST` vectors, the IM 1 interrupt routine (0038 -> 0119) | firmware |
| 4000-7FFF | Genio ROM, banked by port 0x01 | firmware |
| 8000-BFFF | cartridge window, page chosen by port 0x03 | cartridge |
| C000-DFFF | RAM, 8 KiB (not kept when the unit is off) | hardware |
| E000-FFFF | not used (a mirror of the RAM on the unit; unmapped in MAME) | |

## Cartridge pages (port 0x03)
| Value | Page | Contents | Used |
|---|---|---|---|
| 0x80 | 1 (EEPROM 0x0000-0x3FFF) | EASM: header, API table, drivers, editor, command line, assembler, monitor, disassembler | 10780 of 16384 bytes |
| 0x83 | 2 (EEPROM 0x4000-0x7FFF) | the guide: viewer and compressed text | 8142 of 16384 bytes |

Bit 1 of the selector drives A14 on the RevD board with an AT28C256 (measured by EBASIC); MAME
decodes bit 0, so 0x83 selects the second half on both. EASM uses two pages: a third page would need
a larger EEPROM and a board that decodes another selector bit, which has not been examined. Page 1 is
mapped at all times except while the guide runs, which reaches page 1 through stubs in RAM.

### Page 1 layout
| Address | |
|---|---|
| 8000-8003 | autostart signature `55 AA 59 45` |
| 8004 | `JP cold` (the firmware jumps here) |
| 8007-800F | `"EASM 1.0 "` |
| **8010-8036** | **the API table**, 13 `JP` entries, 3 bytes apart (fixed; `tools/mkcart.py` checks it) |
| 8037- | code and tables (`out/page1.map`) |

| API | Address | | API | Address |
|---|---|---|---|---|
| PRINTSTR | 8010 | | PRHEX16 | 8025 |
| PUTCHAR | 8013 | | PRDEC | 8028 |
| GETKEY | 8016 | | BEEP | 802B |
| KEYPOLL | 8019 | | DELAY | 802E |
| CLS | 801C | | EXIT | 8031 |
| SETCUR | 801F | | NEWLINE | 8034 |
| PRHEX8 | 8022 | | | |

### Page 2 layout
| Address | |
|---|---|
| 8000 | jump table: slot 0 = `help` (called from page 1 through `R_FAR`) |
| 8003- | the guide's viewer, then `out/helpdata.s`: the index, the 128-piece dictionary, the pages |

## RAM
| Range | Size | Use |
|---|---|---|
| C000-C0FF | 256 | `LBUF`: the line being edited (editor and command line); page aligned |
| C100-C1F8 | 249 of 256 | variables (`src/shared.inc`): shadow screen `SCR` (C100-C14F), cursor, keyboard, editor, assembler, monitor, guide |
| C200-C2FF | 256 | `WBUF`: the line being assembled, a page of the guide; `ROWBUF` (C280) builds viewer screens |
| C300-C37F | 128 | `RAMCODE`: page trampolines and the interrupt hook, copied from page 1 at start-up |
| C380-C3CF | 80 | `SCRSAVE`: the command-line screen while the editor, a viewer or the guide covers it |
| C3D0-C3F7 | 40 | `HLINES`: start and end of each line of a guide page |
| C400-C4FF | 256 | the stack (SP starts at C500), shared with user programs |
| C500-CFFF | 2816 | the source text, then (during and after ASM) the symbol table |
| **D000-DAFF** | **2816** | **user RAM**: the only memory EASM writes code or data into (`USERRAM`-`USEREND`) |
| DB00-DFFF | 1280 | the firmware's: its interrupt routine's variables (DB00, DB01, DCF0-DCF7) and the hook at DFF5 |

### Source text (C500-TXTEND)
One record per line: `[length][bytes]`. If the line starts with spaces, the first byte is their count
(1-31). There is always at least one line. Example: `  LD A,1` is `07 02 4C 44 20 41 2C 31`.

### Symbol table (TXTEND-SYMEND)
`[name length][name, upper case][value low][value high]`, built by pass 1 right after the text and
valid until the text changes. The built-in names are a table of the same format in page 1.

## I/O ports used
| Port | Use in EASM |
|---|---|
| 0x03 (W) | cartridge page: 0x80 / 0x83 |
| 0x0A / 0x0B (W) | HD44780 command / data (about 70 µs per write, no busy-flag read) |
| 0x10 (W) | keyboard column (also the printer data lines on the DB25) |
| 0x10, 0x11 (R) | keyboard rows; 0x11 bits 0-4 the activity panel, bit 1 of column 7 OFF |
| 0x12 (W) | bit 3 speaker, bit 5 caps LED, bit 0 power off (written only by OFF) |

## Firmware state that EASM relies on
At start-up EASM enables interrupts only if 0038 is `JP 0119` and the hook at DFF5 is 0033, as EBASIC
does. It then sets DB00 = D0 (the routine skips its keyboard scan and idle power-off), DB01 = FF (with
DB00 = D0 the routine would power off if DB01 were B4, the value it has on the real unit), clears
DCF0-DCF7 and installs its hook. The routine draws EASM's cursor (DCF4-DCF7). The hook, in RAM,
checks ANSWER while a program runs. `BYE` puts DB00 = C0 back and jumps to 0030.
