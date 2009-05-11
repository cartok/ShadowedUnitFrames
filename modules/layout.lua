local Layout = ShadowUF:NewModule("Layout", "AceEvent-3.0")
local SML, config
local ordering, backdropCache, anchoringQueued, mediaRequired = {}, {}, {}, {}
local fontRequired, barRequired

function Layout:ToggleVisibility(frame, visible)
	if( frame ) then
		if( visible ) then
			frame:Show()
		else
			frame:Hide()
		end
	end
end	
	
-- We didn't have a texture or font needed at application, so check again here to find out if it was loaded yet
-- SML calls this on every register, even if the media is registered.
function Layout:MediaRegistered(event, mediaType, key)
	if( mediaType == SML.MediaType.STATUSBAR and barRequired and barRequired == key ) then
		barRequired = nil
		
		for frame in pairs(mediaRequired) do
			self:ApplyAll(frame)
		end
		
	elseif( mediaType == SML.MediaType.FONT and fontRequired and fontRequired == key ) then
		fontRequired = nil

		for frame in pairs(mediaRequired) do
			self:ApplyAll(frame)
		end
	end
	
	if( not fontRequired and not barRequired ) then
		for frame in pairs(mediaRequired) do
			mediaRequired[frame] = nil
		end
	end
end

-- Do a full update
function Layout:ApplyAll(frame)
	local unitConfig = ShadowUF.db.profile.layout[frame.unitType]
	if( not unitConfig ) then
		return
	end	
	
	self:ApplyUnitFrame(frame, unitConfig)
	self:ApplyPortrait(frame, unitConfig)
	self:ApplyBarVisuals(frame, unitConfig)
	self:ApplyBars(frame, unitConfig)
	self:ApplyIndicators(frame, unitConfig)
	self:ApplyAuras(frame, unitConfig)
	self:ApplyText(frame, unitConfig)
	
	-- Layouts been fully set
	ShadowUF:FireModuleEvent("LayoutApplied", frame)
end

function Layout:LoadSML()
	SML = SML or LibStub:GetLibrary("LibSharedMedia-3.0")
	SML.RegisterCallback(self, "LibSharedMedia_Registered", "MediaRegistered")

	SML:Register(SML.MediaType.FONT, "Myriad Condensed Web", "Interface\\AddOns\\ShadowedUnitFrames\\media\\fonts\\Myriad Condensed Web.ttf")
	SML:Register(SML.MediaType.STATUSBAR, "BantoBar", "Interface\\Addons\\ShadowedUnitFrames\\media\\textures\\banto")
	SML:Register(SML.MediaType.STATUSBAR, "Smooth",   "Interface\\Addons\\ShadowedUnitFrames\\media\\textures\\smooth")
	SML:Register(SML.MediaType.STATUSBAR, "Perl",     "Interface\\Addons\\ShadowedUnitFrames\\media\\textures\\perl")
	SML:Register(SML.MediaType.STATUSBAR, "Glaze",    "Interface\\Addons\\ShadowedUnitFrames\\media\\textures\\glaze")
	SML:Register(SML.MediaType.STATUSBAR, "Charcoal", "Interface\\Addons\\ShadowedUnitFrames\\media\\textures\\Charcoal")
	SML:Register(SML.MediaType.STATUSBAR, "Otravi",   "Interface\\Addons\\ShadowedUnitFrames\\media\\textures\\otravi")
	SML:Register(SML.MediaType.STATUSBAR, "Striped",  "Interface\\Addons\\ShadowedUnitFrames\\media\\textures\\striped")
	SML:Register(SML.MediaType.STATUSBAR, "LiteStep", "Interface\\Addons\\ShadowedUnitFrames\\media\\textures\\LiteStep")
	SML:Register(SML.MediaType.STATUSBAR, "Aluminium", "Interface\\Addons\\ShadowedUnitFrames\\media\\textures\\Aluminium")
end

