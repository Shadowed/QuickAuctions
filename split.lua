-- Splitting code
-- I moved this into a new file for sanity reasons mostly
local foundSlots = {}
local splitLink, splitQuantity, timerFrame
local newStacks, timeElapsed = 0, 0

-- Start splitting something new
function QA:StartSplitting(stacks, link, quantity)
	for k in pairs(foundSlots) do foundSlots[k] = nil end
	
	newStacks = stacks
	splitLink = link
	splitQuantity = quantity
	
	self:Log("Going to be splitting into %d (%d) new stacks, of %s (%s) x %d.", newStacks or -1, stacks or -1, (GetItemInfo(splitLink)), splitLink, splitQuantity)
	self:ProcessSplitQueue()
end

-- Find out where we can place something, if we can.
function QA:FindEmptyInventorySlot(forItemFamily)
	for bag=0, 4 do
		local bagFamily = 0
		if( bag ~= 0 and bag ~= -1 ) then
			bagFamily = GetItemFamily(GetInventoryItemLink("player", ContainerIDToInventoryID(bag)))
		end
		
		if( bagFamily == 0 or bagFamily == forItemFamily ) then
			for slot=1, GetContainerNumSlots(bag) do
				if( not GetContainerItemLink(bag, slot) ) then
					return bag, slot
				end
			end
		end
	end
	
	return nil, nil
end

-- Split an item if needed
function QA:ProcessSplitQueue()
	-- Loop through bags
	for bag=0, 4 do
		-- Scanning a bag
		for slot=1, GetContainerNumSlots(bag) do
			local link = self:GetSafeLink(GetContainerItemLink(bag, slot))
			local itemCount, itemLocked = select(2, GetContainerItemInfo(bag, slot))
			-- Slot has something in it
			if( link == splitLink and itemCount > splitQuantity ) then
				-- It's still locked, so we have to wait before we try and use it again
				if( itemLocked ) then
					timeElapsed = 0.15
					timerFrame:Show()
					return
				end
				
				-- Bad, ran out of space
				local freeBag, freeSlot = self:FindEmptyInventorySlot(GetItemFamily(link))
				if( not freeBag and not freeSlot ) then
					self:Print("Ran out of free space to keep splitting, not going to finish up splits.")
					return
				end

				self:Log("Splitting item %s x %d from bag %d/slot %d, moving it into bag %d/slot %d.", (GetItemInfo(link)), splitQuantity, bag, slot, freeBag, freeSlot)

				self.frame:RegisterEvent("BAG_UPDATE")
				SplitContainerItem(bag, slot, splitQuantity)
				PickupContainerItem(freeBag, freeSlot)
				return
			end
		end
	end
		
	self:Log("Bad stack size found. We still need to split %s into %d new stacks of %d.", (GetItemInfo(splitLink)), newStacks, splitQuantity)
	
	newStacks = 0
	splitLink = nil

	self:FinishedSplitting()
end

-- Check bags now that everythings settled down
local function checkBags(self, elapsed)
	timeElapsed = timeElapsed + elapsed
	if( timeElapsed < 0.25 ) then
		return
	end
	
	timeElapsed = 0
	self:Hide()

	-- Check how many stacks we have left
	for bag=0, 4 do
		for slot=1, GetContainerNumSlots(bag) do
			local link = QA:GetSafeLink(GetContainerItemLink(bag, slot))
			local itemCount = select(2, GetContainerItemInfo(bag, slot))
			if( not foundSlots[bag .. slot] and link == splitLink and itemCount == splitQuantity ) then
				foundSlots[bag .. slot] = true
				newStacks = newStacks - 1

				QA:Log("Found valid stack, %s in bag %d/slot %d, quantity %d.", (GetItemInfo(link)), bag, slot, itemCount)
			end
		end
	end
	
	-- No more splitting needed
	if( newStacks <= 0 ) then
		newStacks = 0
		splitLink = nil

		QA:FinishedSplitting()
	else
		QA:ProcessSplitQueue()
	end
end

-- Player bags changed, start a timer before scanning them
function QA:BAG_UPDATE()
	self.frame:UnregisterEvent("BAG_UPDATE")
	self:Log("BAG_UPDATE")

	-- Create it if needed
	if( not timerFrame ) then
		timerFrame = CreateFrame("Frame")
		timerFrame:SetScript("OnUpdate", checkBags)
	end

	-- Start timer going
	timeElapsed = 0
	timerFrame:Show()
end