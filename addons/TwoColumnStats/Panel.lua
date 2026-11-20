-- The two-column panel: frame pools, layout and refreshing.
local _, ns = ...
local C, Layout, Stats = ns.Config, ns.Layout, ns.Stats

local Panel = {}
ns.Panel = Panel

local frame            -- our panel
local columns = {}     -- the two column frames
local rowPool, headerPool = {}, {}
local usedRows, usedHeaders = 0, 0

function Panel.Frame()
	return frame
end

---------------------------------------------------------------------------
-- Frame pools
---------------------------------------------------------------------------

local function acquireRow()
	usedRows = usedRows + 1
	local row = rowPool[usedRows]
	if not row then
		row = CreateFrame("Frame", nil, frame, "CharacterStatFrameTemplate")
		row:SetSize(C.COLUMN_WIDTH - 10, C.ROW_HEIGHT)
		rowPool[usedRows] = row
	end
	-- Clear anything a previous stat left behind.
	row.tooltip, row.tooltip2, row.tooltip3 = nil, nil, nil
	row.onEnterFunc, row.UpdateTooltip, row.numericValue = nil, nil, nil
	row.statDef, row.resDef = nil, nil
	row.Label:SetText("")
	row.Value:SetText("")
	row:ClearAllPoints()
	row:Show()
	return row
end

local function acquireHeader(text)
	usedHeaders = usedHeaders + 1
	local header = headerPool[usedHeaders]
	if not header then
		header = CreateFrame("Frame", nil, frame, "CharacterStatFrameCategoryTemplate")
		header:SetSize(C.COLUMN_WIDTH, C.HEADER_HEIGHT)
		headerPool[usedHeaders] = header
	end
	header.Title:SetText(text or "")
	header:ClearAllPoints()
	header:Show()
	return header
end

local function releaseAll()
	for _, f in ipairs(rowPool) do f:Hide() end
	for _, f in ipairs(headerPool) do f:Hide() end
	usedRows, usedHeaders = 0, 0
end

local function usedRowList()
	local rows = {}
	for i = 1, usedRows do rows[i] = rowPool[i] end
	return rows
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local function pixelsPerUnit(region)
	local _, physicalHeight = GetPhysicalScreenSize()
	return Layout.PixelsPerUnit(region:GetEffectiveScale(), physicalHeight)
end

local function layoutColumn(column, blocks, first, last, rowHeight)
	local ppu = pixelsPerUnit(column)
	local rowH = Layout.Snap(rowHeight, ppu)
	local headerH = Layout.Snap(C.HEADER_HEIGHT, ppu)
	local gap = Layout.Snap(C.BLOCK_GAP, ppu)
	local y = 0
	for i = first, last do
		local block = blocks[i]
		local header = acquireHeader(block.title)
		header:SetHeight(headerH)
		header:SetPoint("TOP", column, "TOP", 0, -y)
		y = y + headerH
		for n, row in ipairs(block.rows) do
			row:SetHeight(rowH)
			row:SetPoint("TOP", column, "TOP", 0, -y)
			row.Background:SetHeight(rowH)   -- the stripe grows with the row
			row.Background:SetShown(n % 2 == 0)
			y = y + rowH
		end
		y = y + gap
	end
end

local function inCombat()
	return InCombatLockdown() or UnitAffectingCombat("player")
end

function Panel.Refresh()
	if not frame or not frame:IsVisible() then return end
	if usedRows > 0 and inCombat() then
		Stats.UpdateInPlace(usedRowList())
		return
	end
	releaseAll()
	local ok, blocks = pcall(Stats.Collect, acquireRow)
	if not ok then return end   -- leave it empty rather than throw errors at the player

	local rowCounts = {}
	for i, block in ipairs(blocks) do rowCounts[i] = #block.rows end
	local split = Layout.ChooseSplit(rowCounts)
	local avail = (frame:GetHeight() or 0) - C.PADDING - C.BOTTOM_MARGIN
	local rowHeight = Layout.ChooseRowHeight(rowCounts, split, avail)
	layoutColumn(columns[1], blocks, 1, split, rowHeight)
	layoutColumn(columns[2], blocks, split + 1, #blocks, rowHeight)
end

-- Several events can arrive at once (gear swap, buffs): refresh once.
local pending = false
function Panel.RefreshSoon()
	if pending then return end
	pending = true
	C_Timer.After(0.1, function()
		pending = false
		Panel.Refresh()
	end)
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

-- Creates the panel over host (the game's stats pane). Parented to it, so it
-- shows and hides with it, and sized to fill it.
function Panel.Create(host)
	if frame then return frame end
	frame = CreateFrame("Frame", "TwoColumnStatsPanel", host)
	frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
	frame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
	frame:SetFrameLevel(host:GetFrameLevel() + 50)
	frame:EnableMouse(true)   -- keeps the hidden list underneath from showing tooltips

	local top = Layout.Snap(C.PADDING, pixelsPerUnit(frame))
	for i = 1, 2 do
		local col = CreateFrame("Frame", nil, frame)
		col:SetSize(C.COLUMN_WIDTH, 1)
		if i == 1 then
			col:SetPoint("TOPLEFT", frame, "TOPLEFT", C.LEFT_INSET, -top)
		else
			col:SetPoint("TOPLEFT", columns[1], "TOPRIGHT", C.COLUMN_GAP, 0)
		end
		columns[i] = col
	end

	frame:SetScript("OnShow", Panel.Refresh)
	return frame
end
