QA = {}

local isScanning, searchFilter, scanType, scanTotal, scanIndex
local page, badRetries, totalCancels, totalPosts = 0, 0, 0, 0
local activeAuctions, scanList, priceList, queryQueue, postList = {}, {}, {}, {}, {}
local AHTime = 12 * 60

function QA:OnInitialize()
	QuickAuctionsDB = QuickAuctionsDB or {undercutBy = 100, uncut = false, smartUndercut = true, threshold = (100 * 10000), specialThresh = {}, fallback = 2250000, specialFallback = {}, postCap = 2, whitelist = {}}
		
	-- Interrupt our scan if they start to browse
	--[[
	local orig = BrowseSearchButton:GetScript("OnClick")
	BrowseSearchButton:SetScript("OnClick", function(self, ...)
		isScanning = nil
		orig(self, ...)
	end)
	]]
	
	-- Hook the query function so we know what we last sent a search on
	local orig_QueryAuctionItems = QueryAuctionItems
	QueryAuctionItems = function(name, ...)
		if( CanSendAuctionQuery() ) then
			searchFilter = name
		end
		
		return orig_QueryAuctionItems(name, ...)
	end
	
	-- Scan our posted gems
	local button = CreateFrame("Button", nil, AuctionFrameAuctions, "UIPanelButtonTemplate")
	button:SetPoint("TOPRIGHT", AuctionFrameAuctions, "TOPRIGHT", 49, -15)
	button:SetText("Scan Gems")
	button:SetWidth(100)
	button:SetHeight(18)
	button:SetScript("OnClick", function(self)
		QA:ScanAuctions()
	end)
	
	self.scanButton = button

	-- Post inventory gems
	local button = CreateFrame("Button", nil, AuctionFrameAuctions, "UIPanelButtonTemplate")
	button:SetPoint("TOPRIGHT", self.scanButton, "TOPLEFT", 0, 0)
	button:SetText("Post Gems")
	button:SetWidth(100)
	button:SetHeight(18)
	button:SetScript("OnClick", function(self)
		QA:PostAuctions()
	end)
	
	self.postButton = button
	
	-- Hook chat to block auction post/cancels, and also let us know when we're done posting
	local orig_ChatFrame_SystemEventHandler = ChatFrame_SystemEventHandler
	ChatFrame_SystemEventHandler = function(self, event, msg)
		if( msg == "Auction cancelled." and totalCancels > 0 ) then
			totalCancels = totalCancels - 1
			if( totalCancels <= 0 ) then
				totalCancels = 0
				QA:Print("Done cancelling auctions.")
			end
			return true

		elseif( msg == "Auction created." and totalPosts > 0 ) then
			totalPosts = totalPosts - 1
			if( totalPosts <= 0 ) then
				totalPosts = 0
				QA:Print("Done posting auctions.")

				QA.postButton:Enable()
				QA.postButton:SetText("Post Gems")
			else
				QA.postButton:Disable()
				QA.postButton:SetFormattedText("%d/%d items", totalPosts, QA.postButton.totalPosts)
			end
			
			return true
		end
	end
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

function QA:IsValidGem(link)
	local _, _, _, _, _, itemType, _, stackCount = GetItemInfo(link)
	if( itemType ~= "Gem" ) then
		return nil
	end
	
	if( stackCount == 1 or ( stackCount == 20 and QuickAuctionsDB.uncut ) ) then
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
		-- Figure out if this is a gem
		self.tooltip:ClearLines()
		self.tooltip:SetAuctionItem("owner", i)
		
		local name = GetAuctionItemInfo("owner", i)
		local itemLink = select(2, self.tooltip:GetItem())
		
		if( itemLink and self:IsValidGem(itemLink) and select(13, GetAuctionItemInfo("owner", i)) == 0 ) then
			hasItems = true
			tempList[name] = true
		end
	end
	
	if( hasItems ) then
		self:StartScan(tempList, "scan")
	end
end

function QA:PostAuctions()
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

	for bag=0, 4 do
		for slot=1, GetContainerNumSlots(bag) do
			local link = GetContainerItemLink(bag, slot)
			if( link ) then
				local name = GetItemInfo(link)
				-- Make sure we aren't already at the post cap, to reduce the item scans needed
				if( not tempList[name] and self:IsValidGem(link) and ( not activeAuctions[name] or ( activeAuctions[name] < QuickAuctionsDB.postCap ) ) ) then
					table.insert(postList, name)
					tempList[name] = true
				end
			end
		end
	end
	
	self:StartScan(tempList, "post")
