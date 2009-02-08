-- Ugly code, need to clean it up later
QA = {}

local scanType, scanTotal, scanIndex, money, defaults
local badRetries, totalCancels, totalPosts, totalPostsSet = 0, 0, 0, 0
local activeAuctions, scanList, auctionData, queryQueue, postList, auctionPostQueue, tempList, currentQuery = {}, {}, {}, {}, {}, {}, {}, {}
local validTypes = {["uncut"] = "uncut gems", ["gems"] = "cut gems", ["glyphs"] = "glyphs", ["enchants"] = "enchanting materials"}
local typeInfo = {["Gem1"] = "gems", ["Gem20"] = "uncut", ["Glyph20"] = "glyphs", ["Enchanting20"] = "enchants"}
local AHTime = 12 * 60

local L = QuickAuctionsLocals

-- Addon loaded
function QA:OnInitialize()
	-- Default things
	defaults = {
		smartUndercut = true,
		smartCancel = true,
		logging = false,
		bidpercent = 1.0,
		itemTypes = {},
		itemList = {},
		whitelist = {},
		undercut = {},
		threshold = {},
		fallback = {},
		postCap = {},
		logs = {},
		categoryToggle = {},
	}
	
	-- Upgrade DB format
	if( QuickAuctionsDB and not QuickAuctionsDB.revision ) then
		QuickAuctionsDB = nil
		self:Print(L["DB format upgraded, reset configuration."])
	end
	
	-- Load defaults in
	QuickAuctionsDB = QuickAuctionsDB or {}
	for key, value in pairs(defaults) do
		if( QuickAuctionsDB[key] == nil ) then
			if( type(value) == "table" ) then
				QuickAuctionsDB[key] = CopyTable(value)
			else
				QuickAuctionsDB[key] = value
			end
		end
	end

	-- Got to let the "module" access these
	QA.auctionData = auctionData
	QA.activeAuctions = activeAuctions
	
	-- DB is now up to date
	QuickAuctionsDB.revision = tonumber(string.match("$Revision$", "(%d+)") or 1)
end

