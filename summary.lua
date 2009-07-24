QA.Summary = {}

local Summary = QA.Summary
local L = QuickAuctionsLocals
local gettingData, selectedSummary, summaryCats, createQuantity, focusedLink
local displayData, createdCats, rowDisplay, usedLinks = {}, {}, {}, {}
local MAX_SUMMARY_ROWS = 24
local ROW_HEIGHT = 20

Summary.displayData = displayData


-- Find the ID of the auction categories
function Summary:GetCategoryIndex(searchFor)
	for i=1, select("#", GetAuctionItemClasses()) do
		if( select(i, GetAuctionItemClasses()) == searchFor ) then
			return i
		end
	end
	
	return nil
end

function Summary:GetSubCategoryIndex(parent, searchFor)
	for i=1, select("#", GetAuctionItemSubClasses(parent)) do
		if( select(i, GetAuctionItemSubClasses(parent)) == searchFor ) then
			return i
		end
	end
	
	return nil
end

function Summary:GetData(type)
	if( not AuctionFrame or not AuctionFrame:IsVisible() ) then
		QA:Print(L["Auction House must be visible for you to use this."])
		return
	end

	local data = summaryCats[type]
	
	local classIndex = self:GetCategoryIndex(data.auctionClass)
	local subClassIndex = classIndex and data.auctionSubClass and self:GetSubCategoryIndex(classIndex, data.auctionSubClass) or 0
	
	if( not classIndex or not subClassIndex ) then
		QA:Print(L["Cannot find class or sub class index, localization issue perhaps?"])
		return
	end
	
	gettingData = true
	QA:StartCategoryScan(classIndex, subClassIndex, "summary")
	
	-- Add some progressy bar stuff here
	self.getDataButton:Disable()
	self.stopButton:Enable()
	
	self.progressBar.lastValue = 0
end

-- Show highest price first
local function sortData(a, b)
	if( a.sortID and b.sortID ) then
		return a.sortID > b.sortID
	elseif( a.buyout and b.buyout ) then
		return a.buyout > b.buyout
	elseif( a.name and a.name ) then
		return a.name < b.name
	elseif( a.enabled ) then
		return true
	elseif( b.enabled ) then
		return false	
	end
end

-- Progress bar updating on scan status
local frame = CreateFrame("Frame")
frame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
frame:SetScript("OnEvent", function()
	if( not gettingData ) then
		return
	end
	
	local self = Summary
	local total = select(2, GetNumAuctionItems("list"))
	local value = (AuctionFrameBrowse.page + 1) * NUM_AUCTION_ITEMS_PER_PAGE
	
	-- Due to retrying, it might go from page 5 -> 4 -> 5 -> 3 -> 5 so just do this to make it look smooth
	if( self.progressBar.lastValue < value ) then
		self.progressBar.lastValue = value
		
		self.progressBar:SetMinMaxValues(0, total)
		self.progressBar:SetValue(self.progressBar.lastValue)
	end
end)

-- We got all the data!
function Summary:Finished()
	gettingData = nil

	self:CompileData()

	-- And now let us rescan data if we want
	self.getDataButton:Enable()
	self.stopButton:Disable()
end

