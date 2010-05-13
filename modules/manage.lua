local QuickAuctions = select(2, ...)
local Manage = QuickAuctions:NewModule("Manage", "AceEvent-3.0")
local L = QuickAuctions.L
local status = QuickAuctions.status
local reverseLookup, postQueue, scanList, tempList, stats = {}, {}, {}, {}, {}
local totalToCancel, totalCancelled = 0, 0

Manage.reverseLookup = reverseLookup
Manage.stats = stats

function Manage:OnInitialize()
	self:RegisterMessage("QA_AH_CLOSED", "AuctionHouseClosed")
end

function Manage:AuctionHouseClosed()
	if( self.cancelFrame and self.cancelFrame:IsShown() ) then
		QuickAuctions:Print(L["Cancelling interrupted due to Auction House being closed."])
		QuickAuctions:Log("cancelstatus", L["Auction House closed before you could tell Quick Auctions to cancel."])
		
		self:StopCancelling()
		self.cancelFrame:Hide()
	elseif( status.isCancelling and status.isScanning ) then
		self:StopCancelling()
	elseif( status.isManaging and not status.isCancelling ) then
		self:StopPosting()
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
	
	for group, items in pairs(QuickAuctions.db.global.groups) do
		if( not QuickAuctions.db.profile.groupStatus[group] ) then
			for itemID in pairs(items) do
				reverseLookup[itemID] = group
			end
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
	QuickAuctions:UnlockButtons()
	
	status.isCancelling = nil
	totalCancelled = 0
	totalToCancel = 0
end

function Manage:CancelScan()
	self:StartLog()
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	self:UpdateReverseLookup()
	QuickAuctions:LockButtons()
	
	table.wipe(scanList)
	table.wipe(tempList)
	table.wipe(status)
	
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
		QuickAuctions:UnlockButtons()
		return
	end
	
	--QuickAuctions.Split:ScanStopped()
	--QuickAuctions.Split:Stop()
	QuickAuctions.Post:Stop()

	status.isCancelling = true
	status.totalScanQueue = #(scanList)
	status.queueTable = scanList
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

function Manage:CancelMatch(match)
	QuickAuctions:WipeLog()
	QuickAuctions:LockButtons()
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	
	table.wipe(tempList)
	table.wipe(status)
	status.isCancelling = true
	
	local itemID = tonumber(string.match(match, "item:(%d+)"))
	if( itemID ) then
		match = GetItemInfo(itemID)
	end
	
	for i=1, GetNumAuctionItems("owner") do
		local name, _, _, _, _, _, _, _, _, _, _, _, wasSold = GetAuctionItemInfo("owner", i)     
		local itemLink = GetAuctionItemLink("owner", i)
		if( wasSold == 0 and string.match(string.lower(name), string.lower(match)) ) then
			if( not tempList[name] ) then
				tempList[name] = true
				QuickAuctions:Log(name, string.format(L["Cancelled %s"], itemLink))
			end
			
			totalToCancel = totalToCancel + 1
			totalCancelled = totalCancelled + 1
			CancelAuction(i)
		end
	end
	
	if( totalToCancel == 0 ) then
		QuickAuctions:Log("cancelstatus", string.format(L["Nothing to cancel, no matches found for \"%s\""], match))
		self:StopCancelling()
	end
end

function Manage:CancelAll(group, duration, price)
	QuickAuctions:WipeLog()
	QuickAuctions:LockButtons()
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	self:UpdateReverseLookup()

	table.wipe(tempList)
	table.wipe(status)

	status.isCancelling = true
	
	if( duration ) then
		QuickAuctions:Log("masscancel", string.format(L["Mass cancelling posted items with less than %d hours left"], duration == 3 and 12 or 2))
	elseif( group ) then
		QuickAuctions:Log("masscancel", string.format(L["Mass cancelling posted items in the group |cfffed000%s|r"], group))
	elseif( money ) then
		QuickAuctions:Log("masscancel", string.format(L["Mass cancelling posted items below %s"], QuickAuctions:FormatTextMoney(money)))
	else
		QuickAuctions:Log("masscancel", L["Mass cancelling posted items"])
	end
	
	for i=1, GetNumAuctionItems("owner") do
		local name, _, _, _, _, _, _, _, buyoutPrice, _, _, _, wasSold = GetAuctionItemInfo("owner", i)     
		local timeLeft = GetAuctionItemTimeLeft("owner", i)
		local itemLink = GetAuctionItemLink("owner", i)
		local itemID = QuickAuctions:GetSafeLink(itemLink)
		if( wasSold == 0 and ( group and reverseLookup[itemID] == group or not group ) and ( duration and timeLeft <= duration or not duration ) and ( price and buyoutPrice <= price or not price ) ) then
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

