-- Which stats to show and how to fill a row, using the game's own stat
-- functions so values and tooltips match the default character sheet.
local _, ns = ...

local Stats = {}
ns.Stats = Stats

-- Resistances aren't in the game's stat category list, so they're added here.
-- Built on demand because the DAMAGE_SCHOOLn globals are game strings.
function Stats.Resistances()
	return {
		{ name = DAMAGE_SCHOOL7, school = "Arcane" },
		{ name = DAMAGE_SCHOOL3, school = "Fire" },
		{ name = DAMAGE_SCHOOL5, school = "Frost" },
		{ name = DAMAGE_SCHOOL4, school = "Nature" },
		{ name = DAMAGE_SCHOOL6, school = "Shadow" },
	}
end

-- In combat, Forever hides some values from addons ("secret" values).
-- They can be shown but not compared or used in arithmetic.
function Stats.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) and true or false
end

local function roleMatches(roles, role)
	for _, r in pairs(roles) do
		if r == role then return true end
	end
	return false
end

-- Same filtering rules as the default sheet.
function Stats.IsWanted(stat)
	if stat.unit and stat.unit ~= "player" then return false end
	if stat.showFunc then
		local ok, show = pcall(stat.showFunc)
		if ok and not show then return false end
	end
	if (stat.primary or stat.roles) and C_SpecializationInfo then
		local spec = C_SpecializationInfo.GetSpecialization()
		if spec then
			if stat.primary then
				local primary = select(6, C_SpecializationInfo.GetSpecializationInfo(
					spec, false, false, nil, UnitSex("player")))
				if primary and stat.primary ~= primary then return false end
			end
			if stat.roles and GetSpecializationRoleEnum
				and not roleMatches(stat.roles, GetSpecializationRoleEnum(spec)) then
				return false
			end
		end
	end
	return true
end

-- Fills a row with one stat. Returns false if the stat should be hidden
-- (unknown stat, the game's function failed or hid it, or it's at hideAt).
function Stats.Fill(row, stat)
	local info = PAPERDOLL_STATINFO and PAPERDOLL_STATINFO[stat.stat]
	if not info or not info.updateFunc then return false end
	local ok, value = pcall(info.updateFunc, row, "player", stat.id)
	if not ok or not row:IsShown() then return false end
	if value == nil then value = row.numericValue end
	if stat.hideAt ~= nil and value ~= nil and not Stats.IsSecret(value) and value == stat.hideAt then
		return false
	end
	return true
end

-- Fills a row with one resistance. Returns false if it can't be read.
function Stats.FillResistance(row, res)
	local damageClass = Enum and Enum.Damageclass and Enum.Damageclass[res.school]
	if not damageClass then return false end
	local ok, _, _, effective, bonus = pcall(UnitResistance, "player", damageClass)
	if not ok or effective == nil then return false end
	pcall(PaperDollFrame_SetResistanceTooltips, row, res.name, effective, "player", damageClass)
	local text = Stats.IsSecret(effective) and effective or BreakUpLargeNumbers(effective)
	if PaperDollFrame_FormatBonusValue and bonus ~= nil and not Stats.IsSecret(bonus) then
		text = PaperDollFrame_FormatBonusValue(text, bonus)
	end
	PaperDollFrame_SetLabelAndText(row, res.name, text, false, effective)
	return true
end

-- Builds the list of categories to show: { { title, rows = { row, ... } }, ... }.
-- acquireRow() must return a cleared, shown row; rows that end up unused are
-- hidden. Each row remembers its stat so it can be refreshed in place.
function Stats.Collect(acquireRow)
	local blocks = {}
	for _, cat in ipairs(PAPERDOLL_STATCATEGORIES or {}) do
		if cat.unit == nil or cat.unit == "player" then
			local block = { title = cat.categoryName, rows = {} }
			for _, stat in ipairs(cat.stats or {}) do
				if Stats.IsWanted(stat) then
					local row = acquireRow()
					row.statDef = stat
					if Stats.Fill(row, stat) then
						block.rows[#block.rows + 1] = row
					else
						row:Hide()
					end
				end
			end
			if #block.rows > 0 then blocks[#blocks + 1] = block end
		end
	end

	local res = { title = STAT_CATEGORY_RESISTANCE or RESISTANCE_LABEL or "Resistance", rows = {} }
	for _, r in ipairs(Stats.Resistances()) do
		local row = acquireRow()
		row.resDef = r
		if Stats.FillResistance(row, r) then
			res.rows[#res.rows + 1] = row
		else
			row:Hide()
		end
	end
	if #res.rows > 0 then blocks[#blocks + 1] = res end
	return blocks
end

-- Refreshes rows without changing the layout. Used in combat, where some
-- values are hidden from addons and asking for them throws: a row the game
-- won't update keeps showing its last value until combat ends.
function Stats.UpdateInPlace(rows)
	for _, row in ipairs(rows) do
		if row:IsShown() and (row.statDef or row.resDef) then
			local label, value = row.Label:GetText(), row.Value:GetText()
			local ok
			if row.statDef then
				ok = Stats.Fill(row, row.statDef)
			else
				local called, result = pcall(Stats.FillResistance, row, row.resDef)
				ok = called and result
			end
			if not ok or not row:IsShown() then
				row.Label:SetText(label)
				row.Value:SetText(value)
				row:Show()
			end
		end
	end
end
