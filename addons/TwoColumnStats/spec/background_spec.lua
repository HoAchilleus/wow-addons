local wow = require("wow")
local loadAddon = require("addon")

-- Every atlas resolves to the same file, covering the texture's full width.
local atlasInfo = {
	GetAtlasInfo = function(atlas)
		return { file = "file:" .. atlas, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 }
	end,
}

describe("Background", function()
	local ns, Background, C, root, host

	-- A texture in host with an atlas and a screen rectangle (x from the
	-- pane's left edge; the widened pane is 0..433 wide).
	local function art(atlas, l, r, height, parent)
		local tex = (parent or host):CreateTexture(nil, "BACKGROUND")
		tex:SetAtlas(atlas)
		tex:_SetRect(l, r, 500, 500 - height)
		return tex
	end

	local function regionsOf(frame)
		return { frame:GetRegions() }
	end

	local function ours(frame)
		local list = {}
		for _, r in ipairs(regionsOf(frame)) do
			if Background.IsOurs(r) then list[#list + 1] = r end
		end
		return list
	end

	before_each(function()
		wow.reset({ C_Texture = atlasInfo })
		ns = loadAddon("TwoColumnStats", { "Config.lua", "Layout.lua", "Background.lua" })
		Background, C = ns.Background, ns.Config
		root = wow.newFrame("CharacterFrame")
		root:_SetRect(-300, 433, 520, 0)
		host = wow.newFrame(nil, root)
		host:_SetRect(0, 233 + C.EXTRA_WIDTH, 500, 0)
	end)

	describe("TextureSource", function()
		it("uses atlas coordinates", function()
			local file, l, r, t, b = Background.TextureSource(art("A", 0, 10, 10))
			assert.are.same({ "file:A", 0, 1, 0, 1 }, { file, l, r, t, b })
		end)

		it("falls back to a plain file and its coordinates", function()
			local tex = host:CreateTexture()
			tex:SetTexture("plain")
			tex:SetTexCoord(0.1, 0.9, 0.2, 0.8)
			local file, l, r, t, b = Background.TextureSource(tex)
			assert.are.same({ "plain", 0.1, 0.9, 0.2, 0.8 }, { file, l, r, t, b })
		end)

		it("returns nil for an empty texture", function()
			assert.is_nil(Background.TextureSource(host:CreateTexture()))
		end)
	end)

	describe("the main stats background", function()
		it("is redrawn as two mirrored halves centred on the pane", function()
			local bg = art(C.SPLIT_ATLAS, 0, 233 + C.EXTRA_WIDTH, 464)
			Background.Update(host, root, true)

			local copies = ours(host)
			assert.are.equal(2, #copies)
			local half = (233 + C.EXTRA_WIDTH) / 2
			assert.are.near(half, copies[1]._width, 1e-9)
			assert.are.near(half, copies[2]._width, 1e-9)

			local edge = half / 233
			assert.are.same({ 0, edge, 0, 1 }, copies[1]._coords)
			assert.are.same({ edge, 0, 0, 1 }, copies[2]._coords)   -- mirrored
			assert.is_true(copies[1]:IsShown() and copies[2]:IsShown())
			assert.are.equal(0, bg:GetAlpha())
		end)

		it("waits if the pane hasn't widened yet", function()
			art(C.SPLIT_ATLAS, 0, 233, 464)
			Background.Update(host, root, true)
			assert.are.equal(0, #ours(host))
		end)

		it("is put back when the window narrows", function()
			local bg = art(C.SPLIT_ATLAS, 0, 233 + C.EXTRA_WIDTH, 464)
			Background.Update(host, root, true)
			Background.Update(host, root, false)
			local copies = ours(host)
			assert.is_false(copies[1]:IsShown() or copies[2]:IsShown())
			assert.are.equal(1, bg:GetAlpha())
		end)

		it("is only built once", function()
			art(C.SPLIT_ATLAS, 0, 233 + C.EXTRA_WIDTH, 464)
			Background.Update(host, root, true)
			Background.Update(host, root, true)
			assert.are.equal(2, #ours(host))
		end)
	end)

	describe("other art", function()
		it("splits fixed-width art that ends at the old edge (the header strip)", function()
			local strip = art("StoneBG3", 0, 233, 59)
			Background.Update(host, root, true)
			assert.are.equal(2, #ours(host))
			assert.are.equal(0, strip:GetAlpha())
			assert.is_true(Background.IsExtended(strip))
		end)

		it("reflects art inside the old pane across the old edge", function()
			local crest = art("Crest", 40, 140, 120)
			Background.Update(host, root, true)
			local copies = ours(host)
			assert.are.equal(1, #copies)
			local gap = (233 + C.EXTRA_WIDTH) - 140
			local _, _, _, offset = copies[1]:GetPoint(1)
			assert.are.equal(2 * (gap - C.EXTRA_WIDTH), offset)
			assert.are.same({ 1, 0, 0, 1 }, copies[1]._coords)
			assert.are.equal(1, crest:GetAlpha())   -- the original stays
		end)

		it("leaves art that already stretches alone", function()
			art("Stretchy", 0, 233 + C.EXTRA_WIDTH, 464)
			Background.Update(host, root, true)
			assert.are.equal(0, #ours(host))
		end)

		it("ignores textures outside the pane and in the skipped frame", function()
			local left = wow.newFrame(nil, root)
			art("Model", -300, -67, 400, left)   -- the character model side
			local panel = wow.newFrame(nil, host)
			art("Ours", 0, 233, 100, panel)
			Background.Update(host, root, true, panel)
			assert.are.equal(0, #ours(left) + #ours(panel) + #ours(host))
		end)

		it("ignores hidden textures", function()
			art("StoneBG3", 0, 233, 59):Hide()
			Background.Update(host, root, true)
			assert.are.equal(0, #ours(host))
		end)

		it("finds art nested deeper in the window", function()
			local child = wow.newFrame(nil, wow.newFrame(nil, root))
			art("StoneBG3", 0, 233, 59, child)
			Background.Update(host, root, true)
			assert.are.equal(2, #ours(child))
		end)
	end)
end)
