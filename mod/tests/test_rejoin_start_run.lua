-- luajit tests/test_rejoin_start_run.lua (run from mod/): rejoin restore really loads the saved run
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local src = io.open("ui/lobby/lobby.lua"):read("*a")
local a = src:find("local start_run_ref = G.FUNCS.start_run", 1, true)
local b = src:find("\nend\n", src:find("G.FUNCS.start_run = function", a, true), true)
local calls = {}
local function setup(viewed_back)
	calls = {}
	_G.G = { FUNCS = { start_run = function(e, args) calls[#calls + 1] = args end, exit_overlay_menu = function() end },
		GAME = { viewed_back = viewed_back } }
	_G.MP = { LOBBY = { code = "ABCDE", is_host = false, deck = { back = "Blue Deck", stake = 1 }, config = {} },
		DECK = { MAX_STAKE = 0 }, ACTIONS = { update_player_usernames = function() end }, UI = { UTILS = {} } }
	assert(loadstring(src:sub(a, b + 4)))()
end
setup(nil)
G.FUNCS.start_run(nil, { savetext = "RUN" })
ok(#calls == 1 and calls[1].savetext == "RUN", "savetext goes to the real start_run (run restored, not dropped)")
setup(nil)
local okc, err = pcall(G.FUNCS.start_run, nil, { stake = 1 })
ok(okc, "fresh profile without viewed_back: no crash (" .. tostring(err) .. ")")
ok(MP.LOBBY.deck.back == "Blue Deck", "deck falls back to the lobby deck")
print("PASS: rejoin start_run")
