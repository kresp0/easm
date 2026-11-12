#!/usr/bin/env python3
# Two Intel HEX files (page 1 and page 2, both linked at 0x8000) -> 32 KiB cartridge image for an AT28C256
# (page 1 in the first 16 KiB, port 0x03 = 0x80; page 2 in the second, 0x83: bit 1 drives A14 on the RevD
# board), and a 64 KiB copy for MAME, which maps selector 0x8n to offset n*16 KiB without mirroring.
# Also writes a symbol file (both linker maps) and a report of ROM and RAM use.
# Adapted from EBASIC's mkcart.py.
# Usage: mkcart.py page1.ihx page2.ihx out32.bin out64.bin page1.map page2.map out.sym usage.txt
# Copyright (C) 2026 Santiago Crespo
# SPDX-License-Identifier: GPL-3.0-or-later
import re
import sys


def page(ihx):
    img, top = bytearray(b"\xff" * 0x4000), 0x8000
    for line in open(ihx):
        n, addr, typ = int(line[1:3], 16), int(line[3:7], 16), int(line[7:9], 16)
        if typ != 0:
            continue
        if addr < 0x8000 or addr + n > 0xC000:
            sys.exit("%s: data outside the cartridge window at 0x%04X" % (ihx, addr))
        img[addr - 0x8000:addr - 0x8000 + n] = bytes.fromhex(line[9:9 + 2 * n])
        top = max(top, addr + n)
    return img, top - 0x8000


def symbols(mapfile):
    syms = {}
    for m in re.finditer(r"\b([0-9A-F]{8})\s+([A-Za-z_][A-Za-z0-9_]*)", open(mapfile).read()):
        syms.setdefault(m.group(2), int(m.group(1), 16))
    return syms


p1i, p2i, o32, o64, m1, m2, osym, orep = sys.argv[1:9]
p1, u1 = page(p1i)
p2, u2 = page(p2i)
assert p1[:4] == b"\x55\xaa\x59\x45", "missing autostart signature"
open(o32, "wb").write(p1 + p2)
open(o64, "wb").write((p1 + p2) * 2)

s1, s2 = symbols(m1), symbols(m2)
with open(osym, "w") as f:
    for tag, s in (("P1", s1), ("P2", s2)):
        for n, a in sorted(s.items(), key=lambda x: (x[1], x[0])):
            if not n.startswith(("s_", "l_", ".")):
                f.write("%04X %s %s\n" % (a, tag, n))

# RAM layout from shared.inc (equates of the form NAME = 0x.... or NAME = OTHER+n)
inc, val = open("src/shared.inc").read(), {}
for m in re.finditer(r"^([A-Z_0-9]+)\s*=\s*([^;\n]+)", inc, re.M):
    try:
        val[m.group(1)] = eval(m.group(2).strip(), {}, dict(val))
    except Exception:
        pass
vars_used = val["VARS_END"] - val["VARS"]
assert vars_used <= 256, "the variables pass their page"
rep = []
rep.append("ROM page 1 (0x80, EASM):  %5d of 16384 bytes used, %5d free" % (u1, 16384 - u1))
rep.append("ROM page 2 (0x83, guide): %5d of 16384 bytes used, %5d free" % (u2, 16384 - u2))
rep.append("RAM variables:            %5d of   256 bytes (0x%04X-0x%04X)" % (vars_used, val["VARS"], val["VARS_END"] - 1))
rep.append("RAM text + symbols:       %5d bytes (0x%04X-0x%04X)" % (val["SRCLIM"] - val["SRCBEG"], val["SRCBEG"], val["SRCLIM"] - 1))
rep.append("RAM for user code:        %5d bytes (0x%04X-0x%04X)" % (val["USREND"] + 1 - val["USRBEG"], val["USRBEG"], val["USREND"]))
assert s1["api"] == 0x8010 and s1["api_end"] == 0x8037, "the API table moved"
assert s1["EXIT"] != 0 and s1["PRINTSTR"] != 0
rep.append("API table at 0x%04X-0x%04X, entries every 3 bytes" % (s1["api"], s1["api_end"] - 1))
open(orep, "w").write("\n".join(rep) + "\n")
# RAM addresses for the MAME tests (tests/drive.lua)
with open("out/ramvars.txt", "w") as f:
    for n, v in val.items():
        if isinstance(v, int):
            f.write("%s %d\n" % (n, v))
