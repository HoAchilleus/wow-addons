-- luacheck configuration for every addon in the repo.
-- WoW runs Lua 5.1; addon files share globals through the WoW API below.
std = "lua51"
max_line_length = 120
codes = true

exclude_files = {
	".luarocks/**",
	"**/Libs/**",   -- third-party libraries embedded in an addon
}

-- WoW API used by the addons. Add to this as addons use more of it.
read_globals = {
	-- Frames and widgets
	"CreateFrame", "UIParent", "hooksecurefunc", "GetPhysicalScreenSize",
	"C_Timer", "C_Texture", "C_SpecializationInfo", "Enum",
	-- Unit and combat state
	"InCombatLockdown", "UnitAffectingCombat", "UnitSex", "UnitResistance",
	"GetSpecializationRoleEnum", "issecretvalue",
	-- Character frame
	"CharacterFrame", "CharacterStatsPaneScrollBox",
	"CHARACTER_FRAME_WIDTH", "CHARACTER_FRAME_COLLAPSED_WIDTH",
	"PAPERDOLL_STATINFO", "PAPERDOLL_STATCATEGORIES",
	"PaperDollFrame_UpdateStats", "PaperDollFrame_SetLabelAndText",
	"PaperDollFrame_SetResistanceTooltips", "PaperDollFrame_FormatBonusValue",
	"BreakUpLargeNumbers",
	-- Game strings
	"DAMAGE_SCHOOL3", "DAMAGE_SCHOOL4", "DAMAGE_SCHOOL5", "DAMAGE_SCHOOL6", "DAMAGE_SCHOOL7",
	"STAT_CATEGORY_RESISTANCE", "RESISTANCE_LABEL",
}

-- Globals the game expects addons to set: slash commands.
globals = { "SlashCmdList" }

files["addons/TwoColumnStats/**/*.lua"] = {
	globals = { "TwoColumnStatsDB", "SLASH_TWOCOLUMNSTATS1" },
}

-- Tests run under busted and replace WoW globals with mocks.
files["**/spec/**/*.lua"] = {
	std = "+busted",
	globals = { "_G" },
	read_globals = { "unpack" },
	allow_defined_top = true,
	ignore = { "121", "122" },   -- tests replace WoW globals and their fields (mocked)
}
files["spec/helpers/**/*.lua"] = {
	ignore = { "111", "112", "121", "122" },   -- the mock defines WoW's globals
}
