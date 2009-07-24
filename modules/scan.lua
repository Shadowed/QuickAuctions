local Scan = QuickAuctions:NewModule("Scan", "AceEvent-3.0")
local L = QuickAuctionsLocals
local status = QuickAuctions.status
local auctionData = {}
Scan.auctionData = auctionData

function Scan:OnInitialize()
	self:RegisterMessage("QA_AH_LOADED", "AuctionHouseLoaded")
	self:RegisterMessage("QA_AH_CLOSED", "AuctionHouseClosed")
	
	status.filterList = {}
end

function Scan:AuctionHouseLoaded()
	-- Hook the query function so we know what we last sent a search on
	local orig_QueryAuctionItems = QueryAuctionItems
	QueryAuctionItems = function(name, minLevel, maxLevel, invTypeIndex, classIndex, subClassIndex, page, isUsable, qualityIndex, getAll, ...)
		-- So AH browsing mods will show the status correctly on longer scans
		if( CanSendAuctionQuery() and status.active ) then
			AuctionFrameBrowse.page = page
		end
		
		return orig_QueryAuctionItems(name, minLevel, maxLevel, invTypeIndex, classIndex, subClassIndex, page, isUsable, qualityIndex, getAll, ...)
	end
end

function Scan:AuctionHouseClosed()
	if( status.isScanning ) then
		QuickAuctions:Print(L["Scan interrupted due to Auction House being closed."])
		self:StopScanning(true)
	end
end

