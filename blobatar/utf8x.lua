--- UTF-8, and the three string operations `normalizeSeed` is made of.
---
--- The library's determinism guarantee is that a human-equal name is a hash-equal
--- name, and it buys that with NFC + trim + lowercase before hashing. All three
--- are Unicode operations that the JavaScript original gets from the engine for
--- free. Lua has no engine to ask, so they are here.
---
--- Nothing in this file is loaded eagerly. `blobatar/unicodedata.lua` is required
--- and parsed on the first non-ASCII seed and never for a name that is plain
--- ASCII, which is what almost every name is.

local PREFIX = (...):match("^(.*)%.[^.]*$") or ""
local prefixed = function(name)
  return PREFIX == "" and name or (PREFIX .. "." .. name)
end

local M = {}

local floor = math.floor
local char = string.char
local byte = string.byte
local concat = table.concat

----------------------------------------------------------------------
-- Encoding
----------------------------------------------------------------------

--- Decodes UTF-8 into an array of codepoints.
---
--- Invalid bytes are passed through as their own value rather than raising.
--- A seed is a name, and a name that arrived slightly malformed should still
--- render somebody an avatar.
function M.decode(s)
  local out, n = {}, 0
  local i, len = 1, #s
  while i <= len do
    local c = byte(s, i)
    local cp, size
    if c < 0x80 then
      cp, size = c, 1
    elseif c < 0xC0 then
      cp, size = c, 1 -- stray continuation byte
    elseif c < 0xE0 then
      cp, size = c - 0xC0, 2
    elseif c < 0xF0 then
      cp, size = c - 0xE0, 3
    elseif c < 0xF8 then
      cp, size = c - 0xF0, 4
    else
      cp, size = c, 1
    end
    if size > 1 then
      if i + size - 1 > len then
        cp, size = c, 1
      else
        local ok = true
        local v = cp
        for k = 1, size - 1 do
          local b = byte(s, i + k)
          if b < 0x80 or b > 0xBF then
            ok = false
            break
          end
          v = v * 64 + (b - 0x80)
        end
        if ok then cp = v else cp, size = c, 1 end
      end
    end
    n = n + 1
    out[n] = cp
    i = i + size
  end
  return out, n
end

--- Codepoints back to UTF-8.
function M.encode(cps, n)
  local out = {}
  for i = 1, n or #cps do
    local cp = cps[i]
    if cp < 0x80 then
      out[i] = char(cp)
    elseif cp < 0x800 then
      out[i] = char(0xC0 + floor(cp / 64), 0x80 + cp % 64)
    elseif cp < 0x10000 then
      out[i] = char(0xE0 + floor(cp / 4096), 0x80 + floor(cp / 64) % 64,
                    0x80 + cp % 64)
    else
      out[i] = char(0xF0 + floor(cp / 262144), 0x80 + floor(cp / 4096) % 64,
                    0x80 + floor(cp / 64) % 64, 0x80 + cp % 64)
    end
  end
  return concat(out)
end

--- The UTF-16 code unit count of a UTF-8 string.
---
--- This exists for one line in `hash.lua`: the original seeds its state with
--- `s.length`, and a JavaScript string's length is its UTF-16 unit count. Not
--- its byte count and not its codepoint count. An emoji counts 2. Getting this
--- wrong changes every hash for every seed outside the BMP and for none inside
--- it, so it fails silently on exactly the inputs nobody tests with.
function M.utf16len(s)
  local n = 0
  for i = 1, #s do
    local b = byte(s, i)
    -- Every byte that is not a continuation byte starts a codepoint, and every
    -- 4-byte sequence is a surrogate pair on the other side.
    if b < 0x80 or b >= 0xC0 then n = n + 1 end
    if b >= 0xF0 and b < 0xF8 then n = n + 1 end
  end
  return n
end

--- True when the string is entirely ASCII, which is the fast path for all three
--- operations below and the case that covers essentially every email and handle.
function M.isascii(s)
  return not s:find("[\128-\255]")
end

----------------------------------------------------------------------
-- Unicode tables, parsed on first use
----------------------------------------------------------------------

local U -- { lower = {}, lowerx = {}, ccc = {}, decomp = {}, comp = {} }