end

function QA:StartScan(list, type)
	for i=#(scanList), 1, -1 do table.remove(scanList, i) end
	
	-- Prevents duplicate entries
	for name in pairs(list) do
		table.insert(scanList, name)
	end

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

function QA:CheckItems()
	for k in pairs(tempList) do tempList[k] = nil end
	
	self.scanButton:Enable()
	self.scanButton:SetText("Scan Gems")
	
	totalCancels = 0
	
	for i=1, (GetNumAuctionItems("owner")) do
		local name, texture, quantity, _, _, _, minBid, _, buyoutPrice, _, _, owner, wasSold = GetAuctionItemInfo("owner", i)     
		local priceData = priceList[name]
		
		if( priceData and wasSold == 0 ) then
			-- Check if buyout, our minimum bid are equal or lower than ours
			-- if they aren't us
			-- and if they aren't on our whitelist (We don't care if they undercut us)
			if( ( priceData.buyout < buyoutPrice or ( priceData.buyout == buyoutPrice and priceData.minBid <= minBid ) ) and priceData.owner ~= owner and not QuickAuctionsDB.whitelist[priceData.owner] ) then
				if( not tempList[name] ) then
					print(string.format("Undercut on %s, by %s, buyout %s, bid %s, our buyout %s, our bid %s", name, priceData.owner, self:FormatTextMoney(priceData.buyout), self:FormatTextMoney(priceData.minBid), self:FormatTextMoney(buyoutPrice), self:FormatTextMoney(minBid)))
				end

				totalCancels = totalCancels + 1

				tempList[name] = true
				CancelAuction(i)
			end
		end
	end
end

