local Manage = QuickAuctions:NewModule("Manage", "AceEvent-3.0")
local L = QuickAuctionsLocals
local status = QuickAuctions.status
local reverseLookup, postQueue, scanList, tempList, stats, newLine = {}, {}, {}, {}, {}

Manage.stats = stats

function Manage:OnInitialize()
	self:RegisterMessage("SUF_AH_CLOSED", "AuctionHouseClosed")
end

function Manage:AuctionHouseClosed()
	if( status.isManaging ) then
		self:StopPosting()
		QuickAuctions:Print(L["Posting interrupted due to Auction House being closed."])
	end
end

function Manage:GetConfigValue(itemID, key)
	return reverseLookup[itemID] and QuickAuctions.db.profile[key][reverseLookup[itemID]] or QuickAuctions.db.profile[key].default
end

local function updateReverseLookup()
	table.wipe(reverseLookup)
	
	for group, items in pairs(QuickAuctions.db.profile.groups) do
		for itemID in pairs(items) do
			reverseLookup[itemID] = group
		end
	end
end

function Manage:StartLog()
	self:RegisterMessage("SUF_QUERY_UPDATE")
	self:RegisterMessage("SUF_START_SCAN")
	self:RegisterMessage("SUF_STOP_SCAN")
end

function Manage:StopLog()
	self:UnregisterMessage("SUF_QUERY_UPDATE")
	self:UnregisterMessage("SUF_START_SCAN")
	self:UnregisterMessage("SUF_STOP_SCAN")
end

function Manage:Cancel()
	self:StartLog()
	
	table.wipe(scanList)
	table.wipe(tempList)
	
	updateReverseLookup()
	
	-- Add a scan based on items in the Ah that match
end

-- Makes sure that the items that stack the lowest are posted first to free up space for items
-- that stack higher
local function sortByStack(a, b)
	local aStack = select(8, GetItemInfo(a)) or 20
	local bStack = select(8, GetItemInfo(b)) or 20
	
	return aStack < bStack
end

function Manage:Post()
	self:StartLog()
	
	table.wipe(postQueue)
	table.wipe(scanList)
	table.wipe(tempList)

	updateReverseLookup()
	
	for bag=0, 4 do
		if( QuickAuctions:IsValidBag(bag) ) then
			for slot=1, GetContainerNumSlots(bag) do
				local link = QuickAuctions:GetSafeLink(GetContainerItemLink(bag, slot))
				if( link and reverseLookup[link] ) then
					tempList[link] = true
				end
			end
		end
	end
	
	for itemID in pairs(tempList) do
		table.insert(postQueue, itemID)
	end
	
	table.sort(postQueue, sortByStack)
	if( #(postQueue) == 0 ) then
		QuickAuctions:Log(L["You do not have any items to post."], true)
		return
	end
		
	for _, itemID in pairs(postQueue) do
		table.insert(scanList, (GetItemInfo(itemID)))
	end
	
	
	status.isManaging = true
	QuickAuctions.Scan:StartItemScan(scanList)
end

function Manage:StopPosting()
	table.wipe(postQueue)
	
	startSplitter = nil
	status.isManaging = nil
	self:StopLog()
	
	QuickAuctions.Split:Stop()
end

function Manage:PostItems(itemLink)
	if( not itemLink ) then return end
	
	local name, _, _, _, _, _, _, stackCount = GetItemInfo(itemLink)
	local perAuction = math.min(stackCount, self:GetConfigValue(itemLink, "perAuction"))
	local perPost = math.floor(GetItemCount(itemLink) / perAuction)
	local postCap = self:GetConfigValue(itemLink, "postCap")
	local auctionsCreated, activeAuctions = 0, 0
	
	QuickAuctions:Log(string.format(L["Queued %s to be posted"], name))
	
	if( perPost == 0 ) then
		QuickAuctions:Log(string.format(L["Skipped %s, need %d for a single post, have %d"], name, perAuction, GetItemCount(itemLink)))
		return
	end

	-- Lowest person is either the player or someone on their whitelist
	local buyout, bid, _, isPlayer, isWhitelist = QuickAuctions.Scan:GetLowestAuction(itemLink)
	if( isPlayer or isWhitelist ) then
		activeAuctions = QuickAuctions.Scan:GetItemQuantity(itemLink, buyout, bid)
	end
	
	-- If we have a post cap of 20, and 10 active auctions, but we can only have 5 of the item then this will only let us create 5 auctions
	-- however, if we have 20 of the item it will let us post another 10
	auctionsCreated = math.min(postCap - activeAuctions, perPost)
	if( auctionsCreated <= 0 ) then
		QuickAuctions:Log(string.format(L["Skipped %s, posted %d of %d already"], name, activeAuctions, postCap))
		return
	end
	
	startSplitter = true
	
	-- The splitter will automatically pass items to the post queuer, meaning if an item doesn't even stack it will handle that just fine
	for i=1, auctionsCreated do
		stats[itemLink] = (stats[itemLink] or 0) + 1
		QuickAuctions.Split:QueueItem(itemLink, perAuction)
	end
end

-- Log handler
function Manage:SUF_QUERY_UPDATE(event, type, filter, ...)
	if( type == "retry" ) then	
		local page, totalPages, retries, maxRetries = ...
		QuickAuctions:Log(string.format(L["Retry %d of %d for %s"], retries, maxRetries, filter))
	elseif( type == "page" ) then
		local page, totalPages = ...
		QuickAuctions:Log(string.format(L["Scanning page %d of %d for %s"], page, totalPages, filter))
	elseif( type == "done" ) then
		local page, totalPages = ...
		QuickAuctions:Log(string.format(L["Scanned page %d of %d for %s"], page, totalPages, filter))

		-- Do everything we need to get it splitted/posted
		for i=#(postQueue), 1, -1 do
			if( GetItemInfo(postQueue[i]) == filter ) then
				self:PostItems(table.remove(postQueue, i))
			end
		end
	elseif( type == "next" ) then
		QuickAuctions:Log(string.format(L["Scanning %s"], filter), true)
	end
end

function Manage:SUF_START_SCAN(event, type, total)
	QuickAuctions:WipeLog()
	if( type == "item" ) then
		QuickAuctions:Log(string.format(L["Scanning %d items..."], total), true)
	else
		QuickAuctions:Log(L["Starting an auction scan..."], true)
	end
	
	-- For the first entry when a query update happens to use
	QuickAuctions:Log("", true)
	
	startSplitter = nil
	table.wipe(stats)
end

function Manage:SUF_STOP_SCAN()
	QuickAuctions:Log(L["Scan finished!"], true)

	if( status.isManaging ) then
		status.isManaging = nil
		
		if( startSplitter ) then
			startSplitter = nil
			
			QuickAuctions:Log(L["Starting to split and post items..."], true)
			QuickAuctions.Split:Start()
		else
			QuickAuctions:Log(L["Nothing to post"], true)
		end
		
	elseif( status.isCancelling ) then
		QuickAuctions:Log(L["Starting to cancel..."])
		newLine = true
	end
end





