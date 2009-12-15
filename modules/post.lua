local Post = QuickAuctions:NewModule("Post", "AceEvent-3.0")
local L = QuickAuctionsLocals
local status = QuickAuctions.status
local postQueue, postTotal, overallTotal, scanRunning = {}, {}, 0
local POST_TIMEOUT = 20
local frame = CreateFrame("Frame")
frame:Hide()

function Post:OnInitialize()
	self:RegisterMessage("QA_AH_CLOSED", "AuctionHouseClosed")
end

function Post:AuctionHouseClosed()
	if( status.isPosting and not status.isScanning ) then
		self:Stop()
		QuickAuctions:Print(L["Posting was interrupted due to the Auction House was closed."])
	end
end

function Post:ScanStarted()
	scanRunning = true
end

function Post:ScanStopped()
	scanRunning = nil
	
	if( #(postQueue) == 0 and overallTotal >= status.totalPostQueued ) then
		self:Stop()
	end
end

function Post:Start()
	if( not status.isPosting ) then
		overallTotal = 0
		status.isPosting = true
		self:RegisterEvent("CHAT_MSG_SYSTEM")
		
		frame.timeElapsed = POST_TIMEOUT
		frame:Show()
	end
end

function Post:Stop()
	if( not status.isPosting ) then return end
	
	self:UnregisterEvent("CHAT_MSG_SYSTEM")
	if( overallTotal > 0 ) then
		QuickAuctions:Log(string.format(L["Finished posting |cfffed000%d|r items"], overallTotal))
	else
		QuickAuctions:Log(L["No auctions posted"])
	end
	
	QuickAuctions:UnlockButtons()
	
	table.wipe(postQueue)
	table.wipe(postTotal)
	
	overallTotal = 0
	status.isPosting = nil
	frame:Hide()
end

-- Tells the poster that nothing new has happened long enough it can shut off
frame.timeElapsed = 0
frame:SetScript("OnUpdate", function(self, elapsed)
	self.timeElapsed = self.timeElapsed - elapsed
	if( self.timeElapsed <= 0 and not scanRunning ) then
		self:Hide()
		Post:Stop()
	end
end)

-- Check if an auction was posted and move on if so
function Post:CHAT_MSG_SYSTEM(event, msg)
	if( msg == ERR_AUCTION_STARTED ) then
		-- Update posted count
		overallTotal = overallTotal + 1
		QuickAuctions:SetButtonProgress("post", overallTotal, status.totalPostQueued)
		
		if( overallTotal >= status.totalPostQueued and not scanRunning ) then
			Post:Stop()
			return
		end
		
		-- Also set our timeout so it knows if it can fully stop
		frame.timeElapsed = POST_TIMEOUT
		frame:Show()
	end
end

function Post:PostAuction(queue)
	if( not queue ) then return end
	
	local itemID, bag, slot = queue.link, queue.bag, queue.slot
	local name, itemLink = GetItemInfo(itemID)
	local lowestBuyout, lowestBid, lowestOwner, isWhitelist, isPlayer = QuickAuctions.Scan:GetLowestAuction(itemID)
	
	postTotal[itemID] = (postTotal[itemID] or 0) + 1
	
	-- Set our initial costs
	local fallbackCap, buyoutTooLow, bidTooLow, autoFallback, bid, buyout, differencedPrice, buyoutThresholded
	local fallback = QuickAuctions.Manage:GetConfigValue(itemID, "fallback")
	local threshold = QuickAuctions.Manage:GetConfigValue(itemID, "threshold")
	local priceThreshold = QuickAuctions.Manage:GetConfigValue(itemID, "priceThreshold")
	local priceDifference = QuickAuctions.Scan:CompareLowestToSecond(itemID, lowestBuyout)
	
	-- Difference between lowest that we have and second lowest is too high, undercut second lowest instead
	if( isPlayer and priceDifference and priceDifference >= priceThreshold ) then
		differencedPrice = true
		lowestBuyout, lowestBid = QuickAuctions.Scan:GetSecondLowest(itemID, lowestBuyout)
	end
	
	-- No other auctions up, default to fallback
	if( not lowestOwner ) then
		buyout = QuickAuctions.Manage:GetConfigValue(itemID, "fallback")
		bid = buyout * QuickAuctions.Manage:GetConfigValue(itemID, "bidPercent")
	-- Item goes below the threshold price, default it to fallback
	elseif( QuickAuctions.Manage:GetBoolConfigValue(itemID, "autoFallback") and lowestBuyout <= threshold ) then
		autoFallback = true
		buyout = QuickAuctions.Manage:GetConfigValue(itemID, "fallback")
		bid = buyout * QuickAuctions.Manage:GetConfigValue(itemID, "bidPercent")
	-- Either we already have one up or someone on the whitelist does
	elseif( ( isPlayer or isWhitelist ) and not differencedPrice ) then
		buyout = lowestBuyout
		bid = lowestBid
	-- We got undercut :(
	else
		local goldTotal = lowestBuyout / COPPER_PER_GOLD
		-- Smart undercutting is enabled, and the auction is for at least 1 gold, round it down to the nearest gold piece
		-- the math.floor(blah) == blah check is so we only do a smart undercut if the price isn't a whole gold piece and not a partial
		if( QuickAuctions.db.profile.smartUndercut and lowestBuyout > COPPER_PER_GOLD and goldTotal ~= math.floor(goldTotal) ) then
			buyout = math.floor(goldTotal) * COPPER_PER_GOLD
		else
			buyout = lowestBuyout - QuickAuctions.Manage:GetConfigValue(itemID, "undercut")
		end
		
		-- Check if we're posting something too high
		if( buyout > (fallback * QuickAuctions.Manage:GetConfigValue(itemID, "fallbackCap")) ) then
			buyout = fallback
			fallbackCap = true
		end
		
		-- Check if we're posting too low!
		if( buyout < threshold ) then
			buyout = threshold
			buyoutThresholded = true
		end
		
		bid = math.floor(buyout * QuickAuctions.Manage:GetConfigValue(itemID, "bidPercent"))

		-- Check if the bid is too low
		if( bid < threshold ) then
			bid = threshold
			bidTooLow = true
		end
	end
	
	local quantity = select(2, GetContainerItemInfo(bag, slot))
	local quantityText = quantity > 1 and " x " .. quantity or ""
	
	-- Increase the bid/buyout based on how many items we're posting
	bid = math.floor(bid * quantity)
	buyout = math.floor(buyout * quantity)
	
	if( buyoutThresholded ) then
		QuickAuctions:Log(name, string.format(L["Posting %s%s (%d/%d) bid %s, buyout %s (Increased buyout price due to going below thresold)"], itemLink, quantityText, postTotal[itemID], QuickAuctions.Manage.stats[itemID] or 0, QuickAuctions:FormatTextMoney(bid), QuickAuctions:FormatTextMoney(buyout)))
	elseif( buyoutTooLow ) then
		QuickAuctions:Log(name, string.format(L["Posting %s%s (%d/%d) bid %s, buyout %s (Buyout went below zero, undercut by 1 copper instead)"], itemLink, quantityText, postTotal[itemID], QuickAuctions.Manage.stats[itemID] or 0, QuickAuctions:FormatTextMoney(bid), QuickAuctions:FormatTextMoney(buyout)))
	elseif( autoFallback ) then
		QuickAuctions:Log(name, string.format(L["Posting %s%s (%d/%d) bid %s, buyout %s (Forced to fallback price, market below threshold)"], itemLink, quantityText, postTotal[itemID], QuickAuctions.Manage.stats[itemID] or 0, QuickAuctions:FormatTextMoney(bid), QuickAuctions:FormatTextMoney(buyout)))
	elseif( differencedPrice ) then
		QuickAuctions:Log(name, string.format(L["Posting %s%s (%d/%d) bid %s, buyout %s (Price difference too high, used second lowest price intead)"], itemLink, quantityText, postTotal[itemID], QuickAuctions.Manage.stats[itemID] or 0, QuickAuctions:FormatTextMoney(bid), QuickAuctions:FormatTextMoney(buyout)))
	elseif( fallbackCap ) then
		QuickAuctions:Log(name, string.format(L["Posting %s%s (%d/%d) bid %s, buyout %s (Forced to fallback price, lowest price was too high)"], itemLink, quantityText, postTotal[itemID], QuickAuctions.Manage.stats[itemID] or 0, QuickAuctions:FormatTextMoney(bid), QuickAuctions:FormatTextMoney(buyout)))
	elseif( bidTooLow ) then
		QuickAuctions:Log(name, string.format(L["Posting %s%s (%d/%d) bid %s, buyout %s (Increased bid price due to going below thresold)"], itemLink, quantityText, postTotal[itemID], QuickAuctions.Manage.stats[itemID] or 0, QuickAuctions:FormatTextMoney(bid), QuickAuctions:FormatTextMoney(buyout)))
	elseif( not lowestOwner ) then
		QuickAuctions:Log(name, string.format(L["Posting %s%s (%d/%d) bid %s, buyout %s (No other auctions up)"], itemLink, quantityText, postTotal[itemID], QuickAuctions.Manage.stats[itemID] or 0, QuickAuctions:FormatTextMoney(bid), QuickAuctions:FormatTextMoney(buyout)))
	else
		QuickAuctions:Log(name, string.format(L["Posting %s%s (%d/%d) bid %s, buyout %s"], itemLink, quantityText, postTotal[itemID], QuickAuctions.Manage.stats[itemID] or 0, QuickAuctions:FormatTextMoney(bid), QuickAuctions:FormatTextMoney(buyout)))
	end
		
	PickupContainerItem(bag, slot)
	ClickAuctionSellItemButton()
	StartAuction(bid, buyout, QuickAuctions.Manage:GetConfigValue(itemID, "postTime") * 60)
end

-- This looks a bit odd I know, not sure if I want to keep it like this (or if I even can) where it posts something as soon as it can
-- I THINK it will work fine, but if it doesn't I'm going to change it back to post once, wait for event, post again, repeat
function Post:QueueItem(link, bag, slot)
	table.insert(postQueue, {link = link, bag = bag, slot = slot})
	
	self:Start()
	self:PostAuction(table.remove(postQueue, 1))
end






