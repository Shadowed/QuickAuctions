-- This is still fairly ugly code that needs to be cleaned up more
local Summary = QuickAuctions:NewModule("Summary", "AceEvent-3.0")
local L = QuickAuctionsLocals
local displayData, createdCats, rowDisplay, usedLinks, activeAuctions = {}, {}, {}, {}, {}
local createQuantity, focusedLink, isScanning, startTime, selectedSummary, summaryCats
local MAX_SUMMARY_ROWS = 24
local ROW_HEIGHT = 20

-- Find the ID of the auction categories
function Summary:GetCategoryIndex(searchFor)
	for i=1, select("#", GetAuctionItemClasses()) do
		if( select(i, GetAuctionItemClasses()) == searchFor ) then
			return i
		end
	end
	
	return nil
end

local subClassList = {}
function Summary:GetSubCategoryIndex(parent, searchList)
	table.wipe(subClassList)
	if( not searchList ) then return subClassList end
	
	for i=1, select("#", GetAuctionItemSubClasses(parent)) do
		if( searchList[select(i, GetAuctionItemSubClasses(parent))] ) then
			table.insert(subClassList, i)
		end
	end
	
	return subClassList
end

function Summary:GetData(type)
	if( not AuctionFrame or not AuctionFrame:IsVisible() ) then
		QuickAuctions:Print(L["Auction House must be visible for you to use this."])
		return
	end

	local data = summaryCats[type]
	local classIndex = self:GetCategoryIndex(data.auctionClass)
	if( not classIndex ) then
		QuickAuctions:Print(string.format(L["Cannot find class index. QA still needs to be localized into %s for this feature to work."], GetLocale()))
		return
	end
	
	local subClassList = self:GetSubCategoryIndex(classIndex, data.auctionSubClass)

	self:RegisterMessage("QA_QUERY_UPDATE")
	self:RegisterMessage("QA_START_SCAN")
	self:RegisterMessage("QA_STOP_SCAN")
	isScanning = true
	startTime = GetTime()
	
	QuickAuctions.Scan:StartCategoryScan(classIndex, subClassList)
end

function Summary:QA_START_SCAN()
	self.getDataButton:Disable()
	self.stopButton:Enable()
end

function Summary:QA_QUERY_UPDATE(event, type, filter, ...)
	if( type == "page" or type == "done" ) then
		local page, totalPages = ...
		self.progressBar:SetMinMaxValues(0, totalPages)
		self.progressBar:SetValue(page)

		-- Quick and lazy way of getting me data
		local text = SecondsToTime(GetTime() - startTime, nil, true)
		for i=1, 10 do
			local num = string.match(text, "(%d+) |4")
			if( not num ) then break end
			if( tonumber(num) <= 1 ) then
				text = string.gsub(text, "|4(.-):.-;", "%1")
			else
				text = string.gsub(text, "|4.-:(.-);", "%1")
			end
		end
		
		self.progressBar.text:SetText(text)
	end
end

