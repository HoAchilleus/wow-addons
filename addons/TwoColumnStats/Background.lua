-- Extends the stats pane's background art into the extra width.
--
-- Some art doesn't follow the pane when it widens: fixed-width textures stop
-- where the pane used to end, and the main background repeats its image. So
-- while the window is wide, that art is redrawn as mirror images, which hides
-- the joins. Textures that already stretch are left alone.
local _, ns = ...
local C, Layout = ns.Config, ns.Layout

local Background = {}
ns.Background = Background

local mirrorOf = {}   -- [art texture] = reflected copy (or false if it can't be)
local splitOf = {}    -- [art texture] = { left half, mirrored half } (or false)

-- Calls fn(texture, depth) for every texture under frame, however deeply
-- nested, skipping the frame `skip` (our own panel).
function Background.EachTexture(frame, fn, skip, depth)
	depth = depth or 0
	if depth > 8 then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetAtlas then fn(region, depth) end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		if child ~= skip then Background.EachTexture(child, fn, skip, depth + 1) end
	end
end

-- How far a texture's right edge stops short of hostRight.
function Background.RightGap(tex, hostRight)
	local right = tex:GetRight()
	return right and hostRight and (hostRight - right) or nil
end

-- Texture file and coordinates (left, right, top, bottom), whether the
-- texture uses an atlas or a plain file.
function Background.TextureSource(tex)
	local atlas = tex:GetAtlas()
	local info = atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
	if info and (info.file or info.filename) then
		return info.file or info.filename,
			info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	end
	local file = tex:GetTexture()
	if not file then return nil end
	local ulx, uly, _, lly, urx = tex:GetTexCoord()
	return file, ulx, urx, uly, lly
end

function Background.IsOurs(tex)
	return tex.isTcsMirror == true
end

function Background.IsExtended(tex)
	return (mirrorOf[tex] or splitOf[tex]) and true or false
end

local function newLike(src, file)
	local layer, sublevel = src:GetDrawLayer()
	local tex = src:GetParent():CreateTexture(nil, layer, nil, sublevel)
	tex:SetTexture(file)
	tex:SetVertexColor(src:GetVertexColor())
	tex.isTcsMirror = true
	tex:Hide()
	return tex
end

-- Draws the art's left half-pane, then its mirror image, so the reflection
-- sits exactly on the middle of the widened pane. The original is hidden
-- while these show. baseWidth is the art's normal width.
function Background.BuildSplit(src, baseWidth)
	local file, l, r, t, b = Background.TextureSource(src)
	if not file or not baseWidth or baseWidth <= 0 then
		splitOf[src] = false
		return
	end
	local half, edge = Layout.SplitGeometry(baseWidth, l, r)

	local left = newLike(src, file)
	left:SetTexCoord(l, edge, t, b)
	left:SetPoint("TOPLEFT", src, "TOPLEFT")
	left:SetPoint("BOTTOMLEFT", src, "BOTTOMLEFT")
	left:SetWidth(half)

	local right = newLike(src, file)
	right:SetTexCoord(edge, l, t, b)   -- reversed: a mirror image
	right:SetPoint("TOPLEFT", left, "TOPRIGHT")
	right:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT")
	right:SetWidth(half)

	splitOf[src] = { left, right }
end

-- Reflects art that sits inside the old pane across the old pane edge.
function Background.BuildMirror(src, gap)
	local file, l, r, t, b = Background.TextureSource(src)
	local w = src:GetWidth()
	if not file or not w or w <= 0 or not gap then
		mirrorOf[src] = false
		return
	end
	local offset = Layout.InsideMirrorOffset(gap)
	local tex = newLike(src, file)
	tex:SetAlpha(src:GetAlpha())
	tex:SetTexCoord(r, l, t, b)
	tex:SetPoint("TOPLEFT", src, "TOPRIGHT", offset, 0)
	tex:SetPoint("BOTTOMLEFT", src, "BOTTOMRIGHT", offset, 0)
	tex:SetWidth(w)
	mirrorOf[src] = tex
end

-- Looks for art that needs extending inside host (searching all of scanRoot,
-- since some of the pane's art lives outside host), builds copies for any
-- new ones, and shows or hides every copy. Call after the pane is resized.
function Background.Update(host, scanRoot, widen, skip)
	if widen and host:IsVisible() then
		local hostLeft, hostRight = host:GetLeft(), host:GetRight()
		Background.EachTexture(scanRoot, function(tex)
			if Background.IsOurs(tex) or splitOf[tex] ~= nil or mirrorOf[tex] ~= nil then return end
			if not tex:IsVisible() then return end
			local left = tex:GetLeft()
			if not left or not hostLeft or left < hostLeft - 2 then return end
			if tex:GetAtlas() == C.SPLIT_ATLAS then
				-- Already stretched to the wide pane, so its normal width is the
				-- current one less the extra. If the width hasn't caught up yet,
				-- this runs again on the next check.
				local baseWidth = (tex:GetWidth() or 0) - C.EXTRA_WIDTH
				if baseWidth >= C.MIN_ART_WIDTH then Background.BuildSplit(tex, baseWidth) end
				return
			end
			local w, h = tex:GetSize()
			local gap = Background.RightGap(tex, hostRight)
			local kind = Layout.ClassifyArt(w, h, gap)
			if kind == "edge" then
				Background.BuildSplit(tex, w)
			elseif kind == "inside" then
				Background.BuildMirror(tex, gap)
			end
		end, skip)
	end

	for src, tex in pairs(mirrorOf) do
		if tex then tex:SetShown(widen and src:IsShown()) end
	end
	for src, halves in pairs(splitOf) do
		if halves then
			local show = widen and src:IsShown()
			halves[1]:SetShown(show)
			halves[2]:SetShown(show)
			src:SetAlpha(show and 0 or 1)
		end
	end
end

-- For tests: forget every copy.
function Background._Reset()
	mirrorOf, splitOf = {}, {}
end