-- Update specific item data
local index = 0
function Summary:UpdateItemData(summaryData, name, quantity, link, itemLevel, itemType, subType, stackCount)
	local parent, isParent, parentSort, isValid

	-- Cut gems, "Runed Scarlet Ruby" will be parented to "Scarlet Ruby"
	if( summaryData.groupedBy == "parent" ) then
		isValid = true
		parent = nil

		-- Stacks beyond 1, so it has to be a parent
		if( stackCount > 1 ) then
			isParent = true
		end

	-- Scroll of Enchant Cloak - Speed, will set the parent to "Cloak"
	elseif( summaryData.groupedBy == "match" ) then
		parent = summaryData.match(name, itemType, subType)
		isValid = parent

	-- Sub type, like Glyphs so grouped by class
	elseif( summaryData.groupedBy == "subType" ) then
		parent = subType
		isValid = true

	-- Grouped by item level
	elseif( summaryData.groupedBy == "itemLevel" ) then
		parent = tostring(itemLevel)
		parentSort = itemLevel
		isValid = true
	end
	
	-- Make sure it's the item we care about, for example Scrolls of Enchant category includes spell threads and such when we JUST want the scrolls
	if( not isValid ) then
		return
	end

	index = index + 1
	if( not displayData[index] ) then displayData[index] = {} end
	
	local enchantLink
	-- Don't show this for things grouped by parents, because we already know what they take
	if( summaryData.groupedBy ~= "parent" and type(QuickAuctionsDB.crafts[link]) == "number" ) then
		enchantLink = string.format("enchant:%d", QuickAuctionsDB.crafts[link])
	end
	
	local row = displayData[index]
	local lowestBuyout, lowestBid, lowestOwner, isWhitelist, isPlayer = QA:GetLowestAuction(link)
	row.enabled = true
	row.name = name
	row.quantity = quantity
	row.link = link
	row.enchantLink = enchantLink
	row.buyout = lowestBuyout or 0
	row.bid = lowestBid or 0
	row.isLowest = isWhitelist or isPlayer
	row.isParent = isParent
	row.parent = parent
	row.subType = subType
	row.itemLevel = itemLevel

	-- Create the category row now
	if( row.parent and not createdCats[row.parent] ) then
		createdCats[row.parent] = true

		index = index + 1
		if( not displayData[index] ) then displayData[index] = {} end
		local parentRow = displayData[index]
		parentRow.enabled = true
		parentRow.isParent = true
		parentRow.itemLevel = itemLevel
		parentRow.name = row.parent
		parentRow.sortID = parentSort
	end
end

-- Parse it out into what we need
function Summary:CompileData()
	if( not selectedSummary ) then
		return
	end
	
	-- Create our item list if it's not been
	if( not QuickAuctionsDB.summaryItems[selectedSummary] ) then
		QuickAuctionsDB.summaryItems[selectedSummary] = {}
	end
	
	local summaryData = summaryCats[selectedSummary]
	index = 0
	
	-- Reset
	for _, v in pairs(displayData) do v.enabled = nil; v.isParent = nil; v.parent = nil; v.bid = nil; v.buyout = nil; v.owner = nil; v.link = nil; v.sortID = nil; v.quantity = nil; end
	for k in pairs(createdCats) do createdCats[k] = nil end
	for k in pairs(usedLinks) do usedLinks[k] = nil end
			
	-- Make sure we got data we want
	for link, data in pairs(QA.auctionData) do
		local name, _, _, itemLevel, _, itemType, subType, stackCount = GetItemInfo(link)
		
		-- Is this data we want?
		if( name and data.quantity > 0 and ( not summaryData.itemType or summaryData.itemType == itemType ) and ( not summaryData.notSubType or summaryData.notSubType ~= subType ) and ( not summaryData.subType or summaryData.subType == subType ) ) then
			usedLinks[link] = true
			QuickAuctionsDB.summaryItems[selectedSummary][link] = true
			
			self:UpdateItemData(summaryData, name, data.quantity, link, itemLevel, itemType, subType, stackCount)
		end
	end
		
	-- Add our recorded list of items to it now in case it's not in the auction house
	for link in pairs(QuickAuctionsDB.summaryItems[selectedSummary]) do
		if( not usedLinks[link] ) then
			local name, _, _, itemLevel, _, itemType, subType, stackCount = GetItemInfo(link)

			-- Make sure it's data we want, if it's not something changed and we should remove it from our summary
			if( name and ( not summaryData.itemType or summaryData.itemType == itemType ) and ( not summaryData.notSubType or summaryData.notSubType ~= subType ) and ( not summaryData.subType or summaryData.subType == subType ) ) then
				self:UpdateItemData(summaryData, name, 0, link, itemLevel, itemType, subType, stackCount)
			else
				QuickAuctionsDB.summaryItems[selectedSummary][link] = nil
			end
		end
	end
	
	-- If we're grouping it by the parent, go through and associate all of the parents since we actually know them now
	if( summaryData.groupedBy == "parent" ) then
		for id, data in pairs(displayData) do
			if( data.enabled and data.isParent ) then
				for _, childData in pairs(displayData) do
					if( not childData.parent and string.match(childData.name, data.name .. "$") ) then
						childData.parent = data.name
					end
				end
			end
		end
	end
	
	-- Sorting
	table.sort(displayData, sortData)
	
	-- Update display
	self:Update()
