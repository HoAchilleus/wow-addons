-- Shared constants. Loaded first (see the .toc), so every other file can
-- read them from the addon namespace.
local _, ns = ...

ns.Config = {
	-- Stat rows and category headers (sizes from the game's own templates).
	ROW_HEIGHT     = 15,   -- minimum row height
	MAX_ROW_HEIGHT = 20,   -- rows grow to fill the pane, up to this
	HEADER_HEIGHT  = 24,
	BLOCK_GAP      = 4,    -- space after each category
	COLUMN_WIDTH   = 197,
	COLUMN_GAP     = 8,
	PADDING        = 8,    -- space above the first header
	LEFT_INSET     = 10,
	BOTTOM_MARGIN  = 24,   -- keep clear of the line art at the bottom of the pane

	-- How much wider the character window gets while two columns are showing.
	EXTRA_WIDTH = 200,

	-- The main stats background widens by repeating its image, so it is
	-- redrawn as two mirrored halves instead.
	SPLIT_ATLAS = "UI-Character-Info-Stat-BG",

	-- Smallest texture considered "background art" worth mirroring.
	MIN_ART_WIDTH  = 100,
	MIN_ART_HEIGHT = 30,

	-- Reference height of the UI coordinate system (UIParent is 768 tall).
	UI_REFERENCE_HEIGHT = 768,

	CHAT_PREFIX = "|cffffd100Two Column Stats|r",
}