--[[
	Keep in mind this is relative to where you're parenting it, RT will put the object outside of the frame, on the right side, at the top of it
	while ITR will put it inside the frame, at the top to the right
	
	RT = Right Top, RC = Right Center, RB = Right Bottom
	LT = Left Top, LC = Left Center, LB = Left Bottom,
	BL = Bottom Left, BC = Bottom Center, BR = Bottom Right
	ICL = Inside Center Left, IC = Inside Center Center, ICR = Inside Center Right
	TR = Top Right, TC = Top Center, TL = Top Left
	ITR = Inside Top Right, ITL = Inside Top Left
]]

local preDefPoint = {ICL = "LEFT", RT = "TOPLEFT", BC = "TOP", ICR = "RIGHT", LT = "TOPRIGHT", TR = "BOTTOMRIGHT", BL = "TOPLEFT", LB = "BOTTOMRIGHT", LC = "RIGHT", RB = "BOTTOMLEFT", RC = "LEFT", TC = "BOTTOM", BR = "TOPRIGHT", TL = "BOTTOMLEFT", ITR = "BOTTOMRIGHT", ITL = "BOTTOM", IC = "CENTER"}
local preDefRelative = {ICL = "LEFT", RT = "TOPRIGHT", BC = "BOTTOM", ICR = "RIGHT", LT = "TOPLEFT", TR = "TOPRIGHT", BL = "BOTTOMLEFT", LB = "BOTTOMLEFT", LC = "LEFT", RB = "BOTTOMRIGHT", RC = "RIGHT", TC = "TOP", BR = "BOTTOMRIGHT", TL = "TOPLEFT", ITR = "RIGHT", ITL = "LEFT", IC = "CENTER"}

-- Figures out how text should be justified based on where it's anchoring
function Layout:GetJustify(config)
	local point = config.anchorPoint and preDefPoint[config.anchorPoint] or config.point
	if( point ) then
		if( string.match(point, "LEFT$") ) then
			return "LEFT"
		elseif( string.match(point, "RIGHT$") ) then
			return "RIGHT"
		end
	end
	
	return "CENTER"
end

function Layout:GetPoint(key)
	return preDefPoint[key]
end

function Layout:GetRelative(key)
	return preDefRelative[key]
end

function Layout:AnchorFrame(parent, frame, config)
	if( not config or not config.anchorTo ) then
		return
	end
	
	local scale = 1
	if( config.effectiveScale ) then
		scale = parent:GetEffectiveScale()
	end
	
	-- $ = Indicates we're asking for one of the sub-frames inside the parent
	-- # = Indicates we're asking for one of SSUF's frames, and that it might not be created yet
	local anchorTo
	local prefix = string.sub(config.anchorTo, 0, 1)
	if( config.anchorTo == "$parent" ) then
		anchorTo = parent
	elseif( prefix == "$" ) then
		anchorTo = parent[string.sub(config.anchorTo, 2)]
	elseif( prefix == "#" ) then
		anchorTo = string.sub(config.anchorTo, 2)
		if( not getglobal(anchorTo) ) then
			frame.queuedParent = parent
			frame.queuedConfig = config
			frame.queuedName = anchorTo
			anchoringQueued[frame] = true
			
			-- Default position until we find the frame we want, this is fallback mostly
			-- so if you say, anchor targettarget to focus, then disable focus you'll see that targettarget
			-- has to now be repositioned
			frame:ClearAllPoints()
			frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
			return
		end
	else
		anchorTo = config.anchorTo
	end

	frame:ClearAllPoints()
	
	if( config.anchorPoint ) then
		frame:SetPoint(preDefPoint[config.anchorPoint], anchorTo, preDefRelative[config.anchorPoint], config.x / scale, config.y / scale)
	else
		frame:SetPoint(config.point, anchorTo, config.relativePoint, config.x / scale, config.y / scale)
	end
end

