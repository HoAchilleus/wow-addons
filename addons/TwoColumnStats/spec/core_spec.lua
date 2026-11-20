local wow = require("wow")
local loadAddon = require("addon")

-- A minimal character window: the right pane, the game's stats pane and its
-- scrolling list.
local function characterFrame()
	local frame = wow.newFrame("CharacterFrame")
	frame.RightPaneHost = wow.newFrame(nil, frame)
	frame.RightPaneHost:SetWidth(233)
	local stats = wow.newFrame("CharacterStatsPaneScrollBox", frame.RightPaneHost)
	stats.ScrollBox = wow.newFrame(nil, stats)
	stats.ScrollBar = wow.newFrame(nil, stats)
	frame.IsRightPaneCollapsed = function() return false end
	frame.UpdateSize = function() end
	return frame
end

describe("TwoColumnStats", function()
	local ns, frame

	local function login()
		wow.fire("ADDON_LOADED", "TwoColumnStats")
		wow.fire("PLAYER_LOGIN")
		wow.runTimers()
	end

	before_each(function()
		wow.reset({ CHARACTER_FRAME_WIDTH = 540, CHARACTER_FRAME_COLLAPSED_WIDTH = 300 })
		wow.track("TwoColumnStatsDB", "SLASH_TWOCOLUMNSTATS1", "CharacterFrame", "CharacterStatsPaneScrollBox")
		frame = characterFrame()
		ns = loadAddon("TwoColumnStats")
	end)

	it("registers /tcs", function()
		assert.are.equal("/tcs", SLASH_TWOCOLUMNSTATS1)
		assert.is_function(SlashCmdList.TWOCOLUMNSTATS)
	end)

	it("defaults to enabled", function()
		wow.fire("ADDON_LOADED", "TwoColumnStats")
		assert.is_true(TwoColumnStatsDB.enabled)
	end)

	it("keeps a saved setting", function()
		_G.TwoColumnStatsDB = { enabled = false }
		wow.fire("ADDON_LOADED", "TwoColumnStats")
		assert.is_false(TwoColumnStatsDB.enabled)
	end)

	it("ignores other addons loading", function()
		wow.fire("ADDON_LOADED", "SomethingElse")
		assert.is_nil(TwoColumnStatsDB)
	end)

	describe("after login", function()
		before_each(login)

		it("creates the panel over the stats pane", function()
			local panel = ns.Panel.Frame()
			assert.are.equal(CharacterStatsPaneScrollBox, panel:GetParent())
			assert.is_true(panel:IsShown())
		end)

		it("widens the window and pane", function()
			assert.are.equal(540 + ns.Config.EXTRA_WIDTH, frame._width)
			assert.are.equal(233 + ns.Config.EXTRA_WIDTH, frame.RightPaneHost._width)
		end)

		it("hides the game's own list", function()
			assert.are.equal(0, CharacterStatsPaneScrollBox.ScrollBox:GetAlpha())
		end)

		it("/tcs turns it off and puts everything back", function()
			SlashCmdList.TWOCOLUMNSTATS("")
			assert.is_false(TwoColumnStatsDB.enabled)
			assert.is_false(ns.Panel.Frame():IsShown())
			assert.are.equal(540, frame._width)
			assert.are.equal(233, frame.RightPaneHost._width)
			assert.are.equal(1, CharacterStatsPaneScrollBox.ScrollBox:GetAlpha())
			assert.matches("off", wow.printed[#wow.printed])
		end)

		it("/tcs again turns it back on", function()
			SlashCmdList.TWOCOLUMNSTATS("")
			SlashCmdList.TWOCOLUMNSTATS("")
			assert.is_true(TwoColumnStatsDB.enabled)
			assert.are.equal(540 + ns.Config.EXTRA_WIDTH, frame._width)
			assert.matches("on", wow.printed[#wow.printed])
		end)

		it("goes back to normal width when the stats pane closes", function()
			CharacterStatsPaneScrollBox:Hide()
			assert.are.equal(540, frame._width)
		end)

		it("/tcs debug asks for the window when it has no position", function()
			SlashCmdList.TWOCOLUMNSTATS("debug")
			assert.matches("open the character window first", wow.printed[#wow.printed])
		end)

		it("lays the stats out in two columns", function()
			PAPERDOLL_STATINFO.HEALTH = { updateFunc = function(row) row.Value:SetText("1,769") end }
			_G.PAPERDOLL_STATCATEGORIES = {
				{ categoryName = "General", stats = { { stat = "HEALTH" } } },
			}
			ns.Panel.Refresh()
			local shown = 0
			for _, child in ipairs({ ns.Panel.Frame():GetChildren() }) do
				if child.Value and child:IsShown() then shown = shown + 1 end
			end
			assert.are.equal(1 + 5, shown)   -- health plus five resistances
		end)

		it("refreshes once for a burst of events", function()
			local refreshes = 0
			local refresh = ns.Panel.Refresh
			ns.Panel.Refresh = function() refreshes = refreshes + 1 end
			wow.fire("UNIT_AURA", "player")
			wow.fire("PLAYER_EQUIPMENT_CHANGED")
			wow.runTimers()
			ns.Panel.Refresh = refresh
			assert.are.equal(1, refreshes)
		end)
	end)
end)
