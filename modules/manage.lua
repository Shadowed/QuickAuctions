local Manage = QuickAuctions:NewModule("Manage", "AceEvent-3.0")
local L = QuickAuctionsLocals
local status = QuickAuctions.status
local reverseLookup, postQueue, scanList, tempList, stats = {}, {}, {}, {}, {}
local totalToCancel, totalCancelled = 0, 0

Manage.stats = stats

function Manage:OnInitialize()
	self:RegisterMessage("QA_AH_CLOSED", "AuctionHouseClosed")
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
	self:RegisterMessage("QA_QUERY_UPDATE")
	self:RegisterMessage("QA_START_SCAN")
	self:RegisterMessage("QA_STOP_SCAN")
end

function Manage:StopLog()
	self:UnregisterMessage("QA_QUERY_UPDATE")
	self:UnregisterMessage("QA_START_SCAN")
	self:UnregisterMessage("QA_STOP_SCAN")
end

function Manage:StopCancelling()
	self:StopLog()
	self:UnregisterEvent("CHAT_MSG_SYSTEM")
	
	status.isCancelling = nil
	totalCancelled = 0
	totalToCancel = 0
end

function Manage:CancelScan()
	self:StartLog()
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	
	table.wipe(scanList)
	table.wipe(tempList)
	
	updateReverseLookup()
	
	-- Add a scan based on items in the AH that match
	for i=1, GetNumAuctionItems("owner") do
		if( select(13, GetAuctionItemInfo("owner", i)) == 0 ) then
			local link = QuickAuctions:GetSafeLink(GetAuctionItemLink("owner", i))
			if( reverseLookup[link] ) then
				tempList[GetAuctionItemInfo("owner", i)] = true
			end
		end
	end
	
	for name in pairs(tempList) do
		table.insert(scanList, name)
	end
	
	if( #(scanList) == 0 ) then
		QuickAuctions:Log(L["Nothing to cancel, you have no unsold auctions up."], true)
		return
	end

	status.isCancelling = true
	QuickAuctions.Scan:StartItemScan(scanList)
end

local newLine
function Manage:CHAT_MSG_SYSTEM(event, msg)
	if( msg == ERR_AUCTION_REMOVED ) then
		totalToCancel = totalToCancel - 1
		
		if( totalToCancel <= 0 ) then
			QuickAuctions:Log(string.format(L["Finished cancelling %d auctions"], totalCancelled), true)
			
			-- Unlock posting, cancelling doesn't require the auction house to be open meaning we can cancel everything
			-- then go run to the mailbox while it cancels just fine
			if( not AuctionFrame:IsVisible() ) then
				QuickAuctions:Print(string.format(L["Finished cancelling %d auctions"], totalCancelled))
			end

			self:StopCancelling()
		else
			QuickAuctions:Log(string.format(L["Cancelled %d of %d"], totalToCancel, totalCancelled), newLine)
			newLine = nil
		end
	end
end

function Manage:CancelAll(group)
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	status.isCancelling = true
	table.wipe(tempList)
	
	updateReverseLookup()
	
	if( group ) then
		QuickAuctions:Log(string.format(L["Mass cancelling posted items in the group %s"], group), true)
	else
		QuickAuctions:Log(L["Mass cancelling posted items"], true)
	end
	
	for i=1, GetNumAuctionItems("owner") do
		local name, _, _, _, _, _, _, _, _, _, _, _, wasSold = GetAuctionItemInfo("owner", i)     
		local link = QuickAuctions:GetSafeLink(GetAuctionItemLink("owner", i))
		if( wasSold == 0 and ( group and reverseLookup[link] == group or not group ) ) then
			if( not tempList[name] ) then
				tempList[name] = true
				QuickAuctions:Log(string.format(L["Cancelled %s"], name), true)
			end
			
			totalToCancel = totalToCancel + 1
			totalCancelled = totalCancelled + 1
			CancelAuction(i)
		end
	end
	
	if( totalToCancel == 0 ) then
		QuickAuctions:Log(L["Nothing to cancel"], true)
		self:StopCancelling()
	else
		newLine = true
	end
end

function Manage:Cancel()
	table.wipe(tempList)
	
	for i=1, GetNumAuctionItems("owner") do
		local name, _, quantity, _, _, _, bid, _, buyout, activeBid, highBidder, _, wasSold = GetAuctionItemInfo("owner", i)     
		local link = QuickAuctions:GetSafeLink(GetAuctionItemLink("owner", i))
				
		local lowestBuyout, lowestBid, lowestOwner, isWhitelist, isPlayer = QuickAuctions.Scan:GetLowestAuction(link)
		if( wasSold == 0 and lowestOwner ) then
			buyout = buyout / quantity
			bid = bid / quantity
			
			local threshold = self:GetConfigValue(link, "threshold")
			local fallback = self:GetConfigValue(link, "fallback")
						
			-- They aren't us (The player posting), or on our whitelist so easy enough
			-- They are on our white list, but they undercut us, OR they matched us but the bid is lower
			-- The player is the only one with it on the AH and it's below the threshold
			if( ( not isPlayer and not isWhitelist ) or
				( isWhitelist and ( buyout > lowestBuyout or ( buyout == lowestBuyout and lowestBid < bid ) ) ) or
				( QuickAuctions.db.smartCancel and QuickAuctions.Scan:IsPlayerOnly(link) and buyout < fallback ) ) then
				
				-- Don't cancel if the buyout is equal, or below our threshold
				if( QuickAuctions.db.profile.smartCancel and lowestBuyout <= threshold ) then
					if( not tempList[name] ) then
						tempList[name] = true
						
						QuickAuctions:Log(string.format(L["Undercut on %s by %s, their buyout %s, yours %s (per item), threshold is %s not cancelling"], name, lowestOwner, QuickAuctions:FormatTextMoney(lowestBuyout, true), QuickAuctions:FormatTextMoney(buyout, true), self:FormatTextMoney(threshold, true)), true)
					end
				-- Don't cancel an auction if it has a bid and we're set to not cancel those
				elseif( not QuickAuctions.db.profile.cancelWithBid and activeBid > 0 ) then
					QuickAuctions:Log(string.format(L["Undercut on %s by %s, but %s placed a bid of %s so not cancelling"], name, lowestOwner, highBidder, QuickAuctions:FormatTextMoney(activeBid, true)), true)
				else
					if( not tempList[name] ) then
						tempList[name] = true
						if( QuickAuctions.Scan:IsPlayerOnly(link) and buyout < fallback ) then
							QuickAuctions:Log(string.format(L["You are the only one posting %s, the fallback is %s (per item), cancelling so you can relist it for more gold"], name, QuickAuctions:FormatTextMoney(fallback)), true)
						else
							QuickAuctions:Log(string.format(L["Undercut on %s by %s, buyout %s, yours %s (per item)"], name, lowestOwner, QuickAuctions:FormatTextMoney(lowestBuyout, true), QuickAuctions:FormatTextMoney(buyout, true)), true)
						end
					end
					
					totalToCancel = totalToCancel + 1
					totalCancelled = totalCancelled + 1
					CancelAuction(i)
				end
			end
		end
	end
	
	if( totalToCancel == 0 ) then
		QuickAuctions:Log(L["Nothing to cancel"], true)
		self:StopCancelling()
	end
end

-- Makes sure that the items that stack the lowest are posted first to free up space for items
-- that stack higher
local function sortByStack(a, b)
	local aStack = select(8, GetItemInfo(a)) or 20
	local bStack = select(8, GetItemInfo(b)) or 20
	
	return aStack < bStack
end

function Manage:PostScan()
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
	local threshold = self:GetConfigValue(itemLink, "threshold")
	local auctionsCreated, activeAuctions = 0, 0
	
	QuickAuctions:Log(string.format(L["Queued %s to be posted"], name))
	
	if( perPost == 0 ) then
		QuickAuctions:Log(string.format(L["Skipped %s, need %d for a single post, have %d"], name, perAuction, GetItemCount(itemLink)))
		return
	end

	local buyout, bid, _, isPlayer, isWhitelist = QuickAuctions.Scan:GetLowestAuction(itemLink)
	
	-- Check if we're going to go below the threshold
	if( buyout ) then
		-- Smart undercutting is enabled, and the auction is for at least 1 gold, round it down to the nearest gold piece
		local testBuyout = buyout
		if( QuickAuctions.db.profile.smartUndercut and testBuyout > COPPER_PER_GOLD ) then
			testBuyout = math.floor(buyout / COPPER_PER_GOLD) * COPPER_PER_GOLD
		else
			testBuyout = testBuyout - QuickAuctions.Manage:GetConfigValue(link, "undercut")
		end
		
		if( testBuyout < threshold ) then
			QuickAuctions:Log(string.format(L["Skipped %s, lowest buyout is %s threshold is %s"], name, QuickAuctions:FormatTextMoney(buyout, true), QuickAuctions:FormatTextMoney(threshold, true)))
			return
		end
	end
	
	-- Either the player or a whitelist person is the lowest teir so use this tiers quantity of items
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
function Manage:QA_QUERY_UPDATE(event, type, filter, ...)
	if( not filter ) then return end
	
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

function Manage:QA_START_SCAN(event, type, total)
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

function Manage:QA_STOP_SCAN(event, interrupted)
	self:StopLog()

	if( interrupted ) then
		QuickAuctions:Log(L["Scan interrupted before it could finish"], true)
		return
	end

	QuickAuctions:Log(L["Scan finished!"], true)

	if( status.isManaging ) then
		status.isManaging = nil
		
		if( startSplitter ) then
			startSplitter = nil
			
			QuickAuctions:Log(L["Starting to split and post items..."], true)
			
			-- First do a threshold check on everything
			QuickAuctions.Split:Start()
		else
			QuickAuctions:Log(L["Nothing to post"], true)
		end
		
	elseif( status.isCancelling ) then
		QuickAuctions:Log(L["Starting to cancel..."], true)
		
		self:Cancel()
	end
end





