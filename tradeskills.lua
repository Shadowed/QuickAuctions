QA.Tradeskill = {}

local Tradeskill = QA.Tradeskill
local L = QuickAuctionsLocals
local ROW_HEIGHT = 16
local MAX_ROWS = 23
local throttle, creatingItem, creatingItemID
local itemList, rowDisplay, materials, tradeList = {}, {}, {}, {}

local professions = {
	[GetSpellInfo(2259)] = "Alchemy", [GetSpellInfo(2018)] = "Blacksmith", [GetSpellInfo(33359)] = "Cook",
	[GetSpellInfo(2108)] = "Leatherworker", [GetSpellInfo(7411)] = "Enchanter", [GetSpellInfo(4036)] = "Engineer",
	[GetSpellInfo(51311)] = "Jewelcrafter", [GetSpellInfo(3908)] = "Tailor", [GetSpellInfo(45357)] = "Scribe",
}

function Tradeskill:Update()
	local self = Tradeskill
	
	-- Reset
	for i=#(rowDisplay), 1, -1 do table.remove(rowDisplay, i) end
	for _, row in pairs(self.rows) do row:Hide() end
	
	-- Build our display list
	for id, itemid in pairs(itemList) do
		if( tradeList[itemid] and QuickAuctionsDB.craftQueue[itemid] ) then
			table.insert(rowDisplay, id)
		end
	end
	
	table.insert(rowDisplay, string.format("|cffffce00%s|r", L["Materials required"]))
	
	for itemid, needed in pairs(materials) do
		local itemCount = GetItemCount(itemid)
		local color = RED_FONT_COLOR_CODE
		if( itemCount >= needed ) then
			color = GREEN_FONT_COLOR_CODE
		end
		
		table.insert(rowDisplay, string.format("%s %s[%d/%d]|r", (GetItemInfo(itemid)), color, itemCount, needed))
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
				row:SetFormattedText("%s [%d]", (GetItemInfo(itemid)), QuickAuctionsDB.craftQueue[itemid])
				row.itemID = itemid
			else
				row:SetText(data)
				row.itemID = nil
			end
			
			row:Show()
		end
	end
end

-- Rebuild the item list
local function sortItems(a, b)
	return a > b
end

function Tradeskill:RebuildList()
	for i=#(itemList), 1, -1 do table.remove(itemList, i) end
	for itemid in pairs(QuickAuctionsDB.craftQueue) do
		if( tradeList[itemid] ) then
			table.insert(itemList, itemid)
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
		QA.Tradeskill:RebuildList()
		Tradeskill:Update()
	end
	
	-- Toggle showing the queue frame thing
	self.button = CreateFrame("Button", nil, TradeSkillFrame, "UIPanelButtonGrayTemplate")
	self.button:SetHeight(18)
	self.button:SetWidth(30)
	self.button:SetText("QA")
	self.button:SetPoint("TOPRIGHT", TradeSkillFrame, "TOPRIGHT", -65, -15)
	self.button:SetScript("OnClick", function()
		if( Tradeskill.frame:IsVisible() ) then
			Tradeskill.frame:Hide()
		else
			Tradeskill.frame:Show()
		end
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
		
	-- Container frame backdrop
	local backdrop = {
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 3, right = 3, top = 5, bottom = 3 }
	}
	
	-- scroll frame
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
			local itemid = QA:GetSafeLink(GetTradeSkillItemLink(i))
			if( itemid == self.itemID and QuickAuctionsDB.craftQueue[itemid] ) then
				-- Make sure we don't wait for it to create more than we can
				local quantity = QuickAuctionsDB.craftQueue[itemid]
				local name = GetItemInfo(itemid)
				local createCap = select(3, GetTradeSkillInfo(i))
				if( quantity > createCap ) then
					quantity = createCap
				end

				creatingItem = name
				creatingItemID = itemid

				self:SetAttribute("type", "macro")
				self:SetAttribute("macrotext", string.format("/script DoTradeSkill(%d,%d);", i, quantity))
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

function Tradeskill:ADDON_LOADED(event, addon)
	if( addon ~= "Blizzard_TradeSkillUI" ) then
		return
	end
	
	self:CreateFrame()
end

-- Trade skill opened/updated, save list (again) if needed
function Tradeskill:TRADE_SKILL_UPDATE()
	if( IsTradeSkillLinked() or not GetTradeSkillLine() or not professions[GetTradeSkillLine()] or ( throttle and throttle > GetTime() ) ) then
		return
	end
	
	throttle = GetTime() + 1
	
	-- This way we know we have data for this profession and can show if we can/cannot make it
	if( QuickAuctionsDB.saveCraft ) then
		QuickAuctionsDB.crafts[professions[GetTradeSkillLine()]] = true
	end	
	
	-- Reset materials list
	for k in pairs(materials) do materials[k] = nil end
	-- Reset item list so we know what to show/what not to
	for k in pairs(tradeList) do tradeList[k] = nil end
	
	-- Record list
	for i=1, GetNumTradeSkills() do
		local itemid = QA:GetSafeLink(GetTradeSkillItemLink(i))
		if( itemid ) then
			if( QuickAuctionsDB.saveCraft ) then
				QuickAuctionsDB.crafts[itemid] = true
			end
			
			-- Create a list of items we need to create this item
			if( QuickAuctionsDB.craftQueue[itemid] ) then
				for rID=1, GetTradeSkillNumReagents(i) do
					local perOne = select(3, GetTradeSkillReagentInfo(i, rID))
					local link = QA:GetSafeLink(GetTradeSkillReagentItemLink(i, rID))

					materials[link] = (materials[link] or 0) + (QuickAuctionsDB.craftQueue[itemid] * perOne)
				end
			end
			
			tradeList[itemid] = true
		end
	end
	
	if( self.frame and self.frame:IsVisible() ) then
		self:Update()
	end
end

-- Item we were crafting was created
function Tradeskill:UNIT_SPELLCAST_SUCCEEDED(event, unit, name)
	if( unit == "player" and name == creatingItem ) then
		QuickAuctionsDB.craftQueue[creatingItemID] = QuickAuctionsDB.craftQueue[creatingItemID] - 1

		if( QuickAuctionsDB.craftQueue[creatingItemID] <= 0 ) then
			QuickAuctionsDB.craftQueue[creatingItemID] = nil
		end
	end
end

-- Cast interrupted, reset our flags
function Tradeskill:UNIT_SPELLCAST_INTERRUPTED(event, unit, name)
	if( unit == "player" and name == creatingItem ) then
		creatingItem = nil
		creatingItemID = nil
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("TRADE_SKILL_UPDATE")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
frame:RegisterEvent("BAG_UPDATE")
frame:SetScript("OnEvent", function(self, event, ...)
	Tradeskill[event](Tradeskill, event, ...)
end)


local timeElapsed = 0
frame:Hide()
frame:SetScript("OnUpdate", function(self, elapsed)
	timeElapsed = timeElapsed + elapsed
	
	if( timeElapsed >= 0.25 ) then
		timeElapsed = 0
		self:Hide()
		
		if( Tradeskill.frame and Tradeskill.frame:IsVisible() ) then
			Tradeskill:Update()
		end
	end
end)

-- Bag updating (With throttlign)
function Tradeskill:BAG_UPDATE()
	timeElapsed = 0
	frame:Show()
end
