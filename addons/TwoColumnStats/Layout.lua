-- Pure layout maths: no WoW API calls, so it can be unit tested directly.
local _, ns = ...
local C = ns.Config

local Layout = {}
ns.Layout = Layout

-- Height of one category block laid out at the minimum row height.
function Layout.BlockHeight(rowCount)
	return C.HEADER_HEIGHT + rowCount * C.ROW_HEIGHT + C.BLOCK_GAP
end

-- Given each category's row count (in display order), returns how many
-- categories go in the left column so the two columns are as even as
-- possible. Categories keep their order; ties favour the left column (so a
-- single category goes on the left, not the right).
function Layout.ChooseSplit(rowCounts)
	local total = 0
	for _, n in ipairs(rowCounts) do total = total + Layout.BlockHeight(n) end
	local best, bestDiff, left = 0, math.huge, 0
	for i = 0, #rowCounts do
		if i > 0 then left = left + Layout.BlockHeight(rowCounts[i]) end
		local diff = math.abs(total - 2 * left)
		if diff <= bestDiff then best, bestDiff = i, diff end
	end
	return best
end

-- Row height that makes the taller column fill availHeight, clamped between
-- ROW_HEIGHT and MAX_ROW_HEIGHT. Both columns use the same height so their
-- rows line up.
function Layout.ChooseRowHeight(rowCounts, split, availHeight)
	local best = C.MAX_ROW_HEIGHT
	for _, range in ipairs({ { 1, split }, { split + 1, #rowCounts } }) do
		local rows, fixed = 0, 0
		for i = range[1], range[2] do
			rows = rows + rowCounts[i]
			fixed = fixed + C.HEADER_HEIGHT + C.BLOCK_GAP
		end
		if rows > 0 then
			best = math.min(best, (availHeight - fixed) / rows)
		end
	end
	return math.max(C.ROW_HEIGHT, best)
end

-- Screen pixels per UI unit for a region with the given effective scale.
function Layout.PixelsPerUnit(effectiveScale, physicalHeight)
	if not physicalHeight or physicalHeight <= 0 or not effectiveScale or effectiveScale <= 0 then
		return nil
	end
	return effectiveScale * physicalHeight / C.UI_REFERENCE_HEIGHT
end

-- Rounds a size to a whole number of screen pixels (at least one). At most UI
-- scales a 15-unit row is a fraction of a pixel tall, so the game would round
-- some rows down and others up; whole pixels keep every row the same height.
function Layout.Snap(value, pixelsPerUnit)
	if not pixelsPerUnit then return value end
	return math.max(1, math.floor(value * pixelsPerUnit + 0.5)) / pixelsPerUnit
end

-- Decides how a fixed-width background texture should be extended when the
-- pane widens by EXTRA_WIDTH. gap is how far its right edge stops short of
-- the widened pane's right edge.
--   "edge":   it ends at the old pane edge, so draw it as mirrored halves.
--   "inside": it sits inside the old pane (like a crest), so reflect it
--             across the old edge, if the reflection fits.
--   nil:      leave it alone.
function Layout.ClassifyArt(width, height, gap)
	local extra = C.EXTRA_WIDTH
	if not width or not height or not gap then return nil end
	if width < C.MIN_ART_WIDTH or height < C.MIN_ART_HEIGHT then return nil end
	if gap > extra * 0.6 and gap < extra * 1.4 then return "edge" end
	if gap >= extra * 1.4 and width + gap <= extra * 2 + 4 then return "inside" end
	return nil
end

-- For art drawn as two mirrored halves across the widened pane: each half's
-- width, and the texture x coordinate where the halves meet. baseWidth is the
-- art's normal width; l and r are its texture coordinates.
function Layout.SplitGeometry(baseWidth, l, r)
	local half = (baseWidth + C.EXTRA_WIDTH) / 2
	local edge = l + (r - l) * math.min(1, half / baseWidth)
	return half, edge
end

-- Horizontal offset (from the art's own right edge) for its reflection
-- across the old pane edge.
function Layout.InsideMirrorOffset(gap)
	return 2 * (gap - C.EXTRA_WIDTH)
end
