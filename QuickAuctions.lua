-- Ugly code, need to clean it up later
QA = {}

local isScanning, searchFilter, scanType, scanTotal, scanIndex, spamFrame, money, splittingLink
local page, badRetries, totalCancels, totalPosts, totalPostsSet, totalNewStacks, splitQuantity = 0, 0, 0, 0, 0, 0, 0
local activeAuctions, scanList, priceList, queryQueue, postList, auctionPostQueue, foundSlots = {}, {}, {}, {}, {}, {}, {}
local AHTime = 12 * 60

function QA:OnInitialize()
	local defaults = {
		spammyFrame = 1,
		smartUndercut = true,
		smartCancel = true,
		itemTypes = {["Gem"] = 1},
		itemList = {},
		whitelist = {},
		specialUndercut = {},
		undercutBy = 100,
		threshold = (100 * 10000),
		specialThresh = {},
		fallback = (225 * 10000),
		specialFallback = {},
		postCap = 2,
		specialCap = {},
		logging = false,
		logs = {},
	}
	
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
	
	spamFrame = getglobal("ChatFrame" .. QuickAuctionsDB.spammyFrame) or DEFAULT_CHAT_FRAME
	
	-- Hook the query function so we know what we last sent a search on
	local orig_QueryAuctionItems = QueryAuctionItems
	QueryAuctionItems = function(name, ...)
		if( CanSendAuctionQuery() ) then
			searchFilter = name
		end
		
		return orig_QueryAuctionItems(name, ...)
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
	button.tooltip = "Scan posted auctions to see if any were undercut."
	button:SetPoint("TOPRIGHT", AuctionFrameAuctions, "TOPRIGHT", 51, -15)
	button:SetText("Scan Items")
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
	button.tooltip = "Post items from your inventory into the auction house."
	button:SetPoint("TOPRIGHT", self.scanButton, "TOPLEFT", 0, 0)
	button:SetText("Post Items")
	button:SetWidth(110)
	button:SetHeight(18)
	button:SetScript("OnEnter", showTooltip)
	button:SetScript("OnLeave", hideTooltip)
	button:SetScript("OnClick", function(self)
		QA:PostAuctions()
	end)
	
	self.postButton = button
	
	-- Hook chat to block auction post/cancels, and also let us know when we're done posting
	local orig_ChatFrame_SystemEventHandler = ChatFrame_SystemEventHandler
	ChatFrame_SystemEventHandler = function(self, event, msg)
		if( msg == "Auction cancelled." and totalCancels > 0 ) then
			totalCancels = totalCancels - 1
			
			QA.scanButton:SetFormattedText("%d/%d items", totalCancels, QA.scanButton.totalCancels)
			QA.scanButton:Disable()
			
			if( totalCancels <= 0 ) then
				totalCancels = 0
				
				QA.scanButton:SetText("Scan Items")
				QA.scanButton:Enable()
				QA:Print("Done cancelling auctions.")
			end
			return true

		elseif( msg == "Auction created." and totalPosts > 0 ) then
			totalPosts = totalPosts - 1
			totalPostsSet = totalPostsSet - 1
			
			if( totalPostsSet <= 0 ) then
				QA:Log("Done posting current set.")
				QA:QueueSet()
			end
			
			if( totalPosts <= 0 ) then
				totalPosts = 0
				QA:Print("Done posting auctions.")

				QA.postButton:SetText("Post Items")
				QA.postButton:Enable()
				
				QA:Log("Done posting auctions.")
			else
				-- This one went throughdo next
				if( totalPostsSet > 0 ) then
					QA:PostQueuedAuction()
				end
				
				QA.postButton:SetFormattedText("%d/%d items", totalPosts, QA.postButton.totalPosts)
				QA.postButton:Disable()
			end
			
			return true
		end
	end
end

-- Debugging
function QA:Log(...)
	if( not QuickAuctionsDB.logging ) then
		return
	end
	
	local msg = ""
	for i=1, select("#", ...) do
		msg = msg .. " " .. tostring(select(i, ...))
	end
	
	table.insert(QuickAuctionsDB.logs, string.format("[%s] %s", GetTime(), string.trim(string.gsub(string.gsub(msg, "|r", ""), "|c%x%x%x%x%x%x%x%x", ""))))
end

