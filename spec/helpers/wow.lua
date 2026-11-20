-- A small, in-memory stand-in for the parts of the WoW API the addons use,
-- so their code can run under busted. Shared by every addon in the repo.
--
-- It is deliberately simple: frames and textures remember what was set on
-- them, and tests set screen rectangles explicitly (region:_SetRect) rather
-- than the mock resolving anchors.
--
--   local wow = require("wow")
--   wow.reset()                    -- fresh globals for each test
--   wow.fire("PLAYER_LOGIN")       -- deliver an event to registered frames
--   wow.runTimers()                -- run queued C_Timer.After callbacks
--   wow.printed                    -- lines passed to print()

local wow = {}

local frames, timers

---------------------------------------------------------------------------
-- Regions (shared by frames, textures and font strings)
---------------------------------------------------------------------------

local Region = {}
Region.__index = Region

local function newRegion(class, parent, name)
	return setmetatable({
		_class = class, _parent = parent, _name = name,
		_shown = true, _alpha = 1, _width = 0, _height = 0, _points = {},
	}, class)
end

function Region:GetParent() return self._parent end
function Region:GetName() return self._name end
function Region:GetDebugName() return self._name or "<anon>" end
function Region:Show() self._shown = true end
function Region:Hide() self._shown = false end
function Region:SetShown(shown) self._shown = shown and true or false end
function Region:IsShown() return self._shown end
function Region:IsVisible()
	if not self._shown then return false end
	return self._parent == nil or self._parent:IsVisible()
end
function Region:SetAlpha(a) self._alpha = a end
function Region:GetAlpha() return self._alpha end
function Region:GetEffectiveAlpha()
	return self._alpha * (self._parent and self._parent:GetEffectiveAlpha() or 1)