-- Setup the main frame
function Layout:ApplyUnitFrame(frame, config)
	local layout = ShadowUF.db.profile.layout
	local id = layout.backdrop.backgroundTexture .. layout.backdrop.borderTexture .. layout.backdrop.tileSize .. layout.backdrop.edgeSize .. layout.backdrop.tileSize .. layout.backdrop.inset
	local backdrop = backdropCache[id] or {
			bgFile = layout.backdrop.backgroundTexture,
			edgeFile = layout.backdrop.borderTexture,
			tile = layout.backdrop.tileSize > 0 and true or false,
			edgeSize = layout.backdrop.edgeSize,
			tileSize = layout.backdrop.tileSize,
			insets = {left = layout.backdrop.inset, right = layout.backdrop.inset, top = layout.backdrop.inset, bottom = layout.backdrop.inset}
	}
	
	frame:SetHeight(config.height)
	frame:SetWidth(config.width)
	frame:SetScale(config.scale)
	frame:SetBackdrop(backdrop)
	frame:SetBackdropColor(layout.backdrop.backgroundColor.r, layout.backdrop.backgroundColor.g, layout.backdrop.backgroundColor.b, layout.backdrop.backgroundColor.a)
	frame:SetBackdropBorderColor(layout.backdrop.borderColor.r, layout.backdrop.borderColor.g, layout.backdrop.borderColor.b, layout.backdrop.borderColor.a)
	frame:SetClampedToScreen(true)
	
	if( not frame.ignoreAnchor ) then
		self:AnchorFrame(UIParent, frame, ShadowUF.db.profile.positions[frame.unitType])
	end
	
	-- Grab media needed for this layout, if we can't find the media then flag that we need it still
	frame.barTexture = SML:Fetch(SML.MediaType.STATUSBAR, layout.general.barTexture, true)
	if( not frame.barTexture ) then
		frame.barTexture = "Interface\\Addons\\ShadowedUnitFrames\\media\\textures\\Aluminium"
		barRequired = layout.general.barTexture
		mediaRequired[frame] = true
	end

	frame.fontPath = SML:Fetch(SML.MediaType.font, layout.font.name, true)

	if( not frame.fontPath ) then
		frame.fontPath = "Interface\\AddOns\\ShadowedUnitFrames\\media\\fonts\\Myriad Condensed Web.ttf"
		fontRequired = layout.font.name
		mediaRequired[frame] = true
	end
	
	-- Check our queue
	for queuedFrame in pairs(anchoringQueued) do
		if( queuedFrame.queuedName == frame:GetName() ) then
			self:AnchorFrame(queuedFrame.queuedParent, queuedFrame, queuedFrame.queuedConfig)

			queuedFrame.queuedParent = nil
			queuedFrame.queuedConfig = nil
			anchoringQueued[queuedFrame] = nil
		end
	end
end

-- Setup portraits
function Layout:ApplyPortrait(frame, config)
	-- We want it to be a pixel inside the frame, so inset + clip gets us that
	local clip = ShadowUF.db.profile.layout.backdrop.inset + ShadowUF.db.profile.layout.general.clip
	
	self:ToggleVisibility(frame.portrait, config.portrait and config.portrait.enabled or false)
	if( frame.portrait and frame.portrait:IsShown() ) then
		frame.portrait:SetHeight(config.height - (clip * 2))
		frame.portrait:SetWidth(config.width * config.portrait.width)

		frame.barFrame:SetHeight(frame:GetHeight() - (clip * 2))

		-- Flip the alignment for targets to keep the same look as default
		local position = config.portrait.alignment
		if( not config.portrait.noAutoAlign and ( frame:GetAttribute("unit") == "target" or string.match(frame:GetAttribute("unit"), "%w+target") ) ) then
			position = config.portrait.alignment == "LEFT" and "RIGHT" or "LEFT"
		end

		if( position == "LEFT" ) then
			frame.portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", clip, -clip)
			frame.barFrame:SetPoint("RIGHT", frame.portrait)
			frame.barFrame:SetPoint("RIGHT", frame, -clip, 0)
			frame.barFrame:SetWidth(frame:GetWidth() - (clip * 2) - frame.portrait:GetWidth() - ShadowUF.db.profile.layout.general.clip)
		else
			frame.portrait:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -clip, -clip)
			frame.barFrame:SetPoint("LEFT", frame.portrait)
			frame.barFrame:SetPoint("LEFT", frame, clip, 0)
			frame.barFrame:SetWidth(frame:GetWidth() - (clip * 2) - frame.portrait:GetWidth() - ShadowUF.db.profile.layout.general.clip)
		end
	else
		frame.barFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", clip, -clip)
		frame.barFrame:SetHeight(frame:GetHeight() - (clip * 2))
		frame.barFrame:SetWidth(frame:GetWidth() - (clip * 2))
	end
