-- Drives the EASM cartridge in headless MAME: types on the emulated key matrix, checks the 4x20 shadow
-- screen and memory, and can load a source text straight into RAM. Adapted from EBASIC's drive.lua.
-- env: EA_SCRIPT = script, EA_LOG = log, EA_VARS = RAM addresses (out/ramvars.txt), EA_DIR = tests dir.
-- Script lines:
--   wait <s> | type <text> | press <field>[+<field>] | hold <field> <s> | dump [tag] | snap | quit
--   peek <hex addr> <n>                 log n bytes
--   expect <row> <text>                 row 0-3 of the screen, trailing spaces ignored ("*" = anything after)
--   expectmem <hex addr> <hex bytes...> memory contents
--   load <file>                         the text of <file> becomes the source (at the command line)
--   loadbin <file> <hex addr>           the bytes of <file> into memory
--   expectpc <hex lo>-<hex hi>          the CPU's PC is in that range
--   fields                              log the names of the input fields
-- In "type": \n ENTER, \e ANSWER, \b DELETE, \x DEL, \u \d up/down, \l \r LEFT/RIGHT, \[ \] start/end, \h HELP.
-- Copyright (C) 2026 Santiago Crespo
-- SPDX-License-Identifier: GPL-3.0-or-later
local machine = manager.machine
local mem = machine.devices[":maincpu"].spaces["program"]
local out = io.open(os.getenv("EA_LOG") or "drive.log", "w")
out:setvbuf("line")
local HOLD, GAP = tonumber(os.getenv("EA_HOLD") or "0.05"), tonumber(os.getenv("EA_GAP") or "0.05")
local V = {}
for l in io.lines(os.getenv("EA_VARS")) do
  local n, v = string.match(l, "^(%S+) (%d+)$")
  if n then V[n] = tonumber(v) end
end
local SCR = V.SCR
local npass, nfail = 0, 0

local fields = {}
for _, port in pairs(machine.ioport.ports) do
  for name, f in pairs(port.fields) do fields[name] = f end
end

local SH, AL = "MAYUSCULAS (der.)", "ALT"
local keys = {[" "] = {"ESPACIO"}, ["\n"] = {"INTRO"}, ["\27"] = {"RESPUESTA"}, ["\8"] = {"REPETIR / BORRAR"},
  ["\127"] = {"JUGADOR DERECHA / DEL"}, ["\1"] = {AL, "Ü"}, ["\2"] = {AL, ";"}, ["\3"] = {"RETROCESO"},
  ["\4"] = {"AVANCE"}, ["\5"] = {"AYUDA"}, ["\6"] = {AL, "RETROCESO"}, ["\7"] = {AL, "AVANCE"},
  [","] = {","}, ["."] = {"."}, [";"] = {";"}, ["'"] = {"'"}, ["^"] = {"PAUSA"},
  ["#"] = {SH, "3"}, ["$"] = {SH, "4"}, ["%"] = {SH, "5"}, ["/"] = {SH, "6"}, ["&"] = {SH, "7"},
  ["*"] = {SH, "8"}, ["("] = {SH, "9"}, [")"] = {SH, "0"}, ["?"] = {SH, ","}, ["!"] = {SH, "."},
  ['"'] = {SH, "'"}, [":"] = {SH, ";"}, ["<"] = {SH, "RETROCESO"}, [">"] = {SH, "AVANCE"},
  ["\\"] = {AL, "1"}, ["@"] = {AL, "2"}, ["-"] = {AL, "3"}, ["_"] = {AL, "4"}, ["+"] = {AL, "5"},
  ["["] = {AL, "6"}, ["]"] = {AL, "7"}, ["="] = {AL, "8"}, ["|"] = {AL, "9"}, ["~"] = {AL, "0"}}
for c = 0, 9 do keys[tostring(c)] = {tostring(c)} end
for c = 65, 90 do
  local ch = string.char(c)
  keys[ch] = {ch}                         -- caps lock is on after start-up
  keys[string.lower(ch)] = {SH, ch}
end

