QA = {}

local isScanning, searchFilter, scanType, scanTotal, scanIndex, incrementNext
local page = 0
local badRetries = 0
local activeAuctions = {}
local scanList = {}
local priceList = {}
local queryQueue = {}
local postList = {}

function QA:OnInitialize()
	QuickAuctionsDB = QuickAuctionsDB or {undercutBy = 100, fallbackBid = 2250000, fallbackBuyout = 2250000, postCap = 2, whitelist = {}}
		
	-- Interrupt our scan if they start to browse
	local orig = BrowseSearchButton:GetScript("OnClick")
	BrowseSearchButton:SetScript("OnClick", function(self, ...)
		isScanning = nil
		orig(self, ...)
	end)
	
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
end

local timeElapsed = 0
local function checkSend(self, elapsed)
	timeElapsed = timeElapsed + elapsed
	
	if( timeElapsed >= 0.5 ) then
		timeElapsed = 0
		
		-- Can we send it yet?
		if( CanSendAuctionQuery("list") ) then
			local filter = table.remove(queryQueue, 1)
			local page = table.remove(queryQueue, 1)
			
			QueryAuctionItems(filter, nil, nil, 0, 0, 0, page, 0, 0)
			
			-- Increment the counter since we have sent off this query
			if( isScanning ) then
				scanIndex = scanIndex + 1
				QA.scanButton:SetFormattedText("%d/%d items", scanIndex, scanTotal)
			end
			
			-- Done with our queries
			if( #(queryQueue) == 0 ) then
				QA.isQuerying = nil
				self:SetScript("OnUpdate", nil)
			end
		end
	end

end

function QA:SendQuery(filter, page)
	if( CanSendAuctionQuery("list") ) then
		QueryAuctionItems(filter, nil, nil, 0, 0, 0, page, 0, 0)

		-- Increment the counter since we have sent off this query
		if( isScanning ) then
			scanIndex = scanIndex + 1
			self.scanButton:SetFormattedText("%d/%d items", scanIndex, scanTotal)
		end
		return
	end
	
	table.insert(queryQueue, filter)
	table.insert(queryQueue, page)
	
	self.frame:SetScript("OnUpdate", checkSend)
	self.isQuerying = true
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
	end
	
	local hasItems
	for i=1, (GetNumAuctionItems("owner")) do
		-- Figure out if this is a gem
		self.tooltip:ClearLines()
		self.tooltip:SetAuctionItem("owner", i)
		
		local name = GetAuctionItemInfo("owner", i)
		local itemLink = select(2, self.tooltip:GetItem())
		
		if( itemLink and select(6, GetItemInfo(itemLink)) == "Gem" and select(13, GetAuctionItemInfo("owner", i)) == 0 ) then
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
	
	local scanAuctions = true
	for bag=0, 4 do
		for slot=1, GetContainerNumSlots(bag) do
			local link = GetContainerItemLink(bag, slot)
			if( link ) then
				local name, _, _, _, _, itemType, _, stackSize = GetItemInfo(link)
				-- Cut gems don't stack, so easy check
				if( itemType == "Gem" and stackSize == 1 ) then
					table.insert(postList, name)

					-- No data on this item
					if( not priceList[name] ) then
						tempList[name] = true
						scanAuctions = true
					end
				end
			end
		end
	end
	
	if( scanAuctions ) then
		self:StartScan(tempList, "post")
	end
end

function QA:StartScan(list, type)
	for i=#(scanList), 1, -1 do table.remove(scanList, i) end
	
	-- Prevents duplicate entries
	for name in pairs(list) do
		table.insert(scanList, name)
	end

	searchFilter = table.remove(scanList, 1)
	if( not searchFilter ) then
		return
	end

	self.scanButton:Disable()
	self.scanButton:SetFormattedText("%d/%d items", 0, #(scanList) + 1)

	page = 0
	scanType = type
	scanTotal = #(scanList) + 1
	scanIndex = 0
	isScanning = true
	
	self:SendQuery(searchFilter, page)
end

function QA:CheckItems()
	for k in pairs(tempList) do tempList[k] = nil end
	
	self.scanButton:Enable()
	self.scanButton:SetText("Scan Gems")
	
	for i=1, (GetNumAuctionItems("owner")) do
		local name, texture, quantity, _, _, _, minBid, _, buyoutPrice, _, _, owner, wasSold = GetAuctionItemInfo("owner", i)     
		local priceData = priceList[name]
		
		if( priceData and wasSold == 0 ) then
			-- Check if buyout, our minimum bid are equal or lower than ours
			-- if they aren't us
			-- and if they aren't on our whitelist (We don't care if they undercut us)
			if( ( priceData.buyout <= buyoutPrice or priceData.minBid <= minBid ) and priceData.owner ~= owner and not QuickAuctionsDB.whitelist[priceData.owner] ) then
				if( not tempList[name] ) then
					print(string.format("Undercut on %s, by %s, buyout %.2fg, bid %.2fg, our buyout %.2fg, our bid %.2fg", name, priceData.owner, priceData.buyout / 10000, priceData.minBid / 10000, buyoutPrice / 10000, minBid / 10000))
				end

				tempList[name] = true
				CancelAuction(i)
			end
		end
	end
end

function QA:PostItems()
	self.scanButton:Enable()
	self.scanButton:SetText("Scan Gems")
	
	-- Figure out how many of this is already posted
	for k in pairs(activeAuctions) do activeAuctions[k] = nil end
	for i=1, (GetNumAuctionItems("owner")) do
		local name = GetAuctionItemInfo("owner", i)     
		activeAuctions[name] = (activeAuctions[name] or 0) + 1
	end
	
	for i=#(postList), 1, -1 do
		local name = table.remove(postList, i)
		local priceData = priceList[name]
		
		local totalPosted = activeAuctions[name] or 0
		local minBid, buyout
		if( priceData ) then
			minBid = priceData.minBid
			buyout = priceData.buyout

			-- Don't undercut people on our whitelist, match them
			if( not QuickAuctionsDB.whitelist[priceData.owner] ) then
				buyout = buyout / 10000
				
				-- If the buyout the other person placed is 150g, we undercut it by the amount
				-- if what they placed is 150.99g then we undercut it by 150g
				if( buyout == math.floor(buyout) ) then
					buyout = ( buyout * 10000 ) - QuickAuctionsDB.undercutBy
				else
					buyout = math.floor(buyout) * 10000
				end

				minBid = buyout
			end
		
		-- No other data available, default to 225g a cut
		else
			minBid = QuickAuctionsDB.fallbackBid
			buyout = QuickAuctionsDB.fallbackBuyout
			
			print(string.format("No data found for %s, using %.2fg buyout and %.2fg bid default.", name, buyout / 10000, minBid / 10000))
		end

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
						StartAuction(minBid, buyout, 12 * 60)
					end
				end
			end
		end

	end
end

function QA:AUCTION_ITEM_LIST_UPDATE()
	local shown, total = GetNumAuctionItems("list")
	
	-- Scan the list of auctions and find the one with the lowest bidder, using the data we have.
	local hasBadOwners
	for i=1, shown do
		local name, texture, quantity, _, _, _, minBid, _, buyoutPrice, _, _, owner = GetAuctionItemInfo("list", i)     
		if( not priceList[name] ) then
			priceList[name] = {buyout = 99999999999999999}
		end

		if( buyoutPrice <= priceList[name].buyout and buyoutPrice > 0 ) then
			priceList[name].minBid = minBid
			priceList[name].buyout = buyoutPrice
			priceList[name].owner = owner
			
			if( not owner ) then
				hasBadOwners = true
			end
		end
	end
	
	-- Not scanning, done here
	if( not isScanning ) then
		return
	end
	
	-- Found a query with bad owners
	if( hasBadOwners ) then
		badRetries = badRetries + 1
		
		if( badRetries <= 3 ) then
			badRetries = 0
			self:SendQuery(searchFilter, page)
			return
		end
		
	-- Reset the counter since we got good owners
	elseif( badRetries > 0 ) then
		badRetries = 0
	end	
	
	-- If it's an active scan, and we have shown as much as possible, then scan the next page
	if( shown == 50 ) then
		page = page + 1
		self:SendQuery(searchFilter, page)
	-- Move on to the next in the list
	else
		searchFilter = table.remove(scanList, 1)
		page = 0
		
		-- Nothing else to search, done!
		if( not searchFilter ) then
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
		
		self:SendQuery(searchFilter, page)
	end
end

-- Event handler/misc
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
frame:SetScript("OnEvent", function(self, event, ...)
	if( event == "ADDON_LOADED" and select(1, ...) == "QuickAuctions" ) then
		QA:OnInitialize()
	elseif( event ~= "ADDON_LOADED" ) then
		QA[event](QA, ...)
	end
end)

QA.frame = frame

function QA:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99Quick Auctions|r: %s", msg))
end

function QA:RegisterEvent(event)
	frame:RegisterEvent(event)
end

function QA:UnregisterEvent(event)
	frame:UnregisterEvent(event)
end


-- Slash commands
SLASH_QUICKAUCTIONS1 = "/quickauctions"
SLASH_QUICKAUCTIONS2 = "/qa"
SlashCmdList["QUICKAUCTIONS"] = function(msg)
	msg = msg or ""

	local cmd, arg = string.split(" ", msg, 2)
	cmd = string.lower(cmd or "")

	if( cmd == "undercut" and arg ) then
		QuickAuctionsDB.undercutBy = tonumber(arg) or 100
		QA:Print(string.format("Set undercut amount to %.2fg", QuickAuctions.undercutBy / 10000))

	elseif( cmd == "fallbid" and arg ) then
		QuickAuctionsDB.fallbackBid = tonumber(arg) * 10000
		QA:Print(string.format("Set fallback bid to %.2fg", QuickAuctionsDB.fallbackBid / 10000))

	elseif( cmd == "fallbo" and arg ) then
		QuickAuctionsDB.fallbackBuyout = tonumber(arg) * 10000
		QA:Print(string.format("Set fallback buyout to %.2fg", QuickAuctionsDB.fallbackBuyout / 10000))

	elseif( cmd == "cap" and arg ) then
		QuickAuctionsDB.postCap = tonumber(arg) or 2
		QA:Print(string.format("Set maximum number of the same auction to %d.", QuickAuctionsDB.postCap))

	elseif( cmd == "add" and arg ) then
		QuickAuctionsDB.whitelist[arg] = true
		QA:Print(string.format("Added %s to the whitelist.", arg))

	elseif( cmd == "remove" and arg ) then
		QuickAuctionsDB.whitelist[arg] = nil
		QA:Print(string.format("Removed %s from whitelist.", arg))

	elseif( cmd == "reset" ) then
		QuickAuctionsDB.whitelist = {}
	else
		QA:Print("Slash commands")
		print("/qa undercut <amount in copper> - How much to undercut people by.")
		print("/qa fallbid <amount in gold> - How much gold to put the bid on for auctions we have no data on.")
		print("/qa fallbo <amount in gold> - How much gold to put the buyout on for auctions we have no data on.")
		print("/qa cap <amount> - Only allow <amount> of the same kind of auction to be up at the same time.")
		print("/qa add <name> - Adds a name to the whitelist to not undercut.")
		print("/qa remove <name> - Removes a name from the whitelist.")
		print("/qa reset - Resets the whitelist")
	end
end