local function parse()
  if U then return U end
  local ok, raw = pcall(require, prefixed("unicodedata"))
  if not ok or type(raw) ~= "table" then
    -- Absent by choice, in a build that dropped it. ASCII still normalizes.
    U = { lower = {}, lowerx = {}, ccc = {}, decomp = {}, comp = {}, absent = true }
    return U
  end

  local lower, ccc, decomp, comp, lowerx = {}, {}, {}, {}, {}
  local cased, ignorable = {}, {}

  for s, n, stride, d in raw.lower:gmatch("(%x+):(%x+):(%x+):(%-?%x+)") do
    local start = tonumber(s, 16)
    local count = tonumber(n, 16)
    local step = tonumber(stride, 16)
    local delta = d:sub(1, 1) == "-" and -tonumber(d:sub(2), 16) or tonumber(d, 16)
    for k = 0, count - 1 do
      lower[start + k * step] = start + k * step + delta
    end
  end

  for cp, list in raw.lowerx:gmatch("(%x+):([%x,]+)") do
    local seq = {}
    for v in list:gmatch("%x+") do seq[#seq + 1] = tonumber(v, 16) end
    lowerx[tonumber(cp, 16)] = seq
  end

  for s, n, v in raw.ccc:gmatch("(%x+):(%x+):(%x+)") do
    local start = tonumber(s, 16)
    local count = tonumber(n, 16)
    local value = tonumber(v, 16)
    for k = 0, count - 1 do ccc[start + k] = value end
  end

  for rec in raw.decomp:gmatch("%S+") do
    local cp, a, b = rec:match("^(%x+):(%x+):?(%x*)$")
    if cp then
      decomp[tonumber(cp, 16)] =
        b ~= "" and { tonumber(a, 16), tonumber(b, 16) } or { tonumber(a, 16) }
    end
  end

  for s, n in (raw.cased or ""):gmatch("(%x+):(%x+)") do
    local start, count = tonumber(s, 16), tonumber(n, 16)
    for k = 0, count - 1 do cased[start + k] = true end
  end

  for s, n in (raw.ignorable or ""):gmatch("(%x+):(%x+)") do
    local start, count = tonumber(s, 16), tonumber(n, 16)
    for k = 0, count - 1 do ignorable[start + k] = true end
  end

  for a, b, cp in raw.comp:gmatch("(%x+):(%x+):(%x+)") do
    local first = tonumber(a, 16)
    local row = comp[first]
    if not row then
      row = {}
      comp[first] = row
    end
    row[tonumber(b, 16)] = tonumber(cp, 16)
  end

  U = {
    lower = lower, lowerx = lowerx, ccc = ccc, decomp = decomp, comp = comp,
    cased = cased, ignorable = ignorable,
  }
  return U
end

M._tables = parse

----------------------------------------------------------------------
-- Hangul, which is algorithmic rather than tabulated
----------------------------------------------------------------------

local SBASE, LBASE, VBASE, TBASE = 0xAC00, 0x1100, 0x1161, 0x11A7
local LCOUNT, VCOUNT, TCOUNT = 19, 21, 28
local NCOUNT = VCOUNT * TCOUNT -- 588
local SCOUNT = LCOUNT * NCOUNT -- 11172

----------------------------------------------------------------------
-- NFC
----------------------------------------------------------------------

local function ccc_of(cp)
  return U.ccc[cp] or 0
end

--- Canonical decomposition, applied until nothing decomposes further.
local function decompose(cps, n)
  local out, m = {}, 0
  local function emit(cp)
    local d = U.decomp[cp]
    if d then
      for i = 1, #d do emit(d[i]) end
      return
    end
    if cp >= SBASE and cp < SBASE + SCOUNT then
      local si = cp - SBASE
      m = m + 1; out[m] = LBASE + floor(si / NCOUNT)
      m = m + 1; out[m] = VBASE + floor((si % NCOUNT) / TCOUNT)
      local t = si % TCOUNT
      if t ~= 0 then m = m + 1; out[m] = TBASE + t end
      return
    end
    m = m + 1
    out[m] = cp
  end
  for i = 1, n do emit(cps[i]) end
  return out, m
end

--- Canonical ordering: an insertion sort by combining class, which is stable
--- and is what the algorithm calls for. Runs of non-starters are short, so the
--- quadratic worst case never arrives.
local function reorder(cps, n)
  for i = 2, n do
    local c = ccc_of(cps[i])
    if c ~= 0 then
      local j = i
      while j > 1 do
        local prev = ccc_of(cps[j - 1])
        if prev <= c or prev == 0 then break end
        cps[j], cps[j - 1] = cps[j - 1], cps[j]
        j = j - 1
      end
    end
  end
end

local function compose_pair(a, b)
  -- Hangul first: L + V and LV + T are rules rather than table entries.
  if a >= LBASE and a < LBASE + LCOUNT and b >= VBASE and b < VBASE + VCOUNT then
    return SBASE + ((a - LBASE) * VCOUNT + (b - VBASE)) * TCOUNT
  end
  if a >= SBASE and a < SBASE + SCOUNT and (a - SBASE) % TCOUNT == 0
     and b > TBASE and b < TBASE + TCOUNT then
    return a + (b - TBASE)
  end
  local row = U.comp[a]
  return row and row[b] or nil
end

--- Canonical composition (UAX #15). Walks the decomposed string keeping the
--- most recent starter, and folds each following character into it when nothing
--- of equal or higher class blocks the pair.
local function compose(cps, n)
  if n == 0 then return cps, 0 end
  local out = { cps[1] }
  local m = 1
  local starter = 1
  local lastClass = ccc_of(cps[1])
  if lastClass ~= 0 then lastClass = 256 end

  for i = 2, n do
    local ch = cps[i]
    local chClass = ccc_of(ch)
    local composite = compose_pair(out[starter], ch)
    if composite and (lastClass < chClass or lastClass == 0) then
      out[starter] = composite
    else
      if chClass == 0 then starter = m + 1 end
      lastClass = chClass
      m = m + 1
      out[m] = ch
    end
  end
  return out, m
end

--- NFC. ASCII is already NFC, so it returns immediately.
function M.nfc(s)
  if M.isascii(s) then return s end
  parse()
  if U.absent then return s end
  local cps, n = M.decode(s)
  local d, dn = decompose(cps, n)
  reorder(d, dn)
  local c, cn = compose(d, dn)
  return M.encode(c, cn)
end

----------------------------------------------------------------------
-- Case and whitespace
----------------------------------------------------------------------

local SIGMA, SIGMA_SMALL, SIGMA_FINAL = 0x3A3, 0x3C3, 0x3C2

--- The Final_Sigma condition: a capital sigma is preceded by a cased letter,
--- possibly across case-ignorable characters, and is not followed by one.
---
--- The only context-sensitive rule `toLowerCase` applies without a locale, and
--- the reason Σ in "ΟΔΟΣ" lowercases to ς while the one in "ΣΟΦΙΑ" does not.
--- Both scans test Cased before Case_Ignorable, which is what makes a
--- character that is both (the modifier letters are) resolve the way the
--- property's regular expression resolves it.
local function final_sigma(cps, n, i)
  local before = false
  for k = i - 1, 1, -1 do
    local cp = cps[k]
    if U.cased[cp] then
      before = true
      break
    elseif not U.ignorable[cp] then
      break
    end
  end
  if not before then return false end
  for k = i + 1, n do
    local cp = cps[k]
    if U.cased[cp] then
      return false
    elseif not U.ignorable[cp] then
      break
    end
  end
  return true
end

--- Full Unicode lowercase, matching `String.prototype.toLowerCase`.
function M.lower(s)
  if M.isascii(s) then return (s:gsub("%u", string.lower)) end
  parse()
  if U.absent then return (s:gsub("%u", string.lower)) end
  local cps, n = M.decode(s)
  local out, m = {}, 0
  for i = 1, n do
    local cp = cps[i]
    local x = U.lowerx[cp]
    if x then
      for k = 1, #x do
        m = m + 1
        out[m] = x[k]
      end
    elseif cp == SIGMA then
      m = m + 1
      out[m] = final_sigma(cps, n, i) and SIGMA_FINAL or SIGMA_SMALL
    else
      m = m + 1
      out[m] = U.lower[cp] or cp
    end
  end
  return M.encode(out, m)
end

--- The whitespace `String.prototype.trim` removes: WhiteSpace plus
--- LineTerminator, which is more than `%s` and is why this is a table.
local SPACE = {
  [0x09] = true, [0x0A] = true, [0x0B] = true, [0x0C] = true, [0x0D] = true,
  [0x20] = true, [0xA0] = true, [0x1680] = true, [0x2000] = true,
  [0x2001] = true, [0x2002] = true, [0x2003] = true, [0x2004] = true,
  [0x2005] = true, [0x2006] = true, [0x2007] = true, [0x2008] = true,
  [0x2009] = true, [0x200A] = true, [0x2028] = true, [0x2029] = true,
  [0x202F] = true, [0x205F] = true, [0x3000] = true, [0xFEFF] = true,
}

function M.trim(s)
  if M.isascii(s) then return (s:gsub("^[ \t\n\v\f\r]+", ""):gsub("[ \t\n\v\f\r]+$", "")) end
  local cps, n = M.decode(s)
  local i, j = 1, n
  while i <= j and SPACE[cps[i]] do i = i + 1 end
  while j >= i and SPACE[cps[j]] do j = j - 1 end
  if i == 1 and j == n then return s end
  local out = {}
  for k = i, j do out[k - i + 1] = cps[k] end
  return M.encode(out, j - i + 1)
end

return M
