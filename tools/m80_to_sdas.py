#!/usr/bin/env python3
# Mechanical translation of R.T. Russell's BBC BASIC (Z80) sources (M80/Z80ASM syntax)
# into sdasz80 syntax. Only syntax changes; every instruction is kept as written.
# Usage: m80_to_sdas.py IN.Z80 OUT.s AREA
# Copyright (C) 2026 Santiago Crespo
# SPDX-License-Identifier: 0BSD
import re
import sys

KEEP = {"LD", "CALL", "JR", "POP", "PUSH", "CP", "INC", "EXX", "RET", "OR", "JP", "EX",
        "ADD", "DEC", "XOR", "SBC", "BIT", "AND", "SUB", "SET", "ADC", "DJNZ", "RR", "SCF",
        "RES", "RL", "CCF", "LDIR", "CPIR", "RLCA", "CPL", "RRA", "RLA", "RRCA", "NEG", "SLA",
        "DAA", "SRL", "SRA", "LDI", "LDDR", "RRD", "RLD", "OUT", "IN", "NOP", "DI", "EI",
        "RLC", "RRC", "CPDR", "CPD", "CPI", "LDD", "IM", "RETI", "RETN", "RST", "HALT",
        "OTIR", "INIR", "OUTI", "INI", "OTDR", "INDR", "OUTD", "IND"}
OPS = {"AND": " & ", "OR": " | ", "XOR": " ^ ", "SHL": " << ", "SHR": " >> ", "NOT": "~", "MOD": " % "}
NOHASH = {"JP", "JR", "CALL", "DJNZ", "RST", "IM", "BIT", "SET", "RES"}
REGS = {"A", "B", "C", "D", "E", "H", "L", "I", "R", "AF", "BC", "DE", "HL", "SP", "IX",
        "IY", "AF'", "NZ", "Z", "NC", "PO", "PE", "P", "M"}


def symbol(w):
    """Token names that clash with sdas operators/mnemonics get a prefix."""
    return "S_" + w if w.upper() in OPS else w


def split_comment(line):
    q = False
    for i, ch in enumerate(line):
        if ch == "'":
            q = not q
        elif ch == ";" and not q:
            return line[:i], line[i:]
    return line, ""


def number(tok):
    t = tok.upper()
    if re.fullmatch(r"[0-9][0-9A-F]*H", t):
        return "0x" + t[:-1]
    if re.fullmatch(r"[01]+B", t):
        return "0b" + t[:-1]
    return tok


def expr(s):
    """Translate one expression: numbers, character literals, $."""
    out, i = [], 0
    while i < len(s):
        ch = s[i]
        if ch == "'":
            j, chars = i + 1, []
            while True:
                if j >= len(s):
                    raise ValueError("unterminated literal: " + s)
                if s[j] == "'" and j + 1 < len(s) and s[j + 1] == "'":
                    chars.append("'"); j += 2
                elif s[j] == "'":
                    break
                else:
                    chars.append(s[j]); j += 1
            if len(chars) != 1:
                raise ValueError("multi-char literal in expression: " + s)
            out.append("0x%02X" % ord(chars[0])); i = j + 1
        elif ch == "$":
            out.append("."); i += 1
        elif ch.isalnum() or ch == "_":
            m = re.match(r"[A-Za-z0-9_]+", s[i:])
            w = m.group(0)
            prev = "".join(out).rstrip()
            if w.upper() in OPS and prev and (prev[-1].isalnum() or prev[-1] in ")_"):
                out.append(OPS[w.upper()])
            else:
                out.append(symbol(number(w)))
            i += len(w)
        else:
            out.append(ch); i += 1
    return "".join(out)


def split_args(s):
    args, depth, q, cur = [], 0, False, ""
    for ch in s:
        if ch == "'":
            q = not q
        if not q:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            elif ch == "," and depth == 0:
                args.append(cur.strip()); cur = ""; continue
        cur += ch
    if cur.strip():
        args.append(cur.strip())
    return args


