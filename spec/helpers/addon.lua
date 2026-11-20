-- Loads an addon from addons/<name>/ the way the game does: reads its .toc
-- and runs each listed Lua file with (addonName, namespace) as arguments.
--
--   local loadAddon = require("addon")
--   local ns = loadAddon("TwoColumnStats")                -- every file
--   local ns = loadAddon("TwoColumnStats", { "Config.lua", "Layout.lua" })

local function tocFiles(dir, name)
	local path = dir .. "/" .. name .. ".toc"
	local toc = assert(io.open(path, "r"), "can't open " .. path)
	local files = {}
	for line in toc:lines() do
		line = line:gsub("\r$", ""):match("^%s*(.-)%s*$")
		if line ~= "" and not line:match("^#") and line:match("%.lua$") then
			files[#files + 1] = line
		end
	end
	toc:close()
	return files
end

return function(name, only)
	local dir = "addons/" .. name
	local ns = {}
	for _, file in ipairs(only or tocFiles(dir, name)) do
		local chunk = assert(loadfile(dir .. "/" .. file))
		chunk(name, ns)
	end
	return ns
end