local lines = {}
for l in io.lines(os.getenv("EA_SCRIPT")) do lines[#lines + 1] = l end

local function row(r)
  local s = ""
  for c = 0, 19 do
    local b = mem:read_u8(SCR + r * 20 + c)
    s = s .. ((b >= 32 and b < 127) and string.char(b) or string.format("{%02X}", b))
  end
  return s
end

local queue, held, t_next, li = {}, nil, 0, 1
local function dump(tag)
  out:write(string.format("--- %s t=%.2f\n", tag or "screen", machine.time:as_double()))
  for r = 0, 3 do out:write("|" .. row(r) .. "|\n") end
end

local function result(ok, what)
  if ok then npass = npass + 1 else nfail = nfail + 1 end
  out:write((ok and "PASS " or "FAIL ") .. what .. "\n")
  if not ok then dump("at failure") end
end

-- The text of a file as EASM's source records: [length][count of leading spaces][rest]
local function load(file)
  local a, n = V.SRCBEG, 0
  for l in io.lines(EA_DIR .. "/" .. file) do
    local sp = #(string.match(l, "^ *"))
    local rest = string.sub(l, sp + 1)
    local rec = {}
    while sp > 0 do
      local k = math.min(sp, 31)
      if #rec > 0 then for _ = 1, k do rec[#rec + 1] = 32 end else rec[#rec + 1] = k end
      sp = sp - k
    end
    for i = 1, #rest do rec[#rec + 1] = string.byte(rest, i) end
    mem:write_u8(a, #rec); a = a + 1
    for _, b in ipairs(rec) do mem:write_u8(a, b); a = a + 1 end
    n = n + 1
  end
  if n == 0 then mem:write_u8(a, 0); a = a + 1; n = 1 end
  assert(a < V.SRCLIM, "source too long for EASM's text area")
  mem:write_u16(V.TXTEND, a); mem:write_u16(V.NLINES, n)
  mem:write_u16(V.CURL, 0); mem:write_u16(V.TOPL, 0)
  mem:write_u8(V.SYMOK, 0); mem:write_u8(V.MODIF, 0)
  out:write(string.format("loaded %s: %d lines, %d bytes\n", file, n, a - V.SRCBEG))
end
EA_DIR = os.getenv("EA_DIR") or "."

local esc = {n = "\n", e = "\27", b = "\8", x = "\127", u = "\1", d = "\2", l = "\3", r = "\4", h = "\5",
  ["["] = "\6", ["]"] = "\7"}
local function step(t)
  local l = lines[li]; li = li + 1
  if not l then out:write(string.format("RESULT pass=%d fail=%d\n", npass, nfail)); out:close(); machine:exit() return end
  local cmd, arg = string.match(l, "^(%S+)%s?(.*)$")
  if not cmd then return end
  if cmd == "wait" then t_next = t + tonumber(arg)
  elseif cmd == "type" then
    arg = arg:gsub("\\(.)", function(c) return esc[c] or c end)
    for _, cp in utf8.codes(arg) do
      local ch = utf8.char(cp)
      local k = keys[ch]
      if not k then out:write("NO KEY FOR " .. ch .. "\n") else queue[#queue + 1] = {table.unpack(k)} end
    end
  elseif cmd == "press" then
    local k = {}
    for n in string.gmatch(arg, "[^+]+") do k[#k + 1] = n end
    queue[#queue + 1] = k
  elseif cmd == "hold" then
    local n, s = string.match(arg, "^(.-)%s+([%d%.]+)$")
    queue[#queue + 1] = {n, dur = tonumber(s)}
  elseif cmd == "dump" then dump(arg)
  elseif cmd == "snap" then machine.video:snapshot(); out:write(string.format("snap t=%.2f\n", t))
  elseif cmd == "peek" then
    local a, n = string.match(arg, "^(%x+)%s+(%d+)$")
    local s = ""
    for i = 0, tonumber(n) - 1 do s = s .. string.format("%02X ", mem:read_u8(tonumber(a, 16) + i)) end
    out:write(string.format("peek %s t=%.2f: %s\n", a, t, s))
  elseif cmd == "expect" then
    local r, text = string.match(arg, "^(%d)%s?(.*)$")
    local got = row(tonumber(r)):gsub("%s+$", "")
    local ok
    if text:sub(-1) == "*" then ok = got:sub(1, #text - 1) == text:sub(1, -2)
    else ok = got == text:gsub("%s+$", "") end
    result(ok, string.format("row %s = [%s] (got [%s])", r, text, got))
  elseif cmd == "expectmem" then
    local a, rest = string.match(arg, "^(%x+)%s+(.*)$")
    a = tonumber(a, 16)
    local ok, got = true, ""
    local i = 0
    for h in string.gmatch(rest, "%x%x") do
      local b = mem:read_u8(a + i)
      got = got .. string.format("%02X ", b)
      if b ~= tonumber(h, 16) then ok = false end
      i = i + 1
    end
    result(ok, string.format("mem %04X = %s (got %s)", a, rest, got))
  elseif cmd == "load" then load(arg)
  elseif cmd == "expectpc" then
    -- the CPU's PC is in the range lo-hi (hex)
    local lo, hi = string.match(arg, "^(%x+)-(%x+)$")
    local pc = machine.devices[":maincpu"].state["PC"].value
    result(pc >= tonumber(lo, 16) and pc <= tonumber(hi, 16), string.format("PC in %s (got %04X)", arg, pc))
  elseif cmd == "loadbin" then
    local f, a = string.match(arg, "^(%S+)%s+(%x+)$")
    local data = io.open(EA_DIR .. "/" .. f, "rb"):read("a")
    a = tonumber(a, 16)
    for i = 1, #data do mem:write_u8(a + i - 1, string.byte(data, i)) end
    out:write(string.format("loadbin %s: %d bytes at %04X\n", f, #data, a))
  elseif cmd == "fields" then
    local names = {}
    for n in pairs(fields) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do out:write("field [" .. n .. "]\n") end
  elseif cmd == "quit" then
    out:write(string.format("RESULT pass=%d fail=%d\n", npass, nfail)); out:close(); machine:exit()
  elseif cmd ~= "#" then out:write("BAD LINE " .. l .. "\n") end
end

emu.register_frame_done(function()
  local t = machine.time:as_double()
  if t < t_next then return end
  if held then
    for _, n in ipairs(held) do if fields[n] then fields[n]:set_value(0) end end
    held = nil; t_next = t + GAP; return
  end
  if #queue > 0 then
    -- modifiers go down one step before the key, as a person presses them
    local k = queue[1]
    k.n = (k.n or 0) + 1
    local n = k[k.n]
    if not fields[n] then out:write("MISSING FIELD " .. n .. "\n") else fields[n]:set_value(1) end
    if k.n < #k then t_next = t + 0.02; return end
    table.remove(queue, 1)
    held = k; t_next = t + (k.dur or HOLD); return
  end
  step(t)
end)