-- Handle the cancel key press stuff
function Manage:ReadyToCancel()
	local hasCancelable = self:Cancel(true)
	if( not hasCancelable ) then
		QuickAuctions:Log("cancelstatus", L["Nothing to cancel"])
		self:StopCancelling()
		return
	end

	QuickAuctions:LockButtons()
	
	if( self.cancelFrame ) then
		self.cancelFrame:Show()
		return
	end

	local function showTooltip(self)
		if( self.tooltip ) then
			GameTooltip:SetOwner(self:GetParent(), "ANCHOR_TOPLEFT")
			GameTooltip:SetText(self.tooltip, 1, 1, 1, nil, true)
			GameTooltip:Show()
		end
	end

	local function hideTooltip(self)
		GameTooltip:Hide()
	end

	local function formatTime(seconds)
		if( seconds >= 3600 ) then
			return seconds / 3600, L["hours"]
		elseif( seconds >= 60 ) then
			return seconds / 60, L["minutes"]
		end

		return seconds, L["seconds"]
	end
	
	local scanFinished
	local timeElapsed = 0
	local soundElapsed = 0
	local function OnUpdate(self, elapsed)
		timeElapsed = timeElapsed + elapsed
		if( timeElapsed >= 1 ) then
			timeElapsed = timeElapsed - 1
			self.text:SetFormattedText(L["Auction scan finished, can now smart cancel auctions.\n\nScan data age: %d %s"], formatTime(GetTime() - scanFinished)) 
		end
		
		-- Remind them once every 60 seconds that it's ready
		if( QuickAuctions.db.global.playSound ) then
			soundElapsed = soundElapsed + elapsed
			if( soundElapsed >= 60 ) then
				soundElapsed = soundElapsed - 60
				
				PlaySound("ReadyCheck")
			end
		end
	end
	
	local frame = CreateFrame("Frame", nil, AuctionFrame)
	frame:SetClampedToScreen(true)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetWidth(300)
	frame:SetHeight(100)
	frame:SetBackdrop({
		  bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		  edgeSize = 26,
		  insets = {left = 9, right = 9, top = 9, bottom = 9},
	})
	frame:SetBackdropColor(0, 0, 0, 0.85)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
	frame:Hide()
	frame:SetScript("OnUpdate", OnUpdate)
	frame:SetScript("OnShow", function(self)
		if( QuickAuctions.db.global.cancelBinding ~= "" ) then
			SetOverrideBindingClick(self, true, QuickAuctions.db.global.cancelBinding, self.cancel:GetName())
		end
		
		if( QuickAuctions.db.global.playSound ) then
			PlaySound("ReadyCheck")
		end
		
		-- Setup initial data + update
		scanFinished = GetTime()
		soundElapsed = 0
		OnUpdate(self, 1)
	end)
	frame:SetScript("OnHide", function(self)
		if( not self.wasClicked ) then
			Manage:StopCancelling()
		end
		
		self.wasclicked = nil
		ClearOverrideBindings(self)
	end)
	
	frame.titleBar = frame:CreateTexture(nil, "ARTWORK")
	frame.titleBar:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	frame.titleBar:SetPoint("TOP", 0, 8)
	frame.titleBar:SetWidth(225)
	frame.titleBar:SetHeight(45)

	frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	frame.title:SetPoint("TOP", 0, 0)
	frame.title:SetText("Quick Auctions")

	frame.text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.text:SetText("")
	frame.text:SetPoint("TOPLEFT", 12, -22)
	frame.text:SetWidth(frame:GetWidth() - 20)
	frame.text:SetJustifyH("LEFT")

	frame.cancel = CreateFrame("Button", "QuickAuctionsCancelButton", frame, "UIPanelButtonTemplate")
	frame.cancel:SetText(L["Start"])
	frame.cancel:SetHeight(20)
	frame.cancel:SetWidth(100)
	frame.cancel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6, 8)
	frame.cancel.tooltip = L["Clicking this will cancel auctions based on the data scanned."]
	frame.cancel:SetScript("OnClick", function(self)
		self:GetParent().wasClicked = true
		self:GetParent():Hide()
		Manage:Cancel()
	end)

	frame.rescan = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.rescan:SetText(L["Rescan"])
	frame.rescan:SetHeight(20)
	frame.rescan:SetWidth(100)
	frame.rescan:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 8)
	frame.rescan:SetScript("OnEnter", showTooltip)
	frame.rescan:SetScript("OnLeave", hideTooltip)
	frame.rescan.tooltip = L["If the data is too old and instead of canceling you would rather rescan auctions to get newer data just press this button."]
	frame.rescan:SetScript("OnClick", function(self)
		self:GetParent():Hide()
		Manage:CancelScan()
	end)
	
	self.cancelFrame = frame
	frame:Show()