-- AH loaded
function QA:AHInitialize()
	-- Hook the query function so we know what we last sent a search on
	local orig_QueryAuctionItems = QueryAuctionItems
	QueryAuctionItems = function(name, minLevel, maxLevel, invTypeIndex, classIndex, subClassIndex, page, isUsable, qualityIndex, getAll, ...)
		if( CanSendAuctionQuery() ) then
			currentQuery.name = name
			--currentQuery.page = page or 0
			currentQuery.classIndex = classIndex
			currentQuery.subClassIndex = subClassIndex
			
			-- So AH browsing mods will show the status correctly on longer scans
			if( currentQuery.scanning ) then
				AuctionFrameBrowse.page = page
			end
		end
		
		return orig_QueryAuctionItems(name, minLevel, maxLevel, invTypeIndex, classIndex, subClassIndex, page, isUsable, qualityIndex, getAll, ...)
	end
	
	-- Tooltips!
	local function showTooltip(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:SetText(self.tooltip)
		GameTooltip:Show()
	end
	
	local function hideTooltip(self)
		GameTooltip:Hide()
	end
	
	-- Scan our posted items
	local button = CreateFrame("Button", nil, AuctionFrameAuctions, "UIPanelButtonTemplate")
	button.tooltip = L["Scan posted auctions to see if any were undercut."]
	button:SetPoint("TOPRIGHT", AuctionFrameAuctions, "TOPRIGHT", 51, -15)
	button:SetText(L["Scan Items"])
	button:SetWidth(110)
	button:SetHeight(18)
	button:SetScript("OnEnter", showTooltip)
	button:SetScript("OnLeave", hideTooltip)
	button:SetScript("OnClick", function(self)
		QA:ScanAuctions()
	end)
		
	self.scanButton = button

	-- Post inventory items
	local button = CreateFrame("Button", nil, AuctionFrameAuctions, "UIPanelButtonTemplate")
	button.tooltip = L["Post items from your inventory into the auction house."]
	button:SetPoint("TOPRIGHT", self.scanButton, "TOPLEFT", 0, 0)
	button:SetText(L["Post Items"])
	button:SetWidth(110)
	button:SetHeight(18)
	button:SetScript("OnEnter", showTooltip)
	button:SetScript("OnLeave", hideTooltip)
	button:SetScript("OnClick", function(self)
		QA:PostAuctions()
	end)
	
	self.postButton = button
	
	-- Scan our posted items
	local button = CreateFrame("Button", nil, AuctionFrameAuctions, "UIPanelButtonTemplate")
	button.tooltip = L["View a summary of what the highest selling of certain items is."]
	button:SetPoint("TOPRIGHT", self.postButton, "TOPLEFT", 0, 0)
	button:SetText(L["Summarize"])
	button:SetWidth(110)
	button:SetHeight(18)
	button:SetScript("OnEnter", showTooltip)
	button:SetScript("OnLeave", hideTooltip)
	button:SetScript("OnClick", function(self)
		if( QA.Summary.frame and QA.Summary.frame:IsVisible() ) then
			QA.Summary.frame:Hide()
			return
		end
		
		QA.Summary:CreateGUI()
		QA.Summary.frame:Show()
	end)
		
	self.summaryButton = button

	-- Hook chat to block auction post/cancels, and also let us know when we're done posting
	local orig_ChatFrame_SystemEventHandler = ChatFrame_SystemEventHandler
	ChatFrame_SystemEventHandler = function(self, event, msg)
		if( msg == ERR_AUCTION_REMOVED and totalCancels > 0 ) then
			totalCancels = totalCancels - 1
			
			QA.scanButton:SetFormattedText(L["%d/%d items"], totalCancels, QA.scanButton.totalCancels)
			QA.scanButton:Disable()
			
			if( totalCancels <= 0 ) then
				totalCancels = 0
				
				QA.scanButton:SetText(L["Scan Items"])
				QA.scanButton:Enable()
				QA:Print("Done cancelling auctions.")
			end
			return true

		elseif( msg == ERR_AUCTION_STARTED and totalPosts > 0 ) then
			totalPosts = totalPosts - 1
			totalPostsSet = totalPostsSet - 1
			
			if( totalPostsSet <= 0 ) then
				QA:Log("Done posting current set.")
				QA:QueueSet()
			end
			
			if( totalPosts <= 0 ) then
				totalPosts = 0
				QA:Print("Done posting auctions.")

				QA.postButton:SetText(L["Post Items"])
				QA.postButton:Enable()
				
				QA:Log("Done posting auctions.")
			else
				-- This one went throughdo next
				if( totalPostsSet > 0 ) then
					QA:PostQueuedAuction()
				end
				
				QA.postButton:SetFormattedText(L["%d/%d items"], totalPosts, QA.postButton.totalPosts)
				QA.postButton:Disable()
			end
			
			return true
		end
	end
end

-- Debugging
function QA:Log(msg, ...)
	if( not QuickAuctionsDB.logging ) then
		return
	end
	
	local msg = "[" .. GetTime() .. "] " .. string.format(msg, ...)
	msg = string.trim(string.gsub(string.gsub(msg, "|r", ""), "|c%x%x%x%x%x%x%x%x", ""))
	
	table.insert(QuickAuctionsDB.logs, msg)
end

-- Query queue
local timeElapsed = 0
local function checkSend(self, elapsed)
	timeElapsed = timeElapsed + elapsed
	
	if( timeElapsed >= 0.25 ) then
		timeElapsed = 0
		
		-- Can we send it yet?
		if( CanSendAuctionQuery() ) then
			local filter = table.remove(queryQueue, 1)
			local page = table.remove(queryQueue, 1)
			local classIndex = table.remove(queryQueue, 1)
			local subClassIndex = table.remove(queryQueue, 1)
			local type = table.remove(queryQueue, 1)
			
			QueryAuctionItems(filter, nil, nil, 0, (classIndex == "nil" and 0 or classIndex), (subClassIndex == "nil" and 0 or subClassIndex), page, 0, 0)
			
			-- It's a new request, meaning increment the item counter
			if( currentQuery.showProgress and type == "new" ) then
				QA.scanButton:SetFormattedText(L["%d/%d items"], scanIndex, scanTotal)
				scanIndex = scanIndex + 1
			end
			
			-- Done with our queries
			if( #(queryQueue) == 0 ) then
				QA.isQuerying = nil
				self:SetScript("OnUpdate", nil)
			end
		end
	end

end


function QA:SendQuery(filter, page, type, classIndex, subClassIndex)
	if( CanSendAuctionQuery() ) then
		QueryAuctionItems(filter, nil, nil, 0, classIndex or 0, subClassIndex or 0, page, 0, 0)

		-- It's a new request, meaning increment the item counter
		if( currentQuery.showProgress and type == "new" ) then
			self.scanButton:SetFormattedText(L["%d/%d items"], scanIndex, scanTotal)
			scanIndex = scanIndex + 1
		end
		return
	end
	
	table.insert(queryQueue, filter)
	table.insert(queryQueue, page)
	table.insert(queryQueue, classIndex or "nil")
	table.insert(queryQueue, subClassIndex or "nil")
	table.insert(queryQueue, type)
	
	self.frame:SetScript("OnUpdate", checkSend)
	self.isQuerying = true
end

function QA:IsValidItem(link)
	local name, _, _, _, _, itemType, _, stackCount = GetItemInfo(link)
	if( QuickAuctionsDB.itemList[name] or QuickAuctionsDB.itemTypes[itemType .. stackCount] ) then
		return true
	end
end

function QA:GetItemCategory(link)
	if( not link ) then return "" end
	local name, _, _, _, _, itemType, _, stackCount = GetItemInfo(link)
	return typeInfo[itemType .. stackCount]
end

function QA:GetSafeLink(link)
	if( not link ) then return nil end
	return (string.match(link, "|H(.-):([-0-9]+):([0-9]+)|h"))
end

local tempList = {}
function QA:ScanAuctions()
	-- Reset data
	for i=#(scanList), 1, -1 do table.remove(scanList, i) end
	for k in pairs(tempList) do tempList[k] = nil end
	for _, data in pairs(auctionData) do data.owner = nil data.totalFound = 0 end
	
	local hasItems
	for i=1, (GetNumAuctionItems("owner")) do
		local name = GetAuctionItemInfo("owner", i)
		local itemLink = GetAuctionItemLink("owner", i)
		
		if( itemLink and self:IsValidItem(itemLink) and select(13, GetAuctionItemInfo("owner", i)) == 0 ) then
			hasItems = true
			tempList[name] = true
		end
	end
	
	if( hasItems ) then
		self:StartScan(tempList, "scan")
	end
end

-- Finished splitting this queue
function QA:FinishedSplitting()
	self:Log("Finished split.")
	self:PostItem(table.remove(postList, 1))
end

-- Queue a set for splitting... or post it if it can't be split
function QA:QueueSet()
	if( #(postList) == 0 ) then
		self:Log("Was going to queue set, but the post list is empty.")
		return
	end

	local link = postList[1]
	local name, _, _, _, _, itemType, _, stackCount = GetItemInfo(link)
	local itemCategory = self:GetItemCategory(link)
	local quantity = type(QuickAuctionsDB.itemList[name]) == "number" and QuickAuctionsDB.itemList[name] or 1
	
	-- This item cannot stack, so we don't need to bother with splitting and can post it all
	if( stackCount == 1 ) then
		self:Log("Queued item %s x %d, only stacks up to %d and we have %d of them.", name, quantity, stackCount, GetItemCount(link))
		self:PostItem(table.remove(postList, 1))
		return
	end
	
	-- If post cap is 20, we have 4 on the AH, then we can post 16 more before hitting cap
	local leftToCap = (QuickAuctionsDB.postCap[name] or QuickAuctionsDB.postCap[itemCategory] or QuickAuctionsDB.postCap.default) - (activeAuctions[name] or 0)
	-- If we have 4 of the item, we post it in stacks of 1, we can can post 4
	local canPost = math.floor(GetItemCount(link) / quantity)
	
	-- Can't post any more
	if( leftToCap <= 0 ) then
		self:Log("Already past the post limit for %s, have %d active auctions.", name, (activeAuctions[name] or 0))
		self:QueueSet()
		return
	-- Not enough to post it :(
	elseif( canPost == 0 ) then
		self:Log("We need at least %d of %s to post it, but we only have %d, moving on.", quantity, name, GetItemCount(link))
		table.remove(postList, 1)
		self:QueueSet()
		return
	-- If we can make more than we have left to post, set it to what we have left
	elseif( canPost > leftToCap ) then
		canPost = leftToCap
	end
		
	-- Figure out if we even need to do a split
	local validStacks = 0
	for bag=0, 4 do
		for slot=1, GetContainerNumSlots(bag) do
			if( self:GetSafeLink(GetContainerItemLink(bag, slot)) == link and select(2, GetContainerItemInfo(bag, slot)) == quantity ) then
				validStacks = validStacks + 1
			end
		end
	end
		
	-- Yay we do!
	if( validStacks >= canPost ) then
		self:Log("No splitting needed, going to be posting %d stacks of %s x %d, and we have %d in inventory, with %d left before cap.", canPost, name, quantity, GetItemCount(link), leftToCap)
		self:PostItem(table.remove(postList, 1))
		return
	end
	
	self:Log("Going to be splitting %s into %d stacks of %d each, we already have %d valid stacks, %d of the item in our inventory, will cap in %d posts, and have %d actives.", name, (canPost - validStacks), quantity, validStacks, GetItemCount(link), leftToCap, (activeAuctions[name] or 0))
	
	-- If we can post 4, we have 1 valid stack, we need to do 3 splits, if we have 4 to post and 0 valid stacks, then we need to do all 4 splits
	local newStacks = canPost - validStacks
		
	-- Nothing queued, meaning we have nothing to post for this item
	if( newStacks == 0 ) then
		table.remove(postList, 1)
		
		self:Log("We have nothing to post for %s, we wanted to post it in stacks of %d but only have %d of it in inventory.", name, quantity, GetItemCount(link))
		self:Echo(string.format(L["You only have %d of %s, and posting it in stacks of %d, not posting."], GetItemCount(link), link, quantity))
		self:QueueSet()
		return
	end
	
	-- And here we go!
	self:StartSplitting(newStacks, link, quantity)
end


-- Prepare to post auctions
function QA:PostAuctions()
	-- Reset data
	for k in pairs(tempList) do tempList[k] = nil end
	for i=#(postList), 1, -1 do table.remove(postList, i) end
	for _, data in pairs(auctionData) do data.owner = nil data.totalFound = 0 end
	
	-- Figure out how many of this is already posted
	for k in pairs(activeAuctions) do activeAuctions[k] = nil end
	for i=1, (GetNumAuctionItems("owner")) do
		local name, _, _, _, _, _, _, _, _, _, _, _, wasSold = GetAuctionItemInfo("owner", i)   
		if( wasSold == 0 ) then
			activeAuctions[name] = (activeAuctions[name] or 0) + 1
		end
	end
	
	-- Scan inventory for posting
	for bag=0, 4 do
		for slot=1, GetContainerNumSlots(bag) do
			local link = self:GetSafeLink(GetContainerItemLink(bag, slot))
			if( link ) then
				local name, _, _, _, _, _, _, stackCount = GetItemInfo(link)
				local itemCategory = self:GetItemCategory(link)
				local postCap = QuickAuctionsDB.postCap[name] or QuickAuctionsDB.postCap[itemCategory] or QuickAuctionsDB.postCap.default
				
				-- Make sure we aren't already at the post cap, to reduce the item scans needed
				if( not tempList[name] and self:IsValidItem(link) and ( not activeAuctions[name] or activeAuctions[name] < postCap ) ) then
					table.insert(postList, link)
					tempList[name] = true
				end
			end
		end
	end
		
	self:StartScan(tempList, "post")
end

-- Start scanning the items we will be posting
function QA:StartScan(list, type)
	for i=#(scanList), 1, -1 do table.remove(scanList, i) end
	
	-- Prevents duplicate entries
	for name in pairs(list) do
		table.insert(scanList, name)
	end
	
	self:Log("Starting scan type %s, we will be scanning a total of %d items.", type, #(scanList))

	local filter = table.remove(scanList, 1)
	if( not filter ) then
		return
	end
		
	self.scanButton:Disable()
	self.scanButton:SetFormattedText(L["%d/%d items"], 0, #(scanList) + 1)
	
	-- Setup scan info blah blah
	scanType = type
	scanTotal = #(scanList) + 1
	scanIndex = 1

	currentQuery.scanning = true
	currentQuery.showProgress = true
	currentQuery.classIndex = nil
	currentQuery.subClassIndex = nil
	currentQuery.page = 0
	
	self:SendQuery(filter, currentQuery.page, "new")
end

function QA:StartCategoryScan(classIndex, subClassIndex, type)
	self:Log("Starting category scan type %s, we will be scanning main category %d and sub category %d.", type, classIndex or -1, subClassIndex or -1)
	
	self.scanButton:Disable()
	
	-- Setup scan info blah blah
	scanType = type
	scanTotal = 0
	scanIndex = 0

	currentQuery.scanning = true
	currentQuery.showProgress = nil
	currentQuery.classIndex = nil
	currentQuery.subClassIndex = nil
	currentQuery.page = 0
		
	self:SendQuery("", currentQuery.page, "new", classIndex, subClassIndex)
end

function QA:ForceQueryStop()
	if( currentQuery.scanning ) then
		currentQuery.forceStop = true
		
		for i=#(queryQueue), 1, -1 do
			table.remove(queryQueue, i)
		end
	end
end

function QA:PostQueuedAuction()
	if( #(auctionPostQueue) == 0 ) then
		return
	end
	
	local bag = table.remove(auctionPostQueue, 1)
	local slot = table.remove(auctionPostQueue, 1)
	local minBid = table.remove(auctionPostQueue, 1)
	local buyout = table.remove(auctionPostQueue, 1)

	self:Log("Posted item from bag %d/slot %d in the AH for %d at %s buyout and %s bid.", bag, slot, AHTime / 60, self:FormatTextMoney(buyout), self:FormatTextMoney(minBid))

	PickupContainerItem(bag, slot)
	ClickAuctionSellItemButton()
	StartAuction(minBid, buyout, AHTime)
end

function QA:PostItem(link)
	if( not link ) then
		self:Log("No link provided to post item, exited.")
		return
	end
		
	local name = GetItemInfo(link)
	local priceData = auctionData[name]
	local totalPosted = activeAuctions[name] or 0
	local itemCategory = self:GetItemCategory(link)
	local quantity = type(QuickAuctionsDB.itemList[name]) == "number" and QuickAuctionsDB.itemList[name] or 1
	local postCap = QuickAuctionsDB.postCap[name] or QuickAuctionsDB.postCap[itemCategory] or QuickAuctionsDB.postCap.default
	local minBid, buyout
	
	totalPostsSet = 0

	-- Figure out what price we are posting at
	if( priceData and priceData.owner ) then
		buyout = math.floor(priceData.buyout)

		-- Don't undercut people on our whitelist, match them
		if( not QuickAuctionsDB.whitelist[priceData.owner] ) then
			buyout = buyout / 10000

			-- If smart undercut is on, then someone who posts an auction of 99g99s0c, it will auto undercut to 99g
			-- instead of 99g99s0c - undercutBy
			if( not QuickAuctionsDB.smartUndercut or  buyout == math.floor(buyout) ) then
				buyout = ( buyout * 10000 ) - (QuickAuctionsDB.undercut[name] or QuickAuctionsDB.undercut[itemCategory] or QuickAuctionsDB.undercut.default)
			else
				buyout = math.floor(buyout) * 10000
			end
		end
		
		-- And now the bid!
		minBid = buyout * QuickAuctionsDB.bidpercent

		self:Log("Going to be posting %s x %d, have %d in inventory, %d cap, %d active, with buyout %s/bid %s, owner is %s who posted it at %s buyout.", name, quantity, GetItemCount(link), postCap, totalPosted, self:FormatTextMoney(buyout), self:FormatTextMoney(minBid), priceData.owner, self:FormatTextMoney(priceData.buyout))

	-- No other data available, default to our fallback for it
	else
		buyout = QuickAuctionsDB.fallback[name] or QuickAuctionsDB.fallback[itemCategory] or QuickAuctionsDB.fallback.default
		minBid = buyout * QuickAuctionsDB.bidpercent

		self:Echo(string.format(L["No data found for %s, using %s buyout and %s bid default."], name, self:FormatTextMoney(buyout), self:FormatTextMoney(minBid)))
		self:Log("No data found for %s x %d, have %d in inventory, %d cap, %d active,, so will be posting at %s buyout/%s bid.", name, quantity, GetItemCount(link), postCap, totalPosted, self:FormatTextMoney(buyout), self:FormatTextMoney(minBid))
	end

	-- Find the item in our inventory
	for i=#(auctionPostQueue), 1, -1 do table.remove(auctionPostQueue, i) end
	for bag=0, 4 do
		for slot=1, GetContainerNumSlots(bag) do
			-- It's the correct quantity/link so can post it
			if( self:GetSafeLink(GetContainerItemLink(bag, slot)) == link and select(2, GetContainerItemInfo(bag, slot)) == quantity ) then
				totalPosted = totalPosted + 1
				
				self:Log("Posting? %s, total %d posted, post cap is %d.", name, totalPosted, postCap)
				
				-- Hit limit, done with this item
				if( totalPosted > postCap ) then
					break
				end

				-- Post this auction
				PickupContainerItem(bag, slot)
				ClickAuctionSellItemButton()

				-- Make sure we can post this auction, we save the money and subtract it here
				-- because we chain post before the server gives us the new money
				money = money - CalculateAuctionDeposit(AHTime)
				if( money >= 0 ) then
					table.insert(auctionPostQueue, bag)
					table.insert(auctionPostQueue, slot)
					table.insert(auctionPostQueue, minBid * quantity)
					table.insert(auctionPostQueue, buyout * quantity)
					
					self:Log("Queued for auction in bag %d/slot %d.", bag, slot)
					
					totalPostsSet = totalPostsSet + 1
				else
					for i=#(auctionPostQueue), 1, -1 do table.remove(auctionPostQueue, i) end
					totalPosts = 0
					
					self:Log("Ran out of money to post.")
					self.postButton:SetText(L["Post Items"])
					self.postButton:Enable()
					self:Print(L["Cannot post remaining auctions, you do not have enough money."])
					return
				end

				-- Now reset the button quickly
				ClickAuctionSellItemButton()
				ClearCursor()
			end
		end
	end
			
	-- And now update post totals
	self.postButton:SetFormattedText(L["%d/%d items"], totalPosts, self.postButton.totalPosts)
	self.postButton:Disable()

	-- Now actually post everything
	self:PostQueuedAuction()
end

function QA:PostItems()
	self.scanButton:Enable()
	self.scanButton:SetText(L["Scan Items"])
	self.postButton.totalPosts = 0

	-- Quick check for threshold info
	for i=#(postList), 1, -1 do
		local link = postList[i]
		local name = GetItemInfo(link)
		local priceData = auctionData[name]
		local itemCategory = self:GetItemCategory(link)
		local threshold = QuickAuctionsDB.threshold[name] or QuickAuctionsDB.threshold[itemCategory] or QuickAuctionsDB.threshold.default
		
		if( priceData and priceData.owner and priceData.buyout <= threshold ) then
			self:Echo(string.format(L["Not posting %s, because the buyout is %s per item and the threshold is %s"], name, self:FormatTextMoney(priceData.buyout), self:FormatTextMoney(threshold)))
			table.remove(postList, i)
		else
			-- Figure out how many auctions we will be posting quickly
			local quantity = type(QuickAuctionsDB.itemList[name]) == "number" and QuickAuctionsDB.itemList[name] or 1
			local willPost = math.floor(GetItemCount(link) / quantity)
			local leftToCap = (QuickAuctionsDB.postCap[name] or QuickAuctionsDB.postCap[itemCategory] or QuickAuctionsDB.postCap.default) - (activeAuctions[name] or 0)
			willPost = willPost > leftToCap and leftToCap or willPost
		
			self.postButton.totalPosts = self.postButton.totalPosts + willPost
		end
	end

	-- Nothing to post, it's all below a threshold
	if( #(postList) == 0 ) then
		self.postButton.totalPosts = 0
		return
	end
	
	self.postButton:SetFormattedText(L["%d/%d items"], self.postButton.totalPosts, self.postButton.totalPosts)
	self.postButton:Disable()

	-- Save money so we can check if we have enough to post
	money = GetMoney()
	totalPosts = self.postButton.totalPosts
	
	-- Post a group of items
	self:QueueSet()
end

-- Check if any of our posted auctions were undercut by someone, using the data we got earlier
function QA:CheckItems()
	for k in pairs(tempList) do tempList[k] = nil end
	
	self.scanButton:Disable()
	self.scanButton:SetText(L["Scan Items"])
	
	totalCancels = 0
	self.scanButton.totalCancels = 0
	
	for i=1, (GetNumAuctionItems("owner")) do
		local name, texture, quantity, _, _, _, minBid, _, buyoutPrice, _, _, owner, wasSold = GetAuctionItemInfo("owner", i)     
		local priceData = auctionData[name]
		
		if( priceData and priceData.owner and wasSold == 0 ) then
			buyoutPrice = buyoutPrice / quantity
			minBid = minBid / quantity
			
			-- Check if buyout, our minimum bid are equal or lower than ours. 
			-- If they aren't us and if they aren't on our whitelist (We don't care if they undercut us)
			if( ( priceData.buyout < buyoutPrice or ( priceData.buyout == buyoutPrice and priceData.minBid <= minBid ) ) and priceData.owner ~= owner ) then
				-- They are either not on the white list, or they are but they undercut us so we cancel it anyway.
				if( not QuickAuctionsDB.whitelist[priceData.owner] or ( QuickAuctionsDB.whitelist[priceData.owner] and priceData.buyout < buyoutPrice ) ) then
					local itemCategory = self:GetItemCategory(GetAuctionItemLink("owner", i))
					local threshold, belowThresh

					-- Smart cancelling, lets us choose if we should cancel something
					-- if the auction fell below the threshold
					if( QuickAuctionsDB.smartCancel ) then
						threshold = QuickAuctionsDB.threshold[name] or QuickAuctionsDB.threshold[itemCategory] or QuickAuctionsDB.threshold.default
						belowThresh = priceData.buyout <= threshold
					end

					if( not tempList[name] ) then
						if( not belowThresh ) then
							self:Echo(string.format(L["Undercut on %s, by %s, buyout %s, bid %s, our buyout %s, our bid %s (per item)"], name, priceData.owner, self:FormatTextMoney(priceData.buyout), self:FormatTextMoney(priceData.minBid), self:FormatTextMoney(buyoutPrice / quantity), self:FormatTextMoney(minBid / quantity)))
						else
							self:Echo(string.format(L["Undercut on %s, by %s, buyout %s, our buyout %s (per item), threshold is %s so not cancelling."], name, priceData.owner, self:FormatTextMoney(priceData.buyout), self:FormatTextMoney(buyoutPrice / quantity), self:FormatTextMoney(threshold)))
						end
					end

					if( not belowThresh ) then
						totalCancels = totalCancels + 1
						self.scanButton.totalCancels = self.scanButton.totalCancels + 1
						self.scanButton:SetFormattedText(L["%d/%d items"], totalCancels, QA.scanButton.totalCancels)

						tempList[name] = true
						CancelAuction(i)
					end
				end
			end
		end
	end
	
	if( self.scanButton.totalCancels == 0 ) then
		self:Print(L["Nothing to cancel, all auctions are the lowest price."])
		self.scanButton:Enable()
	end
end

-- Do a delay before scanning the auctions so it has time to load all of the owner information
local scanDelay = 0.20
local scanElapsed = 0
local scanFrame = CreateFrame("Frame")
scanFrame:Hide()
scanFrame:SetScript("OnUpdate", function(self, elapsed)
	scanElapsed = scanElapsed + elapsed
	
	if( scanElapsed >= scanDelay ) then
		scanElapsed = 0
		self:Hide()
		
		QA:ScanAuctionList()
	end
end)

function QA:AUCTION_ITEM_LIST_UPDATE()
	scanElapsed = 0
	scanFrame:Show()
end

-- Time to scan auctions!
function QA:ScanAuctionList()
	-- Not scanning, done here
	if( not currentQuery.scanning or not currentQuery.name ) then
		return
	end
	
	local shown, total = GetNumAuctionItems("list")
	
	-- Scan the list of auctions and find the one with the lowest bidder, using the data we have.
	local hasBadOwners
	for i=1, shown do
		local name, texture, quantity, _, _, _, minBid, _, buyoutPrice, _, _, owner = GetAuctionItemInfo("list", i)     
		if( name and not auctionData[name] ) then
			auctionData[name] = {buyout = 0, totalFound = 0, minBid = 0, link = self:GetSafeLink(GetAuctionItemLink("list", i))}
		end
		
		-- Turn it into price per an item
		buyoutPrice = buyoutPrice / quantity
		minBid = minBid / quantity
		
		-- Only pull good owner data, if they are the lowest
		if( name ) then
			auctionData[name].totalFound = auctionData[name].totalFound + quantity
		end
		
		if( name and owner ~= UnitName("player") and ( buyoutPrice < auctionData[name].buyout or not auctionData[name].owner ) and buyoutPrice > 0 ) then
			if( owner ) then
				auctionData[name].minBid = minBid
				auctionData[name].buyout = buyoutPrice
				auctionData[name].owner = owner
			else
				hasBadOwners = true
			end
		end
	end
	
	-- Found a query with bad owners
	if( hasBadOwners and not currentQuery.forceStop ) then
		badRetries = badRetries + 1
		if( badRetries <= 3 ) then
			-- :( Increase it slightly
			scanDelay = scanDelay + 0.10
			
			badRetries = 0
			self:SendQuery(currentQuery.name, currentQuery.page, "retry", currentQuery.classIndex, currentQuery.subClassIndex)
			return
		end
			
	-- Reset the counter since we got good owners
	elseif( badRetries > 0 ) then
		badRetries = 0
	end	
	
	-- Good request, so reset it
	if( not hasBadOwners ) then
		scanDelay = 0.20
	end
	
	-- If it's an active scan, and we have shown as much as possible, then scan the next page
	if( shown == NUM_AUCTION_ITEMS_PER_PAGE and not currentQuery.forceStop ) then
		currentQuery.page = currentQuery.page + 1
		self:SendQuery(currentQuery.name, currentQuery.page, "page", currentQuery.classIndex, currentQuery.subClassIndex)

	-- Move on to the next in the list
	else
		local filter = table.remove(scanList, 1)
		
		-- Nothing else to search, done!
		if( not filter ) then
			if( self.isQuerying ) then
				return
			end
				
			self.scanButton:Enable()

			currentQuery.forceStop = nil
			currentQuery.scanning = nil
			currentQuery.classIndex = nil
			currentQuery.subClassIndex = nil
			
			if( scanType == "scan" ) then
				self:CheckItems()
			elseif( scanType == "summary" ) then
				self.Summary:Finished()
			elseif( scanType == "post" ) then
				self:PostItems()
			end
			return
		end
		
		self:SendQuery(filter, 0, "new", currentQuery.clasIndex, currentQuery.subClassIndex)
	end
end

-- Event handler/misc
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
frame:SetScript("OnEvent", function(self, event, ...)
	if( event == "ADDON_LOADED" and select(1, ...) == "QuickAuctions" ) then
		QA:OnInitialize()
		
		if( QA.scanButton ) then
			self:UnregisterEvent("ADDON_LOADED")
		end
	elseif( event == "ADDON_LOADED" and IsAddOnLoaded("Blizzard_AuctionUI") ) then
		QA:AHInitialize()
		
		if( defaults ) then
			self:UnregisterEvent("ADDON_LOADED")
		end
	elseif( event ~= "ADDON_LOADED" ) then
		QA[event](QA, ...)
	end
end)

QA.frame = frame

function QA:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99Quick Auctions|r: %s", msg))
end

function QA:Echo(msg)
	DEFAULT_CHAT_FRAME:AddMessage(msg)
end

-- Stolen from Blizzard!
function QA:FormatMoney(money)
	local gold = math.floor(money / COPPER_PER_GOLD)
	local silver = math.floor((money - (gold * COPPER_PER_GOLD)) / COPPER_PER_SILVER)
	local copper = math.fmod(money, COPPER_PER_SILVER)
	
	return gold, silver, copper
end

function QA:DeformatMoney(text)
	text = string.lower(text)
	local gold = string.match(text, "([0-9]+)g")
	local silver = string.match(text, "([0-9]+)s")
	local copper = string.match(text, "([0-9]+)c")
	if( not gold and not silver and not copper ) then
		return nil
	end
	
	gold = tonumber(gold) or 0
	silver = tonumber(silver) or 0
	copper = tonumber(copper) or 0
		
	copper = copper + (gold * COPPER_PER_GOLD) + (silver * COPPER_PER_SILVER)
		
	return copper
end

-- Stolen from Tekkub!
local GOLD_TEXT = "|cffffd700g|r"
local SILVER_TEXT = "|cffc7c7cfs|r"
local COPPER_TEXT = "|cffeda55fc|r"

-- Truncate tries to save space, after 10g stop showing copper, after 100g stop showing silver
function QA:FormatTextMoney(money, truncate)
	local gold, silver, copper = self:FormatMoney(money)
	local text = ""
	
	-- Add gold
	if( gold > 0 ) then
		text = string.format("%d%s ", gold, GOLD_TEXT)
	end
	
	-- Add silver
	if( silver > 0 and ( not truncate or gold < 100 ) ) then
		text = text .. string.format("%d%s ", silver, SILVER_TEXT)
	end
	
	-- Add copper if we have no silver/gold found, or if we actually have copper
	if( text == "" or ( copper > 0 and ( not truncate or gold <= 10 ) ) ) then
		text = text .. string.format("%d%s ", copper, COPPER_TEXT)
	end
	
	return string.trim(text)
end

-- Quick method of setting these variables without duplicating it 500 times
local function parseVariableOption(arg, configKey, isMoney, defaultMsg, setMsg, removedMsg)
	local self = QA
	local amount, link = string.split(" ", arg, 2)
	amount = (isMoney and self:DeformatMoney(amount) or tonumber(amount))
	if( not amount ) then
		if( isMoney ) then
			self:Print(L["Invalid money format given, should be #g for gold, #s for silver, #c for copper. For example: 5g2s10c would set it 5 gold, 2 silver, 10 copper."])
		else
			self:Print(L["Invalid number passed."])
		end
		return
	end
	
	-- Default value
	if( not link ) then
		QuickAuctionsDB[configKey].default = amount
		self:Print(string.format(defaultMsg, (isMoney and self:FormatTextMoney(amount) or amount)))
		return
	end
	
	-- Set it for a specific item
	local name = GetItemInfo(link)

	-- It's an entire category of items, not a specific one
	if( not name and validTypes[link] ) then
		name = link
		link = validTypes[link]
		
	-- Bad link given
	elseif( not name ) then
		self:Print(L["Invalid item link, or item type passed."])
		return
	end
	
	-- If they passed 0 then we remove the value
	if( amount <= 0 ) then
		QuickAuctionsDB[configKey][name] = nil
		self:Print(string.format(removedMsg, link))
		return
	end
	
	-- Set it for this item now!
	QuickAuctionsDB[configKey][name] = amount
	self:Print(string.format(setMsg, link, (isMoney and self:FormatTextMoney(amount) or amount)))
end

-- Slash commands
SLASH_QUICKAUCTIONS1 = "/quickauctions"
SLASH_QUICKAUCTIONS2 = "/qa"
SlashCmdList["QUICKAUCTIONS"] = function(msg)
	msg = msg or ""
	
	local self = QA
	local cmd, arg = string.split(" ", msg, 2)
	cmd = string.lower(cmd or "")

	-- Undercut amount
	if( cmd == "undercut" and arg ) then
		parseVariableOption(arg, "undercut", true, L["Default undercut for auctions set to %s."], L["Set undercut for %s to %s."], L["Removed undercut on %s."])
	-- No data fallback
	elseif( cmd == "fallback" and arg ) then
		parseVariableOption(arg, "fallback", true, L["Default fall back for auctions set to %s."], L["Set fall back for %s to %s."], L["Removed fall back on %s."])
	
	-- Post threshold
	elseif( cmd == "threshold" and arg ) then
		parseVariableOption(arg, "threshold", true, L["Default threshold for auctions set to %s."], L["Set threshold for %s to %s."], L["Removed threshold on %s."])

	-- Post cap
	elseif( cmd == "cap" and arg ) then
		parseVariableOption(arg, "postCap", false, L["Default post cap for auctions set to %s."], L["Set post cap for %s to %s."], L["Removed post cap on %s."])
	
	-- Toggle summary
	elseif( cmd == "summary" ) then
		if( QA.Summary.frame and QA.Summary.frame:IsVisible() ) then
			QA.Summary.frame:Hide()
			return
		end
		
		QA.Summary:CreateGUI()
		QA.Summary.frame:Show()
	
	-- Bid percentage of something
	elseif( cmd == "bidpercent" and arg ) then
		local amount = tonumber(arg)
		if( amount < 0 ) then amount = 0 end
		if( amount > 100 ) then amount = 100 end
		
		self:Print(string.format(L["Bids will now be %d%% of the buyout price for all items."], amount))
		QuickAuctionsDB.bidpercent = amount / 100
	
	-- Enable smart undercutting
	elseif( cmd == "smartcut" ) then
		QuickAuctionsDB.smartUndercut = not QuickAuctionsDB.smartUndercut
		
		if( QuickAuctionsDB.smartUndercut ) then
			self:Print(L["Smart undercutting is now enabled."])
		else
			self:Print(L["Smart undercutting is now disabled."])
		end
	
	-- Adding items to the managed list
	elseif( cmd == "additem" and arg ) then
		local link, quantity = string.match(arg, "(.+) ([0-9]+)")
		if( not link and not quantity ) then
			link = arg
		else
			quantity = tonumber(quantity)
		end
		
		-- Make sure we're giving good data
		local name, link, _, _, _, _, _, stackCount = GetItemInfo(link)
		if( not name ) then
			self:Print(L["Invalid item link given."])
			return
		-- If the item can stack, and they didn't provide how much we should stack it in, then error
		elseif( stackCount > 1 and not quantity or quantity <= 0 ) then
			self:Print(string.format(L["The item %s can stack up to %d, you must set the quantity that it should post them in."], link, stackCount))
			return
		
		-- Make sure they didn't give a bad stack count
		elseif( quantity and quantity > stackCount ) then
			self:Print(string.format(L["The item %s can only stack up to %d, you provided %d so set it to %d instead."], link, stackCount, quantity, quantity))
			quantity = stackCount
		end
		
		QuickAuctionsDB.itemList[name] = quantity or true
		if( quantity ) then
			self:Print(string.format(L["Now managing %s in Quick Auctions! Will post auctions with %s x %d"], link, link, quantity))
		else
			self:Print(string.format(L["Now managing the item %s in Quick Auctions!"], link))
		end
	
	-- Remove an item from the manage list
	elseif( cmd == "removeitem" and arg ) then
		if( not arg or not GetItemInfo(arg) ) then
			self:Print(L["Invalid item link given."])
			return
		end
		
		QuickAuctionsDB.itemList[(GetItemInfo(arg))] = nil
		self:Print(string.format(L["Removed %s from the managed auctions list."], string.trim(arg)))
	
	-- Toggling entire categories
	elseif( cmd == "toggle" and arg ) then
		arg = string.lower(arg)
		
		for data, key in pairs(typeInfo) do
			if( key == arg ) then
				toggleKey = data
				toggleText = validTypes[key]
				break
			end
		end
		
		if( not toggleKey ) then
			self:Print(L["Invalid item type toggle entered."])
			return
		end
		
		if( not QuickAuctionsDB.itemTypes[toggleKey] ) then
			QuickAuctionsDB.itemTypes[toggleKey] = true
			self:Print(string.format(L["Now posting all %s."], toggleText))
		else
			QuickAuctionsDB.itemTypes[toggleKey] = nil
			self:Print(string.format(L["No longer posting all %s."], toggleText))
		end

	-- Post time
	elseif( cmd == "time" and arg ) then
		local time = tonumber(arg)
		if( time ~= 12 and time ~= 24 and time ~= 48 ) then
			self:Print(string.format(L["Invalid time \"%s\" passed, should be 12, 24 or 48."], arg))
			return
		end
		
		AHTime = time * 60
		self:Print(string.format(L["Set auction time to %d hours."], time))
	
	-- Add to whitelist
	elseif( cmd == "addwhite" and arg ) then
		QuickAuctionsDB.whitelist[arg] = true
		self:Print(string.format(L["Added %s to the whitelist."], arg))

	-- Remove from whitelist
	elseif( cmd == "removewhite" and arg ) then
		QuickAuctionsDB.whitelist[arg] = nil
		self:Print(string.format(L["Removed %s from whitelist."], arg))
	
	-- Smart cancelling
	elseif( cmd == "cancel" ) then
		QuickAuctionsDB.smartCancel = not QuickAuctionsDB.smartCancel
		
		if( QuickAuctionsDB.smartCancel ) then
			self:Print(L["Only cancelling if the lowest price isn't below the threshold."])
		else
			self:Print(L["Always cancelling if someone undercuts us."])
		end
	
	-- Enables asshole mode! Automatically scans every 60 seconds, and posts every 30 seconds
	elseif( cmd == "super" ) then
		if( self.superFrame ) then
			if( self.superFrame:IsVisible() ) then
				self:Print(L["Disabled super auctioning!"])
				self.superFrame:Hide()
			else
				self:Print(L["Enabled super auctioning!"])
				self.superFrame.scansRan = 0
				self.superFrame.timeElapsed = 0
				self.superFrame:Show()
			end
			return
		end
		
		self.superFrame = CreateFrame("Frame")
		self.superFrame.timeElapsed = 0
		self.superFrame.scansRan = 0
		self.superFrame:SetScript("OnUpdate", function(self, elapsed)
			self.timeElapsed = self.timeElapsed + elapsed
			
			if( self.timeElapsed >= 30 and not self.postedAlready ) then
				self.postedAlready = true
				if( AuctionFrame:IsVisible() ) then
					QA.postButton:Click()
				end
			end
			
			if( self.timeElapsed >= 60 ) then
				self.timeElapsed = 0
				self.postedAlready = nil
				
				if( AuctionFrame:IsVisible() ) then
					self.scansRan = self.scansRan + 1
					QA.scanButton:Click()
					ChatFrame1:AddMessage(string.format(L["[%s] Scan running..."], self.scansRan))
				end
			end
		end)
		
		self:Print(L["Enabled super auctioning!"])
	else
		self:Print(L["Slash commands"])
		self:Echo(L["/qa smartcut - Toggles smart undercutting (Going from 1.9g -> 1g first instead of 1.9g - undercut amount."])
		self:Echo(L["/qa cancel - Disables undercutting if the lowest price falls below the the threshold."])
		self:Echo(L["/qa bidpercent <0-100> - Percentage of the buyout that the bid should be, 200g buyout and this set at 90 will put the bid at 180g."])
		self:Echo(L["/qa time <12/24/48> - Amount of hours to put auctions up for, only works for the current sesson."])
		self:Echo(L["/qa undercut <money> <link/type> - How much to undercut people by."])
		self:Echo(L["/qa cap <amount> <link/type> - Only allow <amount> of the same kind of auction to be up at the same time."])
		self:Echo(L["/qa fallback <money> <link/type> - How much money to default to if nobody else has an auction up."])
		self:Echo(L["/qa threshold <money> <link/type> - Don't post any auctions that would go below this amount."])
		self:Echo(L["/qa addwhite <name> - Adds a name to the whitelist to not undercut."])
		self:Echo(L["/qa removewhite <name> - Removes a name from the whitelist."])
		self:Echo(L["/qa additem <link> <quantity> - Adds an item to the list of things that should be managed, *IF* the item can stack you must provide a quantity to post it in."])
		self:Echo(L["/qa removeitem <link> - Removes an item from the managed list."])
		self:Echo(L["/qa toggle <gems/uncut/glyphs/enchants> - Lets you toggle entire categories of items: All cut gems, all uncut gems, and all glyphs. These will always be put onto the AH as the single item, if you want to override it to post multiple then use the additem command."])
		self:Echo(L["/qa summary - Toggles the summary frame."])
	end
end
