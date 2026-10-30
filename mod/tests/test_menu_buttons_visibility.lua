-- luajit tests/test_menu_buttons_visibility.lua (run from mod/): Patch notes / Report a bug only on the loaded home menu
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local src = io.open("lib/patch_notes.lua"):read("*a")
local chunk = src:match("(PN%.MENU_BUTTONS_DELAY = .-\nend\n)")
PN = {}
local f = assert(load("local PN = ...; " .. chunk))
f(PN)
local base = { main_menu = true, in_lobby = false, in_run = false, overlay = false, menu_age = 3 }
local function env(o) local e = {} for k, v in pairs(base) do e[k] = v end for k, v in pairs(o or {}) do e[k] = v end return e end
ok(PN.menu_buttons_visible(env()) == true, "home menu, loaded: shown")
ok(PN.menu_buttons_visible(env({ menu_age = 0.2 })) == false, "still loading / intro: hidden")
ok(PN.menu_buttons_visible(env({ main_menu = false })) == false, "splash / not main menu: hidden")
ok(PN.menu_buttons_visible(env({ in_lobby = true })) == false, "lobby screen: hidden")
ok(PN.menu_buttons_visible(env({ in_run = true, main_menu = false })) == false, "run / match: hidden")
ok(PN.menu_buttons_visible(env({ overlay = true })) == false, "other menu open: hidden")
ok(src:find("pcall(PN.update_menu_buttons)", 1, true), "tick shows/hides them every frame")
ok(src:find("if not PN.menu_buttons_visible() then return PN.remove_menu_buttons() end", 1, true), "add_menu_button refuses outside the home menu (lobby re-place calls included)")
ok(io.open("lib/bug_report.lua"):read("*a"):find("menu_buttons_visible", 1, true), "bug report button follows the same rule")
print("PASS: menu buttons visibility")