end

-- Setup bars
function Layout:ApplyBarVisuals(frame, config)
	-- Update health bars
	self:ToggleVisibility(frame.healthBar, config.healthBar and config.healthBar.enabled or false)
	if( frame.healthBar and frame.healthBar:IsShown() ) then
		frame.healthBar:SetStatusBarTexture(frame.barTexture)
		
		if( config.healthBar.background ) then
			frame.healthBar.background:SetTexture(frame.barTexture)
			frame.healthBar.background:Show()
		else
			frame.healthBar.background:Hide()
		end
	end
	
	-- Update mana bars
	self:ToggleVisibility(frame.manaBar, config.manaBar and config.manaBar.enabled or false)
	if( frame.manaBar and frame.manaBar:IsShown() ) then
		frame.manaBar:SetStatusBarTexture(frame.barTexture)

		if( config.manaBar.background ) then
			frame.manaBar.background:SetTexture(frame.barTexture)
			frame.manaBar.background:Show()
		else
			frame.manaBar.background:Hide()
		end
	end

	-- Update cast bars
	self:ToggleVisibility(frame.castBar, config.castBar and config.castBar.enabled or false)
	if( frame.castBar and frame.castBar:IsShown() ) then
		frame.castBar:SetStatusBarTexture(frame.barTexture)

		if( config.castBar.background ) then
			frame.castBar.background:SetTexture(frame.barTexture)
			frame.castBar.background:Show()
		else
			frame.castBar.background:Hide()
		end
	end
	
	-- Update XP bar
	self:ToggleVisibility(frame.xpBar, config.xpBar and config.xpBar.enabled or false)
	if( frame.xpBar and frame.xpBar:IsShown() ) then
		frame.xpBar:SetStatusBarTexture(frame.barTexture)
		frame.xpBar.rested:SetStatusBarTexture(frame.barTexture)
		
		if( config.xpBar.background ) then
			frame.xpBar.background:SetTexture(frame.barTexture)
			frame.xpBar.background:Show()
		else
			frame.xpBar.background:Hide()
		end
	end
end

-- Setup text
local function updateShadows(fontString)
		if( ShadowUF.db.profile.layout.font.shadowColor and ShadowUF.db.profile.layout.font.shadowX and ShadowUF.db.profile.layout.font.shadowY ) then
			fontString:SetShadowColor(ShadowUF.db.profile.layout.font.shadowColor.r, ShadowUF.db.profile.layout.font.shadowColor.g, ShadowUF.db.profile.layout.font.shadowColor.b, ShadowUF.db.profile.layout.font.a)
			fontString:SetShadowOffset(ShadowUF.db.profile.layout.font.shadowX, ShadowUF.db.profile.layout.font.shadowY)
		else
			fontString:SetShadowColor(0, 0, 0, 0)
			fontString:SetShadowOffset(0, 0)
		end
end