function Scan:StartItemScan(filterList)
	if( #(filterList) == 0 ) then
		return
	end
	
	status.active = true
	status.isScanning = "item"
	status.page = 0
	status.retries = 0
	status.hardRetry = nil
	status.filterList = filterList
	status.filter = filterList[1]
	status.startFilter = #(filterList)
	status.classIndex = nil
	status.subClassIndex = nil
	
	table.wipe(auctionData)

	self:SendMessage("QA_START_SCAN", "item", #(status.filterList))
	self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
	self:SendQuery()
end

function Scan:StartCategoryScan(classIndex, subClassList)
	status.active = true
	status.isScanning = "category"
	status.page = 0
	status.retries = 0
	status.hardRetry = nil
	status.filter = nil
	status.filterList = nil
	status.classIndex = classIndex
	status.subClassList = subClassList
	status.subClassIndex = subClassList[1]
	status.startSubClass = #(subClassList)

	table.wipe(auctionData)
	
	self:SendMessage("QA_START_SCAN", "category")
	self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
	self:SendQuery()
end

function Scan:StopScanning(interrupted)
	if( not status.isScanning ) then return end
	
	status.active = nil
	status.isScanning = nil

	self:SendMessage("QA_STOP_SCAN", interrupted)
	self:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
	self.scanFrame:Hide()
end

-- Scan delay if we can't send a query just yet
Scan.frame = CreateFrame("Frame")
Scan.frame.timeElapsed = 0
Scan.frame:SetScript("OnUpdate", function(self, elapsed)
	self.timeElapsed = self.timeElapsed + elapsed
	if( self.timeElapsed >= 0.15 ) then
		self.timeElapsed = 0
		Scan:SendQuery()
	end
end)

function Scan:SendQuery()
	status.queued = not CanSendAuctionQuery()
	if( not status.queued ) then
		self.frame:Hide()

		QueryAuctionItems(status.filter, nil, nil, 0, status.classIndex, status.subClassIndex, status.page, 0, 0)
	else
		self.frame:Show()
	end
end

-- Add a new record
function Scan:AddAuctionRecord(name, link, owner, quantity, bid, buyout)
	auctionData[link] = auctionData[link] or {quantity = 0, onlyPlayer = true, records = {}}
	auctionData[link].quantity = auctionData[link].quantity + quantity
	
	-- Don't add this data, just add the quantity if it has no buyout
	if( buyout <= 0 ) then return end

	-- Not only the player has posted this anymore :(
	if( not QuickAuctions.db.factionrealm.player[owner] ) then
		auctionData[link].onlyPlayer = nil
	end
	
	-- Find one thats unused if we can
	buyout = buyout / quantity
	bid = bid / quantity
	
	-- No sense in using a record for each entry if they are all the exact same data
	for _, record in pairs(auctionData[link].records) do
		if( record.owner == owner and record.buyout == buyout and record.bid == bid ) then
			record.buyout = buyout
			record.bid = bid
			record.owner = owner
			record.quantity = record.quantity + quantity
			record.isPlayer = QuickAuctions.db.factionrealm.player[owner]
			return
		end
	end
	
	-- Nothing available, create a new one
	table.insert(auctionData[link].records, {owner = owner, buyout = buyout, bid = bid, isPlayer = QuickAuctions.db.factionrealm.player[owner], quantity = quantity})
end

-- Find out if we got undercut on this item
function Scan:IsLowestAuction(name, buyout, bid)
	-- We don't even have data on this
	if( not auctionData[link] ) then
		return true
	end
	
	for _, record in pairs(auctionData[link].records) do
		-- They are on our whitelist, and they undercut us, or they matched our buyout but under bid us.
		if( QuickAuctions.db.factionrealm.whitelist[string.lower(record.owner)] ) then
			if( record.buyout < buyout or ( QuickAuctions.db.profile.bidUndercut and record.buyout == buyout and record.bid < bid ) ) then
				return false, record.owner, record.quantity, record.buyout, record.bid
			end
		-- They are not on our whitelist, it's not us, and they either are matching or undercut us
		elseif( not record.isPlayer and record.buyout <= buyout ) then
			return false, record.owner, record.quantity, record.buyout, record.bid
		end
	end
	
	return true
end

-- Searches the item data to find out how many we have on the provided item info
function Scan:GetItemQuantity(link, buyout, bid)
	if( not auctionData[link] ) then
		return 0
	end
	
	for _, record in pairs(auctionData[link].records) do
		if( record.isPlayer and record.buyout == buyout and record.bid == bid ) then
			return record.quantity
		end
	end
	
	return 0
end

function Scan:GetPlayerItemQuantity(link)
	if( not auctionData[link] ) then return 0 end
	
	local total = 0
	for _, record in pairs(auctionData[link].records) do
		if( record.isPlayer ) then
			total = total + record.quantity
		end
	end
	
	
	return total
end

function Scan:IsPlayerOnly(link)
	return auctionData[link] and auctionData[link].onlyPlayer
end

-- Find out the lowest price for this auction
function Scan:GetLowestAuction(link)
	-- No data on it
	if( not auctionData[link] ) then
		return nil
	end
		
	-- Find lowest
	local buyout, bid, owner
	for _, record in pairs(auctionData[link].records) do
		if( not buyout or record.buyout < buyout or ( record.buyout <= buyout and record.bid < bid ) ) then
			buyout, bid, owner = record.buyout, record.bid, record.owner
		end
	end

	-- Now that we know the lowest, find out if this price "level" is a friendly person
	-- the reason we do it like this, is so if Apple posts an item at 50g, Orange posts one at 50g
	-- but you only have Apple on your white list, it'll undercut it because Orange posted it as well
	local isWhitelist, isPlayer = true, true
	for _, record in pairs(auctionData[link].records) do
		if( not record.isPlayer and record.buyout == buyout ) then
			isPlayer = nil
			if( not QuickAuctions.db.factionrealm.whitelist[record.owner] ) then
				isWhitelist = nil
			end
			
			-- If the lowest we found was from the player, but someone else is matching it (and they aren't on our white list)
			-- then we swap the owner to that person
			buyout, bid, owner = record.buyout, record.bid, record.owner
		end
	end
	
	return buyout, bid, owner, isWhitelist, isPlayer
end

-- Do a delay before scanning the auctions so it has time to load all of the owner information
local BASE_DELAY = 0.50
Scan.scanFrame = CreateFrame("Frame")
Scan.scanFrame.timeDelay = BASE_DELAY
Scan.scanFrame:SetScript("OnUpdate", function(self, elapsed)
	self.timeElapsed = self.timeElapsed + elapsed
	if( self.timeElapsed >= self.timeDelay ) then
		self.timeElapsed = 0
		self:Hide()

		Scan:ScanAuctions()
	end
end)
Scan.scanFrame:Hide()

function Scan:AUCTION_ITEM_LIST_UPDATE()
	self.scanFrame.timeDelay = BASE_DELAY
	self.scanFrame.timeElapsed = 0
	self.scanFrame:Show()
end

-- Time to scan auctions!
function Scan:ScanAuctions()
	local shown, total = GetNumAuctionItems("list")
	local totalPages = math.ceil(total / NUM_AUCTION_ITEMS_PER_PAGE)
		
	-- Check for bad data quickly
	if( status.retries < 3 ) then
		-- Blizzard doesn't resolve the GUID -> name of the owner until GetAuctionItemInfo is called for it
		-- meaning will call it for everything on the list then if we had any bad data will requery
		local badData
		for i=1, shown do
			local name, _, _, _, _, _, _, _, _, _, _, owner = GetAuctionItemInfo("list", i)     
			if( not name or not owner ) then
				badData = true
			end
		end
		
		if( badData ) then
			status.retries = status.retries + 1
			
			-- Hard retry
			if( status.hardRetry ) then
				self:SendMessage("QA_QUERY_UPDATE", "retry", status.filter, status.page + 1, totalPages, status.retries, 3)
				self:SendQuery()
			-- Soft retry
			else
				self.scanFrame.timeElapsed = 0
				self.scanFrame.timeDelay = status.retries * 0.66
				self.scanFrame:Show()
				
				-- QA will wait 0.66 seconds per retry (0.66, 1.32, 1.98 = 3.96 seconds) more during a soft retry
				-- if that still fails, it will fallback on a hard retry where it will requery 3 times, if the requeries
				-- fail still, then it will let the data through with an unknown owner
				if( status.retries >= 3 ) then
					status.hardRetry = true
					status.retries = 0
				end
			end
			return
		end
	end
	
	status.hardRetry = nil
	status.retries = 0

	-- Find the lowest auction (if any) out of this list
	for i=1, shown do
		local name, texture, quantity, _, _, _, bid, _, buyout, _, _, owner = GetAuctionItemInfo("list", i)     
		self:AddAuctionRecord(name, QuickAuctions:GetSafeLink(GetAuctionItemLink("list", i)), (owner or ""), quantity, bid, buyout)
	end

	-- This query has more pages to scan
	if( shown == NUM_AUCTION_ITEMS_PER_PAGE ) then
		status.page = status.page + 1
		self:SendMessage("QA_QUERY_UPDATE", "page", status.filter, status.page + 1, totalPages)
		self:SendQuery()
		return
	end

	-- Finished with the page
	self:SendMessage("QA_QUERY_UPDATE", "done", status.filter, totalPages, totalPages)
	
	-- Scanned all the pages for this filter, remove what we were just looking for then
	if( status.isScanning == "item" ) then
		for i=#(status.filterList), 1, -1 do
			if( status.filterList[i] == status.filter ) then
				table.remove(status.filterList, i)
				break
			end
		end
		
		status.filter = status.filterList[1]
	elseif( status.isScanning == "category" ) then
		for i=#(status.subClassList), 1, -1 do
			if( status.subClassList[i] == status.subClassIndex ) then
				table.remove(status.subClassList, i)
			end
		end
		
		status.subClassIndex = status.subClassList[1]
	end
	
	-- Query the next filter if we have one
	if( status.filter ) then
		status.page = 0
		self:SendMessage("QA_QUERY_UPDATE", "next", status.filter, #(status.filterList), status.startFilter)
		self:SendQuery()
		return
	
	-- Orr let us query the next sub class if we got one
	elseif( status.subClassIndex ) then
		status.page = 0
		self:SendMessage("QA_QUERY_UPDATE", "next", status.filter, status.subClassIndex, #(status.subClassIndex), status.startSubClass)
		self:SendQuery()
		return
	end
	
	self:StopScanning()
end
