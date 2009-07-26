local Post = QuickAuctions:NewModule("Post", "AceEvent-3.0")
local L = QuickAuctionsLocals
local status = QuickAuctions.status
local postQueue, postTotal, overallTotal = {}, {}, 0
local POST_TIMEOUT = 5
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
	QuickAuctions:Log(string.format(L["Finished posting |cfffed000%d|r items"], overallTotal))
	self:UnregisterEvent("CHAT_MSG_SYSTEM")
	
	table.wipe(postQueue)
	table.wipe(postTotal)
	
	status.isPosting = nil
	frame:Hide()
end

-- Tells the poster that nothing new has happened long enough it can shut off
frame.timeElapsed = 0
frame:SetScript("OnUpdate", function(self, elapsed)
	self.timeElapsed = self.timeElapsed - elapsed
	if( self.timeElapsed <= 0 ) then
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
		
		if( overallTotal >= status.totalPostQueued ) then
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
	local buyout = lowestBuyout or QuickAuctions.Manage:GetConfigValue(itemID, "fallback")
	local bid = lowestBid or buyout * QuickAuctions.Manage:GetConfigValue(itemID, "bidPercent")
	local fallbackCap, buyoutTooLow, bidTooLow
	
	-- We got undercut :(
	if( lowestOwner and not isPlayer and not isWhitelist ) then
		local goldTotal = buyout / COPPER_PER_GOLD
		-- Smart undercutting is enabled, and the auction is for at least 1 gold, round it down to the nearest gold piece
		-- the math.floor(blah) == blah check is so we only do a smart undercut if the price isn't a whole gold piece and not a partial
		if( QuickAuctions.db.profile.smartUndercut and lowestBuyout > COPPER_PER_GOLD and goldTotal ~= math.floor(goldTotal) ) then
			buyout = math.floor(goldTotal) * COPPER_PER_GOLD
		else
			buyout = buyout - QuickAuctions.Manage:GetConfigValue(itemID, "undercut")
		end
		
		-- Mostly for protection, if the buyout is removed then it will default to undercutting by a copper
		if( buyout <= 0 ) then
			buyout = lowestBuyout - 1
			buyoutTooLow = true
		end
		
		bid = math.floor(bid * QuickAuctions.Manage:GetConfigValue(itemID, "bidPercent"))

		-- Check if we're posting something too high
		local fallback = QuickAuctions.Manage:GetConfigValue(itemID, "fallback")
		if( buyout > (fallback * QuickAuctions.Manage:GetConfigValue(itemID, "fallbackCap")) ) then
			buyout = fallback
			bid = buyout * QuickAuctions.Manage:GetConfigValue(itemID, "bidPercent")
			
			fallbackCap = true
		end

		local threshold = QuickAuctions.Manage:GetConfigValue(itemID, "threshold")
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
	
	if( not lowestOwner ) then
		QuickAuctions:Log(name, string.format(L["Posting %s%s (%d/%d) bid %s, buyout %s (No other auctions up)"], itemLink, quantityText, postTotal[itemID], QuickAuctions.Manage.stats[itemID] or 0, QuickAuctions:FormatTextMoney(bid), QuickAuctions:FormatTextMoney(buyout)))
	elseif( buyoutTooLow ) then
		QuickAuctions:Log(name, string.format(L["Posting %s%s (%d/%d) bid %s, buyout %s (Buyout went below zero, undercut by 1 copper instead)"], itemLink, quantityText, postTotal[itemID], QuickAuctions.Manage.stats[itemID] or 0, QuickAuctions:FormatTextMoney(bid), QuickAuctions:FormatTextMoney(buyout)))
	elseif( fallbackCap ) then
		QuickAuctions:Log(name, string.format(L["Posting %s%s (%d/%d) bid %s, buyout %s (Forced to fallback cap, lowest price was too high)"], itemLink, quantityText, postTotal[itemID], QuickAuctions.Manage.stats[itemID] or 0, QuickAuctions:FormatTextMoney(bid), QuickAuctions:FormatTextMoney(buyout)))
	elseif( bidTooLow ) then
		QuickAuctions:Log(name, string.format(L["Posting %s%s (%d/%d) bid %s, buyout %s (Increased bid price due to going below thresold)"], itemLink, quantityText, postTotal[itemID], QuickAuctions.Manage.stats[itemID] or 0, QuickAuctions:FormatTextMoney(bid), QuickAuctions:FormatTextMoney(buyout)))
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