local timeElapsed = 0
local function checkSend(self, elapsed)
	timeElapsed = timeElapsed + elapsed
	
	if( timeElapsed >= 0.5 ) then
		timeElapsed = 0
		
		-- Can we send it yet?
		if( CanSendAuctionQuery() ) then
			local filter = table.remove(queryQueue, 1)
			local page = table.remove(queryQueue, 1)
			local type = table.remove(queryQueue, 1)

			QueryAuctionItems(filter, nil, nil, 0, 0, 0, page, 0, 0)
			
			-- It's a new request, meaning increment the item counter
			if( isScanning and type == "new" ) then
				QA.scanButton:SetFormattedText("%d/%d items", scanIndex, scanTotal)
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

function QA:SendQuery(filter, page, type)
	if( CanSendAuctionQuery() ) then
		QueryAuctionItems(filter, nil, nil, 0, 0, 0, page, 0, 0)

		-- It's a new request, meaning increment the item counter
		if( isScanning and type == "new" ) then
			self.scanButton:SetFormattedText("%d/%d items", scanIndex, scanTotal)
			scanIndex = scanIndex + 1
		end
		return
	end
	
	table.insert(queryQueue, filter)
	table.insert(queryQueue, page)
	table.insert(queryQueue, type)
	
	self.frame:SetScript("OnUpdate", checkSend)
	self.isQuerying = true
end

function QA:IsValidItem(link)
	local name, _, _, _, _, itemType, _, stackCount = GetItemInfo(link)
	if( QuickAuctionsDB.itemList[name] or QuickAuctionsDB.itemTypes[itemType] == stackCount ) then
		return true
	end
end

local tempList = {}
function QA:ScanAuctions()
	-- Blah @ Tooltip scanning to get itemid
	if( not self.tooltip ) then
		self.tooltip = CreateFrame("GameTooltip", "QuickAuctionsTooltip", UIParent, "GameTooltipTemplate")
		self.tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	end

	-- Reset data
	for i=#(scanList), 1, -1 do table.remove(scanList, i) end
	for k in pairs(tempList) do tempList[k] = nil end
	for _, data in pairs(priceList) do
		data.buyout = 99999999999999999
		data.minBid = 99999999999999999
		data.owner = nil
	end
	
	local hasItems
	for i=1, (GetNumAuctionItems("owner")) do
		-- Figure out if this is a managed auction
		self.tooltip:ClearLines()
		self.tooltip:SetAuctionItem("owner", i)
		
		local name = GetAuctionItemInfo("owner", i)
		local itemLink = select(2, self.tooltip:GetItem())
		
		if( itemLink and self:IsValidItem(itemLink) and select(13, GetAuctionItemInfo("owner", i)) == 0 ) then
			hasItems = true
			tempList[name] = true
		end
	end
	
	if( hasItems ) then
		self:StartScan(tempList, "scan")
	end
end

-- Find out where we can place something, if we can.
function QA:FindEmptyInventorySlot(forItemFamily)
	for bag=4, 0, -1 do
		local bagFamily = 0
		if( bag ~= 0 and bag ~= -1 ) then
			bagFamily = GetItemFamily(GetInventoryItemLink("player", ContainerIDToInventoryID(bag)))
		end
		
		if( bagFamily == 0 or bagFamily == forItemFamily ) then
			for slot=1, GetContainerNumSlots(bag) do
				if( not GetContainerItemLink(bag, slot) ) then
					return bag, slot
				end
			end
		end
	end
	
	return nil, nil
end

-- Split an item if needed
local timerFrame
local timeElapsed = 0
function QA:ProcessSplitQueue()
	-- Loop through bags
	for bag=0, 4 do
		-- Scanning a bag
		for slot=1, GetContainerNumSlots(bag) do
			local link = GetContainerItemLink(bag, slot)
			local itemCount, itemLocked = select(2, GetContainerItemInfo(bag, slot))
			-- Slot has something in it
			if( link == splittingLink and itemCount > splitQuantity ) then
				-- It's still locked, so we have to wait before we try and use it again
				if( itemLocked ) then
					timeElapsed = 0.15
					timerFrame:Show()
					return
				end
				
				local freeBag, freeSlot = self:FindEmptyInventorySlot(GetItemFamily(link))
				-- Bad, ran out of space
				if( not freeBag and not freeSlot ) then
					self:Print("Ran out of free space to keep splitting, not going to finish up splits.")
					return
				end

				self:Log("Splitting", (GetItemInfo(link)), "from bag", bag, "slot", slot, "moving into bag", freeBag, "slot", freeSlot)

				self.frame:RegisterEvent("BAG_UPDATE")
				SplitContainerItem(bag, slot, splitQuantity)
				PickupContainerItem(freeBag, freeSlot)
				
				foundSlots[freeBag .. freeSlot] = true
				totalNewStacks = totalNewStacks - 1
				return
			end
		end
	end
	
	-- Do a second loop, let's make sure we really ran out of things to split
	-- This solves the issue where, if we had 5 stacks of Glyph of Dash, we want to post all 5
	-- It would split 4 of them into single stacks, then error because it doesn't think it can split it anymore
	for bag=0, 4 do
		-- Scanning a bag
		for slot=1, GetContainerNumSlots(bag) do
			local link = GetContainerItemLink(bag, slot)
			local itemCount = select(2, GetContainerItemInfo(bag, slot))
			if( not foundSlots[bag .. slot] and link == splittingLink and itemCount == splitQuantity ) then
				foundSlots[bag .. slot] = true
				totalNewStacks = totalNewStacks - 1
			end
		end
	end
	
	-- We have nothing else we can really do
	if( totalNewStacks > 0 ) then
		self:Log("Odd stack size, cannot split everything, we still have to split", totalNewStacks, "of", (GetItemInfo(splittingLink)))

		totalNewStacks = 0
		splittingLink = nil

		self:FinishedSplitting()
	else
		self:Log("Finished split of", (GetItemInfo(splittingLink)))
		self:FinishedSplitting()
	end
