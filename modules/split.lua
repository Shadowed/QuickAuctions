local QuickAuctions = select(2, ...)
local Split = QuickAuctions:NewModule("Split", "AceEvent-3.0")
local L = QuickAuctions.L
local status = QuickAuctions.status
local splitQueue, alreadySplit, alreadyFound, bagList, lockedSlot = {}, {}, {}, {}, {}
local timeElapsed, splitTimeout, hadSplitFailure, scanRunning = 0, 0
local eventThrottle = CreateFrame("Frame")
eventThrottle:Hide()

function Split:OnInitialize()
	self:RegisterMessage("QA_AH_CLOSED", "AuctionHouseClosed")
end

function Split:AuctionHouseClosed()
	if( status.isSplitting ) then
		self:Stop()
		QuickAuctions:Print(L["Stopped splitting due to Auction House frame being closed."])
	end
end

-- This isn't really the most efficient code for doing splits, but as QA requires the user to not be doing anything else
-- and splitting in general is a pain I'll take the CPU cost
function Split:FindEmptySlot(itemFamily)
	for bag=0, 4 do
		local bagFamily = bag == 0 and 0 or GetItemFamily(GetInventoryItemLink("player", ContainerIDToInventoryID(bag)))
		if( bagFamily == 0 or bagFamily == itemFamily ) then
			for slot=1, GetContainerNumSlots(bag) do
				if( not GetContainerItemLink(bag, slot) and not lockedSlot[bag .. slot] ) then
					return bag, slot
				end
			end
		end
	end
	
	return nil, nil
end

-- Finds any split queues we didn't already check if they have data
function Split:FindSplitData(link, quantity)
	for id, queue in pairs(splitQueue) do
		if( not alreadyFound[id] and queue.link == link and queue.quantity < quantity ) then
			alreadyFound[id] = true
			return queue
		end
	end
	
	return nil
end

-- Check the inventory for anything that we didn't already flag as split, as split then pull it from the queue
function Split:CheckQueueMatch(bag, slot, link, quantity)
	if( alreadySplit[bag .. slot] ) then return end
	
	for i=#(splitQueue), 1, -1 do
		local queue = splitQueue[i]
		if( queue.link == link and queue.quantity == quantity ) then
			alreadySplit[bag .. slot] = true

			QuickAuctions.Post:QueueItem(queue.link, bag, slot)
			table.remove(splitQueue, i)
			break
		end
	end
	
	-- Queues done, so stop splitting
	if( not scanRunning and #(splitQueue) == 0 ) then
		self:Stop()
	end
end

-- Actually rescan bags here
function Split:UpdateBags()
	local recheck
	for bag=0, 4 do
		for slot=1, GetContainerNumSlots(bag) do
			local location = bag .. slot
			local link = QuickAuctions:GetSafeLink(GetContainerItemLink(bag, slot))
			local quantity, locked = select(2, GetContainerItemInfo(bag, slot))
			
			-- Can't use something that's still locked
			if( not locked ) then
				-- Item added, check if we can remove something from the queue
				-- Had to move this away from only checking if the item changed because if you have 5 x Glyph of Rejuvenation
				-- and want 5 on the Auction House, it would split it 4 times and fail to see the original stack which is now
				-- valid to post with because that stack never actually leaves the auction house
				if( link ) then
					self:CheckQueueMatch(bag, slot, link, quantity)
					
				-- This location used to be where a split item was, but as it no longer is we can unflag it
				elseif( bagList[location] and not link ) then
					alreadySplit[location] = nil
					lockedSlot[location] = nil
				end

				bagList[location] = link
			else
				recheck = true
			end
			
		end
	end
	
	-- Nothing else to post
	if( not scanRunning and #(splitQueue) == 0 ) then
		self:Stop()
		return
	end

	-- We had a bag locked, flag that we need to recheck in 0.10 seconds to see if it unlocked itself
	if( recheck ) then
		timeElapsed = 0.10
		eventThrottle:Show()
		return
	end

	-- Provided nothing was locked, let us do some splitting
	table.wipe(alreadyFound)
	
	for bag=0, 4 do
		for slot=1, GetContainerNumSlots(bag) do
			local link = QuickAuctions:GetSafeLink(GetContainerItemLink(bag, slot))
			local quantity = select(2, GetContainerItemInfo(bag, slot))
			local splitData = self:FindSplitData(link, quantity)
			if( splitData ) then
				-- If we don't have a free slot yet, will wait a second then will check again for a free spot
				local freeBag, freeSlot = self:FindEmptySlot(GetItemFamily(link))
				if( not freeBag or not freeSlot ) then
					-- If it takes over 10 seconds without a split occuring, stops trying to split
					if( splitTimeout > 0 and GetTime() > splitTimeout ) then
						splitTimeout = 0
						hadSplitFailure = true
						self:Stop()
						return
					end
					
					-- Wait a second and try again to see if we got room
					timeElapsed = 1
					eventThrottle:Show()
					return
				end
				
				splitTimeout = GetTime() + 10

				-- Move the split into the new spot
				SplitContainerItem(bag, slot, splitData.quantity)
				PickupContainerItem(freeBag, freeSlot)
				
				lockedSlot[freeBag .. freeSlot] = true
			end
		end
	end
end

-- Throttle bag updates because they are a pain and spammy
function Split:BAG_UPDATE()
	timeElapsed = 0.20
	eventThrottle:Show()
end

eventThrottle:SetScript("OnUpdate", function(self, elapsed)
	timeElapsed = timeElapsed - elapsed
	if( timeElapsed <= 0 ) then
		self:Hide()
		Split:UpdateBags()
	end
end)

function Split:ScanStarted()
	scanRunning = true
end

function Split:ScanStopped()
	scanRunning = nil
	
	if( #(splitQueue) == 0 ) then
		self:Stop()
	end
end

function Split:Start()
	if( status.isSplitting ) then return end
	
	splitTimeout = GetTime() + 10
	hadSplitFailure = nil
	status.isSplitting = true

	table.wipe(bagList)
	table.wipe(lockedSlot)
	table.wipe(alreadySplit)
	table.wipe(alreadyFound)
	
	self:RegisterEvent("BAG_UPDATE")
	self:UpdateBags()
end

function Split:Stop()
	if( not status.isSplitting ) then return end
	
	status.isSplitting = nil
	table.wipe(splitQueue)
	self:UnregisterEvent("BAG_UPDATE")
	eventThrottle:Hide()
	
	if( hadSplitFailure ) then
		QuickAuctions:Log(L["Could not post all auctions, ran out of space."], true)
		QuickAuctions:Print(L["Not all your auctions were posted, ran out of space to split items even after waiting 10 seconds."])
	end

	QuickAuctions.Post:ScanStopped()
end

function Split:QueueItem(link, quantity)
	table.insert(splitQueue, {link = link, quantity = quantity})
end