end

function Summary:Update()
	local self = Summary
	
	-- Reset
	for i=#(rowDisplay), 1, -1 do table.remove(rowDisplay, i) end
	for i=1, MAX_SUMMARY_ROWS do
		self.rows[i]:Hide()
	end
	
	-- Add the index we will want in the correct order, so we can do offsets easily
	for index, data in pairs(displayData) do
		-- Build parent
		if( data.enabled and data.isParent and ( not QuickAuctionsDB.hideCategories[data.name] or self.hideButton.showing ) ) then
			table.insert(rowDisplay, index)
			
			-- Is the button supposed to be + or -?
			if( not QuickAuctionsDB.categoryToggle[data.name] ) then
				for index, childData in pairs(displayData) do
					if( childData.enabled and not childData.isParent and childData.parent == data.name ) then
						table.insert(rowDisplay, index)
					end
				end
			end
		end
	end
		
	-- Update scroll bar
	FauxScrollFrame_Update(self.middleFrame.scroll, #(rowDisplay), MAX_SUMMARY_ROWS - 1, ROW_HEIGHT)
	
	-- Figure out active auctions of ours
	QA:CheckActiveAuctions()

	-- Now display
	local summaryData = summaryCats[selectedSummary]
	local offset = FauxScrollFrame_GetOffset(self.middleFrame.scroll)
	local displayIndex = 0
	
	for index, dataID in pairs(rowDisplay) do
		if( index >= offset and displayIndex < MAX_SUMMARY_ROWS ) then
			displayIndex = displayIndex + 1
			
			local row = self.rows[displayIndex]
			local data = displayData[dataID]
			local itemName, link
			if( data.link ) then
				itemName, link = GetItemInfo(data.link)
			end

			if( data.quantity and data.quantity == 0 ) then
				row.quantity:SetText(data.quantity)
			elseif( data.quantity ) then
				local inventory = GetItemCount(data.link) > 0 and string.format("(%d) ", GetItemCount(data.link)) or ""
				local activeNumber = (QA.activeAuctions[data.link] or 0) + QA:GetAltAuctionTotals(data.link)
				local active = ""
				
				if( activeNumber > 0 ) then
					local itemCategory = QA:GetItemCategory(link)
					local postCap = QuickAuctionsDB.postCap[itemName] or QuickAuctionsDB.postCap[itemCategory] or QuickAuctionsDB.postCap.default
					local color = data.isLowest and GREEN_FONT_COLOR_CODE or RED_FONT_COLOR_CODE
					
					active = string.format("[%s%d/%d|r] ", color, activeNumber, postCap)
				end
				
				if( active ~= "" or inventory ~= "" ) then
					row.quantity:SetFormattedText("%s%s%d", active, inventory, data.quantity)
				elseif( data.quantity > 0 ) then
					row.quantity:SetText(data.quantity)
				else
					row.quantity:SetText("")				
				end
			else
				row.quantity:SetText("")
			end

			if( data.buyout and data.buyout > 0 ) then
				row.buyout:SetText(data.buyout and QA:FormatTextMoney(data.buyout, true) or "")
			elseif( data.buyout and data.buyout == 0 ) then
				row.buyout:SetText("----")
			else
				row.buyout:SetText("")
			end
						
			-- Displaying a parent
			if( data.isParent ) then
				row.button.parent = data.name
				row.queryFor = itemName
				row.parent = data.name
				row.link = link
				row.baseLink = nil
				
				-- If it's hidden, label it as red
				if( QuickAuctionsDB.hideCategories[data.name] ) then
					row:SetFormattedText("%s%s|r", RED_FONT_COLOR_CODE, data.name)
				else
					row:SetText(link or data.name)
				end

				row:Show()
				row.button:Show()

				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", self.middleFrame.scroll, "TOPLEFT", row.offsetY + 14, row.offsetX)

				row.buyout:ClearAllPoints()
				row.buyout:SetPoint("TOPRIGHT", row, "TOPRIGHT", -14, -4)
				
				row.quantity:ClearAllPoints()
				row.quantity:SetPoint("TOPRIGHT", row, "TOPRIGHT", -134, -4)

				-- Is the button supposed to be + or -?
				if( not QuickAuctionsDB.categoryToggle[data.name] ) then
					row.button:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-UP")
					row.button:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-DOWN")
					row.button:SetHighlightTexture("Interface\\Buttons\\UI-MinusButton-Hilight", "ADD")
				else
					row.button:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-UP")
					row.button:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-DOWN")
					row.button:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
				end
				
			-- Orrr a child
			else
				row.queryFor = itemName
				row.link = link
				row.enchantLink = data.enchantLink
				row.baseLink = data.link

				local createTag = ""
				if( summaryData.canCraft and not summaryData.canCraft(data.link, itemName) ) then
					createTag = string.format("|T%s:18:18:-1:0|t", READY_CHECK_NOT_READY_TEXTURE)
				end
				
				local craftQuantity = ""
				if( QuickAuctionsDB.craftQueue[data.link] ) then
					craftQuantity = string.format("%s%d|r x ", GREEN_FONT_COLOR_CODE, QuickAuctionsDB.craftQueue[data.link])
				end
				
				local colorCode = ""
				if( focusedLink == row.baseLink ) then
					craftQuantity = string.format("%d x ", createQuantity or 0)
					
					colorCode = "|cffffce00"
					row:EnableKeyboard(true)
				else
					row:EnableKeyboard(false)
				end

				row:SetFormattedText("%s%s%s%s|r", createTag, craftQuantity, colorCode, (summaryData.filter and summaryData.filter(data.name) or data.name))
				row:Show()
				row.button:Hide()
				
				row.buyout:ClearAllPoints()
				row.buyout:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -4)

				row.quantity:ClearAllPoints()
				row.quantity:SetPoint("TOPRIGHT", row, "TOPRIGHT", -120, -4)

				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", self.middleFrame.scroll, "TOPLEFT", row.offsetY, row.offsetX)
			end
		end
	end