end

-- Player bags changed, will have to be ready to do a split again soon

function QA:BAG_UPDATE()
	local self = QA
	self.frame:UnregisterEvent("BAG_UPDATE")
	
	-- Check if we are done splitting
	if( totalNewStacks == 0 ) then
		self:FinishedSplitting()
	else
		-- Create it if needed
		if( not timerFrame ) then
			timerFrame = CreateFrame("Frame")
			timerFrame:SetScript("OnUpdate", function(self, elapsed)
				timeElapsed = timeElapsed + elapsed
				if( timeElapsed >= 0.25 ) then
					self:Hide()
					timeElapsed = 0
					
					QA:ProcessSplitQueue()
					
				end
			end)
		end
		
		-- Start timer going
		timeElapsed = 0
		timerFrame:Show()
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
	local quantity = type(QuickAuctionsDB.itemList[name]) == "number" and QuickAuctionsDB.itemList[name] or 1
	
	-- This item cannot stack, so we don't need to bother with splitting and can post it all
	if( stackCount == 1 ) then
		self:Log("Item queue", name, "only stacks to", stackCount, "so posting it now.")
		self:PostItem(table.remove(postList, 1))
		return
	end
	
	-- If post cap is 20, we have 4 on the AH, then we can post 16 more before hitting cap
	local leftToCap = (QuickAuctionsDB.specialCap[name] or QuickAuctionsDB.postCap)  - (activeAuctions[name] or 0)
	-- If we have 4 of the item, we post it in stacks of 1, we can can post 4
	local canPost = math.floor(GetItemCount(link) / quantity)
	
	-- Can't post any more
	if( leftToCap <= 0 ) then
		self:Log("Can't post any more of", name, "or we will go past the cap, already have", (activeAuctions[name] or 0), "in AH")
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
			if( GetContainerItemLink(bag, slot) == link and select(2, GetContainerItemInfo(bag, slot)) == quantity ) then
				validStacks = validStacks + 1
			end
		end
	end
		
	-- Yay we do!
	if( validStacks >= canPost ) then
		self:Log("We have enough valid stacks", validStacks, "only posting", canPost, "total of item", GetItemCount(link), "post cap", postCap)
		self:PostItem(table.remove(postList, 1))
		return
	end
	
	self:Log("Going to be posting", canPost, "of", name, "x", quantity, "total of item", GetItemCount(link), "valid stacks", validStacks, "left before cap", leftToCap, "active auctions", (activeAuctions[name] or 0))
	
	-- This is a slightly odd, basically what it means is, we need that that item in the quantity provided
	-- so two entries of Bloodstone 4 means we want two x Bloodstones that are stacked up to 4
	totalNewStacks = canPost - validStacks
	splittingLink = link
	splitQuantity = quantity
		
	-- Nothing queued, meaning we have nothing to post for this item
	if( totalNewStacks == 0 ) then
		table.remove(postList, 1)
		
		self:Log("Only have", GetItemCount(link), "of", name, "we want", quantity)
		self:Echo(string.format("You only have %d of %s, and posting it in stacks of %d, not posting.", GetItemCount(link), link, quantity))
		self:QueueSet()
		return
	end
	
	-- Get us going
	for k in pairs(foundSlots) do foundSlots[k] = nil end
	self:ProcessSplitQueue()
end

