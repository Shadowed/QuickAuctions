local Manage = QuickAuctions:NewModule("Manage", "AceEvent-3.0")
local L = QuickAuctionsLocals
local status = QuickAuctions.status
local reverseLookup, postQueue, scanList, tempList, stats = {}, {}, {}, {}, {}
local totalToCancel, totalCancelled, totalQueued = 0, 0, 0

Manage.reverseLookup = reverseLookup
Manage.stats = stats

function Manage:OnInitialize()
	self:RegisterMessage("QA_AH_CLOSED", "AuctionHouseClosed")
end

function Manage:AuctionHouseClosed()
	if( status.isManaging and not status.isScanning ) then
		self:StopPosting()
		QuickAuctions:Print(L["Posting interrupted due to Auction House being closed"])
	end
end

function Manage:GetBoolConfigValue(itemID, key)
	local val = reverseLookup[itemID] and QuickAuctions.db.profile[key][reverseLookup[itemID]]
	if( val ~= nil ) then
		return val
	end
	
	return QuickAuctions.db.profile[key].default
end

function Manage:GetConfigValue(itemID, key)
	return reverseLookup[itemID] and QuickAuctions.db.profile[key][reverseLookup[itemID]] or QuickAuctions.db.profile[key].default
end

function Manage:UpdateReverseLookup()
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
	
	self:UpdateReverseLookup()
	
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
		QuickAuctions:Log("cancelstatus", L["Nothing to cancel, you have no unsold auctions up."])
		return
	end

	status.isCancelling = true
	QuickAuctions.Scan:StartItemScan(scanList)
end

function Manage:CHAT_MSG_SYSTEM(event, msg)
	if( msg == ERR_AUCTION_REMOVED ) then
		totalToCancel = totalToCancel - 1

		QuickAuctions:SetButtonProgress("cancel", totalCancelled - totalToCancel, totalCancelled)
		
		if( totalToCancel <= 0 ) then
			QuickAuctions:Log("cancelprogress", string.format(L["Finished cancelling |cfffed000%d|r auctions"], totalCancelled))
			
			-- Unlock posting, cancelling doesn't require the auction house to be open meaning we can cancel everything
			-- then go run to the mailbox while it cancels just fine
			if( not AuctionFrame:IsVisible() ) then
				QuickAuctions:Print(string.format(L["Finished cancelling |cfffed000%d|r auctions"], totalCancelled))
			end

			self:StopCancelling()
		else
			QuickAuctions:Log("cancelprogress", string.format(L["Cancelling |cfffed000%d|r of |cfffed000%d|r"], totalCancelled - totalToCancel, totalCancelled))
		end
	end
end

function Manage:CancelAll(group, duration)
	QuickAuctions:WipeLog()
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	status.isCancelling = true
	table.wipe(tempList)
	
	self:UpdateReverseLookup()
	
	if( duration ) then
		QuickAuctions:Log("masscancel", string.format(L["Mass cancelling posted items with less than %d hours left"], duration == 3 and 12 or 2))
	elseif( group ) then
		QuickAuctions:Log("masscancel", string.format(L["Mass cancelling posted items in the group |cfffed000%s|r"], group))
	else
		QuickAuctions:Log("masscancel", L["Mass cancelling posted items"])
	end
	
	for i=1, GetNumAuctionItems("owner") do
		local name, _, _, _, _, _, _, _, _, _, _, _, wasSold = GetAuctionItemInfo("owner", i)     
		local timeLeft = GetAuctionItemTimeLeft("owner", i)
		local itemLink = GetAuctionItemLink("owner", i)
		local itemID = QuickAuctions:GetSafeLink(itemLink)
		if( wasSold == 0 and ( group and reverseLookup[itemID] == group or not group ) and ( duration and timeLeft <= duration or not duration ) ) then
			if( name and not tempList[name] ) then
				tempList[name] = true
				QuickAuctions:Log(name, string.format(L["Cancelled %s"], itemLink))
			end
			
			totalToCancel = totalToCancel + 1
			totalCancelled = totalCancelled + 1
			CancelAuction(i)
		end
	end
	
	if( totalToCancel == 0 ) then
		QuickAuctions:Log("cancelstatus", L["Nothing to cancel"])
		self:StopCancelling()
	end
end

