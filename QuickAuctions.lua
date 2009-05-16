QA = {}

local money, defaults, playerName
local totalPostsSet = 0
local activeAuctions, auctionData, postList, auctionPostQueue, tempList, itemQuantities = {}, {}, {}, {}, {}, {}, {}
local currentQuery = {list = {}, total = 0}
local validTypes = {["uncut"] = "uncut gems", ["gems"] = "cut gems", ["glyphs"] = "glyphs", ["enchants"] = "enchanting materials", ["scrolls"] = "item enchants"}
local typeInfo = {["Gem1"] = "gems", ["Gem20"] = "uncut", ["Glyph20"] = "glyphs", ["Enchanting20"] = "enchants", ["Item Enhancement5"] = "scrolls"}

local L = QuickAuctionsLocals

-- Addon loaded
function QA:OnInitialize()
	-- Default things
	defaults = {
		smartUndercut = true,
		smartCancel = true,
		saveCraft = false,
		bidpercent = 1.0,
		pricepercent = 10,
		itemTypes = {},
		itemList = {},
		whitelist = {},
		groups = {},
		postTime = {default = 12},
		undercut = {default = 10000},
		threshold = {default = 500000},
		fallback = {default = 200000},
		postCap = {default = 2},
		craftQueue = {},
		summaryItems = {},
		categoryToggle = {},
		hideCategories = {},
		crafts = {},
		alts = {},
		alertedThreshold = {},
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
	
	-- Got to let the "module" access these
	QA.auctionData = auctionData
	QA.activeAuctions = activeAuctions
	QA.currentQuery = currentQuery
	
	-- DB version
	QuickAuctionsDB.revision = tonumber(string.match("$Revision$", "(%d+)") or 1)

	playerName = UnitName("player")
end

-- Quick starter function for groups
function QA:LoadGems()
	local list = {
		["scarlet"] = {39996, 39999, 39997, 40001, 40002, 40003, 39998, 40000},
		["autumn"] = {40012, 40016, 40017, 40014, 40013, 40015},
		["monarch"] = {40058, 40039, 40043, 40046, 40050, 40054, 40038, 40041, 40057, 40044, 40037, 40045, 40047, 40048, 40053, 40051, 40059, 40040, 40056, 40055, 40049, 40052},
		["forest"] = {40094, 40089, 40105, 40091, 40104, 40086, 40100, 40095, 40103, 40098, 40092, 40106, 40099, 40090, 40096, 40101, 40085, 40102, 40088},
		["earthsiege"] = {41380, 41389, 41395, 41396, 41401, 41385, 41381, 41397, 41398, 41382},
		["skyflare"] = {41285, 41307, 41377, 41333, 41335, 41378, 41379, 41376, 41339, 41400, 41375},
	}
	
	for name, items in pairs(list) do
		QuickAuctionsDB.groups[name] = {}
		local added = {}
		for _, itemid in pairs(items) do
			local itemid = string.format("item:%d", itemid)
			QuickAuctionsDB.groups[name][itemid] = true
			table.insert(added, (select(2, GetItemInfo(itemid))) or itemid)
		end
		
		self:Echo(string.format("Created group %s", name))
		self:Echo(table.concat(added, " "))
	end
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
	
	-- Hook auction OnHide to interrupt scans if we have to
	AuctionFrame:HookScript("OnHide", function(self)
		if( currentQuery.running ) then
			QA:Print(L["Stopped scanning due to the Auction House being closed."])
		elseif( QA.postButton.totalPosts and QA.postButton.totalPosts > 0 ) then
			QA.postButton.totalPosts = 0
			QA.postButton.havePosted = 0
			QA.postButton:SetText(L["Post Items"])
			QA.postButton:Enable()
			QA:Print(L["Stopped posting due to the Auction House being closed."])
			
			for i=#(postList), 1, -1 do table.remove(postList, i) end
		end

		QA:ForceQueryStop()
	end)
	
	-- Little hooky buttons
	self:CreateButtons()
	
	-- Hook chat to block auction post/cancels, and also let us know when we're done posting
	local orig_ChatFrame_SystemEventHandler = ChatFrame_SystemEventHandler
	ChatFrame_SystemEventHandler = function(self, event, msg)
		if( msg == ERR_AUCTION_REMOVED and QA.scanButton.totalCancels and QA.scanButton.totalCancels > 0 ) then
			QA.scanButton.haveCancelled = QA.scanButton.haveCancelled + 1
			QA.scanButton:SetFormattedText(L["%d/%d items"], QA.scanButton.haveCancelled, QA.scanButton.totalCancels)
			
			if( QA.scanButton.haveCancelled >= QA.scanButton.totalCancels ) then
				QA:Print(string.format(L["Done cancelling %d auctions."], QA.scanButton.totalCancels))
				QA.scanButton:SetText(L["Cancel Items"])
				QA.scanButton:Enable()

				QA.scanButton.totalCancels = 0
				QA.scanButton.haveCanceled = 0
			end
			return true

		elseif( msg == ERR_AUCTION_STARTED and QA.postButton.totalPosts and QA.postButton.totalPosts > 0 ) then
			QA.postButton.havePosted = QA.postButton.havePosted + 1
			totalPostsSet = totalPostsSet - 1
			
			if( totalPostsSet <= 0 ) then
				QA:QueueSet()
			end
			
			if( QA.postButton.havePosted >= QA.postButton.totalPosts ) then
				QA:Print(string.format(L["Done posting %d auctions."], QA.postButton.totalPosts))

				QA.postButton:SetText(L["Post Items"])
				QA.postButton:Enable()

				QA.postButton.totalPosts = 0
				QA.postButton.havePosted = 0
			else
				-- This one went through do next
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
	currentQuery.running = true
	currentQuery.page = page
	currentQuery.scanType = scanType
	currentQuery.classIndex = classIndex
	currentQuery.subClassIndex = subClassIndex
	currentQuery.showProgress = showProgress
	currentQuery.filter = filter
	currentQuery.retries = 0

	if( scanType == "summary" ) then
		self:FlagDataReset()
	else
		self:ResetAuctionData()
	end
	
	self:SendQuery()
end

function QA:IsValidItem(link)
	local name, _, _, _, _, itemType, subType, stackCount = GetItemInfo(link)
	
	-- Part of a group
	for group, items in pairs(QuickAuctionsDB.groups) do
		if( items[link] ) then
			return true
		end
	end
	
	-- Managed manually singly, or managed through a predefined set
	if( QuickAuctionsDB.itemList[link] or QuickAuctionsDB.itemTypes[itemType .. stackCount] or QuickAuctionsDB.itemTypes[subType .. stackCount] ) then
		return true
	end
end

function QA:PartOfCategory(link, category)
	if( not link ) then return false end
	local name, _, _, _, _, itemType, _, stackCount = GetItemInfo(link)
	
	-- Part of a group
	if( QuickAuctionsDB.groups[category] and QuickAuctionsDB.groups[category][link] ) then
		return true
	end
	
	-- Nope, check if it's under a default group
	return typeInfo[itemType .. stackCount] == category
end

function QA:GetConfigValue(link, key)
	if( not link ) then return "" end
	-- Link settings overrides everything
	if( QuickAuctionsDB[key][link] ) then 
		return QuickAuctionsDB[key][link]
	end
	
	local name, _, _, _, _, itemType, _, stackCount = GetItemInfo(link)
	
	-- Group settings overrides everything but links
	for group, items in pairs(QuickAuctionsDB.groups) do
		if( items[link] and QuickAuctionsDB[key][group] ) then
			return QuickAuctionsDB[key][group]
		end
	end
	
	-- Item group settings overrides everything but groups/links
	local type = typeInfo[itemType .. stackCount]
	if( type and QuickAuctionsDB[key][type] ) then
		return QuickAuctionsDB[key][type]
	end

	-- And default is the last resort	
	return QuickAuctionsDB[key].default
end

function QA:GetItemCategory(link)
	if( not link ) then return "" end
	local name, _, _, _, _, itemType, _, stackCount = GetItemInfo(link)
	
	-- Check if it's a group
	for group, items in pairs(QuickAuctionsDB.groups) do
		if( items[link] ) then
			return group
		end
	end
	
	-- Nope, check if it's under a default group
	return typeInfo[itemType .. stackCount]
end

function QA:GetSafeLink(link)
	if( not link ) then return nil end
	local link = string.match(link, "|H(.-):([-0-9]+):([0-9]+)|h")
	if( not link ) then
		return nil
	end
	
	-- Reduce the size of the link if it has no important data in it
	return string.gsub(link, ":0:0:0:0:0:0", "")
end

function QA:ScanAuctions()
	for i=1, (GetNumAuctionItems("owner")) do
		local name = GetAuctionItemInfo("owner", i)
		local itemLink = self:GetSafeLink(GetAuctionItemLink("owner", i))
		
		if( itemLink and self:IsValidItem(itemLink) and select(13, GetAuctionItemInfo("owner", i)) == 0 ) then
			self:AddQueryFilter(name)
		end
	end
	
	self:StartScan("scan")
end

-- Finished splitting this queue
function QA:FinishedSplitting()
	self:PostItem(table.remove(postList, 1))
end

-- Queue a set for splitting... or post it if it can't be split
function QA:QueueSet()
	if( #(postList) == 0 ) then
		return
	end

	local link = postList[1]
	local name, _, _, _, _, itemType, _, stackCount = GetItemInfo(link)
	local quantity = type(QuickAuctionsDB.itemList[link]) == "number" and QuickAuctionsDB.itemList[link] or 1
		
	-- This item cannot stack, so we don't need to bother with splitting and can post it all
	if( stackCount == 1 ) then
		self:PostItem(table.remove(postList, 1))
		return
	end
	
	-- If post cap is 20, we have 4 on the AH, then we can post 16 more before hitting cap
	local leftToCap = self:GetConfigValue(link, "postCap")
	-- If we have 4 of the item, we post it in stacks of 1, we can can post 4
	local canPost = math.floor(GetItemCount(link) / quantity)
	
	-- Subtract how many we have on this tier
	local lowestBuyout, lowestBid, lowestOwner, isWhitelist, isPlayer = self:GetLowestAuction(link)
	if( isPlayer or isWhitelist ) then
		leftToCap = leftToCap - self:GetItemQuantity(link, lowestBuyout, lowestBid)
	end
		
	-- Nothing to post, or we can't post anything
	if( leftToCap == 0 or canPost == 0 ) then
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
		self:PostItem(table.remove(postList, 1))
		return
	end
	
	-- Nothing queued, meaning we have nothing to post for this item
	if( canPost == 0 ) then
		table.remove(postList, 1)
		
		self:Echo(string.format(L["You only have %d of %s, and posting it in stacks of %d, not posting."], GetItemCount(link), link, quantity))
		self:QueueSet()
		return
	end
	
	-- And here we go!
	self:StartSplitting(canPost, link, quantity)
end

function QA:CheckActiveAuctions()
	for k in pairs(activeAuctions) do activeAuctions[k] = nil end
	for i=1, (GetNumAuctionItems("owner")) do
		if( select(13, GetAuctionItemInfo("owner", i)) ) then
			local link = self:GetSafeLink(GetAuctionItemLink("owner", i))
			activeAuctions[link] = (activeAuctions[link] or 0) + 1
		end
	end
end

local function sortByStack(a, b)
	local aStack = select(8, GetItemInfo(a)) or 20
	local bStack = select(8, GetItemInfo(b)) or 20
	
	return aStack < bStack
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
				
				-- Make sure we aren't already at the post cap, to reduce the item scans needed
				if( self:IsValidItem(link) ) then
					local added = self:AddQueryFilter(name)
					if( added ) then
						table.insert(postList, link)
					end
				end
			end
		end
	end
	
	-- Sort the post list so that non stackable items are first
	table.sort(postList, sortByStack)
		
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
		return
	end
	
	local bag = table.remove(auctionPostQueue, 1)
	local slot = table.remove(auctionPostQueue, 1)
	local bid = table.remove(auctionPostQueue, 1)
	local buyout = table.remove(auctionPostQueue, 1)
	local postTime = table.remove(auctionPostQueue, 1)
	
	PickupContainerItem(bag, slot)
	ClickAuctionSellItemButton()
	StartAuction(bid, buyout, postTime)
end

function QA:PostItem(link)
	local name = GetItemInfo(link)
	local totalPosted = 0
	local quantity = type(QuickAuctionsDB.itemList[link]) == "number" and QuickAuctionsDB.itemList[link] or 1
	local postTime = self:GetConfigValue(link, "postTime")
	local postCap = self:GetConfigValue(link, "postCap")
	local lowestBuyout, lowestBid, lowestOwner, isWhitelist, isPlayer = self:GetLowestAuction(link)
	local bid, buyout
	
	totalPostsSet = 0
	
	-- Reset the threshold alert
	QuickAuctionsDB.alertedThreshold[link] = nil
		
	-- Figure out what price we are posting at
	if( lowestOwner ) then
		buyout = lowestBuyout
		bid = lowestBid
		
		-- The lowest player is the player, so find out how many they have at this "tier" posted
		if( isPlayer or isWhitelist ) then
			totalPosted = self:GetItemQuantity(link, lowestBuyout, lowestBid)
		end
				
		-- It's not us, and it's not a white list who is lowest, so undercut them
		if( not isPlayer and not isWhitelist ) then
			buyout = buyout / 10000
						
			-- If smart undercut is on, then someone who posts an auction of 99g99s0c, it will auto undercut to 99g
			-- instead of 99g99s0c - undercutBy, also make sure the buyout is above 1g
			if( not QuickAuctionsDB.smartUndercut or buyout == math.floor(buyout) or lowestBuyout < 10000 ) then
				buyout = (buyout * 10000) - self:GetConfigValue(link, "undercut")
			else
				buyout = math.floor(buyout) * 10000
			end

			-- And now the bid!
			bid = buyout * QuickAuctionsDB.bidpercent
		end
		
		bid = math.floor(bid)
		buyout = math.floor(buyout)
		
		-- Check if they are going above out threshold
		if( QuickAuctionsDB.pricepercent > 0 ) then
			local fallback = self:GetConfigValue(link, "fallback")
			if( buyout > (fallback * QuickAuctionsDB.pricepercent) ) then
				buyout = fallback
				bid = fallback * QuickAuctionsDB.bidpercent

				self:Echo(string.format(L["%s by %s is listed at %s, but that is above the maximum price threshold of %s, posted it at %s instead."], name, lowestOwner, self:FormatTextMoney(buyout), self:FormatTextMoney(fallback * QuickAuctionsDB.pricepercent), self:FormatTextMoney(fallback)))
			end
		end		

	-- No other data available, default to our fallback for it
	else
		buyout = self:GetConfigValue(link, "fallback")
		bid = buyout * QuickAuctionsDB.bidpercent
		
		self:Echo(string.format(L["No data found for %s, using %s buyout and %s bid default."], name, self:FormatTextMoney(buyout), self:FormatTextMoney(bid)))
	end
	
	-- We're already above post cap, next set
	if( totalPosted >= postCap ) then
		self:QueueSet()	
		return
	end
		
	-- Find the item in our inventory
	for i=#(auctionPostQueue), 1, -1 do table.remove(auctionPostQueue, i) end
	for bag=0, 4 do
		for slot=1, GetContainerNumSlots(bag) do
			-- It's the correct quantity/link so can post it
			if( self:GetSafeLink(GetContainerItemLink(bag, slot)) == link and select(2, GetContainerItemInfo(bag, slot)) == quantity ) then
				totalPosted = totalPosted + 1
								
				-- Hit limit, done with this item
				if( totalPosted > postCap ) then
					break
				end

				-- Post this auction
				PickupContainerItem(bag, slot)
				ClickAuctionSellItemButton()

				-- Make sure we can post this auction, we save the money and subtract it here
				-- because we chain post before the server gives us the new money
				money = money - CalculateAuctionDeposit(postTime)
				if( money >= 0 ) then
					table.insert(auctionPostQueue, bag)
					table.insert(auctionPostQueue, slot)
					table.insert(auctionPostQueue, bid * quantity)
					table.insert(auctionPostQueue, buyout * quantity)
					table.insert(auctionPostQueue, postTime * 60)
					
					totalPostsSet = totalPostsSet + 1
				else
					for i=#(auctionPostQueue), 1, -1 do table.remove(auctionPostQueue, i) end
					
					self.postButton:SetText(L["Post Items"])
					self.postButton:Enable()
					self:Print(L["Cannot post remaining auctions, you do not have enough money."])

					ClickAuctionSellItemButton()
					ClearCursor()
					return
				end

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
	self.scanButton:SetText(L["Cancel Items"])
	self.postButton.totalPosts = 0
	self.postButton.havePosted = 0
	
	-- Quick check for threshold info
	for i=#(postList), 1, -1 do
		local link = postList[i]
		local name = GetItemInfo(link)
		local threshold = self:GetConfigValue(link, "threshold")
		
		local lowestBuyout, lowestBid, lowestOwner, isWhitelist, isPlayer = self:GetLowestAuction(link)
		if( lowestBuyout and lowestBuyout <= threshold ) then
			if( not QuickAuctionsDB.alertedThreshold[link] ) then
				self:Echo(string.format(L["Not posting %s, because the buyout is %s per item and the threshold is %s"], name, self:FormatTextMoney(lowestBuyout), self:FormatTextMoney(threshold)))
				QuickAuctionsDB.alertedThreshold[link] = time()
			end
			table.remove(postList, i)
		else
			-- Figure out how many auctions we will be posting quickly
			local quantity = type(QuickAuctionsDB.itemList[link]) == "number" and QuickAuctionsDB.itemList[link] or 1
			local willPost = math.floor(GetItemCount(link) / quantity)
			local leftToCap = self:GetConfigValue(link, "postCap")
			if( isPlayer or isWhitelist ) then
				leftToCap = leftToCap - self:GetItemQuantity(link, lowestBuyout, lowestBid)
			end
			
			willPost = willPost > leftToCap and leftToCap or willPost
		
			if( willPost > 0 ) then
				self.postButton.totalPosts = self.postButton.totalPosts + willPost
			end
		end
	end

	-- Nothing to post, it's all below a threshold
	if( #(postList) == 0 or self.postButton.totalPosts == 0 ) then
		self:Print(L["Nothing to post."])
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
	
	self.scanButton:SetText(L["Cancel Items"])
	
	self.scanButton.haveCancelled = 0
	self.scanButton.totalCancels = 0
	
	for i=1, (GetNumAuctionItems("owner")) do
		local name, texture, quantity, _, _, _, bid, _, buyoutPrice, _, _, owner, wasSold = GetAuctionItemInfo("owner", i)     
		local link = self:GetSafeLink(GetAuctionItemLink("owner", i))
				
		local lowestBuyout, lowestBid, lowestOwner, isWhitelist, isPlayer = self:GetLowestAuction(link)
		if( wasSold == 0 and lowestOwner ) then
			buyoutPrice = buyoutPrice / quantity
			bid = bid / quantity
			
			local threshold = self:GetConfigValue(link, "threshold")
			local fallback = self:GetConfigValue(link, "fallback")
						
			
			-- They aren't us (The player posting), or on our whitelist so easy enough
			-- They are on our white list, but they undercut us, OR they matched us but the bid is lower
			-- The player is the only one with it on the AH and it's below the threshold
			if( ( not isPlayer and not isWhitelist ) or ( isWhitelist and ( buyoutPrice > lowestBuyout or ( buyoutPrice == lowestBuyout and lowestBid < bid ) ) ) or ( QuickAuctionsDB.smartCancel and auctionData[link].onlyPlayer and buyoutPrice < fallback ) ) then
				-- Don't cancel if the buyout is equal, or below our threshold
				if( QuickAuctionsDB.smartCancel and lowestBuyout <= threshold ) then
					if( not tempList[link] ) then
						tempList[link] = true
						self:Echo(string.format(L["Undercut on %s, by %s, buyout %s, our buyout %s (per item), threshold is %s so not cancelling."], (GetAuctionItemLink("owner", i)), lowestOwner, self:FormatTextMoney(lowestBuyout), self:FormatTextMoney(buyoutPrice), self:FormatTextMoney(threshold)))
					end
				else
					if( not tempList[link] ) then
						tempList[link] = true
						
						if( auctionData[link].onlyPlayer and buyoutPrice < fallback ) then
							self:Echo(string.format(L["You are the only one posting %s for %s buyout, but the fallback is %s (per item), cancelling so you can re-list higher."], (GetAuctionItemLink("owner", i)), self:FormatTextMoney(buyoutPrice), self:FormatTextMoney(fallback)))
						else
							self:Echo(string.format(L["Undercut on %s, by %s, buyout %s, bid %s, our buyout %s, our bid %s (per item)"], (GetAuctionItemLink("owner", i)), lowestOwner, self:FormatTextMoney(lowestBuyout), self:FormatTextMoney(lowestBid), self:FormatTextMoney(buyoutPrice), self:FormatTextMoney(bid)))
						end
					end
					
					
					self.scanButton.totalCancels = self.scanButton.totalCancels + 1
					self.scanButton:SetFormattedText(L["%d/%d items"], self.scanButton.haveCancelled, QA.scanButton.totalCancels)

					CancelAuction(i)
				end
			end
		end
	end
	
	if( self.scanButton.totalCancels == 0 ) then
		self:Print(L["Nothing to cancel."])
	end
end

-- Do a delay before scanning the auctions so it has time to load all of the owner information
local scanDelay = 1.0
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
	self.scanButton:SetText(L["Cancel Items"])
	self.scanButton:Enable()
	
	local wasForced = currentQuery.forceStop
	
	currentQuery.running = nil
	currentQuery.forceStop = nil
	currentQuery.showProgress = nil

	-- Reset item queue
	for i=#(currentQuery.list), 1, -1 do table.remove(currentQuery.list, i) end
	
	-- Stop was forced, don't trigger callbacks
	if( wasForced and currentQuery.scanType ~= "summary" ) then
		return
	end

	-- Call trigger function
	if( currentQuery.scanType == "scan" ) then
		self:CheckItems()
	elseif( currentQuery.scanType == "post" ) then
		self:PostItems()
	elseif( currentQuery.scanType == "summary" ) then
		self.Summary:Finished()
	end
end

-- Auction data management
function QA:ResetAuctionData()
	for name, data in pairs(auctionData) do
		data.quantity = 0
		data.onlyPlayer = true
		data.reset = nil
		
		for _, record in pairs(data.records) do
			record.owner = nil
			record.used = nil
			record.quantity = 0
			record.buyout = 0
			record.bid = 0
		end
	end
end

function QA:FlagDataReset()
	for name, data in pairs(auctionData) do
		data.reset = true
	end
end

-- Add a new record
function QA:AddAuctionRecord(name, link, owner, quantity, bid, buyout)
	-- No data yet, create it
	if( not auctionData[link] ) then
		auctionData[link] = {quantity = 0, link = link, name = name, onlyPlayer = true, records = {}}
	-- Flagged for reset once we see it
	elseif( auctionData[link].reset ) then
		auctionData[link].quantity = 0
		auctionData[link].onlyPlayer = true
		auctionData[link].reset = nil
		
		for _, record in pairs(auctionData[link].records) do
			record.owner = nil
			record.used = nil
			record.quantity = 0
			record.buyout = 0
			record.bid = 0
		end
	end
	
	-- Update total of this item
	auctionData[link].quantity = auctionData[link].quantity + quantity
	
	-- Don't add this data, just add the quantity if it has no buyout
	if( buyout <= 0 ) then
		return
	end

	-- Not only the player has posted this anymore :(
	local isPlayer = owner == playerName or QuickAuctionsDB.alts[owner]
	if( not isPlayer ) then
		auctionData[link].onlyPlayer = nil
	end
	
	-- Find one thats unused if we can
	buyout = buyout / quantity
	bid = bid / quantity
	
	-- Find either a record that isn't in use, or one that matches this data already we can update
	for _, record in pairs(auctionData[link].records) do
		if( not record.used or ( record.owner == owner and record.buyout == buyout and record.bid == bid ) ) then
			record.used = true
			record.buyout = buyout
			record.bid = bid
			record.owner = owner
			record.quantity = record.quantity + quantity
			record.isPlayer = isPlayer
			return
		end
	end
	
	-- Nothing available, create a new one
	table.insert(auctionData[link].records, {used = true, owner = owner, buyout = buyout, bid = bid, isPlayer = isPlayer, quantity = quantity})
end

-- Find out if we got undercut on this item
function QA:IsLowestAuction(name, buyout, bid)
	-- We don't even have data on this
	if( not auctionData[link] ) then
		return true
	end
	
	for _, record in pairs(auctionData[link].records) do
		if( record.used ) then
			-- They are on our whitelist, and they undercut us, or they matched our buyout but under bid us.
			if( QuickAuctionsDB.whitelist[record.owner] ) then
				if( record.buyout < buyout or ( record.buyout == buyout and record.bid < bid ) ) then
					return false, record.owner, record.quantity, record.buyout, record.bid
				end
			-- They are not on our whitelist, it's not us, and they either are matching or undercut us
			elseif( not record.isPlayer and record.buyout <= buyout ) then
				return false, record.owner, record.quantity, record.buyout, record.bid
			end
		end
	end
	
	return true
end

-- Searches the item data to find out how many we have on the provided item info
function QA:GetItemQuantity(link, buyout, bid)
	if( not auctionData[link] or auctionData[link].quantity == 0 ) then
		return 0
	end
	
	for _, record in pairs(auctionData[link].records) do
		if( record.used and record.isPlayer and record.buyout == buyout and record.bid == bid ) then
			return record.quantity
		end
	end
	
	return 0
end

-- Find out the lowest price for this auction
function QA:GetLowestAuction(link)
	-- No data on it
	if( not auctionData[link] or auctionData[link].quantity == 0 ) then
		return nil
	end
		
	-- Find lowest
	local buyout, bid, owner
	for _, record in pairs(auctionData[link].records) do
		if( record.used and ( not buyout or ( record.buyout < buyout or ( record.buyout <= buyout and record.bid < bid ) ) ) ) then
			buyout = record.buyout
			bid = record.bid
			owner = record.owner
		end
	end

	-- Now that we know the lowest, find out if this price "level" is a friendly person
	-- the reason we do it like this, is so if Apple posts an item at 50g, Orange posts one at 50g
	-- but you only have Apple on your white list, it'll undercut it because Orange posted it as well
	local isWhitelist, isPlayer = true, true
	for _, record in pairs(auctionData[link].records) do
		if( record.used and record.buyout == buyout ) then
			if( not record.isPlayer ) then
				if( not QuickAuctionsDB.whitelist[record.owner] ) then
					isWhitelist = nil
				end
				
				-- If the lowest we found was from the player, but someone else is matching it (and they aren't on our white list)
				-- then we swap the owner to that person
				if( owner == playerName or QuickAuctionsDB.alts[owner] ) then
					buyout = record.buyout
					bid = record.bid
					owner = record.owner
				end

				isPlayer = nil
			end
		end
	end
	
	return buyout, bid, owner, isWhitelist, isPlayer
end

-- Find out how much of an item we have total on alts
function QA:GetAltAuctionTotals(link)
	-- No data on it
	if( not auctionData[link] or auctionData[link].quantity == 0 ) then
		return 0
	end
	
	local total = 0
	for _, record in pairs(auctionData[link].records) do
		if( record.used and record.isPlayer and record.owner ~= playerName ) then
			total = total + record.quantity
		end
	end
	
	return total
end

-- Time to scan auctions!
function QA:ScanAuctionList()
	-- Forced to stop next list, so just finish now
	if( currentQuery.forceStop ) then
		self:FinishedScanning()
		return
	-- Scan not running, shouldn't be recording data
	elseif( not currentQuery.running ) then
		return
	end
		
	local shown, total = GetNumAuctionItems("list")
		
	-- Check for bad data quickly
	if( currentQuery.retries < 2 ) then
		for i=1, shown do
			local name, _, _, _, _, _, _, _, _, _, _, owner = GetAuctionItemInfo("list", i)     
			if( not name or not owner ) then
				currentQuery.retries = currentQuery.retries + 1
				
				self:SendQuery()
				return
			end
		end
	end
	
	-- Find the lowest auction (if any) out of this list
	for i=1, shown do
		local name, texture, quantity, _, _, _, minBid, _, buyoutPrice, _, _, owner = GetAuctionItemInfo("list", i)     
		self:AddAuctionRecord(name, self:GetSafeLink(GetAuctionItemLink("list", i)), (owner or ""), quantity, minBid, buyoutPrice)
	end

	-- Reset our retries and scan delay
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
	button.tooltip = L["Cancels any posted auctions that you were undercut on."]
	button:SetPoint("TOPRIGHT", AuctionFrameAuctions, "TOPRIGHT", 51, -15)
	button:SetText(L["Cancel Items"])
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
	local amount, itemID = string.split(" ", arg, 2)
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
	if( not itemID ) then
		QuickAuctionsDB[configKey].default = amount
		self:Print(string.format(defaultMsg, (isMoney and self:FormatTextMoney(amount) or amount)))
		return
	end
	
	-- Figure out what we're modifying, is it an item, group, or an item type
	local name = GetItemInfo(itemID)
	-- Item link
	if( name ) then
		name = self:GetSafeLink(itemID)
		
	-- Item type
	elseif( validTypes[itemID] ) then
		name = itemID
		itemID = validTypes[itemID]
	
	-- Group
	elseif( QuickAuctionsDB.groups[itemID] ) then
		name = itemID
		
	-- Bad item identifier
	else
		self:Print(L["Invalid item link, item type or group name passed."])
		return
	end
	
	itemID = string.trim(itemID)
	
	-- If they passed 0 then we remove the value
	if( amount <= 0 ) then
		QuickAuctionsDB[configKey][name] = nil
		self:Print(string.format(removedMsg, itemID))
		return
	end
	
	-- Set it for this item now!
	QuickAuctionsDB[configKey][name] = amount
	self:Print(string.format(setMsg, itemID, (isMoney and self:FormatTextMoney(amount) or amount)))
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
	
	-- Post price cap
	elseif( cmd == "pricecap" and arg ) then
		local amount = tonumber(arg)
		if( amount < 0 ) then amount = 0 end
		
		self:Print(string.format(L["Auction prices will not exceed %d%% of the fallback price."], amount))
		QuickAuctionsDB.pricepercent = amount / 100
	
	-- Post time
	elseif( cmd == "time" and arg ) then
		local amount = string.split(" ", arg, 2)
		amount = tonumber(amount)
		if( amount ~= 0 and amount ~= 12 and amount ~= 24 and amount ~= 48 ) then
			self:Print(L["Invalid time passed, should be 12, 24 or 48."])
			return
		end
	
		parseVariableOption(arg, "postTime", false, L["Default post time for auctions set to %s."], L["Set post time for %s to %s."], L["Removed post time for %s."])
		
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
		elseif( stackCount > 1 and ( not quantity or quantity <= 0 ) ) then
			self:Print(string.format(L["The item %s can stack up to %d, you must set the quantity that it should post them in."], link, stackCount))
			return
		
		-- Make sure they didn't give a bad stack count
		elseif( quantity and quantity > stackCount ) then
			self:Print(string.format(L["The item %s can only stack up to %d, you provided %d so set it to %d instead."], link, stackCount, quantity, quantity))
			quantity = stackCount
		end
		
		QuickAuctionsDB.itemList[self:GetSafeLink(link)] = quantity or true
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
	
	-- Add to whitelist
	elseif( cmd == "addwhite" and arg ) then
		QuickAuctionsDB.whitelist[arg] = true
		self:Print(string.format(L["Added %s to the whitelist."], arg))

	-- Remove from whitelist
	elseif( cmd == "removewhite" and arg ) then
		QuickAuctionsDB.whitelist[arg] = nil
		self:Print(string.format(L["Removed %s from whitelist."], arg))

	-- Add alt to list. We might as well add alts to the whitelist, because you don't want to undercut yourself anyway.
	elseif( cmd == "addalt" and arg ) then
		QuickAuctionsDB.whitelist[arg] = true
		QuickAuctionsDB.alts[arg] = true
		self:Print(string.format(L["Added %s to the alt list."], arg))

	-- Remove alt from list
	elseif( cmd == "removealt" and arg ) then
		QuickAuctionsDB.whitelist[arg] = nil
		QuickAuctionsDB.alts[arg] = nil
		self:Print(string.format(L["Removed %s from the alt list."], arg))
	
	-- Add to group list
	elseif( cmd == "addgroup" and arg ) then
		local group, items = string.split(" ", arg, 2)
		if( not group ) then
			self:Print(L["Invalid group name passed."])
			return
		elseif( not items ) then
			self:Print(L["Invalid item link given."])
			return
		end

		-- Parse item linkslocal itemLinks = {}
		local itemLinks = {}
		local foundLink
		for link in string.gmatch(items, "|H(.-):([-0-9]+):([0-9]+)|h") do
			foundLink = true
			itemLinks[string.gsub(link, ":0:0:0:0:0:0", "")] = true
		end
		
		if( not foundLink ) then
			self:Print(L["Invalid item link given."])
			return
		end
		
		-- Setup group
		if( not QuickAuctionsDB.groups[group] ) then
			QuickAuctionsDB.groups[group] = {}
		end
	
		-- Do a quick check, make sure an item isn't in another group
		local text
		for groupName, list in pairs(QuickAuctionsDB.groups) do
			if( groupName ~= group ) then
				for link in pairs(list) do
					if( itemLinks[link] ) then
						text = (text or "") .. select(2, GetItemInfo(link))
						itemLinks[link] = nil
					end
				end
			end
		end
		
		if( text ) then
			self:Print(string.format(L["You cannot add %s to the group %s, it already exists in another group."], text, group))
		end

		-- Now add all the items to it
		local text = ""
		for link in pairs(itemLinks) do
			if( not QuickAuctionsDB.groups[group][link] ) then
				QuickAuctionsDB.groups[group][link] = true
				text = text .. select(2, GetItemInfo(link))
			end
		end
		
		if( text == "" ) then
			return
		end
		
		self:Print(string.format(L["Added %s to the %s group."], text, group))
	
	-- Remove from group list
	elseif( cmd == "removegroup" and arg ) then
		local group, items = string.split(" ", arg, 2)
		if( not group or not QuickAuctionsDB.groups[group] ) then
			self:Print(L["Invalid group name passed."])
			return
		elseif( not items ) then
			self:Print(L["Invalid item link given."])
			return
		end

		-- Parse item linkslocal itemLinks = {}
		local itemLinks = {}
		local foundLink
		for link in string.gmatch(items, "|H(.-):([-0-9]+):([0-9]+)|h") do
			foundLink = true
			itemLinks[string.gsub(link, ":0:0:0:0:0:0", "")] = true
		end
		
		if( not foundLink ) then
			self:Print(L["Invalid item link given."])
			return
		end

		-- Now add all the items to it
		local text = ""
		for link in pairs(itemLinks) do
			if( QuickAuctionsDB.groups[group][link] ) then
				QuickAuctionsDB.groups[group][link] = nil
				text = text .. select(2, GetItemInfo(link))
			end
		end

		self:Print(string.format(L["Removed %s from the %s group."], text, group))
			
	-- Smart cancelling
	elseif( cmd == "smartcancel" ) then
		QuickAuctionsDB.smartCancel = not QuickAuctionsDB.smartCancel
		
		if( QuickAuctionsDB.smartCancel ) then
			self:Print(L["Smart cancelling is now enabled."])
		else
			self:Print(L["Smart cancelling is now disabled."])
		end
	
	-- Cancel all player auctions
	elseif( cmd == "cancelall" ) then
		self.scanButton:SetText(L["Cancel Items"])

		self.scanButton.haveCancelled = 0
		self.scanButton.totalCancels = 0

		for i=1, (GetNumAuctionItems("owner")) do
			local name, _, _, _, _, _, _, _, _, _, _, _, wasSold = GetAuctionItemInfo("owner", i)   
			local link = self:GetSafeLink(GetAuctionItemLink("owner", i))
			
			if( wasSold == 0 and ( not arg or ( arg and self:PartOfCategory(link, arg) ) ) ) then
				self.scanButton.totalCancels = self.scanButton.totalCancels + 1
				CancelAuction(i)
			end
		end
	
	-- Sum if everything sells
	elseif( cmd == "sumall" ) then
		local totalPrice = 0
		local totalAuctions = 0
		for i=1, (GetNumAuctionItems("owner")) do
			local name, texture, quantity, _, _, _, bid, _, buyoutPrice, _, _, owner, wasSold = GetAuctionItemInfo("owner", i)     
			if( wasSold == 0 ) then
				totalAuctions = totalAuctions + 1
				totalPrice = totalPrice + buyoutPrice
			end
		end
		
		if( totalAuctions == 0 ) then
			self:Print(L["No active auctions found to summarize."])
		else
			self:Print(string.format(L["Summary for %d auctions: %s - 5%% = %s total made."], totalAuctions, self:FormatTextMoney(totalPrice), self:FormatTextMoney(totalPrice * 0.95)))
		end

	-- Trade skill saving
	elseif( cmd == "tradeskill" ) then
		QuickAuctionsDB.saveCraft = not QuickAuctionsDB.saveCraft
		
		if( QuickAuctionsDB.saveCraft ) then
			self:Print(L["Trade skill saving is now enabled."])
		else
			self:Print(L["Trade skill saving is now disabled."])
			QuickAuctionsDB.crafts = {}
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
			
			if( self.timeElapsed >= 300 ) then
				self.timeElapsed = 0
				if( AuctionFrame:IsVisible() and QA.postButton:IsEnabled() and QA.scanButton:IsEnabled() ) then
					QA.postButton:Click()
				end
			end
		end)
		
		self:Print(L["Enabled super auctioning!"])
	
	elseif( cmd == "list" and arg ) then
		if( arg == "bidpercent" ) then
			self:Print(string.format(L["Posting auction bids at %d%% of buyout."], QuickAuctionsDB.bidpercent))
		elseif( arg == "items" ) then
			local list = {}
			for link, quantity in pairs(QuickAuctionsDB.itemList) do
				table.insert(list, string.format("%s x |cff33ff99%d|r", (select(2, GetItemInfo(link))) or link, type(quantity) == "number" and quantity or 1))	
			end
			
			if( #(list) > 0 ) then
				self:Echo(table.concat(list, ", "))
			else
				self:Print(L["Found no items to list."])
			end
			
		elseif( arg == "groups" ) then
			local found
			for name, list in pairs(QuickAuctionsDB.groups) do
				found = true
				self:Echo(string.format("|cff33ff99%s|r", name))
				
				for link in pairs(list) do
					self:Echo(string.format("- %s", (GetItemInfo(link)) or link))
				end
			end
			
			if( not found ) then
				self:Print(L["Found no items to list."])
			end
		
		elseif( arg == "whitelist" or arg == "alts" ) then
			local list = {}
			for name in pairs(QuickAuctionsDB[arg]) do
				-- Since we cheat and add alts to the whitelist, don't show them in the white list if it's an alt
				if( arg == "alts" or  arg == "whitelist" and not QuickAuctionsDB.alts[name] ) then
					table.insert(list, name)
				end
			end
			
			if( #(list) > 0 ) then
				if( arg == "whitelist" ) then
					self:Print(string.format(L["White list: %s"], table.concat(list, ", ")))
				else
					self:Print(string.format(L["Alt list: %s"], table.concat(list, ", ")))
				end
			else
				self:Print(L["Found no characters to list."])
			end
			
		elseif( arg == "time" or arg == "cap" or arg == "undercut" or arg == "fallback" or arg == "threshold" ) then
			self:Print(L["LIST"][arg])
			
			local key = arg
			if( arg == "time" ) then
				key = "postTime"
			elseif( arg == "cap" ) then
				key = "postCap"
			end
			
			local list = {}
			for link, value in pairs(QuickAuctionsDB[key]) do
				list[value] = list[value] or {}
				table.insert(list[value], (select(2, GetItemInfo(link))) or link)
			end
			
			for category, items in pairs(list) do
				if( arg ~= "time" and arg ~= "cap" ) then
					category = self:FormatTextMoney(category)
				else
					category = string.format("|cff33ff99%s|r", category)
				end
				
				if( #(items) <= 4 ) then
					self:Echo(string.format("%s - %s", category, table.concat(items, ", ")))
				else
					for _, item in pairs(items) do
						self:Echo(string.format("- %s", item))
					end
				end
			end
			
		else
			self:Print(L["Invalid argument passed for listing configurations."])
		end
	else
		self:Print(L["Slash commands"])
		self:Echo(L["/qa tradeskill - Saves what items you can create from various trade skills and displays them in the summary."])
		self:Echo(L["/qa smartcut - Toggles smart undercutting (Going from 1.9g -> 1g first instead of 1.9g - undercut amount."])
		self:Echo(L["/qa smartcancel - Toggles smart canceling, will not cancel if the item is below the threshold, or will cancel if you can make more relisting it."])
		self:Echo(L["/qa bidpercent <0-100> - Percentage of the buyout that the bid should be, 200g buyout and this set at 90 will put the bid at 180g."])
		self:Echo(L["/qa pricecap <percent> - How high above the fallback price an item should be posted at. 100 means an item will not be listed for more than the fallback price."])
		self:Echo(L["/qa time <12/24/48> <link/type/group> - Amount of hours to put auctions up for."])
		self:Echo(L["/qa undercut <money> <link/type/roup> - How much to undercut people by."])
		self:Echo(L["/qa cap <amount> <link/type/group> - Only allow <amount> of the same kind of auction to be up at the same time."])
		self:Echo(L["/qa fallback <money> <link/type/group> - How much money to default to if nobody else has an auction up."])
		self:Echo(L["/qa threshold <money> <link/type/group> - Don't post any auctions that would go below this amount."])
		self:Echo(L["/qa addwhite/removewhite <name> - White list management, will not undercut people on this list."])
		self:Echo(L["/qa addalt/removealt <name> - Alt list management, will show auctions by them in the summary, as if you were on them."])
		self:Echo(L["/qa additem <link> <quantity> - Adds an item to the list of things that should be managed, *IF* the item can stack you must provide a quantity to post it in."])
		self:Echo(L["/qa addgroup/removegroup <group> <link> - Group management for unique categories of items."])
		self:Echo(L["/qa removeitem <link> - Removes an item from the managed list."])
		self:Echo(L["/qa toggle <gems/uncut/glyphs/enchants/scrolls> - Lets you toggle entire categories of items: All item enchants, All cut gems, all uncut gems, and all glyphs. These will always be put onto the AH as the single item, if you want to override it to post multiple then use the additem command."])
		self:Echo(L["/qa list <time/bidpercent/cap/undercut/fallback/threshold/whitelist/alts/items> - Lists the set values for any of the passed categories."])
		self:Echo(L["/qa cancelall - Cancel all of your auctions. REGARDLESS of if you were undercut or not."])
		self:Echo(L["/qa summary - Toggles the summary frame."])
	end
end
