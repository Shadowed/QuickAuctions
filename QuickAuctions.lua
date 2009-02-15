QA = {}

local money, defaults, playerName
local totalPostsSet = 0
local activeAuctions, auctionData, postList, auctionPostQueue, tempList, itemQuantities = {}, {}, {}, {}, {}, {}, {}
local currentQuery = {list = {}, total = 0}
local validTypes = {["uncut"] = "uncut gems", ["gems"] = "cut gems", ["glyphs"] = "glyphs", ["enchants"] = "enchanting materials"}
local typeInfo = {["Gem1"] = "gems", ["Gem20"] = "uncut", ["Glyph20"] = "glyphs", ["Enchanting20"] = "enchants"}

local L = QuickAuctionsLocals

-- Addon loaded
function QA:OnInitialize()
	-- Default things
	defaults = {
		smartUndercut = true,
		smartCancel = true,
		logging = false,
		bidpercent = 1.0,
		auctionTime = 12 * 60,
		itemTypes = {},
		itemList = {},
		whitelist = {},
		undercut = {default = 10000},
		threshold = {default = 500000},
		fallback = {default = 200000},
		postCap = {default = 2},
		categoryToggle = {},
		logs = {},
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
	QA.currentQuery = currentQuery
	
	-- DB version
	QuickAuctionsDB.revision = tonumber(string.match("$Revision$", "(%d+)") or 1)
	
	playerName = UnitName("player")
end

-- AH loaded
function QA:AHInitialize()
	-- Hook the query function so we know what we last sent a search on
	local orig_QueryAuctionItems = QueryAuctionItems
	QueryAuctionItems = function(name, minLevel, maxLevel, invTypeIndex, classIndex, subClassIndex, page, isUsable, qualityIndex, getAll, ...)
		-- So AH browsing mods will show the status correctly on longer scans
		if( CanSendAuctionQuery() and currentQuery.running ) then
			AuctionFrameBrowse.page = page
		end
		
		return orig_QueryAuctionItems(name, minLevel, maxLevel, invTypeIndex, classIndex, subClassIndex, page, isUsable, qualityIndex, getAll, ...)
	end
	
	-- Little hooky buttons
	self:CreateButtons()
	
	-- Hook chat to block auction post/cancels, and also let us know when we're done posting
	local orig_ChatFrame_SystemEventHandler = ChatFrame_SystemEventHandler
	ChatFrame_SystemEventHandler = function(self, event, msg)
		if( msg == ERR_AUCTION_REMOVED and QA.scanButton.totalCancels and QA.scanButton.totalCancels > 0 ) then
			QA.scanButton.haveCancelled = QA.scanButton.haveCancelled + 1
			QA.scanButton:SetFormattedText(L["%d/%d items"], QA.scanButton.haveCancelled, QA.scanButton.totalCancels)
			
			if( QA.scanButton.haveCancelled >= QA.scanButton.totalCancels ) then
				QA.scanButton.totalCancels = 0
				QA.scanButton.haveCanceled = 0
				
				QA:Print("Done cancelling auctions.")
				QA.scanButton:SetText(L["Scan Items"])
				QA.scanButton:Enable()
			end
			return true

		elseif( msg == ERR_AUCTION_STARTED and QA.postButton.totalPosts and QA.postButton.totalPosts > 0 ) then
			QA.postButton.havePosted = QA.postButton.havePosted + 1
			totalPostsSet = totalPostsSet - 1
			
			if( totalPostsSet <= 0 ) then
				QA:QueueSet()
			end
			
			if( QA.postButton.havePosted >= QA.postButton.totalPosts ) then
				QA.postButton.totalPosts = 0
				QA.postButton.havePosted = 0
				
				QA:Print("Done posting auctions.")

				QA.postButton:SetText(L["Post Items"])
				QA.postButton:Enable()
			else
				-- This one went throughdo next
				if( totalPostsSet > 0 ) then
					QA:PostQueuedAuction()
				end
				
				QA.postButton:SetFormattedText(L["%d/%d items"], QA.postButton.havePosted, QA.postButton.totalPosts)
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

-- AUCTION QUERYING
local timeElapsed = 0
local function checkQueryStatus(self, elapsed)
	timeElapsed = timeElapsed + elapsed
	
	if( timeElapsed >= 0.15 ) then
		timeElapsed = 0
		
		-- We have a query queued, and we can send it
		if( currentQuery.queued and CanSendAuctionQuery() ) then
			self:SetScript("OnUpdate", nil)
			QA:SendQuery(true)
		end
	end
end

-- Simply stops it from scanning when it sees this
function QA:ForceQueryStop()
	if( currentQuery.running ) then
		currentQuery.forceStop = true
	end
end

-- Send the actual query
function QA:SendQuery(skipCheck)
	-- We can't send it yet, 
	if( not skipCheck and not CanSendAuctionQuery() ) then
		currentQuery.queued = true
		self.frame:SetScript("OnUpdate", checkQueryStatus)
		return
	end
			
	currentQuery.queued = nil
	QueryAuctionItems(currentQuery.filter, nil, nil, 0, currentQuery.classIndex, currentQuery.subClassIndex, currentQuery.page, 0, 0)
end

-- Add an item that we will be looking for
function QA:AddQueryFilter(name)
	for _, itemName in pairs(currentQuery.list) do
		if( itemName == name ) then
			return false
		end
	end
	
	table.insert(currentQuery.list, name)
	return true
end

-- Sets up QA to start querying for this filter/indexes
function QA:SetupAuctionQuery(scanType, showProgress, filter, page, classIndex, subClassIndex)
	-- Reset auction data
	for _, data in pairs(auctionData) do data.owner = nil data.totalFound = 0 data.playerBouyout = nil end
	
	currentQuery.running = true
	currentQuery.page = page
	currentQuery.scanType = scanType
	currentQuery.classIndex = classIndex
	currentQuery.subClassIndex = subClassIndex
	currentQuery.showProgress = showProgress
	currentQuery.filter = filter
	currentQuery.retries = 0

	self:SendQuery()
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

function QA:ScanAuctions()
	for i=1, (GetNumAuctionItems("owner")) do
		local name = GetAuctionItemInfo("owner", i)
		local itemLink = GetAuctionItemLink("owner", i)
		
		if( itemLink and self:IsValidItem(itemLink) and select(13, GetAuctionItemInfo("owner", i)) == 0 ) then
			self:AddQueryFilter(name)
		end
	end
	
	self:StartScan("scan")
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
	
	-- If we can post 4, we have 1 valid stack, we need to do 3 splits, if we have 4 to post and 0 valid stacks, then we need to do all 4 splits
	local newStacks = canPost - validStacks

	self:Log("Going to be splitting %s into %d stacks of %d each, we already have %d valid stacks and can post %d, %d of the item in our inventory, will cap in %d posts, and have %d actives.", name, newStacks, quantity, validStacks, canPost, GetItemCount(link), leftToCap, (activeAuctions[name] or 0))
		
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

function QA:CheckActiveAuctions()
	for k in pairs(activeAuctions) do activeAuctions[k] = nil end
	for i=1, (GetNumAuctionItems("owner")) do
		local name, _, _, _, _, _, _, _, _, _, _, _, wasSold = GetAuctionItemInfo("owner", i)   
		if( wasSold == 0 ) then
			activeAuctions[name] = (activeAuctions[name] or 0) + 1
		end
	end
end

-- Prepare to post auctions
function QA:PostAuctions()
	-- Reset data
	for i=#(postList), 1, -1 do table.remove(postList, i) end
	
	-- Figure out how many of this is already posted
	self:CheckActiveAuctions()
	
	-- Scan inventory for posting
	for bag=0, 4 do
		for slot=1, GetContainerNumSlots(bag) do
			local link = self:GetSafeLink(GetContainerItemLink(bag, slot))
			if( link ) then
				local name, _, _, _, _, _, _, stackCount = GetItemInfo(link)
				local itemCategory = self:GetItemCategory(link)
				local postCap = QuickAuctionsDB.postCap[name] or QuickAuctionsDB.postCap[itemCategory] or QuickAuctionsDB.postCap.default
				
				-- Make sure we aren't already at the post cap, to reduce the item scans needed
				if( self:IsValidItem(link) and ( not activeAuctions[name] or activeAuctions[name] < postCap ) ) then
					local added = self:AddQueryFilter(name)
					if( added ) then
						table.insert(postList, link)
					end
				end
			end
		end
	end
		
	-- Start us up!
	self:StartScan("post")
end

-- Start scanning the items we will be posting
function QA:StartScan(type)
	if( #(currentQuery.list) == 0 ) then
		return
	end
	
	-- Setup scan info blah blah
	self.scanButton.totalScanned = 0
	self.scanButton.totalItems = #(currentQuery.list)
	self.scanButton:SetFormattedText(L["%d/%d items"], 0, self.scanButton.totalItems)
	self.scanButton:Disable()
	
	-- Set it up to start scanning this item
	self:SetupAuctionQuery(type, true, currentQuery.list[1], 0, 0, 0)
end

function QA:StartCategoryScan(classIndex, subClassIndex, type)
	self.scanButton:Disable()
	self:SetupAuctionQuery(type, nil, "", 0, classIndex, subClassIndex)
end

function QA:PostQueuedAuction()
	if( #(auctionPostQueue) == 0 ) then
		self:Log("Nothing else to queue.")
		return
	end
	
	local bag = table.remove(auctionPostQueue, 1)
	local slot = table.remove(auctionPostQueue, 1)
	local minBid = table.remove(auctionPostQueue, 1)
	local buyout = table.remove(auctionPostQueue, 1)
	
	PickupContainerItem(bag, slot)
	ClickAuctionSellItemButton()
	StartAuction(minBid, buyout, QuickAuctionsDB.auctionTime)
end

function QA:PostItem(link)
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
				money = money - CalculateAuctionDeposit(QuickAuctionsDB.auctionTime)
				if( money >= 0 ) then
					table.insert(auctionPostQueue, bag)
					table.insert(auctionPostQueue, slot)
					table.insert(auctionPostQueue, minBid * quantity)
					table.insert(auctionPostQueue, buyout * quantity)
					
					self:Log("Queued for auction in bag %d/slot %d.", bag, slot)
					
					totalPostsSet = totalPostsSet + 1
				else
					for i=#(auctionPostQueue), 1, -1 do table.remove(auctionPostQueue, i) end
					
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
	self.postButton:SetFormattedText(L["%d/%d items"], self.postButton.havePosted, self.postButton.totalPosts)
	self.postButton:Disable()

	-- Now actually post everything
	self:PostQueuedAuction()
end

function QA:PostItems()
	self.scanButton:Enable()
	self.scanButton:SetText(L["Scan Items"])
	self.postButton.totalPosts = 0
	self.postButton.havePosted = 0

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
	
	self.postButton:SetFormattedText(L["%d/%d items"], self.postButton.havePosted, self.postButton.totalPosts)
	self.postButton:Disable()

	-- Save money so we can check if we have enough to post
	money = GetMoney()
	
	-- Post a group of items
	self:QueueSet()
end

-- Check if any of our posted auctions were undercut by someone, using the data we got earlier
function QA:CheckItems()
	for k in pairs(tempList) do tempList[k] = nil end
	
	self.scanButton:Disable()
	self.scanButton:SetText(L["Scan Items"])
	
	self.scanButton.haveCancelled = 0
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
						self.scanButton.totalCancels = self.scanButton.totalCancels + 1
						self.scanButton:SetFormattedText(L["%d/%d items"], self.scanButton.haveCancelled, QA.scanButton.totalCancels)

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
local scanDelay = 0.50
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

function QA:FinishedScanning()
	self.scanButton:SetText(L["Scan Items"])
	self.scanButton:Enable()

	currentQuery.running = nil
	currentQuery.forceStop = nil
	currentQuery.showProgress = nil

	-- Reset item queue
	for i=#(currentQuery.list), 1, -1 do table.remove(currentQuery.list, i) end

	-- Call trigger function
	if( currentQuery.scanType == "scan" ) then
		self:CheckItems()
	elseif( currentQuery.scanType == "post" ) then
		self:PostItems()
	elseif( currentQuery.scanType == "summary" ) then
		self.Summary:Finished()
	end
end

-- Time to scan auctions!
function QA:ScanAuctionList()
	-- Forced to stop next list, so just finish now
	if( currentQuery.forceStop ) then
		self:FinishedScanning()
		return
	elseif( not currentQuery.running ) then
		return
	end
		
	local shown, total = GetNumAuctionItems("list")
		
	-- Check for bad data quickly
	if( currentQuery.retries <= 5 ) then
		for i=1, shown do
			if( not GetAuctionItemInfo("list", i) ) then
				currentQuery.retries = currentQuery.retries + 1
				--scanDelay = scanDelay + 0.10

				self:SendQuery()
				return
			end
		end
	end

	-- Find the lowest auction (if any) out of this list
	for i=1, shown do
		local name, texture, quantity, _, _, _, minBid, _, buyoutPrice, _, _, owner = GetAuctionItemInfo("list", i)     
		
		-- If we get to this point, we've already hit the retry limit so just set a blank owner
		owner = owner or ""
		
		if( not auctionData[name] ) then
			auctionData[name] = {buyout = 0, totalFound = 0, minBid = 0, link = self:GetSafeLink(GetAuctionItemLink("list", i))}
		end

		-- Increment total for this loop
		auctionData[name].totalFound = auctionData[name].totalFound + quantity

		-- Turn it into price per an item
		buyoutPrice = buyoutPrice / quantity
		minBid = minBid / quantity
				
		-- Only pull good owner data, if they are the lowest
		if( ( buyoutPrice < auctionData[name].buyout or not auctionData[name].owner ) and buyoutPrice > 0 ) then
			-- Player owns it, so list that as the lowest in another field for summary
			if( owner == playerName ) then
				auctionData[name].playerBuyout = buyoutPrice
			else
				auctionData[name].minBid = minBid
				auctionData[name].buyout = buyoutPrice
				auctionData[name].owner = owner
			end
		end
	end

	-- Reset our retries and scan delay
	--scanDelay = 0.50
	currentQuery.retries = 0

	-- If it's an active scan, and we have shown as much as possible, then scan the next page
	if( shown == NUM_AUCTION_ITEMS_PER_PAGE ) then
		currentQuery.page = currentQuery.page + 1
		self:SendQuery()
		return
	end
		
	-- Remove the filter we just looked at
	for i=#(currentQuery.list), 1, -1 do
		if( currentQuery.list[i] == currentQuery.filter ) then
			table.remove(currentQuery.list, i)
			break
		end
	end
	
	-- Figure out what next to scan (If anything)
	local filter = currentQuery.list[1]
	
	-- New request, so time to update the counter
	if( filter and currentQuery.showProgress ) then
		self.scanButton.totalScanned = self.scanButton.totalScanned + 1
		self.scanButton:SetFormattedText(L["%d/%d items"], self.scanButton.totalScanned, self.scanButton.totalItems)
	end
	

	-- We don't have anything else to search, but we do have something queued so wait for that first
	if( not filter and currentQuery.queued ) then
		return
	-- Nothing else to search, done!
	elseif( not filter or currentQuery.forceStop ) then
		self:FinishedScanning()
		return
	end
	
	-- Send off onto the next page
	currentQuery.page = 0
	currentQuery.filter = filter
	
	self:SendQuery()
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

-- Create AH buttons, hidden down here so I don't have to scroll through this, given I'll never modify it basically
function QA:CreateButtons()
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
		
		QuickAuctionsDB.auctionTime = time * 60
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
	
	-- Cancel all player auctions
	elseif( cmd == "cancelall" ) then
		self.scanButton:Disable()
		self.scanButton:SetText(L["Scan Items"])

		self.scanButton.haveCancelled = 0
		self.scanButton.totalCancels = 0

		for i=1, (GetNumAuctionItems("owner")) do
			local name, _, _, _, _, _, _, _, _, _, _, _, wasSold = GetAuctionItemInfo("owner", i)   
			if( wasSold == 0 ) then
				self.scanButton.totalCancels = self.scanButton.totalCancels + 1
				CancelAuction(i)
			end
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
		self:Echo(L["/qa cancelall - Cancel all of your auctions. REGARDLESS of if you were undercut or not."])
		self:Echo(L["/qa summary - Toggles the summary frame."])
	end
end
