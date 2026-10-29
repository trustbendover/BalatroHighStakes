-- Balatro High Stakes - DEV ONLY. GPL-3.0. Real screenshots from a running instance.
-- F9 = screenshot; scenarios call shot(label). Files: <HS_DEV_CAPTURE>/<name>_<n>_<label>.png
local C = { n = 0, every_t = 0 }
local D

function C.file_name(name, n, label)
	return string.format("%s_%03d_%s.png", name, n, (tostring(label or "shot"):gsub("[^%w_%-]", "_")))
end

function C.init(d)
	D = d
	if not D.capture then return end
	local kp = love.keypressed
	love.keypressed = function(key, ...)
		if key == "f9" then C.shot("manual") end
		if kp then return kp(key, ...) end
	end
end

function C.shot(label)
	if not (D and D.capture and love.graphics and love.graphics.captureScreenshot) then return false end
	C.n = C.n + 1
	local path = D.capture .. "/" .. C.file_name(D.name, C.n, label)
	love.graphics.captureScreenshot(function(img)
		local ok, err = pcall(function()
			local fd = img:encode("png")
			local f = assert(io.open(path, "wb"))
			f:write(fd:getString()); f:close()
		end)
		D.log((ok and "screenshot " or "screenshot FAILED ") .. path .. (ok and "" or (": " .. tostring(err))))
	end)
	return path
end

function C.tick(d, dt, t)
	if d.shot_every > 0 then
		C.every_t = C.every_t + dt
		if C.every_t >= d.shot_every then C.every_t = 0; C.shot("every") end
	end
end

return C
