local wow = require("wow")
local loadAddon = require("addon")

-- A stat row like the game's template, made with the mock.
local function newRow()
	return wow.newFrame(nil, nil, "CharacterStatFrameTemplate")
end

-- A stat definition plus a PAPERDOLL_STATINFO entry that writes `value`.
local function defineStat(key, value, opts)
	opts = opts or {}
	PAPERDOLL_STATINFO[key] = {
		updateFunc = opts.updateFunc or function(row)
			row.Label:SetText(key)
			row.Value:SetText(tostring(value))
			return value
		end,
	}
	local stat = { stat = key }
	for k, v in pairs(opts.stat or {}) do stat[k] = v end
	return stat
end

describe("Stats", function()
	local Stats

	before_each(function()
		wow.reset()
		Stats = loadAddon("TwoColumnStats", { "Config.lua", "Layout.lua", "Stats.lua" }).Stats
	end)

	describe("IsWanted", function()
		it("keeps a plain stat", function()
			assert.is_true(Stats.IsWanted({ stat = "X" }))
		end)

		it("skips pet stats", function()
			assert.is_false(Stats.IsWanted({ stat = "X", unit = "pet" }))
		end)

		it("respects showFunc", function()
			assert.is_false(Stats.IsWanted({ stat = "X", showFunc = function() return false end }))
			assert.is_true(Stats.IsWanted({ stat = "X", showFunc = function() return true end }))
		end)

		it("keeps the stat if showFunc errors", function()
			assert.is_true(Stats.IsWanted({ stat = "X", showFunc = function() error("boom") end }))
		end)

		it("filters by primary stat and role when specs exist", function()
			wow.track("C_SpecializationInfo", "GetSpecializationRoleEnum")
			_G.C_SpecializationInfo = {
				GetSpecialization = function() return 1 end,
				GetSpecializationInfo = function() return 1, "Spec", "", 0, "TANK", 2 end,
			}
			_G.GetSpecializationRoleEnum = function() return 0 end

			assert.is_true(Stats.IsWanted({ stat = "X", primary = 2 }))
			assert.is_false(Stats.IsWanted({ stat = "X", primary = 1 }))
			assert.is_true(Stats.IsWanted({ stat = "X", roles = { 0 } }))
			assert.is_false(Stats.IsWanted({ stat = "X", roles = { 1, 2 } }))
		end)
	end)

	describe("Fill", function()
		it("fills a row using the game's function", function()
			local row = newRow()
			assert.is_true(Stats.Fill(row, defineStat("STRENGTH", 86)))
			assert.are.equal("86", row.Value:GetText())
		end)

		it("hides unknown stats", function()
			assert.is_false(Stats.Fill(newRow(), { stat = "NOPE" }))
		end)

		it("hides a stat whose function errors (as in combat)", function()
			local stat = defineStat("X", 1, { updateFunc = function() error("secret") end })
			assert.is_false(Stats.Fill(newRow(), stat))
		end)

		it("hides a stat the game hid", function()
			local stat = defineStat("X", 1, { updateFunc = function(row) row:Hide() end })
			assert.is_false(Stats.Fill(newRow(), stat))
		end)

		it("hides a stat at its hideAt value", function()
			assert.is_false(Stats.Fill(newRow(), defineStat("X", 0, { stat = { hideAt = 0 } })))
			assert.is_true(Stats.Fill(newRow(), defineStat("Y", 3, { stat = { hideAt = 0 } })))
		end)

		it("falls back to the row's numericValue", function()
			local stat = defineStat("X", nil, {
				stat = { hideAt = 0 },
				updateFunc = function(row) row.numericValue = 0 end,
			})
			assert.is_false(Stats.Fill(newRow(), stat))
		end)

		it("never compares secret values with hideAt", function()
			local secret = {}
			wow.track("issecretvalue")
			_G.issecretvalue = function(v) return rawequal(v, secret) end
			-- If the code compared, secret == hideAt would hide the row.
			local stat = defineStat("X", nil, { stat = { hideAt = secret }, updateFunc = function() return secret end })
			assert.is_true(Stats.Fill(newRow(), stat))
		end)
	end)

	describe("FillResistance", function()
		it("shows the effective resistance", function()
			_G.UnitResistance = function() return 10, 15, 15, 5 end
			local row = newRow()
			assert.is_true(Stats.FillResistance(row, { name = "Fire", school = "Fire" }))
			assert.are.equal("Fire", row.Label:GetText())
			assert.are.equal("15", row.Value:GetText())
		end)

		it("skips unknown schools", function()
			assert.is_false(Stats.FillResistance(newRow(), { name = "Holy", school = "Holy" }))
		end)

		it("skips resistances the game won't give", function()
			_G.UnitResistance = function() error("secret") end
			assert.is_false(Stats.FillResistance(newRow(), { name = "Fire", school = "Fire" }))
		end)
	end)

	describe("Collect", function()
		local function acquire()
			return newRow()
		end

		it("builds categories in order, followed by resistances", function()
			_G.PAPERDOLL_STATCATEGORIES = {
				{ categoryName = "General", stats = { defineStat("HEALTH", 1769), defineStat("MANA", 3148) } },
				{ categoryName = "Attributes", stats = { defineStat("STRENGTH", 86) } },
			}
			local blocks = Stats.Collect(acquire)
			assert.are.same({ "General", "Attributes", "Resistances" },
				{ blocks[1].title, blocks[2].title, blocks[3].title })
			assert.are.equal(2, #blocks[1].rows)
			assert.are.equal(5, #blocks[3].rows)
		end)

		it("skips pet categories and empty categories", function()
			_G.PAPERDOLL_STATCATEGORIES = {
				{ categoryName = "Pet", unit = "pet", stats = { defineStat("A", 1) } },
				{ categoryName = "Hidden", stats = { defineStat("B", 0, { stat = { hideAt = 0 } }) } },
				{ categoryName = "Shown", stats = { defineStat("C", 1) } },
			}
			local blocks = Stats.Collect(acquire)
			assert.are.equal("Shown", blocks[1].title)
			assert.are.equal("Resistances", blocks[2].title)
			assert.are.equal(2, #blocks)
		end)

		it("hides rows it doesn't use and remembers each row's stat", function()
			local hidden = defineStat("B", 0, { stat = { hideAt = 0 } })
			local shown = defineStat("C", 1)
			_G.PAPERDOLL_STATCATEGORIES = { { categoryName = "Cat", stats = { hidden, shown } } }
			local rows = {}
			Stats.Collect(function() local r = newRow(); rows[#rows + 1] = r; return r end)
			assert.is_false(rows[1]:IsShown())
			assert.are.equal(shown, rows[2].statDef)
			assert.is_not_nil(rows[3].resDef)
		end)
	end)

	describe("UpdateInPlace", function()
		it("updates rows the game allows", function()
			local value = 1
			local stat = defineStat("X", nil, {
				updateFunc = function(row) row.Value:SetText(tostring(value)) end,
			})
			local row = newRow()
			row.statDef = stat
			Stats.Fill(row, stat)
			value = 2
			Stats.UpdateInPlace({ row })
			assert.are.equal("2", row.Value:GetText())
		end)

		it("keeps the last value when the game refuses (combat)", function()
			local fail = false
			local stat = defineStat("X", nil, {
				updateFunc = function(row)
					if fail then
						row.Value:SetText("")
						row:Hide()
						error("secret")
					end
					row.Label:SetText("Parry")
					row.Value:SetText("4.8%")
				end,
			})
			local row = newRow()
			row.statDef = stat
			Stats.Fill(row, stat)
			fail = true
			Stats.UpdateInPlace({ row })
			assert.is_true(row:IsShown())
			assert.are.equal("Parry", row.Label:GetText())
			assert.are.equal("4.8%", row.Value:GetText())
		end)

		it("keeps the last resistance when the game refuses", function()
			local row = newRow()
			row.resDef = { name = "Fire", school = "Fire" }
			Stats.FillResistance(row, row.resDef)
			_G.UnitResistance = function() error("secret") end
			Stats.UpdateInPlace({ row })
			assert.are.equal("0", row.Value:GetText())
		end)

		it("leaves hidden rows alone", function()
			local row = newRow()
			row.statDef = defineStat("X", 1)
			row:Hide()
			Stats.UpdateInPlace({ row })
			assert.is_false(row:IsShown())
		end)
	end)
end)
