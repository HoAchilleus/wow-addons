local loadAddon = require("addon")

describe("Layout", function()
	local Layout, C

	before_each(function()
		local ns = loadAddon("TwoColumnStats", { "Config.lua", "Layout.lua" })
		Layout, C = ns.Layout, ns.Config
	end)

	describe("ChooseSplit", function()
		it("puts everything left when there's a single category", function()
			assert.are.equal(1, Layout.ChooseSplit({ 5 }))
		end)

		it("returns 0 for no categories", function()
			assert.are.equal(0, Layout.ChooseSplit({}))
		end)

		it("splits equal categories down the middle", function()
			assert.are.equal(2, Layout.ChooseSplit({ 3, 3, 3, 3 }))
		end)

		it("balances the columns by height, keeping category order", function()
			-- 10 rows on its own is about as tall as the other three together.
			assert.are.equal(1, Layout.ChooseSplit({ 10, 2, 2, 2 }))
			assert.are.equal(3, Layout.ChooseSplit({ 2, 2, 2, 10 }))
		end)

		it("matches the in-game layout", function()
			-- General 3, Attributes 5, Weapons 2 | Modifiers 4, Defense 4, Resistances 5
			assert.are.equal(3, Layout.ChooseSplit({ 3, 5, 2, 4, 4, 5 }))
		end)
	end)

	describe("ChooseRowHeight", function()
		it("never goes below the minimum row height", function()
			assert.are.equal(C.ROW_HEIGHT, Layout.ChooseRowHeight({ 20, 20 }, 1, 100))
		end)

		it("never goes above the maximum row height", function()
			assert.are.equal(C.MAX_ROW_HEIGHT, Layout.ChooseRowHeight({ 1, 1 }, 1, 1000))
		end)

		it("fills the available height in the taller column", function()
			local avail = 2 * (C.HEADER_HEIGHT + C.BLOCK_GAP) + 10 * 17
			assert.are.near(17, Layout.ChooseRowHeight({ 5, 5, 3 }, 2, avail), 1e-9)
		end)

		it("copes with an empty right column", function()
			assert.are.equal(C.MAX_ROW_HEIGHT, Layout.ChooseRowHeight({ 2 }, 1, 1000))
		end)
	end)

	describe("PixelsPerUnit and Snap", function()
		it("converts UI units to screen pixels", function()
			assert.are.near(1.5, Layout.PixelsPerUnit(1, 1152), 1e-9)
			assert.are.near(3, Layout.PixelsPerUnit(2, 1152), 1e-9)
		end)

		it("returns nil for unusable screen sizes", function()
			assert.is_nil(Layout.PixelsPerUnit(1, 0))
			assert.is_nil(Layout.PixelsPerUnit(0, 1080))
		end)

		it("rounds to whole pixels", function()
			local ppu = 1080 / 768   -- about 1.406 pixels per unit
			local snapped = Layout.Snap(15, ppu)
			local pixels = snapped * ppu
			assert.are.near(math.floor(pixels + 0.5), pixels, 1e-9)
			assert.are.near(21, pixels, 1e-9)
		end)

		it("gives every row the same pixel height", function()
			local ppu = 1080 / 768 * 0.9
			local h = Layout.Snap(15, ppu)
			for i = 1, 20 do
				local top, bottom = (i - 1) * h * ppu, i * h * ppu
				assert.are.near(h * ppu, bottom - top, 1e-9)
			end
		end)

		it("is at least one pixel", function()
			assert.are.equal(1, Layout.Snap(0.01, 1))
		end)

		it("leaves the value alone without a pixel size", function()
			assert.are.equal(15, Layout.Snap(15, nil))
		end)
	end)

	describe("ClassifyArt", function()
		local extra
		before_each(function() extra = C.EXTRA_WIDTH end)

		it("treats art ending at the old pane edge as 'edge'", function()
			assert.are.equal("edge", Layout.ClassifyArt(233, 59, extra))
		end)

		it("treats art inside the old pane as 'inside' if its mirror fits", function()
			assert.are.equal("inside", Layout.ClassifyArt(100, 120, extra * 1.45))
		end)

		it("ignores art whose mirror wouldn't fit", function()
			assert.is_nil(Layout.ClassifyArt(300, 120, extra * 1.45))
		end)

		it("ignores art that already stretches to the edge", function()
			assert.is_nil(Layout.ClassifyArt(433, 464, 0))
		end)

		it("ignores small textures", function()
			assert.is_nil(Layout.ClassifyArt(50, 200, extra))
			assert.is_nil(Layout.ClassifyArt(200, 20, extra))
		end)

		it("ignores missing measurements", function()
			assert.is_nil(Layout.ClassifyArt(nil, 100, extra))
			assert.is_nil(Layout.ClassifyArt(200, 100, nil))
		end)
	end)

	describe("SplitGeometry", function()
		it("makes each half half the widened pane", function()
			local half = Layout.SplitGeometry(233, 0, 1)
			assert.are.near((233 + C.EXTRA_WIDTH) / 2, half, 1e-9)
		end)

		it("puts the join at the matching point of the texture", function()
			local half, edge = Layout.SplitGeometry(233, 0.2, 0.8)
			assert.are.near(0.2 + 0.6 * (half / 233), edge, 1e-9)
		end)

		it("never goes past the texture's right edge", function()
			local _, edge = Layout.SplitGeometry(100, 0, 1)
			assert.are.equal(1, edge)
		end)
	end)

	describe("InsideMirrorOffset", function()
		it("is zero for art ending at the old edge", function()
			assert.are.equal(0, Layout.InsideMirrorOffset(C.EXTRA_WIDTH))
		end)

		it("reflects across the old edge", function()
			-- Right edge 50 units inside the old edge -> mirror starts 100 units right of it.
			assert.are.equal(100, Layout.InsideMirrorOffset(C.EXTRA_WIDTH + 50))
		end)
	end)
end)