function Manage:Cancel()
	table.wipe(tempList)
	
	for i=1, GetNumAuctionItems("owner") do
		local name, _, quantity, _, _, _, bid, _, buyout, activeBid, highBidder, _, wasSold = GetAuctionItemInfo("owner", i)     
		local itemLink = GetAuctionItemLink("owner", i)
		local itemID = QuickAuctions:GetSafeLink(itemLink)
				
		local lowestBuyout, lowestBid, lowestOwner, isWhitelist, isPlayer = QuickAuctions.Scan:GetLowestAuction(itemID)
		
		-- The item is in a group that's not supposed to be cancelled
		if( wasSold == 0 and lowestOwner and self:GetBoolConfigValue(itemID, "noCancel") ) then
			if( not tempList[name] ) then
				QuickAuctions:Log(name .. "notcancel", string.format(L["Skipped cancelling %s flagged to not be canelled."], itemLink))
				tempList[name] = true
			end
		elseif( wasSold == 0 and lowestOwner and self:GetBoolConfigValue(itemID, "autoFallback") and lowestBuyout <= self:GetConfigValue(itemID, "threshold") ) then
			if( not tempList[name] ) then
				QuickAuctions:Log(name .. "notcancel", string.format(L["Skipped cancelling %s flagged to post at fallback when market is below threshold."], itemLink))
				tempList[name] = true
			end
		-- It is supposed to be cancelled!
		elseif( wasSold == 0 and lowestOwner ) then
			buyout = buyout / quantity
			bid = bid / quantity
			
			local threshold = self:GetConfigValue(itemID, "threshold")
			local fallback = self:GetConfigValue(itemID, "fallback")
						
			-- They aren't us (The player posting), or on our whitelist so easy enough
			-- They are on our white list, but they undercut us, OR they matched us but the bid is lower
			-- The player is the only one with it on the AH and it's below the threshold
			if( ( not isPlayer and not isWhitelist ) or
				( isWhitelist and ( buyout > lowestBuyout or ( buyout == lowestBuyout and lowestBid < bid ) ) ) or
				( QuickAuctions.db.profile.smartCancel and QuickAuctions.Scan:IsPlayerOnly(itemID) and buyout < fallback ) ) then
				
				-- Don't cancel if the buyout is equal, or below our threshold
				if( QuickAuctions.db.profile.smartCancel and lowestBuyout <= threshold and not QuickAuctions.Scan:IsPlayerOnly(itemID)) then
					if( not tempList[name] ) then
						tempList[name] = true
						
						QuickAuctions:Log(name .. "notcancel", string.format(L["Undercut on %s by |cfffed000%s|r, their buyout %s, yours %s (per item), threshold is %s not cancelling"], itemLink, lowestOwner, QuickAuctions:FormatTextMoney(lowestBuyout, true), QuickAuctions:FormatTextMoney(buyout, true), QuickAuctions:FormatTextMoney(threshold, true)))
					end
				-- Don't cancel an auction if it has a bid and we're set to not cancel those
				elseif( not QuickAuctions.db.profile.cancelWithBid and activeBid > 0 ) then
					QuickAuctions:Log(name .. "bid", string.format(L["Undercut on %s by |cfffed000%s|r, but %s placed a bid of %s so not cancelling"], itemLink, lowestOwner, highBidder, QuickAuctions:FormatTextMoney(activeBid, true)))
				else
					if( not tempList[name] ) then
						tempList[name] = true
						if( QuickAuctions.Scan:IsPlayerOnly(itemID) and buyout < fallback ) then
							QuickAuctions:Log(name, string.format(L["You are the only one posting %s, the fallback is %s (per item), cancelling so you can relist it for more gold"], itemLink, QuickAuctions:FormatTextMoney(fallback)))
						else
							QuickAuctions:Log(name, string.format(L["Undercut on %s by |cfffed000%s|r, buyout %s, yours %s (per item)"], itemLink, lowestOwner, QuickAuctions:FormatTextMoney(lowestBuyout, true), QuickAuctions:FormatTextMoney(buyout, true)))
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
		QuickAuctions:Log("cancelstatus", L["Nothing to cancel"])
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

	self:UpdateReverseLookup()
	
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
		QuickAuctions:Log("poststatus", L["You do not have any items to post"])
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
	
	totalQueued = 0
	status.isManaging = nil
	self:StopLog()
	
	QuickAuctions.Split:Stop()
end

