--- A test runner, in the fifty lines this suite needs of one.
---
--- No dependency, because the whole point of the library is that it has none and
--- a test suite that needs busted to run is a test suite most people will not run.

local M = {}

local suites = {}
local current

function M.describe(name, fn)
  current = { name = name, tests = {} }
  suites[#suites + 1] = current
  fn()
  current = nil
end

function M.test(name, fn)
  current.tests[#current.tests + 1] = { name = name, fn = fn }
end

local function fail(msg, detail)
  error({ blobatar_test = true, msg = msg, detail = detail }, 3)
end

function M.ok(v, msg)
  if not v then fail(msg or "expected a truthy value", tostring(v)) end
end

function M.eq(a, b, msg)
  if a ~= b then
    fail(msg or "not equal", string.format("expected %s, got %s", tostring(b), tostring(a)))
  end
end

function M.near(a, b, tol, msg)
  tol = tol or 1e-9
  if not (math.abs(a - b) <= tol) then
    fail(msg or "not close enough",
         string.format("expected %.12g +/- %g, got %.12g", b, tol, a))
  end
end

function M.lt(a, b, msg)
  if not (a < b) then fail(msg or "not less than", string.format("%.12g >= %.12g", a, b)) end
end

function M.lte(a, b, msg)
  if not (a <= b) then fail(msg or "not at most", string.format("%.12g > %.12g", a, b)) end
end

function M.gt(a, b, msg)
  if not (a > b) then fail(msg or "not greater than", string.format("%.12g <= %.12g", a, b)) end
end

function M.gte(a, b, msg)
  if not (a >= b) then fail(msg or "not at least", string.format("%.12g < %.12g", a, b)) end
end

function M.matches(s, pattern, msg)
  if not tostring(s):match(pattern) then
    fail(msg or "no match", string.format("%q does not match %s", tostring(s), pattern))
  end
end

function M.run()
  local passed, failed = 0, 0
  for _, suite in ipairs(suites) do
    print(suite.name)
    for _, t in ipairs(suite.tests) do
      local ok, err = pcall(t.fn)
      if ok then
        passed = passed + 1
        print("  ok   " .. t.name)
      else
        failed = failed + 1
        print("  FAIL " .. t.name)
        if type(err) == "table" and err.blobatar_test then
          print("       " .. err.msg)
          if err.detail then print("       " .. err.detail) end
        else
          print("       " .. tostring(err))
        end
      end
    end
  end
  print(string.format("\n%d passed, %d failed", passed, failed))
  return failed
end

return M
