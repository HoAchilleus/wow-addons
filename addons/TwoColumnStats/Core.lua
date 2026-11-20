-- Entry point: saved settings, events, window widening and slash commands.
local ADDON, ns = ...
local C, Panel, Background = ns.Config, ns.Panel, ns.Background

local Core = {}
ns.Core = Core

local baseHostWidth   -- the right pane's normal width

local function db()
	return TwoColumnStatsDB
end

local function paneHost()
	return CharacterFrame and CharacterFrame.RightPaneHost
end

local function shouldWiden()
	local frame = CharacterFrame
	local collapsed = frame.IsRightPaneCollapsed and frame:IsRightPaneCollapsed()
	return db().enabled and not collapsed and CharacterStatsPaneScrollBox:IsShown() and true or false
end

-- Widens the character window while the two columns are showing, and back.
function Core.ApplyWidth()
	local frame = CharacterFrame
	if not paneHost() or not baseHostWidth then return end
	local widen = shouldWiden()
	local collapsed = frame.IsRightPaneCollapsed and frame:IsRightPaneCollapsed()
	local base = collapsed and CHARACTER_FRAME_COLLAPSED_WIDTH or CHARACTER_FRAME_WIDTH
	if base then
		frame:SetWidth(base + (widen and C.EXTRA_WIDTH or 0))
	end
	paneHost():SetWidth(baseHostWidth + (widen and C.EXTRA_WIDTH or 0))
	Background.Update(paneHost(), frame, widen, Panel.Frame())
	-- Positions can settle a frame later, so check once more then.
	C_Timer.After(0, function()
		Background.Update(paneHost(), frame, shouldWiden(), Panel.Frame())
	end)
end

-- Hides the game's own (scrolling) list underneath while we're showing.
local function setNativeListVisible(visible)
	local host = CharacterStatsPaneScrollBox
	local alpha = visible and 1 or 0
	if host.ScrollBox then host.ScrollBox:SetAlpha(alpha) end
	if host.ScrollBar then host.ScrollBar:SetAlpha(alpha) end
end

function Core.SetEnabled(enabled)
	db().enabled = enabled
	local panel = Panel.Frame()
	if panel then
		panel:SetShown(enabled)
		setNativeListVisible(not enabled)
		Core.ApplyWidth()
	end
end

function Core.Setup()
	local host = CharacterStatsPaneScrollBox
	if not host or not paneHost() or Panel.Frame() then return end
	baseHostWidth = paneHost():GetWidth()

	local panel = Panel.Create(host)
	panel:SetShown(db().enabled)
	setNativeListVisible(not db().enabled)

	-- Keep the width right whenever the game resizes the window or the stats
	-- pane opens or closes (other tabs, equipment manager, titles, pet).
	if CharacterFrame.UpdateSize then
		hooksecurefunc(CharacterFrame, "UpdateSize", Core.ApplyWidth)
	end
	host:HookScript("OnShow", Core.ApplyWidth)
	host:HookScript("OnHide", Core.ApplyWidth)
	CharacterFrame:HookScript("OnShow", Core.ApplyWidth)
	Core.ApplyWidth()

	-- Refresh whenever the game refreshes its own stats.
	if PaperDollFrame_UpdateStats then
		hooksecurefunc("PaperDollFrame_UpdateStats", Panel.RefreshSoon)
	end
end

---------------------------------------------------------------------------
-- Debugging: /tcs debug
---------------------------------------------------------------------------

-- Lists every texture drawn at the crest's spot (about 90 units in from the
-- pane's left edge, halfway down), anywhere in the UI, so art that isn't
-- being mirrored can be identified.
function Core.PrintDebug()
	local host = paneHost()
	if not host then print(C.CHAT_PREFIX .. ": no CharacterFrame.RightPaneHost") return end
	local hostLeft, hostRight = host:GetLeft(), host:GetRight()
	local top, bottom = host:GetTop(), host:GetBottom()
	if not (hostLeft and top and bottom) then
		print(C.CHAT_PREFIX .. ": open the character window first")
		return
	end
	local x, y = hostLeft + 90, (top + bottom) / 2
	print(C.CHAT_PREFIX .. " textures under the crest (gap = distance short of the right edge):")
	local found = 0
	Background.EachTexture(UIParent, function(tex)
		if Background.IsOurs(tex) or not tex:IsVisible() then return end
		local l, r, t, b = tex:GetLeft(), tex:GetRight(), tex:GetTop(), tex:GetBottom()
		if not (l and r and t and b) or x < l or x > r or y < b or y > t then return end
		found = found + 1
		local parent = tex:GetParent()
		print(string.format("%s  %dx%d  gap %d  %s  alpha %.2f  in %s%s",
			tostring(tex:GetAtlas() or tex:GetTexture()), r - l, t - b,
			Background.RightGap(tex, hostRight) or -1, tostring((tex:GetDrawLayer())),
			tex.GetEffectiveAlpha and tex:GetEffectiveAlpha() or tex:GetAlpha(),
			parent and (parent:GetDebugName() or "?") or "?",
			Background.IsExtended(tex) and "  <- mirrored" or ""))
	end, Panel.Frame(), -4)
	if found == 0 then print("  none found") end
end

---------------------------------------------------------------------------
-- Slash command and events
---------------------------------------------------------------------------

function Core.HandleSlash(msg)
	if msg and msg:lower():match("^%s*debug") then
		Core.PrintDebug()
		return
	end
	Core.SetEnabled(not db().enabled)
	print(C.CHAT_PREFIX .. " " .. (db().enabled and "on" or "off (showing the default stats)"))
end

function Core.OnEvent(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		TwoColumnStatsDB = TwoColumnStatsDB or {}
		if TwoColumnStatsDB.enabled == nil then TwoColumnStatsDB.enabled = true end
	elseif event == "PLAYER_LOGIN" then
		Core.Setup()
	else
		local panel = Panel.Frame()
		if panel and panel:IsVisible() then Panel.RefreshSoon() end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterUnitEvent("UNIT_AURA", "player")
events:SetScript("OnEvent", Core.OnEvent)

SLASH_TWOCOLUMNSTATS1 = "/tcs"
SlashCmdList.TWOCOLUMNSTATS = Core.HandleSlash