end

function Manage:Cancel(isTest)
	table.wipe(tempList)
	
	for i=1, GetNumAuctionItems("owner") do
		local name, _, quantity, _, _, _, bid, _, buyout, activeBid, highBidder, _, wasSold = GetAuctionItemInfo("owner", i)     
		local itemLink = GetAuctionItemLink("owner", i)
		local itemID = QuickAuctions:GetSafeLink(itemLink)
				
		local lowestBuyout, lowestBid, lowestOwner, isWhitelist, isPlayer = QuickAuctions.Scan:GetLowestAuction(itemID)
		
		-- The item is in a group that's not supposed to be cancelled
		if( wasSold == 0 and lowestOwner and self:GetBoolConfigValue(itemID, "noCancel") ) then
			if( not tempList[name] and not isTest ) then
				QuickAuctions:Log(name .. "notcancel", string.format(L["Skipped cancelling %s flagged to not be canelled."], itemLink))
				tempList[name] = true
			end
		elseif( wasSold == 0 and lowestOwner and self:GetBoolConfigValue(itemID, "autoFallback") and lowestBuyout <= self:GetConfigValue(itemID, "threshold") ) then
			if( not tempList[name] and not isTest ) then
				QuickAuctions:Log(name .. "notcancel", string.format(L["Skipped cancelling %s flagged to post at fallback when market is below threshold."], itemLink))
				tempList[name] = true
			end
		-- It is supposed to be cancelled!
		elseif( wasSold == 0 and lowestOwner ) then
			buyout = buyout / quantity
			bid = bid / quantity
			
			local threshold = self:GetConfigValue(itemID, "threshold")
			local fallback = self:GetConfigValue(itemID, "fallback")
			local priceDifference = QuickAuctions.Scan:CompareLowestToSecond(itemID, lowestBuyout)
			local priceThreshold = self:GetConfigValue(itemID, "priceThreshold")
			
			-- Lowest is the player, and the difference between the players lowest and the second lowest are too far apart
			if( isPlayer and priceDifference and priceDifference >= priceThreshold ) then
				-- The item that the difference is too high is actually on the tier that was too high as well
				-- so cancel it, the reason this check is done here is so it doesn't think it undercut itself.
				if( math.floor(lowestBuyout) == math.floor(buyout) ) then
					if( isTest ) then return true end
					
					if( not tempList[name] ) then
						tempList[name] = true
						QuickAuctions:Log(name .. "diffcancel", string.format(L["Price threshold on %s at %s, second lowest is |cfffed000%d%%|r higher and above the |cfffed000%d%%|r threshold, cancelling"], itemLink, QuickAuctions:FormatTextMoney(lowestBuyout, true), priceDifference * 100, priceThreshold * 100))
					end
	
					totalToCancel = totalToCancel + 1
					totalCancelled = totalCancelled + 1
					CancelAuction(i)
				end
				
			-- They aren't us (The player posting), or on our whitelist so easy enough
			-- They are on our white list, but they undercut us, OR they matched us but the bid is lower
			-- The player is the only one with it on the AH and it's below the threshold
			elseif( ( not isPlayer and not isWhitelist ) or
				( isWhitelist and ( buyout > lowestBuyout or ( buyout == lowestBuyout and lowestBid < bid ) ) ) or
				( QuickAuctions.db.global.smartCancel and QuickAuctions.Scan:IsPlayerOnly(itemID) and buyout < fallback ) ) then
				
				local undercutBuyout, undercutBid, undercutOwner
				if( QuickAuctions.db.factionrealm.player[lowestOwner] ) then
					undercutBuyout, undercutBid, undercutOwner = QuickAuctions.Scan:GetSecondLowest(itemID, lowestBuyout)
				end

				undercutBuyout = undercutBuyout or lowestBuyout
				undercutBid = undercutBid or lowestBid
				undercutOwner = undercutOwner or lowestOwner
				
				-- Don't cancel if the buyout is equal, or below our threshold
				if( QuickAuctions.db.global.smartCancel and lowestBuyout <= threshold and not QuickAuctions.Scan:IsPlayerOnly(itemID)) then
					if( not tempList[name] ) then
						tempList[name] = true
						
						QuickAuctions:Log(name .. "notcancel", string.format(L["Undercut on %s by |cfffed000%s|r, their buyout %s, yours %s (per item), threshold is %s not cancelling"], itemLink, undercutOwner, QuickAuctions:FormatTextMoney(undercutBuyout, true), QuickAuctions:FormatTextMoney(buyout, true), QuickAuctions:FormatTextMoney(threshold, true)))
					end
				-- Don't cancel an auction if it has a bid and we're set to not cancel those
				elseif( not QuickAuctions.db.global.cancelWithBid and activeBid > 0 ) then
					if( not isTest ) then
						QuickAuctions:Log(name .. "bid", string.format(L["Undercut on %s by |cfffed000%s|r, but %s placed a bid of %s so not cancelling"], itemLink, undercutOwner, highBidder, QuickAuctions:FormatTextMoney(activeBid, true)))
					end
				else
					if( isTest ) then return true end
					if( not tempList[name] ) then
						tempList[name] = true
						if( QuickAuctions.Scan:IsPlayerOnly(itemID) and buyout < fallback ) then
							QuickAuctions:Log(name .. "cancel", string.format(L["You are the only one posting %s, the fallback is %s (per item), cancelling so you can relist it for more gold"], itemLink, QuickAuctions:FormatTextMoney(fallback)))
						else
							QuickAuctions:Log(name .. "cancel", string.format(L["Undercut on %s by |cfffed000%s|r, buyout %s, yours %s (per item)"], itemLink, undercutOwner, QuickAuctions:FormatTextMoney(undercutBuyout, true), QuickAuctions:FormatTextMoney(buyout, true)))
						end
					end
					
					totalToCancel = totalToCancel + 1
					totalCancelled = totalCancelled + 1
					CancelAuction(i)
				end
			end
		end
	end
