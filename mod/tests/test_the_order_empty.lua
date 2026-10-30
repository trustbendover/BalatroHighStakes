-- luajit tests/test_the_order_empty.lua (run from mod/): The Order's pseudorandom_element survives an empty pool
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local src = io.open("compatibility/TheOrder.lua"):read("*a")
local a = src:find("local orig_pseudorandom_element = pseudorandom_element", 1, true)
local b = src:find("\nend\n", a, true)
local chunk = src:sub(a, b + 4)
local orig_called = 0
pseudorandom_element = function(t) orig_called = orig_called + 1; return nil end
MP = { should_use_the_order = function() return true end }
give_shufflevals = function() end
assert(loadstring(chunk))()
local okc, err = pcall(pseudorandom_element, {}, "seed")
ok(okc, "empty table does not crash (" .. tostring(err) .. ")")
ok(orig_called == 1, "falls back to the vanilla picker")
print("PASS: The Order empty pool")