def wrapped(a):
    """True if the whole operand is one (...) group, i.e. memory/indirect."""
    if not (a.startswith("(") and a.endswith(")")):
        return False
    depth = 0
    for i, ch in enumerate(a):
        depth += ch == "("
        depth -= ch == ")"
        if depth == 0 and i != len(a) - 1:
            return False
    return True


def operand(a, op):
    u = a.upper()
    if u == "AF_PRIME":
        return "af'"
    if u in REGS:
        return a
    if wrapped(a):
        inner = a[1:-1].strip()
        m = re.fullmatch(r"(IX|IY)\s*([+-].*)?", inner, re.I)
        if m and op == "JP":
            return a
        if m:
            off = m.group(2)
            if not off:
                return "0(%s)" % m.group(1)
            off = expr(off)
            if "(" in off:
                raise ValueError("parenthesised index offset: " + a)
            return "%s(%s)" % (off, m.group(1))
        if inner.upper() in REGS:
            return a
        return "(" + expr(inner) + ")"
    e = expr(a)
    return e if op in NOHASH else "#" + e


def data_bytes(args):
    out = []
    for a in args:
        if a.startswith("'") and a.endswith("'") and len(a) > 3 and wrapped("(" + a + ")"):
            body = a[1:-1].replace("''", "'")
            out += ["0x%02X" % ord(c) for c in body]
        else:
            out.append(expr(a))
    return out


def convert(lines, area):
    res = [".area %s" % area]
    for raw in lines:
        line = re.sub(r"(?i)(?<!')\bAF'", "AF_PRIME", raw.rstrip("\r\n"))
        code, comment = split_comment(line)
        if not code.strip():
            res.append(comment); continue
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)?(:)?\s*(.*)$", code)
        label, rest = m.group(1), m.group(3).strip()
        if label and not m.group(2) and not code[0].isspace() and not rest.upper().startswith("EQU"):
            raise ValueError("label without colon: " + line)
        parts = rest.split(None, 1)
        op = parts[0].upper() if parts else ""
        args = split_args(parts[1]) if len(parts) > 1 else []
        prefix = label + ":" if label and op != "EQU" else ""
        if op == "EQU":
            res.append("%s = %s\t%s" % (symbol(label), expr(args[0]), comment)); continue
        if op == "ORG":
            res.append("\t.org\t" + expr(args[0])); continue
        if op in ("TITLE", "END", "ASEG", "IF", "ENDIF", "ERROR"):
            res.append(prefix + "\t;" + line.strip()); continue
        if op in ("GLOBAL", "EXTRN"):
            res.append("\t.globl\t%s" % ",".join(args)); continue
        if op in ("DEFB", "DEFM"):
            body = "\t.db\t" + ", ".join(data_bytes(args)) if args else ""
            res.append(prefix + body + "\t" + comment); continue
        if op == "DEFW":
            res.append(prefix + "\t.dw\t" + ", ".join(expr(a) for a in args) + "\t" + comment); continue
        if op == "DEFS":
            res.append(prefix + "\t.ds\t" + expr(args[0]) + "\t" + comment); continue
        if op == "":
            res.append(prefix + "\t" + comment); continue
        if op not in KEEP:
            raise ValueError("unknown op %s: %s" % (op, line))
        ops = ", ".join(operand(a, op) for a in args)
        res.append("%s\t%s\t%s\t%s" % (prefix, op.lower(), ops, comment))
    return "\n".join(res) + "\n"


if __name__ == "__main__":
    src, dst, area = sys.argv[1:4]
    with open(src, encoding="latin-1") as f:
        text = convert(f.readlines(), area)
    with open(dst, "w") as f:
        f.write("; Generated by m80_to_sdas.py from %s (BBC BASIC (Z80) by R.T. Russell, zlib licence).\n" % src.split("/")[-1])
        f.write("; Altered source: syntax converted for sdasz80%s. Do not edit; edit the generator.\n"
                % (" and banner changed (see the Makefile)" if src.startswith("out/") else ""))
        f.write(text)