end

-- Makes sure that the items that stack the lowest are posted first to free up space for items
-- that stack higher
local function sortByStack(a, b)
	local aStack = select(8, GetItemInfo(a)) or 20
	local bStack = select(8, GetItemInfo(b)) or 20
	
	if( aStack == bStack ) then
		return GetItemCount(a) < GetItemCount(b)
	end
	
	return aStack < bStack
end

function Manage:PostScan()
	self:StartLog()
	self:UpdateReverseLookup()
	QuickAuctions:LockButtons()
	
	table.wipe(postQueue)
	table.wipe(scanList)
	table.wipe(tempList)
	table.wipe(status)
	
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
	status.totalPostQueued = 0
	status.totalScanQueue = #(postQueue)
	status.queueTable = postQueue
	--QuickAuctions.Split:ScanStarted()
	QuickAuctions.Post:ScanStarted()
	--QuickAuctions.Split:Start()
	QuickAuctions.Scan:StartItemScan(scanList)
end

function Manage:StopPosting()
	table.wipe(postQueue)
	
	status.isManaging = nil
	status.totalPostQueued = 0
	status.totalScanQueue = 0
	self:StopLog()
	
	--QuickAuctions.Split:ScanStopped()
	--QuickAuctions.Split:Stop()
	QuickAuctions.Post:Stop()
	QuickAuctions:UnlockButtons()
end

