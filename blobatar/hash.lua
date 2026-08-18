--- Seed hashing. A bit-exact port of `src/hash.ts`.
---
--- Two guarantees this file exists to provide, unchanged from the original:
---
--- 1. Avalanche: "alain" and "alaim" must produce visually unrelated blobatars.
---    Plain FNV-1a does not give you this; the murmur3 finalizer does.
--- 2. Streaming: the seed is hashed once, then each trait key continues from
---    that state. Trait values are therefore independent of one another, so
---    adding a trait in a later version cannot disturb existing blobatars.
---
--- Two details are load-bearing for producing the same numbers as the original
--- and are easy to miss:
---
--- * The state is seeded with the seed's **UTF-16 code unit count**, because
---   that is what `String.prototype.length` is. Not bytes, not codepoints. A
---   name with an emoji in it hashes differently if you use either of those.
--- * The bytes fed in are **UTF-8**, which for a Lua string it already is, so
---   the encode step the original needs is a no-op here.

local PREFIX = (...):match("^(.*)%.[^.]*$") or ""
local prefixed = function(name)
  return PREFIX == "" and name or (PREFIX .. "." .. name)
end

local bit32 = require(prefixed("bit32"))
local utf8x = require(prefixed("utf8x"))

local imul, bxor, rotl, rshift = bit32.imul, bit32.bxor, bit32.rotl, bit32.rshift
local byte = string.byte

local M = {}

local SEP = 0xff

--- Mixes bytes into a 32-bit state.
local function feed(h, s)
  for i = 1, #s do
    h = imul(bxor(h, byte(s, i)), 3432918353)
    h = rotl(h, 13)
  end
  return h
end

--- murmur3 fmix32: a bijection on uint32 with full avalanche.
local function finalize(h)
  h = imul(bxor(h, rshift(h, 16)), 2246822507)
  h = imul(bxor(h, rshift(h, 13)), 3266489909)
  return bxor(h, rshift(h, 16))
end

--- Normalizes a seed so that inputs a human considers equal hash equally.
---
--- NFC first, so precomposed "é" and decomposed "é" agree; then trim, then
--- lowercase. Without this, `Alain@x.com` and `alain@x.com` produce different
--- blobatars for the same person, which gets reported as a bug, every time.
function M.normalizeSeed(seed)
  return utf8x.lower(utf8x.trim(utf8x.nfc(seed)))
end

--- Hashes the seed once into a reusable state.
function M.seedState(seed, normalize)
  if normalize == nil then normalize = true end
  local s = normalize and M.normalizeSeed(seed) or seed
  return feed(bxor(1779033703, utf8x.utf16len(s)), s)
end

--- Derives one uniform float in [0, 1) for `key`, independent of every other key.
function M.stream(state, key)
  return finalize(feed(feed(state, string.char(SEP)), key)) / 4294967296
end

return M