function QA:PostItems()
	self.scanButton:Enable()
	self.scanButton:SetText("Scan Gems")

	-- Quick check for threshold info
	for i=#(postList), 1, -1 do
		local name = postList[i]
		local priceData = priceList[name]
		local threshold = QuickAuctionsDB.specialThresh[name] or QuickAuctionsDB.threshold
		
		if( priceData and priceData.buyout <= threshold ) then
			print(string.format("Not posting %s, because the buyout is %s and the threshold is %s.", name, self:FormatTextMoney(priceData.buyout), self:FormatTextMoney(QuickAuctionsDB.threshold)))
			table.remove(postList, i)
		end
	end

	-- Save money
	local money = GetMoney()
	
	if( #(postList) > 0 ) then
		self.postButton.totalPosts = 0
		self.postButton:Disable()
	end
	
	-- Start posting
	for i=#(postList), 1, -1 do
		local name = table.remove(postList, i)
		local priceData = priceList[name]
		
		local totalPosted = activeAuctions[name] or 0
		local minBid, buyout
		if( priceData and priceData.owner ) then
			minBid = priceData.minBid
			buyout = priceData.buyout
						
			-- Don't undercut people on our whitelist, match them
			if( not QuickAuctionsDB.whitelist[priceData.owner] ) then
				buyout = buyout / 10000
				
				-- If smart undercut is on, then someone who posts an auction of 99g99s0c, it will auto undercut to 99g
				-- instead of 99g99s0c - undercutBy
				if( not QuickAuctionsDB.smartUndercut or  buyout == math.floor(buyout) ) then
					buyout = ( buyout * 10000 ) - QuickAuctionsDB.undercutBy
				else
					buyout = math.floor(buyout) * 10000
				end

				minBid = buyout
			end
		
		-- No other data available, default to 225g a cut
		else
			minBid = QuickAuctionsDB.specialFallback[name] or QuickAuctionsDB.fallback
			buyout = QuickAuctionsDB.specialFallback[name] or QuickAuctionsDB.fallback
			
			print(string.format("No data found for %s, using %s buyout and %s bid default.", name, self:FormatTextMoney(buyout), self:FormatTextMoney(minBid)))
		end
		
		-- Find the item in our inventory
		for bag=0, 4 do
			for slot=1, GetContainerNumSlots(bag) do
				local link = GetContainerItemLink(bag, slot)
				if( link ) then
					local itemName = GetItemInfo(link)

					if( name == itemName ) then
						totalPosted = totalPosted + 1

						-- Hit limit, done with this item
						if( totalPosted > QuickAuctionsDB.postCap ) then
							break
						end

						-- Post this auction
						PickupContainerItem(bag, slot)
						ClickAuctionSellItemButton()
						
						-- Make sure we can post this auction, we save the money and subtract it here
						-- because we chain post before the server gives us the new money
						money = money - CalculateAuctionDeposit(AHTime)
						if( money >= 0 ) then
							totalPosts = totalPosts + 1
							StartAuction(minBid, buyout, AHTime)

							-- Update post totals
							self.postButton.totalPosts = self.postButton.totalPosts + 1
							self.postButton:Disable()
							self.postButton:SetFormattedText("%d/%d items", totalPosts, self.postButton.totalPosts)
						else
							ClickAuctionSellItemButton()
							ClearCursor()
							
							self.postButton:SetText("Post Gems")
							self.postButton:Enable()
							self:Print("Cannot post remaining auctions, you do not have enough money.")
							return
						end
					end
				end
			end
		end
	end
end

-- Do a delay before scanning the auctions so it has time to load all of the owner information
local scanElapsed = 0
local scanFrame = CreateFrame("Frame")
scanFrame:Hide()
scanFrame:SetScript("OnUpdate", function(self, elapsed)
	scanElapsed = scanElapsed + elapsed
	
	if( scanElapsed >= 0.40 ) then
		scanElapsed = 0
		self:Hide()
		
		QA:ScanAuctionList()
	end
end)

function QA:AUCTION_ITEM_LIST_UPDATE()
	scanElapsed = 0
	scanFrame:Show()
end

function QA:ScanAuctionList()
	local shown, total = GetNumAuctionItems("list")
	
	-- Scan the list of auctions and find the one with the lowest bidder, using the data we have.
	local hasBadOwners
	for i=1, shown do
		local name, texture, quantity, _, _, _, minBid, _, buyoutPrice, _, _, owner = GetAuctionItemInfo("list", i)     
		if( not priceList[name] ) then
			priceList[name] = {buyout = 99999999999999999, minBid = 99999999999999999}
		end
		
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
	
	-- Not scanning, done here
	if( not isScanning or not searchFilter ) then
		return
	end
	
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
		QuickAuctionsDB.undercutBy = self:DeformatMoney(arg) or QuickAuctionsDB.undercutBy
		self:Print(string.format("Undercutting auctions by %s", self:FormatTextMoney(QuickAuctionsDB.undercutBy)))
	
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
			QuickAuctionsDB.threshold = self:DeformatMoney(amount) or QuickAuctionsDB.threshold
			self:Print(string.format("Set default threshold to %s", self:FormatTextMoney(QuickAuctionsDB.threshold)))
			return
		end
		
		-- Set it for this specific item
		local name = GetItemInfo(link)
		if( amount <= 0 ) then
			QuickAuctionsDB.specialThresh[name] = nil
			self:Print(string.format("Removed threshold on %s.", link))
			return
		end
		
		QuickAuctionsDB.specialThresh[name] = amount or QuickAuctionsDB.specialThresh[name]
		self:Print(string.format("Set threshold for %s to %s.", link, self:FormatTextMoney(QuickAuctionsDB.specialThresh[name])))

	-- Post cap
	elseif( cmd == "cap" and arg ) then
		QuickAuctionsDB.postCap = tonumber(arg) or 2
		self:Print(string.format("Set maximum number of the same auction to %d.", QuickAuctionsDB.postCap))
	
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
		print("/qa undercut <money> - How much to undercut people by.")
		print("/qa smartcut - Toggles smart undercutting (Going from 1.9g -> 1g first instead of 1.9g - undercut amount.")
		--print("/qa uncut - Toggles posting of uncut metas and gems.")
		print("/qa cap <amount> - Only allow <amount> of the same kind of auction to be up at the same time.")
		print("/qa fallback <money> <link> - How much money to default to if nobody else has an auction up.")
		print("/qa threshold <money> <link> - Don't post any auctions that would go below this amount.")
		print("/qa time <12/24/48> - Amount of hours to put auctions up for, only works for the current sesson.")
		print("/qa add <name> - Adds a name to the whitelist to not undercut.")
		print("/qa remove <name> - Removes a name from the whitelist.")
		print("For fallback and threshold, if a link is provided it's set for the specific item, if none is then it's set globally as a default.")
		print("<money> format is \"#g\" for gold \"#s\" for silver and \"#c\" for copper, so \"5g2s5c\" will be 5 gold, 2 silver, 5 copper.")
	end
end
