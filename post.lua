local Post = QuickAuctions:NewModule("Post", "AceEvent-3.0")
local L = QuickAuctionsLocals
local status = QuickAuctions.status
local postQueue, postTotal, overallTotal = {}, {}, 0
local POST_TIMEOUT = 5
local frame = CreateFrame("Frame")
frame:Hide()

function Post:OnInitialize()
	self:RegisterMessage("SUF_AH_CLOSED", "AuctionHouseClosed")
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
		frame:Show()
	end
end

function Post:Stop()
	QuickAuctions:Log(string.format(L["Finished posting %d items"], overallTotal))
	
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
		self:PostAuction(table.remove(postQueue, 1))
	end
end

function Post:PostAuction(queue)
	if( not queue ) then return end
	
	local link, bag, slot = queue.link, queue.bag, queue.slot
	local name = GetItemInfo(link)
	local lowestBuyout, lowestBid, lowestOwner, isWhitelist, isPlayer = QuickAuctions.Scan:GetLowestAuction(link)
	
	postTotal[link] = (postTotal[link] or 0) + 1
	overallTotal = overallTotal + 1
	
	-- Also set our timeout so it knows if it can fully stop
	frame.timeElapsed = POST_TIMEOUT
	frame:Show()

	-- Set our initial costs
	local buyout = lowestBuyout or QuickAuctions.Manage:GetConfigValue(link, "fallback")
	local bid = lowestBid or buyout * QuickAuctions.Manage:GetConfigValue(link, "bidPercent")
	local fallbackCap, buyoutLow
	
	-- We got undercut :(
	if( lowestOwner and not isPlayer and not isWhitelist ) then
		-- Smart undercutting is enabled, and the auction is for at least 1 gold, round it down to the nearest gold piece
		if( QuickAuctions.db.profile.smartUndercut and lowestBuyout > COPPER_PER_GOLD ) then
			buyout = math.floor(buyout / COPPER_PER_GOLD) * COPPER_PER_GOLD
		else
			buyout = buyout - QuickAuctions.Manage:GetConfigValue(link, "undercut")
		end
		
		-- Mostly for protection, if the buyout is removed then it will default to undercutting by a copper
		if( buyout <= 0 ) then
			buyout = lowestBuyout - 1
			buyoutLow = true
		end
		
		bid = math.floor(bid * QuickAuctions.Manage:GetConfigValue(link, "bidPercent"))

		-- Check if we're posting something too high
		local fallback = QuickAuctions.Manage:GetConfigValue(link, "fallback")
		if( buyout > (fallback * QuickAuctions.Manage:GetConfigValue(link, "fallbackCap")) ) then
			buyout = fallback
			bid = buyout * QuickAuctions.Manage:GetConfigValue(link, "bidPercent")
			
			fallbackCap = true
		end
	end
	
	local quantity = select(2, GetContainerItemInfo(bag, slot))
	if( not lowestOwner ) then
		QuickAuctions:Log(string.format(L["Posted %s (%d/%d) bid %s, buyout %s (No other auctions up)"], name, postTotal[link], QuickAuctions.Manage.stats[link], QuickAuctions:FormatTextMoney(bid), QuickAuctions:FormatTextMoney(buyout)), true)
	elseif( buyoutLow ) then
		QuickAuctions:Log(string.format(L["Posted %s (%d/%d) bid %s, buyout %s (Buyout went below zero, undercut by 1 copper instead)"], name, postTotal[link], QuickAuctions.Manage.stats[link], QuickAuctions:FormatTextMoney(bid), QuickAuctions:FormatTextMoney(buyout)), true)
	elseif( fallbackCap ) then
		QuickAuctions:Log(string.format(L["Posted %s (%d/%d) bid %s, buyout %s (Forced to fallback cap, lowest price was too high)"], name, postTotal[link], QuickAuctions.Manage.stats[link], QuickAuctions:FormatTextMoney(bid), QuickAuctions:FormatTextMoney(buyout)), true)
	else
		QuickAuctions:Log(string.format(L["Posted %s (%d/%d) bid %s, buyout %s"], name, postTotal[link], QuickAuctions.Manage.stats[link], QuickAuctions:FormatTextMoney(bid), QuickAuctions:FormatTextMoney(buyout)), true)
	end
		
	PickupContainerItem(bag, slot)
	ClickAuctionSellItemButton()
	StartAuction(bid * quantity, buyout * quantity, QuickAuctions.Manage:GetConfigValue(link, "postTime") * 60)
end

function Post:QueueItem(link, bag, slot)
	table.insert(postQueue, {link = link, bag = bag, slot = slot})

	self:Start()
	self:PostAuction(table.remove(postQueue, 1))
end






