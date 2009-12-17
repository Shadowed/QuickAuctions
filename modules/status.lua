local QuickAuctions = select(2, ...)
local Status = QuickAuctions:NewModule("Status", "AceEvent-3.0")
local L = QuickAuctions.L
local status = QuickAuctions.status
local statusList, scanList, tempList = {}, {}, {}

local function sortByGroup(a, b)
	return QuickAuctions.Manage.reverseLookup[a] < QuickAuctions.Manage.reverseLookup[b]
end

function Status:OutputResults()
	table.sort(statusList, sortByGroup)
	
	for _, itemID in pairs(statusList) do
		local itemLink = select(2, GetItemInfo(itemID))
		local lowestBuyout, lowestBid, lowestOwner = QuickAuctions.Scan:GetLowestAuction(itemID)
		if( lowestBuyout ) then
			local quantity = QuickAuctions.Scan:GetTotalItemQuantity(itemID)
			local playerQuantity = QuickAuctions.Scan:GetPlayerItemQuantity(itemID)
			
			QuickAuctions:Log(itemID .. "statusres", string.format(L["%s lowest buyout %s (threshold %s), total posted |cfffed000%d|r (%d by you)"], itemLink, QuickAuctions:FormatTextMoney(lowestBuyout, true), QuickAuctions:FormatTextMoney(QuickAuctions.Manage:GetConfigValue(itemID, "threshold"), true), quantity, playerQuantity))
		else
			QuickAuctions:Log(itemID .. "statusres", string.format(L["Cannot find data for %s."], itemLink or itemID))
		end
	end
	
	QuickAuctions:Log("statusresdone", L["Finished status report"])
end

function Status:StartLog()
	self:RegisterMessage("QA_QUERY_UPDATE")
	self:RegisterMessage("QA_START_SCAN")
	self:RegisterMessage("QA_STOP_SCAN")
end

function Status:StopLog()
	self:UnregisterMessage("QA_QUERY_UPDATE")
	self:UnregisterMessage("QA_START_SCAN")
	self:UnregisterMessage("QA_STOP_SCAN")
end

function Status:Scan()
	self:StartLog()
	
	table.wipe(statusList)
	table.wipe(scanList)
	table.wipe(tempList)
	
	QuickAuctions.Manage:UpdateReverseLookup()
	
	for bag=0, 4 do
		if( QuickAuctions:IsValidBag(bag) ) then
			for slot=1, GetContainerNumSlots(bag) do
				local link = QuickAuctions:GetSafeLink(GetContainerItemLink(bag, slot))
				if( link and QuickAuctions.Manage.reverseLookup[link] ) then
					tempList[link] = true
				end
			end
		end
	end
	
	-- Add a scan based on items in the AH that match
	for i=1, GetNumAuctionItems("owner") do
		if( select(13, GetAuctionItemInfo("owner", i)) == 0 ) then
			local link = QuickAuctions:GetSafeLink(GetAuctionItemLink("owner", i))
			if( link and QuickAuctions.Manage.reverseLookup[link] ) then
				tempList[link] = true
			end
		end
	end
	
	for itemID in pairs(tempList) do
		table.insert(statusList, itemID)
	end
	
	if( #(statusList) == 0 ) then
		QuickAuctions:Log("statusstatusmushroommushroom", L["No auctions or inventory items found that are managed by Quick Auctions that can be scanned."])
		return
	end
		
	for _, itemID in pairs(statusList) do
		table.insert(scanList, (GetItemInfo(itemID)))
	end
	
	QuickAuctions.Scan:StartItemScan(scanList)
end

function Status:Stop()
	table.wipe(statusList)
	self:StopLog()
end

-- Log handler
function Status:QA_QUERY_UPDATE(event, type, filter, ...)
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
	elseif( type == "next" ) then
		QuickAuctions:Log(filter .. "query", string.format(L["Scanning %s"], filter))
	end
end

function Status:QA_START_SCAN(event, type, total)
	QuickAuctions:WipeLog()
	QuickAuctions:Log("scanstatus", string.format(L["Scanning |cfffed000%d|r items..."], total or 0))
end

function Status:QA_STOP_SCAN(event, interrupted)
	self:StopLog()

	if( interrupted ) then
		QuickAuctions:Log("scaninterrupt", L["Scan interrupted before it could finish"])
		return
	end

	QuickAuctions:Log("scandone", L["Scan finished!"], true)
	
	self:OutputResults()
end