end

function Summary:CreateGUI()
	if( self.frame ) then
		return
	end
	
	-- Create our category info quickly
	self:CreateCategoryData()
	
	self.frame = CreateFrame("Frame", "QASummaryGUI", UIParent)
	self.frame:SetWidth(550)
	self.frame:SetHeight(474)
	self.frame:SetMovable(true)
	self.frame:EnableMouse(true)
	self.frame:SetClampedToScreen(true)
	self.frame:SetFrameStrata("HIGH")
	self.frame:SetToplevel(true)
	self.frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		edgeSize = 26,
		insets = {left = 9, right = 9, top = 9, bottom = 9},
	})
	self.frame:SetScript("OnShow", function(self)
		Summary:Update()
	end)
	
	self.frame:Hide()
	
	-- Make it act like a real frame
	table.insert(UISpecialFrames, "QASummaryGUI")
	
	-- Create the title/movy thing
	local texture = self.frame:CreateTexture(nil, "ARTWORK")
	texture:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	texture:SetPoint("TOP", 0, 12)
	texture:SetWidth(250)
	texture:SetHeight(60)
	
	local title = CreateFrame("Button", nil, self.frame)
	title:SetPoint("TOP", 0, 4)
	title:SetText(L["Quick Auctions"])
	title:SetPushedTextOffset(0, 0)

	title:SetNormalFontObject(GameFontNormal)
	title:SetHeight(20)
	title:SetWidth(200)
	title:RegisterForDrag("LeftButton")
	title:SetScript("OnDragStart", function(self)
		self.isMoving = true
		Summary.frame:StartMoving()
	end)
	
	title:SetScript("OnDragStop", function(self)
		if( self.isMoving ) then
			self.isMoving = nil
			Summary.frame:StopMovingOrSizing()
		end
	end)
	
	-- Close button, this needs more work not too happy with how it looks
	local button = CreateFrame("Button", nil, self.frame, "UIPanelCloseButton")
	button:SetHeight(27)
	button:SetWidth(27)
	button:SetPoint("TOPRIGHT", -1, -1)
	button:SetScript("OnClick", function()
		HideUIPanel(Summary.frame)
	end)
	
	-- Container frame backdrop
	local backdrop = {
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 3, right = 3, top = 5, bottom = 3 }
	}
	
	-- Left 30%ish width panel
	self.leftFrame = CreateFrame("Frame", nil, self.frame)
	self.leftFrame:SetWidth(140)
	self.leftFrame:SetHeight(442)
	self.leftFrame:SetBackdrop(backdrop)
	self.leftFrame:SetBackdropColor(0, 0, 0, 0.65)
	self.leftFrame:SetBackdropBorderColor(0.75, 0.75, 0.75, 0.90)
	self.leftFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 12, -20)
	
	-- Top frame, around 70% width panel
	self.topFrame = CreateFrame("Frame", nil, self.frame)
	self.topFrame:SetWidth(387)
	self.topFrame:SetHeight(20)
	self.topFrame:SetBackdrop(backdrop)
	self.topFrame:SetBackdropColor(0, 0, 0, 0.65)
	self.topFrame:SetBackdropBorderColor(0.75, 0.75, 0.75, 0.90)
	self.topFrame:SetPoint("TOPLEFT", self.leftFrame, "TOPRIGHT", 0, 0)
	
	-- Middle-ish frame, remaining space
	self.middleFrame = CreateFrame("Frame", nil, self.frame)
	self.middleFrame:SetWidth(387)
	self.middleFrame:SetHeight(422)
	self.middleFrame:SetBackdrop(backdrop)
	self.middleFrame:SetBackdropColor(0, 0, 0, 0.65)
	self.middleFrame:SetBackdropBorderColor(0.75, 0.75, 0.75, 0.90)
	self.middleFrame:SetPoint("TOPLEFT", self.topFrame, "BOTTOMLEFT", 0, 0)
	
	-- Date scroll frame
	self.middleFrame.scroll = CreateFrame("ScrollFrame", "QASummaryGUIScrollMiddle", self.frame, "FauxScrollFrameTemplate")
	self.middleFrame.scroll:SetPoint("TOPLEFT", self.middleFrame, "TOPLEFT", 0, -4)
	self.middleFrame.scroll:SetPoint("BOTTOMRIGHT", self.middleFrame, "BOTTOMRIGHT", -26, 3)
	self.middleFrame.scroll:SetScript("OnVerticalScroll", function(self, value) FauxScrollFrame_OnVerticalScroll(self, value, ROW_HEIGHT, Summary.Update) end)
	
	-- Progress bar!
	self.progressBar = CreateFrame("StatusBar", nil, self.topFrame)
	self.progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
	self.progressBar:SetStatusBarColor(0.10, 1.0, 0.10)
	self.progressBar:SetHeight(5)
	self.progressBar:SetHeight(12)
	self.progressBar:SetWidth(360)
	self.progressBar:SetPoint("TOPLEFT", self.topFrame, "TOPLEFT", 4, -4)
	self.progressBar:SetPoint("TOPRIGHT", self.topFrame, "TOPRIGHT", -4, 0)
	self.progressBar:SetMinMaxValues(0, 100)
	self.progressBar:SetValue(0)

	-- Create the select category buttons
	self.catButtons = {}
	
	local function showTooltip(self)
		if( self.tooltip ) then
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
			GameTooltip:SetText(self.tooltip)
			GameTooltip:Show()
		elseif( self.enchantLink or self.link ) then
			if( self.button:IsVisible() ) then
				GameTooltip:SetOwner(self.button, "ANCHOR_LEFT")
			else
				GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			end
			
			GameTooltip:SetHyperlink(self.enchantLink or self.link)
		end
	end
	
	local function hideTooltip(self)
		GameTooltip:Hide()
	end
	
	local function selectType(self)
		for _, button in pairs(Summary.catButtons) do
			button:UnlockHighlight()
		end
		
		selectedSummary = self.id
		
		self:LockHighlight()
		
		if( not gettingData ) then
			Summary.getDataButton:Enable()
		end
		
		Summary:CompileData()
		Summary:Update()
	end
	
	local index = 1
	for id, data in pairs(summaryCats) do
		local row = CreateFrame("Button", nil, self.leftFrame, "UIPanelButtonTemplate")
		row:SetHeight(16)
		row:SetWidth(130)
		row:SetText(data.text)
		row:SetScript("OnClick", selectType)
		row:SetNormalFontObject(GameFontNormalSmall)
		row:SetHighlightFontObject(GameFontHighlightSmall)
		row:SetDisabledFontObject(GameFontDisableSmall)
		row:GetFontString():SetPoint("LEFT", row, "LEFT", 8, 0)
		row.id = id
		
		if( index > 1 ) then
			row:SetPoint("TOPLEFT", self.catButtons[index - 1], "BOTTOMLEFT", 0, -2)
		else
			row:SetPoint("TOPLEFT", self.leftFrame, "TOPLEFT", 6, -6)
		end
		
		self.catButtons[index] = row	
		index = index + 1
	end

	-- And now create our "Get data button"
	local row = CreateFrame("Button", nil, self.leftFrame, "UIPanelButtonTemplate")
	row:SetHeight(16)
	row:SetWidth(90)
	row:SetNormalFontObject(GameFontNormalSmall)
	row:SetHighlightFontObject(GameFontHighlightSmall)
	row:SetDisabledFontObject(GameFontDisableSmall)
	row:SetText(L["Get Data"])
	row:SetScript("OnClick", function()
		if( selectedSummary ) then
			Summary:GetData(selectedSummary)
		end
	end)
	row:SetPoint("TOPLEFT", self.catButtons[index - 1], "BOTTOMLEFT", 0, -4)
	row:Disable()
	
	self.getDataButton = row

	-- And then the stop request one
	local row = CreateFrame("Button", nil, self.leftFrame, "UIPanelButtonTemplate")
	row:SetHeight(16)
	row:SetWidth(40)
	row:SetNormalFontObject(GameFontNormalSmall)
	row:SetHighlightFontObject(GameFontHighlightSmall)
	row:SetDisabledFontObject(GameFontDisableSmall)
	row:SetText(L["Stop"])
	row:SetScript("OnClick", function()
		QA:ForceQueryStop()
	end)
	row:SetPoint("TOPLEFT", self.getDataButton, "TOPRIGHT", 0, 0)
	row:Disable()
	
	self.stopButton = row

	-- Toggle for showing hidden items
	local row = CreateFrame("Button", nil, self.leftFrame, "UIPanelButtonTemplate")
	row:SetHeight(16)
	row:SetWidth(130)
	row:SetNormalFontObject(GameFontNormalSmall)
	row:SetHighlightFontObject(GameFontHighlightSmall)
	row:SetDisabledFontObject(GameFontDisableSmall)
	row:SetText(L["Show hidden"])
	row:SetScript("OnEnter", showTooltip)
	row:SetScript("OnLeave", hideTooltip)
	row:SetScript("OnClick", function()
		if( row.showing ) then
			row.showing = nil
			row:SetText(L["Show hidden"])
		else
			row.showing = true
			row:SetText(L["Hide hidden"])
		end
				
		Summary:Update()
	end)
	row:SetPoint("TOPLEFT", self.getDataButton, "BOTTOMLEFT", 0, -8)
	row.tooltip = L["CTRL click item categories to remove them from the list completely, CTRL clicking again will show them."]
	
	self.hideButton = row

	-- Reset shopping queue
	local row = CreateFrame("Button", nil, self.leftFrame, "UIPanelButtonTemplate")
	row:SetHeight(16)
	row:SetWidth(130)
	row:SetNormalFontObject(GameFontNormalSmall)
	row:SetHighlightFontObject(GameFontHighlightSmall)
	row:SetDisabledFontObject(GameFontDisableSmall)
	row:SetText(L["Reset craft queue"])
	row:SetScript("OnEnter", showTooltip)
	row:SetScript("OnLeave", hideTooltip)
	row:SetScript("OnClick", function()
		for k in pairs(QuickAuctionsDB.craftQueue) do
			QuickAuctionsDB.craftQueue[k] = nil
		end
		
		Summary:Update()
	end)
	row:SetPoint("TOPLEFT", self.hideButton, "BOTTOMLEFT", 0, -2)
	row.tooltip = L["Reset the craft queue list for every item."]
	
	self.hideButton = row
	
	-- Rows
	local function toggleCategory(self)
		if( self.parent ) then
			QuickAuctionsDB.categoryToggle[self.parent] = not QuickAuctionsDB.categoryToggle[self.parent]
			Summary:Update()
		end
	end
	
	local function rowClicked(self)
		if( IsAltKeyDown() and CanSendAuctionQuery() and self.queryFor ) then
			AuctionFrameBrowse.page = 0
			BrowseName:SetText(self.queryFor)

			QueryAuctionItems(self.queryFor, nil, nil, 0, 0, 0, 0, 0, 0)
			return
		end
		
		if( self.baseLink ) then
			return
		end
		
		if( IsControlKeyDown() and self.parent ) then
			QuickAuctionsDB.hideCategories[self.parent] = not QuickAuctionsDB.hideCategories[self.parent]
			Summary:Update()
		else
			toggleCategory(self)
		end
	end
	
	-- Set this row as focused
	local function OnDoubleClick(self)
		if( self.baseLink ) then
			if( focusedLink == self.baseLink ) then
				focusedLink = nil
				createQuantity = nil
				Summary:Update()
				return
			end
			
			createQuantity = nil
			focusedLink = self.baseLink
			Summary:Update()
		end
	end
	
	-- They typed a quantity in
	local function OnKeyDown(self, key)
		if( not self.baseLink ) then
			return
		end
		
		-- Enter pressed, unfocus
		if( key == "ENTER" and createQuantity ) then
			QuickAuctionsDB.craftQueue[self.baseLink] = tonumber(createQuantity)
			createQuantity = nil
			focusedLink = nil
			Summary:Update()
			
			if( QA.Tradeskill.frame and QA.Tradeskill.frame:IsVisible() ) then
				QA.Tradeskill:RebuildList()
				QA.Tradeskill:Update()
			end
			
			return
		-- Escape, don't add to list
		elseif( key == "ESCAPE" ) then
			focusedLink = nil
			createQuantity = nil
			QuickAuctionsDB.craftQueue[self.baseLink] = nil
			Summary:Update()

			if( QA.Tradeskill.frame and QA.Tradeskill.frame:IsVisible() ) then
				QA.Tradeskill:RebuildList()
				QA.Tradeskill:Update()
			end

			return
		end
		
		-- Make sure it's a number now (obviously)
		local number = tonumber(key)
		if( not number ) then
			return
		end
		
		if( not createQuantity ) then
			createQuantity = number
		else
			createQuantity = createQuantity .. number
		end
		
		Summary:Update()
	end
	
	self.rows = {}
		
	local lastFocused
	local offset = 0
	for i=1, MAX_SUMMARY_ROWS do
		local row = CreateFrame("Button", nil, self.middleFrame)
		row:SetWidth(355)
		row:SetHeight(ROW_HEIGHT)
		row:SetNormalFontObject(GameFontHighlightSmall)
		row:SetText("*")
		row:GetFontString():SetPoint("LEFT", row, "LEFT", 0, 0)
		row:SetPushedTextOffset(0, 0)
		--row:SetScript("OnClick", toggleParent)
		row:SetScript("OnKeyUp", OnKeyDown)
		row:SetScript("OnDoubleClick", OnDoubleClick)
		row:SetScript("OnEnter", showTooltip)
		row:SetScript("OnLeave", hideTooltip)
		row:SetScript("OnClick", rowClicked)
		row.offsetY = 6
		
		row.buyout = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.bid = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.quantity = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		
		row.button = CreateFrame("Button", nil, row)
		row.button:SetScript("OnClick", toggleCategory)
		row.button:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-UP")
		row.button:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-DOWN")
		row.button:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
		row.button:SetPoint("TOPLEFT", row, "TOPLEFT", -16, -4)
		row.button:SetHeight(14)
		row.button:SetWidth(14)
		
		if( i > 1 ) then
			offset = offset + ROW_HEIGHT - 3
			row.offsetX = -offset
		else
			row.offsetX = 1
		end
		
		row.button:Hide()
		row:Hide()

		self.rows[i] = row
	end
	
	-- Positioning
	self.frame:SetPoint("CENTER")