function Layout:ApplyText(frame, config)
	-- Update cast bar text
	if( frame.castBar and frame.castBar:IsShown() ) then
			frame.castBar.name:SetFont(frame.fontPath, ShadowUF.db.profile.layout.font.size)
			frame.castBar.name:SetWidth(frame.castBar:GetWidth() * 0.80)
			frame.castBar.name:SetHeight(ShadowUF.db.profile.layout.font.size + 1)
			frame.castBar.name:SetJustifyH(self:GetJustify(config.castBar.castName))
			self:AnchorFrame(frame.castBar, frame.castBar.name, config.castBar.castName)

			updateShadows(frame.castBar.name)
			
			frame.castBar.time:SetFont(frame.fontPath, ShadowUF.db.profile.layout.font.size)
			frame.castBar.time:SetWidth(frame.castBar:GetWidth() * 0.20)
			frame.castBar.time:SetHeight(ShadowUF.db.profile.layout.font.size + 1)
			frame.castBar.time:SetJustifyH(self:GetJustify(config.castBar.castTime))
			self:AnchorFrame(frame.castBar, frame.castBar.time, config.castBar.castTime)

			updateShadows(frame.castBar.time)
	end

	-- Update tag text
	if( not config.text ) then
		if( frame.fontStrings ) then
			for _, fontString in pairs(frame.fontStrings) do
				fontString:Hide()
			end
		end
		return
	end
	
	frame.fontStrings = frame.fontStrings or {}
	for _, fontString in pairs(frame.fontStrings) do
		fontString:Hide()
	end
	
	for id, row in pairs(config.text) do
		local parent = row.anchorTo == "$parent" and frame or frame[string.sub(row.anchorTo, 2)]
		if( parent and row.enabled ) then
			local fontString = frame.fontStrings[id] or frame:CreateFontString(nil, "ARTWORK")
			fontString:SetFont(frame.fontPath, ShadowUF.db.profile.layout.font.size)
			fontString:SetText(row.text)
			fontString:SetParent(parent)
			fontString:SetJustifyH(self:GetJustify(row))
			self:AnchorFrame(frame, fontString, row)
			
			if( row.widthPercent ) then
				fontString:SetWidth(parent:GetWidth() * row.widthPercent)
				fontString:SetHeight(ShadowUF.db.profile.layout.font.size + 1)
			elseif( row.height or row.width ) then
				fontString:SetWidth(row.width)
				fontString:SetHeight(row.height)
			end
			
			updateShadows(fontString)
			
			ShadowUF.modules.Tags:Register(frame, fontString, row.text)
			fontString:UpdateTags()
			fontString:Show()
			
			frame.fontStrings[id] = fontString
			frame:RegisterUpdateFunc(fontString, "UpdateTags")
		end
	end
end

-- Setup indicators
function Layout:ApplyIndicators(frame, config)
	if( not frame.indicators or not config.indicators ) then
		if( frame.indicators ) then
			for _, indicator in pairs(frame.indicators) do
				indicator:Hide()
			end
		end
		return
	end
	
	for _, key in pairs(frame.indicators.list) do
		local indicator = frame.indicators[key]
		self:ToggleVisibility(indicator, config.indicators[key] and config.indicators[key].enabled or false)
		
		if( indicator:IsShown() ) then
			indicator:SetHeight(config.indicators[key].height)
			indicator:SetWidth(config.indicators[key].width)
			
			self:AnchorFrame(frame, indicator, config.indicators[key])
		end
	end
end