function Manage:PostItems(itemID)
	if( not itemID ) then return end
	
	local name, itemLink, _, _, _, _, _, stackCount = GetItemInfo(itemID)
	local perAuction = math.min(stackCount, self:GetConfigValue(itemID, "perAuction"))
	local perPost = math.floor(GetItemCount(itemID) / perAuction)
	local postCap = self:GetConfigValue(itemID, "postCap")
	local threshold = self:GetConfigValue(itemID, "threshold")
	local auctionsCreated, activeAuctions = 0, 0
	
	QuickAuctions:Log(name .. "query", string.format(L["Queued %s to be posted"], itemLink))
	
	if( perPost == 0 ) then
		QuickAuctions:Log(name .. "query", string.format(L["Skipped %s need |cff20ff20%d|r for a single post, have |cffff2020%d|r"], itemLink, perAuction, GetItemCount(itemID)))
		return
	end

	local buyout, bid, _, isPlayer, isWhitelist = QuickAuctions.Scan:GetLowestAuction(itemID)
	
	-- Check if we're going to go below the threshold
	if( buyout and not self:GetBoolConfigValue(itemID, "autoFallback") ) then
		-- Smart undercutting is enabled, and the auction is for at least 1 gold, round it down to the nearest gold piece
		local testBuyout = buyout
		if( QuickAuctions.db.profile.smartUndercut and testBuyout > COPPER_PER_GOLD ) then
			testBuyout = math.floor(buyout / COPPER_PER_GOLD) * COPPER_PER_GOLD
		else
			testBuyout = testBuyout - self:GetConfigValue(itemID, "undercut")
		end
		
		if( testBuyout < threshold ) then
			QuickAuctions:Log(name .. "query", string.format(L["Skipped %s lowest buyout is %s threshold is %s"], itemLink, QuickAuctions:FormatTextMoney(buyout, true), QuickAuctions:FormatTextMoney(threshold, true)))
			return
		end
	end
	
	-- Either the player or a whitelist person is the lowest teir so use this tiers quantity of items
	if( isPlayer or isWhitelist ) then
		activeAuctions = QuickAuctions.Scan:GetPlayerAuctionCount(itemID, buyout, bid)
	end
	
	-- If we have a post cap of 20, and 10 active auctions, but we can only have 5 of the item then this will only let us create 5 auctions
	-- however, if we have 20 of the item it will let us post another 10
	auctionsCreated = math.min(postCap - activeAuctions, perPost)
	if( auctionsCreated <= 0 ) then
		QuickAuctions:Log(name .. "query", string.format(L["Skipped %s posted |cff20ff20%d|r of |cff20ff20%d|r already"], itemLink, activeAuctions, postCap))
		return
	end
	
	-- Warn that they don't have enough to post
	if( perPost < postCap ) then
		QuickAuctions:Log(name .. "query", string.format(L["Queued %s to be posted (Cap is |cffff2020%d|r, only can post |cffff2020%d|r need to restock)"], itemLink, postCap, perPost))
	end

	-- The splitter will automatically pass items to the post queuer, meaning if an item doesn't even stack it will handle that just fine
	for i=1, auctionsCreated do
		stats[itemID] = (stats[itemID] or 0) + 1
		totalQueued = totalQueued + 1
		
		QuickAuctions.Split:QueueItem(itemID, perAuction)
	end
end

-- Log handler
function Manage:QA_QUERY_UPDATE(event, type, filter, ...)
	if( not filter ) then return end
	
	if( type == "retry" ) then	
		local page, totalPages, retries, maxRetries = ...
		QuickAuctions:Log(filter .. "query", string.format(L["Retry |cfffed000%d|r of |cfffed000%d|r for %s"], retries, maxRetries, filter))
	elseif( type == "page" ) then
		local page, totalPages = ...
		QuickAuctions:Log(filter .. "query", string.format(L["Scanning page |cfffed000%d|r of |cfffed000%d|r for %s"], page, totalPages, filter))
	elseif( type == "done" ) then
		local page, totalPages = ...
		QuickAuctions:Log(filter .. "query", string.format(L["Scanned page |cfffed000%d|r of |cfffed000%d|r for %s"], page, totalPages, filter))

		-- Do everything we need to get it splitted/posted
		for i=#(postQueue), 1, -1 do
			if( GetItemInfo(postQueue[i]) == filter ) then
				self:PostItems(table.remove(postQueue, i))
			end
		end
	elseif( type == "next" ) then
		QuickAuctions:Log(filter .. "query", string.format(L["Scanning %s"], filter))
	end
end

function Manage:QA_START_SCAN(event, type, total)
	QuickAuctions:WipeLog()
	QuickAuctions:Log("scanstatus", string.format(L["Scanning |cfffed000%d|r items..."], total or 0))
	
	totalQueued = 0
	table.wipe(stats)
end

function Manage:QA_STOP_SCAN(event, interrupted)
	self:StopLog()

	if( interrupted ) then
		QuickAuctions:Log("scaninterrupt", L["Scan interrupted before it could finish"])
		return
	end

	QuickAuctions:Log("scandone", L["Scan finished!"], true)

	if( status.isManaging ) then
		status.isManaging = nil
		
		if( totalQueued > 0 ) then
			status.totalPostQueued = totalQueued
			
			QuickAuctions:Log(L["Starting to split and post items..."])
			QuickAuctions:SetButtonProgress("post", 0, status.totalPostQueued)
			QuickAuctions.Split:Start()
			
			totalQueued = 0
		else
			QuickAuctions:Log(L["Nothing to post"])
		end
		
	elseif( status.isCancelling ) then
		QuickAuctions:Log("cancelstatus", L["Starting to cancel..."])
		
		self:Cancel()
	end
end





