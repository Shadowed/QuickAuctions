local QuickAuctions = select(2, ...)
local Tradeskill = QuickAuctions:NewModule("Tradeskill", "AceEvent-3.0")
local L = QuickAuctions.L
local ROW_HEIGHT = 16
local MAX_ROWS = 23
local creatingItem, creatingItemID
local itemList, rowDisplay, materials, tradeList, enchantMap = {}, {}, {}, {}, {}
local professions = {[GetSpellInfo(2259)] = "Alchemy", [GetSpellInfo(2018)] = "Blacksmith", [GetSpellInfo(33359)] = "Cook", [GetSpellInfo(2108)] = "Leatherworker", [GetSpellInfo(7411)] = "Enchanter", [GetSpellInfo(4036)] = "Engineer", [GetSpellInfo(51311)] = "Jewelcrafter", [GetSpellInfo(3908)] = "Tailor", [GetSpellInfo(45357)] = "Scribe"}

function Tradeskill:OnInitialize()
	self:RegisterEvent("TRADE_SKILL_SHOW")
	self:RegisterEvent("TRADE_SKILL_UPDATE")
	self:RegisterEvent("TRADE_SKILL_CLOSE")
	
	if( GetTradeSkillLine() and professions[GetTradeSkillLine()] ) then
		self:TRADE_SKILL_SHOW()
	end
end

function Tradeskill:StartCastEvents()
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
end

function Tradeskill:StopCastEvents()
	self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	self:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED")
end

function Tradeskill:GetEnchantItemID(tradeID)
	local name = GetTradeSkillInfo(tradeID)
	return name and enchantMap[name]
end