-- Setup auras
local function positionAuras(self, config)
	for id, button in pairs(self.buttons) do
		button:SetHeight(config.size)
		button:SetWidth(config.size)
		button.border:SetHeight(config.size + 1)
		button.border:SetWidth(config.size + 1)
		button:ClearAllPoints()
		
		-- If's ahoy
		if( id > 1 ) then
			if( config.position == "BOTTOM" or config.position == "TOP" or config.position == "INSIDE" ) then
				if( id % config.inColumn == 1 ) then
					if( config.position == "TOP" ) then
						button:SetPoint("BOTTOM", self.buttons[id - config.inColumn], "TOP", 0, 3)
					else
						button:SetPoint("TOP", self.buttons[id - config.inColumn], "BOTTOM", 0, -3)
					end
				elseif( config.position == "INSIDE" ) then
					button:SetPoint("RIGHT", self.buttons[id - 1], "LEFT", -3, 0)
				else
					button:SetPoint("LEFT", self.buttons[id - 1], "RIGHT", 3, 0)
				end
			elseif( config.rows == 1 or id % config.rows == 1 ) then
				if( config.position == "RIGHT" ) then
						button:SetPoint("LEFT", self.buttons[id - config.rows], "RIGHT", 2, 0)
				else
					button:SetPoint("RIGHT", self.buttons[id - config.rows], "LEFT", -2, 0)
				end
			else
				button:SetPoint("TOP", self.buttons[id - 1], "BOTTOM", 0, -3)
			end
		elseif( config.position == "INSIDE" ) then
			button:SetPoint("TOPRIGHT", self.parent.healthBar, "TOPRIGHT", config.x + -ShadowUF.db.profile.layout.general.clip, config.y + -ShadowUF.db.profile.layout.general.clip)
		elseif( config.position == "BOTTOM" ) then
			button:SetPoint("BOTTOMLEFT", self.parent, "BOTTOMLEFT", config.x + ShadowUF.db.profile.layout.backdrop.inset, config.y + -(config.size + 2))
		elseif( config.position == "TOP" ) then
			button:SetPoint("TOPLEFT", self.parent, "TOPLEFT", config.x + ShadowUF.db.profile.layout.backdrop.inset, config.y + (config.size + 2))
		elseif( config.position == "LEFT" ) then
			button:SetPoint("TOPLEFT", self.parent, "TOPLEFT", config.x + -config.size, config.y + ShadowUF.db.profile.layout.backdrop.inset + ShadowUF.db.profile.layout.general.clip)
		elseif( config.position == "RIGHT" ) then
			button:SetPoint("TOPRIGHT", self.parent, "TOPRIGHT", config.x + config.size, config.y + ShadowUF.db.profile.layout.backdrop.inset + ShadowUF.db.profile.layout.general.clip)
		end
	end
end

function Layout:ApplyAuras(frame, config)
	if( not frame.auras or not config.auras ) then
		if( frame.auras ) then
			for _, aura in pairs(frame.auras) do
				aura:Hide()
			end
		end
		return
	end
	
	-- Update aura position
	for key, aura in pairs(frame.auras) do
		self:ToggleVisibility(aura, config.auras[key].enabled)
		
		if( aura:IsShown() ) then
			positionAuras(aura, config.auras[key])
		end
	end
	
	-- Do the auras share the same location?
	frame.aurasShared = config.auras.buffs.position == config.auras.debuffs.position
end

-- Setup the bar ordering/info
local currentConfig
local function sortOrder(a, b)
	return ((currentConfig[a].order or 100) < (currentConfig[b].order or 100))
end

function Layout:ApplyBars(frame, config)
	-- Figure out the height of a few widgets, and set the size/positioning correctly
	local totalWeight = 0
	local totalBars = -1

	for i=#(ordering), 1, -1 do table.remove(ordering, i) end
	for key, data in pairs(config) do
			if( type(data) == "table" and data.heightWeight and frame[key] and frame[key]:IsShown() ) then
				totalWeight = totalWeight + data.heightWeight
				totalBars = totalBars + 1
				
				table.insert(ordering, key)
			end
	end
	
	currentConfig = config
	table.sort(ordering, sortOrder)
		
	local lastFrame
	local availableHeight = frame.barFrame:GetHeight() - (math.abs(ShadowUF.db.profile.layout.general.barSpacing) * totalBars)
	for id, key in pairs(ordering) do
		local bar = frame[key]
		bar:ClearAllPoints()
		bar:SetWidth(frame.barFrame:GetWidth())
		bar:SetHeight(availableHeight * (config[key].heightWeight / totalWeight))
		
		if( id > 1 ) then
				bar:SetPoint("TOPLEFT", lastFrame, "BOTTOMLEFT", 0, ShadowUF.db.profile.layout.general.barSpacing)
		else
				bar:SetPoint("TOPLEFT", frame.barFrame, "TOPLEFT", 0, 0)
		end
		
		lastFrame = bar
	end
end



 