end	

function Summary:CreateCategoryData()
	if( summaryCats ) then
		return
	end
	
	summaryCats = {
		["Gems"] = {
			text = L["Gems"],
			itemType = "Gem",
			canCraft = function(link, name) 
				if( not QuickAuctionsDB.crafts.Jewelcrafter ) then return true end
				if( string.match(name, L["Perfect (.+)"]) ) then 
					return true
				else 
					return QuickAuctionsDB.crafts[link]
				end
			end,
			notSubType = "Simple",
			groupedBy = "parent",
			showCatPrice = true,
			auctionClass = L["Gem"],
		}, -- Oh Blizzard, I love you and your fucking stupid inconsistency like "Bracer" vs "Bracers" for scrolls
		["Scrolls"] = {
			text = L["Enchant scrolls"],
			subType = "Item Enhancement",
			groupedBy = "match",
			filter = function(name) return string.match(name, L["Scroll of Enchant (.+)"]) end,
			match = function(name, itemType, subType) local type = string.match(name, L["Scroll of Enchant (.+) %- .+"]) if( type == L["Bracer"] ) then return L["Bracers"] end return type end,
			auctionClass = L["Consumable"],
			auctionSubClass = L["Item Enhancement"],
		},
		["Flasks"] = {
			text = L["Flasks"],
			subType = "Flask",
			canCraft = function(link, name) if( not QuickAuctionsDB.crafts.Alchemy ) then return true else return QuickAuctionsDB.crafts[link] end end,
			groupedBy = "itemLevel",
			auctionClass = L["Consumable"],
			auctionSubClass = L["Flask"],
		},
		["Elixirs"] = {
			text = L["Elixirs"],
			canCraft = function(link, name) if( not QuickAuctionsDB.crafts.Alchemy ) then return true else return QuickAuctionsDB.crafts[link] end end,
			subType = "Elixir",
			groupedBy = "itemLevel",
			auctionClass = L["Consumable"],
			auctionSubClass = L["Elixir"],
		},
		["Food"] = {
			text = L["Food"],
			canCraft = function(link, name) if( not QuickAuctionsDB.crafts.Cook ) then return true else return QuickAuctionsDB.crafts[link] end end,
			subType = "Food & Drink",
			groupedBy = "itemLevel",
			auctionClass = L["Consumable"],
			auctionSubClass = L["Food & Drink"],
		},
		["Elemental"] = {
			text = L["Elemental"],
			subType = "Elemental",
			groupedBy = "itemLevel",
			auctionClass = L["Trade Goods"],
			auctionSubClass = L["Elemental"],
		},
		["Herbs"] = {
			text = L["Herbs"],
			subType = "Herb",
			groupedBy = "itemLevel",
			auctionClass = L["Trade Goods"],
			auctionSubClass = L["Herb"],
		},
		["Enchanting"] = {
			text = L["Enchant materials"],
			itemType = L["Trade Goods"],
			groupedBy = "itemLevel",
			auctionClass = L["Trade Goods"],
			auctionSubClass = L["Enchanting"],
		},
		["Glyphs"] = {
			text = L["Glyphs"],
			itemType = "Glyph",
			canCraft = function(link, name) if( not QuickAuctionsDB.crafts.Scribe ) then return true else return QuickAuctionsDB.crafts[link] end end,
			groupedBy = "subType",
			auctionClass = L["Glyph"],
		},
	}
end