function Tradeskill:Update()
	local self = Tradeskill
	
	-- Reset
	for i=#(rowDisplay), 1, -1 do table.remove(rowDisplay, i) end
	for _, row in pairs(self.rows) do row:Hide() end
	
	-- Build our display list
	for id, itemid in pairs(itemList) do
		if( tradeList[itemid] and QuickAuctions.db.realm.craftQueue[itemid] ) then
			table.insert(rowDisplay, id)
		end
	end
	
	if( #(rowDisplay) > 0 ) then
		table.insert(rowDisplay, string.format("|cffffce00%s|r", L["Materials required"]))
		
		for itemid, needed in pairs(materials) do
			local itemCount = GetItemCount(itemid)
			local color = RED_FONT_COLOR_CODE
			if( itemCount >= needed ) then
				color = GREEN_FONT_COLOR_CODE
			end
			
			table.insert(rowDisplay, string.format("%s %s[%d/%d]|r", (GetItemInfo(itemid)), color, itemCount, needed))
		end
	end
		
	-- Update scroll bar
	FauxScrollFrame_Update(self.frame.scroll, #(rowDisplay), MAX_ROWS - 1, ROW_HEIGHT)
	
	-- Now display
	local offset = FauxScrollFrame_GetOffset(self.frame.scroll)
	local displayIndex = 0
	
	for index, data in pairs(rowDisplay) do
		if( index >= offset and displayIndex < MAX_ROWS ) then
			displayIndex = displayIndex + 1
			
			local row = self.rows[displayIndex]
			if( type(data) == "number" ) then	
				local itemid = itemList[data]
				local itemName = GetItemInfo(itemid) or GetSpellInfo(itemid)
				row:SetFormattedText("%s [%d]", itemName, QuickAuctions.db.realm.craftQueue[itemid])
				row.itemID = itemid
			else
				row:SetText(data)
				row.itemID = nil
			end
			
			row:Show()
		end
	end
end

function Tradeskill:BuyMaterials()
	for i=1, GetMerchantNumItems() do
		local link = QuickAuctions:GetSafeLink(GetMerchantItemLink(i))
		if( materials[link] ) then
			local maxStack = GetMerchantItemMaxStack(i)
			local toBuy = materials[link] - GetItemCount(link)
			while( toBuy > 0 ) do
				BuyMerchantItem(i, math.min(toBuy, maxStack))
				toBuy = toBuy - maxStack
			end
		end
	end
end

-- Rebuild the item list
local function sortItems(a, b)
	return a > b
end

function Tradeskill:RebuildList()
	table.wipe(itemList)
	table.wipe(enchantMap)
	
	for itemid in pairs(QuickAuctions.db.realm.craftQueue) do
		if( tradeList[itemid] ) then
			table.insert(itemList, itemid)
			enchantMap[string.match(GetItemInfo(itemid) or "", L["Scroll of (.+)"]) or ""] = itemid
		end
	end

	table.sort(itemList, sortItems)
end

-- Trade skill queue list
function Tradeskill:CreateFrame()
	if( self.frame ) then
		return
	end
	
	local function OnShow()
		Tradeskill:RebuildList()
		Tradeskill:Update()
	end

	local function showTooltip(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText(self.tooltip, nil, nil, nil, nil, true)
		GameTooltip:Show()
	end

	local function hideTooltip(self)
		GameTooltip:Hide()
	end
	
	-- Toggle showing the queue frame thing
	self.button = CreateFrame("Button", nil, TradeSkillFrame, "UIPanelButtonGrayTemplate")
	self.button:SetHeight(18)
	self.button:SetWidth(30)
	self.button:SetText("QA")
	self.button.tooltip = L["Click to view Quick Auctions tradeskill queue"]
	self.button:SetPoint("TOPRIGHT", TradeSkillFrame, "TOPRIGHT", -60, -15)
	self.button:SetScript("OnEnter", showTooltip)
	self.button:SetScript("OnLeave", hideTooltip)
	self.button:SetScript("OnClick", function()
		if( Tradeskill.frame:IsVisible() ) then
			Tradeskill.frame:Hide()
		else
			Tradeskill.frame:Show()
		end
	end)
	
	local timeLeft = 0
	local function OnUpdate(self, elapsed)
		timeLeft = timeLeft - elapsed
		if( timeLeft <= 0 ) then
			self:Enable()
			self:SetText("Buy")
			self:SetScript("OnUpdate", nil)
			return
		end
		
		self:SetFormattedText("%.1f", timeLeft)
	end

	-- Toggle showing the queue frame thing
	self.buy = CreateFrame("Button", nil, TradeSkillFrame, "UIPanelButtonGrayTemplate")
	self.buy:SetHeight(18)
	self.buy:SetWidth(30)
	self.buy:SetText(L["Buy"])
	self.buy:SetPoint("TOPLEFT", TradeSkillFrame, "TOPLEFT", 68, -15)
	self.buy.tooltip = L["Click to buy materials required.\n\nThis might lock your client up for a few seconds."]
	self.buy:SetScript("OnEnter", showTooltip)
	self.buy:SetScript("OnLeave", hideTooltip)
	self.buy:SetScript("OnHide", function() timeLeft = 0 end)
	self.buy:SetScript("OnClick", function(self)
		timeLeft = 4
		self:SetScript("OnUpdate", OnUpdate)
		self:Disable()
		Tradeskill:BuyMaterials()
	end)
	
	-- Actual queue frame UI
	self.frame = CreateFrame("Frame", nil, TradeSkillFrame)
	self.frame:SetWidth(250)
	self.frame:SetHeight(427)
	self.frame:SetClampedToScreen(true)
	self.frame:SetFrameStrata("HIGH")
	self.frame:SetScript("OnShow", OnShow)
	self.frame:SetPoint("TOPLEFT", TradeSkillFrame, "TOPRIGHT", -10, -10)
	self.frame:Hide()
	self.frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		edgeSize = 26,
		insets = {left = 9, right = 9, top = 9, bottom = 9},
	})
		
	-- Scroll frame
	self.frame.scroll = CreateFrame("ScrollFrame", "QACraftGUIScroll", self.frame, "FauxScrollFrameTemplate")
	self.frame.scroll:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -10)
	self.frame.scroll:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -30, 8)
	self.frame.scroll:SetScript("OnVerticalScroll", function(self, value) FauxScrollFrame_OnVerticalScroll(self, value, ROW_HEIGHT, Tradeskill.Update) end)
	
	self.rows = {}
		
	local function craftItem(self)
		if( InCombatLockdown() ) then
			return
		end
		
		if( not self.itemID or UnitCastingInfo("player") or UnitChannelInfo("player") ) then
			self:SetAttribute("type", nil)
			return
		end
				
		for i=1, GetNumTradeSkills() do
			local itemid = QuickAuctions:GetSafeLink(GetTradeSkillItemLink(i)) or Tradeskill:GetEnchantItemID(i)
			if( itemid == self.itemID and QuickAuctions.db.realm.craftQueue[itemid] ) then
				-- Make sure we don't wait for it to create more than we can
				local createCap = select(3, GetTradeSkillInfo(i))
				local quantity = math.min(QuickAuctions.db.realm.craftQueue[itemid], createCap)
				local name = GetItemInfo(itemid) or GetSpellInfo(itemid)

				creatingItem = name
				creatingItemID = itemid

				self:SetAttribute("type", "macro")
				self:SetAttribute("macrotext", string.format("/script DoTradeSkill(%d,%d);", i, quantity))
				
				Tradeskill:StartCastEvents()
			end
		end
	end
	
	for i=1, MAX_ROWS do
		local row = CreateFrame("Button", nil, self.frame, "SecureActionButtonTemplate")
		row:SetWidth(self.frame:GetWidth())
		row:SetHeight(ROW_HEIGHT)
		row:SetNormalFontObject(GameFontHighlightSmall)
		row:SetText("*")
		row:GetFontString():SetPoint("LEFT", row, "LEFT", 0, 0)
		row:SetPushedTextOffset(0, 0)
		row:SetScript("PreClick", craftItem)
		
		if( i > 1 ) then
			row:SetPoint("TOPLEFT", self.rows[i - 1], "BOTTOMLEFT", 0, -2)
		else
			row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 12, -8)
		end
		
		self.rows[i] = row
	end