-- Prepare to post auctions
function QA:PostAuctions()
	-- Reset data
	for k in pairs(tempList) do tempList[k] = nil end
	for i=#(postList), 1, -1 do table.remove(postList, i) end
	for _, data in pairs(priceList) do
		data.buyout = 99999999999999999
		data.minBid = 99999999999999999
		data.owner = nil
	end
	
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
			local link = GetContainerItemLink(bag, slot)
			if( link ) then
				local name, _, _, _, _, _, _, stackCount = GetItemInfo(link)
				local postCap = QuickAuctionsDB.specialCap[name] or QuickAuctionsDB.postCap
				
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
	
	self:Log("Starting scan", type, "items", #(scanList))

	local filter = table.remove(scanList, 1)
	if( not filter ) then
		return
	end
		
	self.scanButton:Disable()
	self.scanButton:SetFormattedText("%d/%d items", 0, #(scanList) + 1)
	
	-- Setup scan info blah blah
	scanType = type
	scanTotal = #(scanList) + 1
	scanIndex = 1
	isScanning = true
	page = 0
	
	self:SendQuery(filter, page, "new")
end

function QA:PostQueuedAuction()
	if( #(auctionPostQueue) == 0 ) then
		return
	end
	
	local bag = table.remove(auctionPostQueue, 1)
	local slot = table.remove(auctionPostQueue, 1)
	local minBid = table.remove(auctionPostQueue, 1)
	local buyout = table.remove(auctionPostQueue, 1)

	self:Log("Posted bag", bag, "slot", slot, "in the AH for", AHTime, " at", self:FormatTextMoney(buyout), self:FormatTextMoney(minBid))

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
	local priceData = priceList[name]
	local totalPosted = activeAuctions[name] or 0
	local quantity = type(QuickAuctionsDB.itemList[name]) == "number" and QuickAuctionsDB.itemList[name] or 1
	local minBid, buyout
	
	totalPostsSet = 0

	-- Figure out what price we are posting at
	if( priceData and priceData.owner ) then
		minBid = math.floor(priceData.minBid)
		buyout = math.floor(priceData.buyout)

		-- Don't undercut people on our whitelist, match them
		if( not QuickAuctionsDB.whitelist[priceData.owner] ) then
			buyout = buyout / 10000

			-- If smart undercut is on, then someone who posts an auction of 99g99s0c, it will auto undercut to 99g
			-- instead of 99g99s0c - undercutBy
			if( not QuickAuctionsDB.smartUndercut or  buyout == math.floor(buyout) ) then
				buyout = ( buyout * 10000 ) - (QuickAuctionsDB.specialUndercut[name] or QuickAuctionsDB.undercutBy)
			else
				buyout = math.floor(buyout) * 10000
			end

			minBid = buyout
		end

		self:Log("Going to post", name, "at buyout/bid", self:FormatTextMoney(buyout), " data says owner is", (priceData.owner or "<none>"), "with posted at", self:FormatTextMoney(priceData.buyout))

	-- No other data available, default to our fallback for it
	else
		minBid = QuickAuctionsDB.specialFallback[name] or QuickAuctionsDB.fallback
		buyout = QuickAuctionsDB.specialFallback[name] or QuickAuctionsDB.fallback

		self:Echo(string.format("No data found for %s, using %s buyout and %s bid default.", name, self:FormatTextMoney(buyout), self:FormatTextMoney(minBid)))
		self:Log("Going to post", name, "at buyout/bid", self:FormatTextMoney(buyout), " no owner found.")
	end

	-- Find the item in our inventory
	for i=#(auctionPostQueue), 1, -1 do table.remove(auctionPostQueue, i) end
	for bag=0, 4 do
		for slot=1, GetContainerNumSlots(bag) do
			local itemLink = GetContainerItemLink(bag, slot)
			local itemCount = select(2, GetContainerItemInfo(bag, slot))
			-- It's the correct quantity/link so can post it
			if( itemLink == link and itemCount == quantity ) then
				totalPosted = totalPosted + 1

				-- Hit limit, done with this item
				local postCap = QuickAuctionsDB.specialCap[name] or QuickAuctionsDB.postCap
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
					
					totalPostsSet = totalPostsSet + 1
				else
					for i=#(auctionPostQueue), 1, -1 do table.remove(auctionPostQueue, i) end
					totalPosts = 0
					
					self.postButton:SetText("Post Items")
					self.postButton:Enable()
					self:Print("Cannot post remaining auctions, you do not have enough money.")
					return
				end

				-- Now reset the button quickly
				ClickAuctionSellItemButton()
				ClearCursor()
			end
		end
	end
		
	-- And now update post totals
	self.postButton:SetFormattedText("%d/%d items", totalPosts, self.postButton.totalPosts)
	self.postButton:Disable()

	-- Now actually post everything
	self:PostQueuedAuction()
end

function QA:PostItems()
	self.scanButton:Enable()
	self.scanButton:SetText("Scan Items")
	self.postButton.totalPosts = 0

	-- Quick check for threshold info
	for i=#(postList), 1, -1 do
		local link = postList[i]
		local name = GetItemInfo(link)
		local priceData = priceList[name]
		local threshold = QuickAuctionsDB.specialThresh[name] or QuickAuctionsDB.threshold
		
		if( priceData and priceData.owner and priceData.buyout <= threshold ) then
			spamFrame:AddMessage(string.format("Not posting %s, because the buyout is %s per item and the threshold is %s", name, self:FormatTextMoney(priceData.buyout), self:FormatTextMoney(threshold)))
			table.remove(postList, i)
		else
			-- Figure out how many auctions we will be posting quickly
			local quantity = type(QuickAuctionsDB.itemList[name]) == "number" and QuickAuctionsDB.itemList[name] or 1
			local willPost = math.floor(GetItemCount(link) / quantity)
			local postCap = QuickAuctionsDB.specialCap[name] or QuickAuctionsDB.postCap
			willPost = willPost > postCap and postCap or willPost
			
			self.postButton.totalPosts = self.postButton.totalPosts + willPost
		end
	end

	-- Nothing to post, it's all below a threshold
	if( #(postList) == 0 ) then
		self.postButton.totalPosts = 0
		return
	end
	
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
	self.scanButton:SetText("Scan Items")
	
	totalCancels = 0
	self.scanButton.totalCancels = 0
	
	for i=1, (GetNumAuctionItems("owner")) do
		local name, texture, quantity, _, _, _, minBid, _, buyoutPrice, _, _, owner, wasSold = GetAuctionItemInfo("owner", i)     
		local priceData = priceList[name]
		
		if( priceData and wasSold == 0 ) then
			buyoutPrice = buyoutPrice / quantity
			minBid = minBid / quantity
			
			-- Check if buyout, our minimum bid are equal or lower than ours. 
			-- If they aren't us and if they aren't on our whitelist (We don't care if they undercut us)
			if( ( priceData.buyout < buyoutPrice or ( priceData.buyout == buyoutPrice and priceData.minBid <= minBid ) ) and priceData.owner ~= owner and not QuickAuctionsDB.whitelist[priceData.owner] ) then
				local threshold, belowThresh
				
				-- Smart cancelling, lets us choose if we should cancel something
				-- if the auction fell below the threshold
				if( QuickAuctionsDB.smartCancel ) then
					threshold = QuickAuctionsDB.specialThresh[name] or QuickAuctionsDB.threshold
					belowThresh = priceData.buyout <= threshold
				end
				
				if( not tempList[name] ) then
					if( not belowThresh ) then
						self:Echo(string.format("Undercut on %s, by %s, buyout %s, bid %s, our buyout %s, our bid %s (per item)", name, priceData.owner, self:FormatTextMoney(priceData.buyout), self:FormatTextMoney(priceData.minBid), self:FormatTextMoney(buyoutPrice / quantity), self:FormatTextMoney(minBid / quantity)))
					else
						spamFrame:AddMessage(string.format("Undercut on %s, by %s, buyout %s, our buyout %s (per item), threshold is %s so not cancelling.", name, priceData.owner, self:FormatTextMoney(priceData.buyout), self:FormatTextMoney(buyoutPrice / quantity), self:FormatTextMoney(threshold)))
					end
				end

				if( not belowThresh ) then
					totalCancels = totalCancels + 1
					self.scanButton.totalCancels = self.scanButton.totalCancels + 1
					self.scanButton:SetFormattedText("%d/%d items", totalCancels, QA.scanButton.totalCancels)

					tempList[name] = true
					CancelAuction(i)
				end
			end
		end
	end
	
	if( self.scanButton.totalCancels == 0 ) then
		self:Print("Nothing to cancel, all auctions are the lowest price.")
		self.scanButton:Enable()
	end
end

-- Do a delay before scanning the auctions so it has time to load all of the owner information
-- Trying something different, the first scan uses a 0.50s delay to be safe
-- after that, we swap to 0.25s so it's faster
local scanDelay = 0.50
local scanElapsed = 0
local scanFrame = CreateFrame("Frame")
scanFrame:Hide()
scanFrame:SetScript("OnUpdate", function(self, elapsed)
	scanElapsed = scanElapsed + elapsed
	
	if( scanElapsed >= scanDelay ) then
		scanElapsed = 0
		scanDelay = 0.25
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
	if( not isScanning or not searchFilter ) then
		return
	end
	
	local shown, total = GetNumAuctionItems("list")
	
	-- Scan the list of auctions and find the one with the lowest bidder, using the data we have.
	local hasBadOwners
	for i=1, shown do
		local name, texture, quantity, _, _, _, minBid, _, buyoutPrice, _, _, owner = GetAuctionItemInfo("list", i)     
		if( not priceList[name] ) then
			priceList[name] = {buyout = 99999999999999999, minBid = 99999999999999999}
		end
		
		-- Turn it into price per an item
		buyoutPrice = buyoutPrice / quantity
		minBid = minBid / quantity
		
		-- Only pull good owner data, if they are the lowest
		if( owner ~= UnitName("player") and ( buyoutPrice < priceList[name].buyout ) and buyoutPrice > 0 ) then
			if( owner ) then
				priceList[name].minBid = minBid
				priceList[name].buyout = buyoutPrice
				priceList[name].owner = owner
			else
				hasBadOwners = true
			end
		end
	end
	
	self:Log("Finished scan for", (searchFilter or "<none>"), "has bad owners?", hasBadOwners, "retries", badRetries, "total/shown", total, shown, "scan type", scanType)
	
	-- Found a query with bad owners
	if( hasBadOwners ) then
		badRetries = badRetries + 1
		if( badRetries <= 3 ) then
			badRetries = 0
			self:SendQuery(searchFilter, page, "retry")
			return
		end
			
	-- Reset the counter since we got good owners
	elseif( badRetries > 0 ) then
		badRetries = 0
	end	
	
	-- If it's an active scan, and we have shown as much as possible, then scan the next page
	if( shown == 50 ) then
		page = page + 1
		self:SendQuery(searchFilter, page, "page")

	-- Move on to the next in the list
	else
		local filter = table.remove(scanList, 1)
		page = 0
		
		-- Nothing else to search, done!
		if( not filter ) then
			if( self.isQuerying ) then
				return
			end
			
			isScanning = nil
			
			if( scanType == "scan" ) then
				self:CheckItems()
			elseif( scanType == "post" ) then
				self:PostItems()
			end
			return
		end
		
		self:SendQuery(filter, page, "new")
	end
end

-- Event handler/misc
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
frame:SetScript("OnEvent", function(self, event, ...)
	if( event == "ADDON_LOADED" and IsAddOnLoaded("Blizzard_AuctionUI") ) then
		self:UnregisterEvent("ADDON_LOADED")
		QA:OnInitialize()
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

function QA:FormatTextMoney(money)
	local gold, silver, copper = self:FormatMoney(money)
	local text = ""
	
	-- Add gold
	if( gold > 0 ) then
		text = string.format("%d%s ", gold, GOLD_TEXT)
	end
	
	-- Add silver
	if( silver > 0 ) then
		text = text .. string.format("%d%s ", silver, SILVER_TEXT)
	end
	
	-- Add copper if we have no silver/gold found, or if we actually have copper
	if( text == "" or copper > 0 ) then
		text = text .. string.format("%d%s ", copper, COPPER_TEXT)
	end
	
	return string.trim(text)
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
		local amount, link = string.split(" ", arg, 2)
		amount = self:DeformatMoney(amount)
		if( not amount ) then
			self:Print("Invalid money format given, should be #g for gold, #s for silver, #c for copper, or 5g2s for 5 gold, 2 silver.")
			return
		end
		
		-- Set it globally as a default
		if( not link ) then
			QuickAuctionsDB.undercutBy = amount
			self:Print(string.format("Undercutting auctions by %s", self:FormatTextMoney(QuickAuctionsDB.undercutBy)))
			return
		end
		
		-- Set it for this specific item
		local name = GetItemInfo(link)
		if( not name ) then
			self:Print("Invalid item link given.")
			return
		end

		if( amount <= 0 ) then
			QuickAuctionsDB.specialUndercut[name] = nil
			self:Print(string.format("Removed undercut on %s.", link))
			return
		end
		
		QuickAuctionsDB.specialUndercut[name] = amount or QuickAuctionsDB.specialUndercut[name]
		self:Print(string.format("Set undercut for %s to %s.", link, self:FormatTextMoney(QuickAuctionsDB.specialUndercut[name])))
	
	-- Enable smart undercutting
	elseif( cmd == "smartcut" ) then
		QuickAuctionsDB.smartUndercut = not QuickAuctionsDB.smartUndercut
		
		if( QuickAuctionsDB.smartUndercut ) then
			self:Print("Smart undercutting is now enabled.")
		else
			self:Print("Smart undercutting is now disabled.")
		end
	
	-- No data fallback
	elseif( cmd == "fallback" and arg ) then
		local amount, link = string.split(" ", arg, 2)
		amount = self:DeformatMoney(amount)
		
		if( not amount ) then
			self:Print("Invalid money format given, should be #g for gold, #s for silver, #c for copper, or 5g2s for 5 gold, 2 silver.")
			return
		end
		
		-- Set it globally as a default
		if( not link ) then
			QuickAuctionsDB.fallback = self:DeformatMoney(arg) or QuickAuctionsDB.fallback
			self:Print(string.format("Set fallback to %s", self:FormatTextMoney(QuickAuctionsDB.fallback)))
			return
		end
		
		-- Set it for this specific item
		local name = GetItemInfo(link)
		if( not name ) then
			self:Print("Invalid item link given.")
			return
		end

		if( amount <= 0 ) then
			QuickAuctionsDB.specialFallback[name] = nil
			self:Print(string.format("Removed fallback buyout on %s.", link))
			return
		end
		
		QuickAuctionsDB.specialFallback[name] = amount or QuickAuctionsDB.specialFallback[name]
		self:Print(string.format("Set fallback for %s to %s.", link, self:FormatTextMoney(QuickAuctionsDB.specialFallback[name])))
	
	-- Post threshold
	elseif( cmd == "threshold" and arg ) then
		local amount, link = string.split(" ", arg, 2)
		amount = self:DeformatMoney(amount)

		if( not amount ) then
			self:Print("Invalid money format given, should be #g for gold, #s for silver, #c for copper, or 5g2s for 5 gold, 2 silver.")
			return
		end
		
		-- Set it globally as a default
		if( not link ) then
			QuickAuctionsDB.threshold = amount
			self:Print(string.format("Set default threshold to %s", self:FormatTextMoney(QuickAuctionsDB.threshold)))
			return
		end
		
		-- Set it for this specific item
		local name, link = GetItemInfo(link)
		if( not name ) then
			self:Print("Invalid item link given.")
			return
		end

		if( amount <= 0 ) then
			QuickAuctionsDB.specialThresh[name] = nil
			self:Print(string.format("Removed threshold on %s.", link))
			return
		end
		
		QuickAuctionsDB.specialThresh[name] = amount or QuickAuctionsDB.specialThresh[name]
		self:Print(string.format("Set threshold for %s to %s.", link, self:FormatTextMoney(QuickAuctionsDB.specialThresh[name])))

	-- Post cap
	elseif( cmd == "cap" and arg ) then
		local amount, link = string.split(" ", arg, 2)
		amount = tonumber(amount)
		if( not amount ) then
			self:Print("Invalid cap entered, must be a number.")
			return
		end
		
		if( not link ) then
			QuickAuctionsDB.postCap = tonumber(amount)
			self:Print(string.format("Set maximum number of the same auction to %d.", QuickAuctionsDB.postCap))
			return
		end
		
		local name, link = GetItemInfo(link)
		if( not name ) then
			self:Print("Invalid item link given.")
			return
		end

		if( amount <= 0 ) then
			QuickAuctionsDB.specialCap[name] = nil
			self:Print(string.format("Removed specific cap on %s.", link))
			return
		end
		
		QuickAuctionsDB.specialCap[name] = amount
		self:Print(string.format("Only keeping up to %d of %s up in the auction house at the same time.", amount, link))
	
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
			self:Print("Invalid item link given.")
			return
		-- If the item can stack, and they didn't provide how much we should stack it in, then error
		elseif( stackCount > 1 and not quantity or quantity <= 0 ) then
			self:Print(string.format("The item %s can stack up to %d, you must set the quantity that it should post them in.", link, stackCount))
			return
		
		-- Make sure they didn't give a bad stack count
		elseif( quantity and quantity > stackCount ) then
			self:Print(string.format("The item %s can only stack up to %d, you provided %d so set it to %d instead.", link, stackCount, quantity, quantity))
			quantity = stackCount
		end
		
		QuickAuctionsDB.itemList[name] = quantity or true
		if( quantity ) then
			self:Print(string.format("Now managing %s in Quick Auctions! Will post auctions with %s x %d", link, link, quantity))
		else
			self:Print(string.format("Now managing the item %s in Quick Auctions!", link))
		end
	
	-- Remove an item from the manage list
	elseif( cmd == "removeitem" and arg ) then
		if( not arg or not GetItemInfo(arg) ) then
			self:Print("Invalid item link given.")
			return
		end
		
		QuickAuctionsDB.itemList[(GetItemInfo(arg))] = nil
		self:Print(string.format("Removed %s from the managed auctions list.", string.trim(arg)))
	
	-- Toggling entire categories
	elseif( cmd == "toggle" and arg ) then
		arg = string.lower(arg)
		local type, textType, stackCheck
		if( arg == "gems" ) then
			type = "Gem"	
			textType = "cut gems"
			stackCheck = 1
		elseif( arg == "uncut" ) then
			type = "Gem"
			textType = "uncut gems"
			stackCheck = 20
		elseif( arg == "glyphs" ) then
			type = "Glyph"
			textType = "glyphs"
			stackCheck = 20
		end
		
		if( not type ) then
			self:Print("Invalid item type toggle entered.")
			return
		end
		
		if( not QuickAuctionsDB.itemTypes[type] ) then
			QuickAuctionsDB.itemTypes[type] = stackCheck
			self:Print(string.format("Now posting all %s.", textType))
		else
			QuickAuctionsDB.itemTypes[type] = nil
			self:Print(string.format("No longer posting all %s.", textType))
		end

	-- Post time
	elseif( cmd == "time" and arg ) then
		local time = tonumber(arg) or 12
		if( time ~= 12 and time ~= 24 and time ~= 48 ) then
			time = 12
		end
		
		AHTime = time * 60
		self:Print(string.format("Set auction time to %d hours.", time))
	
	-- Add to whitelist
	elseif( cmd == "add" and arg ) then
		QuickAuctionsDB.whitelist[arg] = true
		self:Print(string.format("Added %s to the whitelist.", arg))

	-- Remove from whitelist
	elseif( cmd == "remove" and arg ) then
		QuickAuctionsDB.whitelist[arg] = nil
		self:Print(string.format("Removed %s from whitelist.", arg))
	
	-- Post uncut gems
	elseif( cmd == "uncut" ) then
		QuickAuctionsDB.uncut = not QuickAuctionsDB.uncut
		
		if( QuickAuctionsDB.uncut ) then
			self:Print("Now posting uncut metas and gems.")
		else
			self:Print("No longer posting uncut metas and gems.")
		end
	
	-- Smart cancelling
	elseif( cmd == "cancel" ) then
		QuickAuctionsDB.smartCancel = not QuickAuctionsDB.smartCancel
		
		if( QuickAuctionsDB.smartCancel ) then
			self:Print("Only cancelling if the lowest price isn't below the threshold.")
		else
			self:Print("Always cancelling if someone undercuts us.")
		end
	
	-- Enables asshole mode! Automatically scans every 60 seconds, and posts every 30 seconds
	elseif( cmd == "super" ) then
		if( self.superFrame ) then
			if( self.superFrame:IsVisible() ) then
				self:Print("Disabled super auctioning!")
				self.superFrame:Hide()
			else
				self:Print("Enabled super auctioning!")
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
					ChatFrame1:AddMessage(string.format("[%s] Scan running...", self.scansRan))
				end
			end
		end)
		
		self:Print("Enabled super auctioning!")
	else
		self:Print("Slash commands")
		self:Echo("/qa undercut <money> <link> - How much to undercut people by.")
		self:Echo("/qa smartcut - Toggles smart undercutting (Going from 1.9g -> 1g first instead of 1.9g - undercut amount.")
		self:Echo("/qa cap <amount> <link> - Only allow <amount> of the same kind of auction to be up at the same time.")
		self:Echo("/qa fallback <money> <link> - How much money to default to if nobody else has an auction up.")
		self:Echo("/qa threshold <money> <link> - Don't post any auctions that would go below this amount.")
		self:Echo("/qa time <12/24/48> - Amount of hours to put auctions up for, only works for the current sesson.")
		self:Echo("/qa cancel - Disables undercutting if the lowest price falls below the the threshold.")
		self:Echo("/qa add <name> - Adds a name to the whitelist to not undercut.")
		self:Echo("/qa remove <name> - Removes a name from the whitelist.")
		self:Echo("/qa additem <link> <quantity> - Adds an item to the list of things that should be managed, *IF* the item can stack you must provide a quantity to post it in.")
		self:Echo("/qa removeitem <link> - Removes an item from the managed list.")
		self:Echo("/qa toggle <gems/uncut/glyphs> - Lets you toggle entire categories of items: All cut gems, all uncut gems, and all glyphs. These will always be put onto the AH as the single item, if you want to override it to post multiple then use the additem command.")
		self:Echo("For undercut, fallback, threshold and cap, if a link is provided it's set for the specific item, if none is then it's set globally as a default.")
		self:Echo("<money> format is \"#g\" for gold \"#s\" for silver and \"#c\" for copper, so \"5g2s5c\" will be 5 gold, 2 silver, 5 copper.")
	end
end