end
function Region:GetEffectiveScale() return self._scale or (self._parent and self._parent:GetEffectiveScale()) or 1 end
function Region:SetWidth(w) self._width = w end
function Region:SetHeight(h) self._height = h end
function Region:SetSize(w, h) self._width, self._height = w, h end
function Region:GetWidth() return self._rect and (self._rect.r - self._rect.l) or self._width end
function Region:GetHeight() return self._rect and (self._rect.t - self._rect.b) or self._height end
function Region:GetSize() return self:GetWidth(), self:GetHeight() end
function Region:SetPoint(...) self._points[#self._points + 1] = { ... } end
function Region:ClearAllPoints() self._points = {} end
function Region:GetNumPoints() return #self._points end
function Region:GetPoint(i) return unpack(self._points[i or 1] or {}) end

-- Test helper: give the region a screen rectangle.
function Region:_SetRect(l, r, t, b) self._rect = { l = l, r = r, t = t, b = b } end
function Region:GetLeft() return self._rect and self._rect.l end
function Region:GetRight() return self._rect and self._rect.r end
function Region:GetTop() return self._rect and self._rect.t end
function Region:GetBottom() return self._rect and self._rect.b end

---------------------------------------------------------------------------
-- Font strings and textures
---------------------------------------------------------------------------

local FontString = setmetatable({}, { __index = Region })
FontString.__index = FontString
function FontString:SetText(text) self._text = text end
function FontString:GetText() return self._text end

local Texture = setmetatable({}, { __index = Region })
Texture.__index = Texture

function Texture:SetTexture(file) self._texture = file; self._atlas = nil end
function Texture:GetTexture() return self._texture end
function Texture:SetAtlas(atlas) self._atlas = atlas end
function Texture:GetAtlas() return self._atlas end
-- Stored in the 4-number form; returned in the 8-number corner form, as the
-- game does.
function Texture:SetTexCoord(l, r, t, b) self._coords = { l, r, t, b } end
function Texture:GetTexCoord()
	local c = self._coords or { 0, 1, 0, 1 }
	return c[1], c[3], c[1], c[4], c[2], c[3], c[2], c[4]
end
function Texture:SetVertexColor(r, g, b, a) self._color = { r or 1, g or 1, b or 1, a or 1 } end
function Texture:GetVertexColor()
	local c = self._color or { 1, 1, 1, 1 }
	return c[1], c[2], c[3], c[4]
end
function Texture:GetDrawLayer() return self._layer or "ARTWORK", self._sublevel or 0 end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local Frame = setmetatable({}, { __index = Region })
Frame.__index = Frame

local templates = {}

-- The character sheet's stat row and category header templates.
templates.CharacterStatFrameTemplate = function(f)
	f.Label = f:CreateFontString()
	f.Value = f:CreateFontString()
	f.Background = f:CreateTexture(nil, "BACKGROUND")
end
templates.CharacterStatFrameCategoryTemplate = function(f)
	f.Title = f:CreateFontString()
	f.Background = f:CreateTexture(nil, "BACKGROUND")
end

local function newFrame(name, parent, template)
	local f = newRegion(Frame, parent, name)
	f._children, f._regions, f._scripts, f._hooks, f._events = {}, {}, {}, {}, {}
	f._level = parent and (parent._level + 1) or 0
	if parent then parent._children[#parent._children + 1] = f end
	for t in tostring(template or ""):gmatch("[^,%s]+") do
		assert(templates[t], "mock has no template " .. t)(f)
	end
	frames[#frames + 1] = f
	if name then _G[name] = f end
	return f
end

function Frame:CreateTexture(name, layer, _, sublevel)
	local t = newRegion(Texture, self, name)
	t._layer, t._sublevel = layer, sublevel
	self._regions[#self._regions + 1] = t
	return t
end
function Frame:CreateFontString(name)
	local fs = newRegion(FontString, self, name)
	self._regions[#self._regions + 1] = fs
	return fs
end
function Frame:GetRegions() return unpack(self._regions) end
function Frame:GetChildren() return unpack(self._children) end
function Frame:SetFrameLevel(level) self._level = level end
function Frame:GetFrameLevel() return self._level end
function Frame:EnableMouse(enabled) self._mouse = enabled end

function Frame:SetScript(event, fn) self._scripts[event] = fn end
function Frame:GetScript(event) return self._scripts[event] end
function Frame:HookScript(event, fn)
	self._hooks[event] = self._hooks[event] or {}
	table.insert(self._hooks[event], fn)
end
-- Test helper: run a script handler and its hooks.
function Frame:_RunScript(event, ...)
	if self._scripts[event] then self._scripts[event](self, ...) end
	for _, fn in ipairs(self._hooks[event] or {}) do fn(self, ...) end
end
-- Showing or hiding runs OnShow/OnHide, as in the game.
function Frame:Show()
	local was = self._shown
	self._shown = true
	if not was then self:_RunScript("OnShow") end
end
function Frame:Hide()
	local was = self._shown
	self._shown = false
	if was then self:_RunScript("OnHide") end
end
function Frame:SetShown(shown)
	if shown then self:Show() else self:Hide() end
end

function Frame:RegisterEvent(event) self._events[event] = true end
function Frame:RegisterUnitEvent(event) self._events[event] = true end
function Frame:UnregisterEvent(event) self._events[event] = nil end

---------------------------------------------------------------------------
-- Globals
---------------------------------------------------------------------------

-- Names of every global the mock defines, so reset() can clear leftovers
-- (including ones the addon under test created).
-- The original values are kept so globals busted itself uses (print) come back.
local defined, originals = {}, {}

local function define(name, value)
	if originals[name] == nil then originals[name] = { value = _G[name] } end
	defined[name] = true
	_G[name] = value
end

local function restore(name)
	_G[name] = originals[name] and originals[name].value
end

function wow.fire(event, ...)
	for _, f in ipairs(frames) do
		if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
	end
end

function wow.runTimers()
	local queue = timers
	timers = {}
	for _, fn in ipairs(queue) do fn() end
	return #queue
end

function wow.newFrame(name, parent, template) return newFrame(name, parent, template) end

wow.inCombat = false
wow.printed = {}

-- Clears globals from the previous test and installs fresh ones. `extra`
-- globals (a table) are added on top, for game data a test needs.
function wow.reset(extra)
	for name in pairs(defined) do restore(name) end
	for _, f in ipairs(frames or {}) do
		if f._name then _G[f._name] = nil end
	end
	defined, frames, timers = {}, {}, {}
	wow.inCombat = false
	wow.printed = {}

	define("CreateFrame", function(_, name, parent, template) return newFrame(name, parent, template) end)
	define("UIParent", newFrame(nil, nil))
	define("C_Timer", { After = function(_, fn) timers[#timers + 1] = fn end })
	define("hooksecurefunc", function(a, b, c)
		local tbl, name, hook = a, b, c
		if type(a) == "string" then tbl, name, hook = _G, a, b end
		local orig = tbl[name]
		tbl[name] = function(...)
			local results = { orig(...) }
			hook(...)
			return unpack(results)
		end
	end)
	define("GetPhysicalScreenSize", function() return 1920, 1080 end)
	define("InCombatLockdown", function() return wow.inCombat end)
	define("UnitAffectingCombat", function() return wow.inCombat end)
	define("UnitSex", function() return 2 end)
	define("print", function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		wow.printed[#wow.printed + 1] = table.concat(parts, " ")
	end)
	define("SlashCmdList", {})
	define("BreakUpLargeNumbers", function(n) return tostring(n) end)
	define("Enum", { Damageclass = { Arcane = 6, Fire = 2, Frost = 4, Nature = 3, Shadow = 5 } })
	define("DAMAGE_SCHOOL3", "Fire")
	define("DAMAGE_SCHOOL4", "Nature")
	define("DAMAGE_SCHOOL5", "Frost")
	define("DAMAGE_SCHOOL6", "Shadow")
	define("DAMAGE_SCHOOL7", "Arcane")
	define("STAT_CATEGORY_RESISTANCE", "Resistances")
	define("UnitResistance", function() return 0, 0, 0, 0 end)
	define("PaperDollFrame_SetLabelAndText", function(row, label, text)
		row.Label:SetText(label)
		row.Value:SetText(text)
	end)
	define("PaperDollFrame_SetResistanceTooltips", function() end)
	define("PaperDollFrame_FormatBonusValue", nil)
	define("PAPERDOLL_STATINFO", {})
	define("PAPERDOLL_STATCATEGORIES", {})

	for name, value in pairs(extra or {}) do define(name, value) end
end

-- Globals the addon itself is expected to create, for reset() to clear.
function wow.track(...)
	for i = 1, select("#", ...) do
		local name = select(i, ...)
		if originals[name] == nil then originals[name] = { value = _G[name] } end
		defined[name] = true
	end
end

return wow