end

function Tradeskill:TRADE_SKILL_SHOW()
	self:RegisterEvent("BAG_UPDATE")
	self:CreateFrame()
	self:TradeskillUpdate()
end

function Tradeskill:TRADE_SKILL_CLOSE()
	self:UnregisterEvent("BAG_UPDATE")
end


-- Trade skill opened/updated, save list (again) if needed
do
	local timeElapsed = 0
	local frame = CreateFrame("Frame")
	frame:SetScript("OnUpdate", function(self, elapsed)
		timeElapsed = timeElapsed + elapsed
		
		if( timeElapsed >= 0.25 ) then
			timeElapsed = 0
			self:Hide()
			
			Tradeskill:TradeskillUpdate()
		end
	end)
	frame:Hide()
	
	function Tradeskill:TRADE_SKILL_UPDATE()
		timeElapsed = 0
		frame:Show()
	end
	
	function Tradeskill:TradeskillUpdate()
		if( IsTradeSkillLinked() or not GetTradeSkillLine() or not professions[GetTradeSkillLine()]) then
			return
		end
		
		-- This way we know we have data for this profession and can show if we can/cannot make it
		QuickAuctions.db.realm.crafts[professions[GetTradeSkillLine()]] = true
				
		-- Reset materials list
		for k in pairs(materials) do materials[k] = nil end
		-- Reset item list so we know what to show/what not to
		for k in pairs(tradeList) do tradeList[k] = nil end
		
		-- Record list
		for i=1, GetNumTradeSkills() do
			local itemid = QuickAuctions:GetSafeLink(GetTradeSkillItemLink(i))
			if( itemid ) then
				local enchantid = string.match(GetTradeSkillRecipeLink(i), "enchant:([0-9]+)")
				QuickAuctions.db.realm.crafts[itemid] = tonumber(enchantid) or true
				
				-- Create a list of items we need to create this item
				if( QuickAuctions.db.realm.craftQueue[itemid] ) then
					for rID=1, GetTradeSkillNumReagents(i) do
						local perOne = select(3, GetTradeSkillReagentInfo(i, rID))
						local link = QuickAuctions:GetSafeLink(GetTradeSkillReagentItemLink(i, rID))
						if( link ) then
							materials[link] = (materials[link] or 0) + (QuickAuctions.db.realm.craftQueue[itemid] * perOne)
						end
					end
				end
				
				tradeList[itemid] = true
			end
		end
		
		if( self.frame and self.frame:IsVisible() ) then
			self:RebuildList()
			self:Update()
		end
	end
end

-- Item we were crafting was created
function Tradeskill:UNIT_SPELLCAST_SUCCEEDED(event, unit, name)
	if( unit == "player" and name == creatingItem and QuickAuctions.db.realm.craftQueue[creatingItemID] ) then
		QuickAuctions.db.realm.craftQueue[creatingItemID] = QuickAuctions.db.realm.craftQueue[creatingItemID] - 1

		if( QuickAuctions.db.realm.craftQueue[creatingItemID] <= 0 ) then
			QuickAuctions.db.realm.craftQueue[creatingItemID] = nil

			creatingItem = nil
			creatingItemID = nil
			
			self:StopCastEvents()
		end
	end
end

-- Cast interrupted, reset our flags
function Tradeskill:UNIT_SPELLCAST_INTERRUPTED(event, unit, name)
	if( unit == "player" and name == creatingItem ) then
		creatingItem = nil
		creatingItemID = nil
		self:StopCastEvents()
	end
end

do
	local timeElapsed = 0
	local frame = CreateFrame("Frame")
	frame:SetScript("OnUpdate", function(self, elapsed)
		timeElapsed = timeElapsed + elapsed
		
		if( timeElapsed >= 0.25 ) then
			timeElapsed = 0
			self:Hide()
			
			Tradeskill:Update()
		end
	end)
	frame:Hide()

	-- Bag updating (With throttlign)
	function Tradeskill:BAG_UPDATE()
		timeElapsed = 0
		frame:Show()
	end
end