function Manage:PostItems(itemID)
	if( not itemID ) then return end
	
	local name, itemLink, _, _, _, _, _, stackCount = GetItemInfo(itemID)
	local perAuction = math.min(stackCount, self:GetConfigValue(itemID, "perAuction"))
	local maxCanPost = math.floor(GetItemCount(itemID) / perAuction)
	local postCap = self:GetConfigValue(itemID, "postCap")
	local threshold = self:GetConfigValue(itemID, "threshold")
	local auctionsCreated, activeAuctions = 0, 0
	
	QuickAuctions:Log(name, string.format(L["Queued %s to be posted"], itemLink))
	
	if( maxCanPost == 0 ) then
		QuickAuctions:Log(name, string.format(L["Skipped %s need |cff20ff20%d|r for a single post, have |cffff2020%d|r"], itemLink, perAuction, GetItemCount(itemID)))
		return
	end

	local buyout, bid, _, isPlayer, isWhitelist = QuickAuctions.Scan:GetLowestAuction(itemID)
	
	-- Check if we're going to go below the threshold
	if( buyout and not self:GetBoolConfigValue(itemID, "autoFallback") ) then
		-- Smart undercutting is enabled, and the auction is for at least 1 gold, round it down to the nearest gold piece
		local testBuyout = buyout
		if( QuickAuctions.db.global.smartUndercut and testBuyout > COPPER_PER_GOLD ) then
			testBuyout = math.floor(buyout / COPPER_PER_GOLD) * COPPER_PER_GOLD
		else
			testBuyout = testBuyout - self:GetConfigValue(itemID, "undercut")
		end
				
		if( testBuyout < threshold and buyout <= threshold ) then
			QuickAuctions:Log(name, string.format(L["Skipped %s lowest buyout is %s threshold is %s"], itemLink, QuickAuctions:FormatTextMoney(buyout, true), QuickAuctions:FormatTextMoney(threshold, true)))
			return
		end
	end

	-- Auto fallback is on, and lowest buyout is below threshold, instead of posting them all
	-- use the post count of the fallback tier
	if( self:GetBoolConfigValue(itemID, "autoFallback") and buyout and buyout <= threshold ) then	
		local fallbackBuyout = QuickAuctions.Manage:GetConfigValue(itemID, "fallback")
		local fallbackBid = fallbackBuyout * QuickAuctions.Manage:GetConfigValue(itemID, "bidPercent")
		activeAuctions = QuickAuctions.Scan:GetPlayerAuctionCount(itemID, fallbackBuyout, fallbackBid)
			
	-- Either the player or a whitelist person is the lowest teir so use this tiers quantity of items
	elseif( isPlayer or isWhitelist ) then
		activeAuctions = QuickAuctions.Scan:GetPlayerAuctionCount(itemID, buyout or 0, bid or 0)
	end
	
	-- If we have a post cap of 20, and 10 active auctions, but we can only have 5 of the item then this will only let us create 5 auctions
	-- however, if we have 20 of the item it will let us post another 10
	auctionsCreated = math.min(postCap - activeAuctions, maxCanPost)
	if( auctionsCreated <= 0 ) then
		QuickAuctions:Log(name, string.format(L["Skipped %s posted |cff20ff20%d|r of |cff20ff20%d|r already"], itemLink, activeAuctions, postCap))
		return
	end
	
	-- Warn that they don't have enough to post
	if( maxCanPost < postCap ) then
		QuickAuctions:Log(name, string.format(L["Queued %s to be posted (Cap is |cffff2020%d|r, only can post |cffff2020%d|r need to restock)"], itemLink, postCap, maxCanPost))
	end

	-- The splitter will automatically pass items to the post queuer, meaning if an item doesn't even stack it will handle that just fine
	stats[itemID] = (stats[itemID] or 0) + auctionsCreated
	status.totalPostQueued = status.totalPostQueued + auctionsCreated
	QuickAuctions.Post:QueueItem(itemID, perAuction, auctionsCreated)
	--QuickAuctions.Split:QueueItem(itemID, perAuction)
	--QuickAuctions.Split:UpdateBags()
end

-- Log handler
function Manage:QA_QUERY_UPDATE(event, type, filter, ...)
	if( not filter ) then return end
	
	if( type == "retry" ) then	
		local page, totalPages, retries, maxRetries = ...
		QuickAuctions:Log(filter, string.format(L["Retry |cfffed000%d|r of |cfffed000%d|r for %s"], retries, maxRetries, filter))
	elseif( type == "page" ) then
		local page, totalPages = ...
		QuickAuctions:Log(filter, string.format(L["Scanning page |cfffed000%d|r of |cfffed000%d|r for %s"], page, totalPages, filter))
	elseif( type == "done" ) then
		local page, totalPages = ...
		QuickAuctions:Log(filter, string.format(L["Scanned page |cfffed000%d|r of |cfffed000%d|r for %s"], page, totalPages, filter))
		QuickAuctions:SetButtonProgress("status", status.totalScanQueue - #(status.queueTable), status.totalScanQueue)

		-- Do everything we need to get it splitted/posted
		for i=#(postQueue), 1, -1 do
			if( GetItemInfo(postQueue[i]) == filter ) then
				self:PostItems(table.remove(postQueue, i))
			end
		end
	elseif( type == "next" ) then
		QuickAuctions:Log(filter, string.format(L["Scanning %s"], filter))
	end
end

function Manage:QA_START_SCAN(event, type, total)
	QuickAuctions:WipeLog()
	QuickAuctions:Log("scanstatus", string.format(L["Scanning |cfffed000%d|r items..."], total or 0))
	
	status.totalPostQueued = 0
	table.wipe(stats)
end

function Manage:QA_STOP_SCAN(event, interrupted)
	self:StopLog()
	status.isManaging = nil
	--QuickAuctions.Split:ScanStopped()

	if( interrupted ) then
		QuickAuctions:Log("scaninterrupt", L["Scan interrupted before it could finish"])
		return
	end

	QuickAuctions:Log("scandone", L["Scan finished!"], true)
	
	if( status.isCancelling ) then
		QuickAuctions:Log("cancelstatus", L["Starting to cancel..."])
		self:ReadyToCancel()
	end
end