-- We got all the data!
function Summary:QA_STOP_SCAN(event, interrupted)
	self:UnregisterMessage("QA_QUERY_UPDATE")
	self:UnregisterMessage("QA_START_SCAN")
	self:UnregisterMessage("QA_STOP_SCAN")

	-- And now let us rescan data if we want
	self.getDataButton:Enable()
	self.stopButton:Disable()
	self.progressBar:SetMinMaxValues(0, 1)
	self.progressBar:SetValue(1)
	isScanning = nil
	
	if( interrupted ) then return end
	self:CompileData()
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
	if( summaryData.groupedBy ~= "parent" and type(QuickAuctions.db.realm.crafts[link]) == "number" ) then
		enchantLink = string.format("enchant:%d", QuickAuctions.db.realm.crafts[link])
	end
		
	local row = displayData[index]
	local lowestBuyout, lowestBid, lowestOwner, isWhitelist, isPlayer = QuickAuctions.Scan:GetLowestAuction(link)
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
	row.disableCraftQueue = summaryData.disableCraftQueue

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
	if( not QuickAuctions.db.global.summaryItems[selectedSummary] ) then
		QuickAuctions.db.global.summaryItems[selectedSummary] = {}
	end
	
	local summaryData = summaryCats[selectedSummary]
	index = 0
	
	-- Reset
	for _, v in pairs(displayData) do v.enabled = nil; v.isParent = nil; v.parent = nil; v.bid = nil; v.buyout = nil; v.owner = nil; v.link = nil; v.sortID = nil; v.quantity = nil; end
	for k in pairs(createdCats) do createdCats[k] = nil end
	for k in pairs(usedLinks) do usedLinks[k] = nil end
			
	-- Make sure we got data we want
	for link, data in pairs(QuickAuctions.Scan.auctionData) do
		local name, _, _, itemLevel, _, itemType, subType, stackCount = GetItemInfo(link)
		
		-- Is this data we want?
		if( name and data.quantity > 0 and ( not summaryData.itemType or summaryData.itemType == itemType ) and ( not summaryData.notSubType or summaryData.notSubType ~= subType ) and ( not summaryData.subType or summaryData.subType == subType ) ) then
			usedLinks[link] = true
			QuickAuctions.db.global.summaryItems[selectedSummary][link] = true
			
			self:UpdateItemData(summaryData, name, data.quantity, link, itemLevel, itemType, subType, stackCount)
		end
	end
		
	-- Add our recorded list of items to it now in case it's not in the auction house
	for link in pairs(QuickAuctions.db.global.summaryItems[selectedSummary]) do
		if( not usedLinks[link] ) then
			local name, _, _, itemLevel, _, itemType, subType, stackCount = GetItemInfo(link)

			-- Make sure it's data we want, if it's not something changed and we should remove it from our summary
			if( name and ( not summaryData.itemType or summaryData.itemType == itemType ) and ( not summaryData.notSubType or summaryData.notSubType ~= subType ) and ( not summaryData.subType or summaryData.subType == subType ) ) then
				self:UpdateItemData(summaryData, name, 0, link, itemLevel, itemType, subType, stackCount)
			else
				QuickAuctions.db.global.summaryItems[selectedSummary][link] = nil
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
	local summaryData = summaryCats[selectedSummary]
	
	-- Reset
	for i=#(rowDisplay), 1, -1 do table.remove(rowDisplay, i) end
	for i=1, MAX_SUMMARY_ROWS do
		self.rows[i]:Hide()
	end
	
	-- Add the index we will want in the correct order, so we can do offsets easily
	for index, data in pairs(displayData) do
		-- Build parent
		if( data.enabled and data.isParent ) then
			table.insert(rowDisplay, index)
			
			-- Is the button supposed to be + or -?
			if( not QuickAuctions.db.profile.categories[data.name] ) then
				for index, childData in pairs(displayData) do
					if( childData.enabled and not childData.isParent and childData.parent == data.name ) then
						if( not summaryData.canCraft or not QuickAuctions.db.profile.hideUncraft or summaryData.canCraft(childData.link, (GetItemInfo(childData.link)) or "") ) then
							table.insert(rowDisplay, index)
						end
					end
				end
			end
		end
	end
		
	-- Update scroll bar
	FauxScrollFrame_Update(self.middleFrame.scroll, #(rowDisplay), MAX_SUMMARY_ROWS - 1, ROW_HEIGHT)
	
	-- Update active auctions
	table.wipe(activeAuctions)
	for i=1, GetNumAuctionItems("owner") do
		if( select(13, GetAuctionItemInfo("owner", i)) == 0 ) then
			local link = QuickAuctions:GetSafeLink(GetAuctionItemLink("owner", i))
			if( link ) then
				activeAuctions[link] = (activeAuctions[link] or 0) + 1
			end
		end
	end
			
	-- Now display
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
			
			row.tooltipData = nil
			
			if( data.quantity and data.quantity == 0 ) then
				row.quantity:SetText(data.quantity)
			elseif( data.quantity ) then
				local inventory = GetItemCount(data.link) > 0 and string.format("(%d) ", GetItemCount(data.link)) or ""
				local activeNumber = QuickAuctions.Scan:GetPlayerItemQuantity(data.link)
				local active = ""
				
				row.tooltipData = string.format(L["\n\n%d in inventory\n%d on the Auction House"], GetItemCount(data.link), data.quantity)
				
				if( activeNumber > 0 ) then
					local postCap = QuickAuctions.Manage:GetConfigValue(data.link, "postCap")
					local color = data.isLowest and GREEN_FONT_COLOR_CODE or RED_FONT_COLOR_CODE
					
					active = string.format("[%s%d/%d|r] ", color, activeNumber, postCap)
					
					row.tooltipData = row.tooltipData .. "\n" .. string.format(L["%d (max %d) posted by yourself (%s)"], activeNumber, postCap, (data.isLowest and L["lowest price"] or L["undercut"]))
				else
					row.tooltipData = row.tooltipData .. "\n" .. L["None posted by yourself"]
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
				row.buyout:SetText(data.buyout and QuickAuctions:FormatTextMoney(data.buyout, true) or "")
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
				row.disableCraftQueue = data.disableCraftQueue
				
				row:SetText(link or data.name)

				row:Show()
				row.button:Show()

				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", self.middleFrame.scroll, "TOPLEFT", row.offsetY + 14, row.offsetX)

				row.buyout:ClearAllPoints()
				row.buyout:SetPoint("TOPRIGHT", row, "TOPRIGHT", -14, -4)
				
				row.quantity:ClearAllPoints()
				row.quantity:SetPoint("TOPRIGHT", row, "TOPRIGHT", -134, -4)

				-- Is the button supposed to be + or -?
				if( not QuickAuctions.db.profile.categories[data.name] ) then
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
				row.subType = data.subType
				row.disableCraftQueue = data.disableCraftQueue
			
				local createTag = ""
				if( summaryData.canCraft and not summaryData.canCraft(data.link, itemName) ) then
					createTag = string.format("|T%s:18:18:-1:0|t", READY_CHECK_NOT_READY_TEXTURE)
				end
				
				local craftQuantity = ""
				local craftData = QuickAuctions.db.realm.craftQueue[data.link] or QuickAuctions.db.realm.craftQueue[data.enchantLink]
				if( craftData ) then
					craftQuantity = string.format("%s%d|r x ", GREEN_FONT_COLOR_CODE, craftData)
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

function Summary:Toggle()
	if( self.frame and self.frame:IsVisible() ) then
		self.frame:Hide()
	else
		self:CreateGUI()
		self.frame:Show()
	end
end

function Summary:CreateGUI()
	if( self.frame ) then
		return
	end
	
	-- Create our category info quickly
	self:CreateCategoryData()
	
	self.frame = CreateFrame("Frame", "QuickAuctionsSummaryGUI", UIParent)
	self.frame:SetWidth(550)
	self.frame:SetHeight(474)
	self.frame:SetMovable(true)
	self.frame:EnableMouse(true)
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
	table.insert(UISpecialFrames, "QuickAuctionsSummaryGUI")
	
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

	-- Timer text
	local path, size = GameFontHighlight:GetFont()
	self.progressBar.text = self.progressBar:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	self.progressBar.text:SetFont(path, size, "OUTLINE")
	self.progressBar.text:SetPoint("CENTER")

	-- Create the select category buttons
	self.catButtons = {}
	
	local function showTooltip(self)
		if( self.tooltip ) then
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
			GameTooltip:SetText(self.tooltip, nil, nil, nil, nil, true)
			GameTooltip:Show()
		elseif( self.enchantLink or self.link ) then
			if( self.button:IsVisible() ) then
				GameTooltip:SetOwner(self.button, "ANCHOR_LEFT")
			else
				GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			end
			
			GameTooltip:SetHyperlink(self.enchantLink or self.link)
			
			if( self.tooltipData ) then
				GameTooltip:AddLine(self.tooltipData, 0.90, 0.90, 0.90, 1, true)
				GameTooltip:Show()
			end
		end
	end
	
	local function hideTooltip(self)
		GameTooltip:Hide()
	end
	
	local function selectType(self)
		if( Summary.helpFrame ) then
			Summary.helpFrame:Hide()
		end
		
		for _, button in pairs(Summary.catButtons) do
			button:UnlockHighlight()
		end
		
		selectedSummary = self.id
		
		self:LockHighlight()
		if( not isScanning ) then
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
		QuickAuctions.Scan:StopScanning(true)
	end)
	row:SetPoint("TOPLEFT", self.getDataButton, "TOPRIGHT", 0, 0)
	row:Disable()
	
	self.stopButton = row

	-- Craft queue help
	local row = CreateFrame("Button", nil, self.leftFrame, "UIPanelButtonTemplate")
	row:SetHeight(16)
	row:SetWidth(130)
	row:SetNormalFontObject(GameFontNormalSmall)
	row:SetHighlightFontObject(GameFontHighlightSmall)
	row:SetDisabledFontObject(GameFontDisableSmall)
	row:SetText(QuickAuctions.db.profile.hideUncraft and L["Show uncraftables"] or L["Hide uncraftables"])
	row:SetScript("OnEnter", showTooltip)
	row:SetScript("OnLeave", hideTooltip)
	row:SetScript("OnClick", function(self)
		QuickAuctions.db.profile.hideUncraft = not QuickAuctions.db.profile.hideUncraft
		self:SetText(QuickAuctions.db.profile.hideUncraft and L["Show uncraftables"] or L["Hide uncraftables"])
		Summary:Update()
	end)
	row:SetPoint("TOPLEFT", self.getDataButton, "BOTTOMLEFT", 0, -10)
	row.tooltip = L["Toggles hiding items you cannot craft in the summary window."]
	
	self.hideUncraft = row
	
	-- Craft queue help
	local row = CreateFrame("Button", nil, self.leftFrame, "UIPanelButtonTemplate")
	row:SetHeight(16)
	row:SetWidth(130)
	row:SetNormalFontObject(GameFontNormalSmall)
	row:SetHighlightFontObject(GameFontHighlightSmall)
	row:SetDisabledFontObject(GameFontDisableSmall)
	row:SetText(L["Craft queue help"])
	row:SetScript("OnEnter", showTooltip)
	row:SetScript("OnLeave", hideTooltip)
	row:SetScript("OnClick", function(self)
		self = Summary
		if( not self.helpFrame ) then
			self.helpFrame = CreateFrame("Frame", nil, self.middleFrame)
			self.helpFrame:SetWidth(self.middleFrame:GetWidth())
			self.helpFrame:SetHeight(self.middleFrame:GetHeight())
			self.helpFrame:SetPoint("TOPLEFT", self.middleFrame)
			self.helpFrame:SetPoint("BOTTOMRIGHT", self.middleFrame)
			self.helpFrame:SetFrameStrata("HIGH")
			self.helpFrame:SetFrameLevel(20)
			self.helpFrame:SetBackdrop({
				bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true,
				tileSize = 16,
				edgeSize = 16,
				insets = { left = 3, right = 3, top = 5, bottom = 3 }
			})
			self.helpFrame:SetBackdropColor(0, 0, 0, 1)

			-- Close button, this needs more work not too happy with how it looks
			local button = CreateFrame("Button", nil, self.helpFrame, "UIPanelCloseButton")
			button:SetHeight(27)
			button:SetWidth(27)
			button:SetPoint("TOPRIGHT", -1, -1)
			button:SetScript("OnClick", function(self)
				self:GetParent():Hide()
			end)
			
			self.helpFrame.text = self.helpFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			self.helpFrame.text:SetPoint("TOPLEFT", 6, -10)
			self.helpFrame.text:SetWidth(self.helpFrame:GetWidth() - 10)
			self.helpFrame.text:SetHeight(self.helpFrame:GetHeight() - 20)
			self.helpFrame.text:SetJustifyH("LEFT")
			self.helpFrame.text:SetJustifyV("TOP")
			
			-- I feel sorry for the person who translates this
			self.helpFrame.text:SetText(L["The craft queue in Quick Auctions is a way of letting you queue up a list of items that can then be seen in that professions Tradeskill window, or through /qa tradeskill with a tradeskill open.\n\n|cffff2020**NOTE**|r This does not work with the enchant scroll category.\nQueues are setup through the summary window by holding SHIFT + double clicking an item in the summary.\n\nFor example: If you want to cut 20 |cff0070dd[Insightful Earthsiege Diamond]|r you SHIFT + double click the |cff0070dd[Insightful Earthsiege Diamond]|r text in the summary window, it will then show\n\n|cfffed0000 x|r Insightful Earthsiege Diamond|r\n\nThis tells you that it is ready and you can input how many you want, once you are done setting how many you want to make hit ENTER. If you were to enter 20 it will now look like\n\n0 x |cff20ff202Insightful Earthsiege Diamond|r\nAnd you're done! Once you open the Jewelcrafting Tradeskill window you will see a frame pop up with\n\n|cff0070dd[Insightful Earthsiege Diamond]|r [20]\n\nIf you click that text you will create 20 |cff0070dd[Insightful Earthsiege Diamond]|r providing you have the materials"])
		elseif( self.helpFrame:IsVisible() ) then
			self.helpFrame:Hide()
		else
			self.helpFrame:Show()
		end
	end)
	row:SetPoint("TOPLEFT", self.hideUncraft, "BOTTOMLEFT", 0, -6)
	row.tooltip = L["Shows information on how to use the craft queue"]
	
	self.helpCraftQueue = row

	-- Show craft queue
	local row = CreateFrame("Button", nil, self.leftFrame, "UIPanelButtonTemplate")
	row:SetHeight(16)
	row:SetWidth(130)
	row:SetNormalFontObject(GameFontNormalSmall)
	row:SetHighlightFontObject(GameFontHighlightSmall)
	row:SetDisabledFontObject(GameFontDisableSmall)
	row:SetText(L["Show craft queue"])
	row:SetScript("OnEnter", showTooltip)
	row:SetScript("OnLeave", hideTooltip)
	row:SetScript("OnClick", function()
	end)
	row:SetPoint("TOPLEFT", self.helpCraftQueue, "BOTTOMLEFT", 0, -4)
	row.tooltip = L["Toggles the craft queue window"]
	
	self.showCraftButton = row

	-- Reset craft queue
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
		for k in pairs(QuickAuctions.db.realm.craftQueue) do
			QuickAuctions.db.realm.craftQueue[k] = nil
		end
		
		Summary:Update()
	end)
	row:SetPoint("TOPLEFT", self.showCraftButton, "BOTTOMLEFT", 0, -10)
	row.tooltip = L["Reset the craft queue list for every item."]
	
	self.resetCraftButton = row	
	
	-- Rows
	local function toggleCategory(self)
		if( self.parent ) then
			QuickAuctions.db.profile.categories[self.parent] = not QuickAuctions.db.profile.categories[self.parent]
			Summary:Update()
		end
	end
	
	local function rowClicked(self, mouseButton)
		if( mouseButton == "LeftButton" and IsAltKeyDown() ) then
			if( not AuctionFrameBrowse or not self.queryFor ) then return end
		
			AuctionFrameBrowse.page = 0
			BrowseName:SetText(self.queryFor)

			QueryAuctionItems(self.queryFor, nil, nil, 0, 0, 0, 0, 0, 0)
				
			AuctionFrameTab_OnClick(AuctionFrameTab1)
		elseif( not self.baseLink ) then
			toggleCategory(self)
		elseif( not self.disableCraftQueue and mouseButton == "LeftButton" and self.baseLink and not IsModifierKeyDown() ) then
			QuickAuctions.db.realm.craftQueue[self.baseLink] = (QuickAuctions.db.realm.craftQueue[self.baseLink] or 0) + 1
			Summary:Update()
		elseif( not self.disableCraftQueue and mouseButton == "RightButton" and self.baseLink and not IsModifierKeyDown() ) then
			if( QuickAuctions.db.realm.craftQueue[self.baseLink] and QuickAuctions.db.realm.craftQueue[self.baseLink] > 1 ) then
				QuickAuctions.db.realm.craftQueue[self.baseLink] = QuickAuctions.db.realm.craftQueue[self.baseLink] - 1
			else
				QuickAuctions.db.realm.craftQueue[self.baseLink] = nil
			end
			Summary:Update()
		end
	end
	
	-- Set this row as focused
	local function OnDoubleClick(self)
		if( self.disableCraftQueue or not IsShiftKeyDown() or not self.baseLink ) then return end
		
		if( focusedLink == self.baseLink ) then
			focusedLink = nil
			createQuantity = nil
			Summary:Update()
			return
		end
			
		createQuantity = QuickAuctions.db.realm.craftQueue[self.baseLink]
		focusedLink = self.baseLink
		Summary:Update()
	end
	
	-- They typed a quantity in
	local function OnKeyDown(self, key)
		if( not self.baseLink or self.disableCraftQueue ) then
			return
		end
		
		-- Number paduses NUMPAD# instead of just # so strip out the NUMPAD portion
		key = string.gsub(key, "NUMPAD", "")
	
		-- Enter pressed, unfocus
		if( key == "ENTER" ) then
			QuickAuctions.db.realm.craftQueue[self.baseLink] = tonumber(createQuantity)
			if( QuickAuctions.db.realm.craftQueue[self.baseLink] <= 0 ) then
				QuickAuctions.db.realm.craftQueue[self.baseLink] = nil
			end
				
			if( QuickAuctions.Tradeskill.frame and QuickAuctions.Tradeskill.frame:IsVisible() ) then
				QuickAuctions.Tradeskill:RebuildList()
				QuickAuctions.Tradeskill:TradeskillUpdate()
			end

			createQuantity = nil
			focusedLink = nil
			Summary:Update()
			
			return
		-- Escape, don't add to list
		elseif( key == "ESCAPE" ) then
			focusedLink = nil
			createQuantity = nil
			QuickAuctions.db.realm.craftQueue[self.baseLink] = nil
			Summary:Update()

			if( QuickAuctions.Tradeskill.frame and QuickAuctions.Tradeskill.frame:IsVisible() ) then
				QuickAuctions.Tradeskill:RebuildList()
				QuickAuctions.Tradeskill:TradeskillUpdate()
			end

			return
		-- Backspace, remove previous
		elseif( key == "BACKSPACE" ) then
			if( createQuantity and string.len(createQuantity) > 0 ) then
				createQuantity = tonumber(string.sub(createQuantity, 0, -2)) or 0
				Summary:Update()
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
		row:SetScript("OnKeyDown", OnKeyDown)
		row:RegisterForClicks("AnyUp")
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
			itemType = L["Gem"],
			canCraft = function(link, name) 
				if( not QuickAuctions.db.realm.crafts.Jewelcrafter ) then return true end
				
				if( QuickAuctions.db.realm.crafts[link] ) then
					return true
				elseif( string.match(name, L["Perfect (.+)"]) or ( L["ALTER_PERFECT"] ~= "ALERT_PERFECT" and string.match(name, L["ALTER_PERFECT"]) ) ) then 
					return true
				end
			end,
			notSubType = L["Simple"],
			groupedBy = "parent",
			showCatPrice = true,
			auctionClass = L["Gem"],
		}, -- Oh Blizzard, I love you and your stupid inconsistencies like "Bracer" vs "Bracers" for scrolls
		["Scrolls"] = {
			text = L["Enchant scrolls"],
			subType = L["Item Enhancement"],
			groupedBy = "match",
			filter = function(name) return string.match(name, L["Scroll of Enchant (.+)"]) end,
			match = function(name, itemType, subType) local type = string.match(name, L["Scroll of Enchant (.+) %- .+"]) if( type == L["Bracer"] ) then return L["Bracers"] end return type end,
			auctionClass = L["Consumable"],
			auctionSubClass = {[L["Item Enhancement"]] = true},
		},
		["Flasks"] = {
			text = L["Flasks"],
			subType = L["Flask"],
			canCraft = function(link, name) if( not QuickAuctions.db.realm.crafts.Alchemy ) then return true else return QuickAuctions.db.realm.crafts[link] end end,
			groupedBy = "itemLevel",
			auctionClass = L["Consumable"],
			auctionSubClass = {[L["Flask"]] = true},
		},
		["Elixirs"] = {
			text = L["Elixirs"],
			canCraft = function(link, name) if( not QuickAuctions.db.realm.crafts.Alchemy ) then return true else return QuickAuctions.db.realm.crafts[link] end end,
			subType = L["Elixir"],
			groupedBy = "itemLevel",
			auctionClass = L["Consumable"],
			auctionSubClass = {[L["Elixir"]] = true},
		},
		["Food"] = {
			text = L["Food"],
			canCraft = function(link, name) if( not QuickAuctions.db.realm.crafts.Cook ) then return true else return QuickAuctions.db.realm.crafts[link] end end,
			subType = L["Food & Drink"],
			groupedBy = "itemLevel",
			auctionClass = L["Consumable"],
			auctionSubClass = {[L["Food & Drink"]] = true},
		},
		["Elemental"] = {
			text = L["Elemental"],
			subType = L["Elemental"],
			groupedBy = "itemLevel",
			auctionClass = L["Trade Goods"],
			auctionSubClass = {[L["Elemental"]] = true},
		},
		["Herbs"] = {
			text = L["Herbs"],
			subType = L["Herb"],
			groupedBy = "itemLevel",
			auctionClass = L["Trade Goods"],
			auctionSubClass = {[L["Herb"]] = true},
		},
		["Enchanting"] = {
			text = L["Enchant materials"],
			itemType = L["Trade Goods"],
			groupedBy = "itemLevel",
			auctionClass = L["Trade Goods"],
			auctionSubClass = {[L["Enchanting"]] = true},
		},
		["Glyphs"] = {
			text = L["Glyphs"],
			itemType = L["Glyph"],
			canCraft = function(link, name) if( not QuickAuctions.db.realm.crafts.Scribe ) then return true else return QuickAuctions.db.realm.crafts[link] end end,
			groupedBy = "subType",
			auctionClass = L["Glyph"],
		},
	}
end