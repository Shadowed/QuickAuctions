-- This will need a lot of rewriting before it's done
local QuickAuctions = select(2, ...)
local Mail = QuickAuctions:NewModule("Mail", "AceEvent-3.0")
local L = QuickAuctions.L

local eventThrottle = CreateFrame("Frame", nil, MailFrame)
local reverseLookup = QuickAuctions.modules.Manage.reverseLookup
local bagTimer, itemTimer, cacheFrame, activeMailTarget, mailTimer, lastTotal, autoLootTotal, waitingForData, resetIndex, waitForCancel
local lockedItems, mailTargets = {}, {}
local playerName = string.lower(UnitName("player"))
local allowTimerStart = true
local LOOT_MAIL_INDEX = 1
local MAIL_WAIT_TIME = 0.30
local RECHECK_TIME = 2
local FOUND_POSTAL

function Mail:OnInitialize()
	local function showTooltip(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:SetText(self.tooltip, 1, 1, 1, nil, true)
		GameTooltip:Show()
	end
	local function hideTooltip(self)
		GameTooltip:Hide()
	end

	-- Mass opening
	local button = CreateFrame("Button", nil, InboxFrame, "UIPanelButtonTemplate")
	button:SetText(L["Open all"])
	button:SetHeight(24)
	button:SetWidth(130)
	button:SetPoint("BOTTOM", InboxFrame, "CENTER", -10, -165)
	button:SetScript("OnClick", function(self) Mail:StartAutoLooting() end)

	-- Don't show mass opening if Postal is enabled since postals button will block QAs
	if( select(6, GetAddOnInfo("Postal")) == nil ) then
		FOUND_POSTAL = true
		button:Hide()
	end
	
	self.massOpening = button
	
	local check = CreateFrame("CheckButton", "QuickAuctionsAutoMail", MailFrame, "OptionsCheckButtonTemplate")
	check:SetHeight(26)
	check:SetWidth(26)
	check:SetChecked(false)
	check:SetFrameStrata("HIGH")
	check:SetHitRectInsets(0, -70, 0, 0)
	check:SetScript("OnEnter", showTooltip)
	check:SetScript("OnLeave", hideTooltip)
	check:SetScript("OnHide", function()
		Mail:Stop()
	end)
	check:SetScript("OnShow", function(self)
		if( QuickAuctions.db.char.autoMail ) then
			if( not IsShiftKeyDown() ) then
				self:SetChecked(true)
				Mail:Start()
			else
				QuickAuctions:Print(L["Disabling auto mail, SHIFT key was down when opening the mail box."])
			end
		end
	end)
	check:SetScript("OnClick", function(self)
		if( self:GetChecked() ) then
			QuickAuctions.db.char.autoMail = true
			Mail:Start()
		else
			QuickAuctions.db.char.autoMail = false
			Mail:Stop()
		end
	end)
	check:SetPoint("TOPLEFT", MailFrame, "TOPLEFT", 68, -13)
	check.tooltip = L["Enables Quick Auctions auto mailer, the last batch of mails will take ~10 seconds to send.|n|n[WARNING!] You will not get any confirmation before it starts to send mails, it is your own fault if you mistype your bankers name."]
	QuickAuctionsAutoMailText:SetText(L["Auto mail"])

	if( MailFrame:IsVisible() ) then
		check:GetScript("OnShow")(check)
	end
		
	-- Hide Inbox/Send Mail text, it's wasted space and makes my lazyly done checkbox look bad. Also hide the too much mail warning
	local noop = function() end
	InboxTooMuchMail:Hide()
	InboxTooMuchMail.Show = noop
	InboxTooMuchMail.Hide = noop
	
	InboxTitleText:Hide()
	SendMailTitleText:Hide()

	-- Timer for mailbox cache updates
	cacheFrame = CreateFrame("Frame", nil, MailFrame)
	cacheFrame:SetScript("OnEnter", showTooltip)
	cacheFrame:SetScript("OnLeave", hideTooltip)
	cacheFrame:EnableMouse(true)
	cacheFrame.tooltip = L["How many seconds until the mailbox will retrieve new data and you can continue looting mail."]
	cacheFrame:SetScript("OnUpdate", function(self, elapsed)
		if( not waitingForData ) then
			local seconds = self.endTime - GetTime()
			if( seconds <= 0 ) then
				-- Look for new mail
				-- Sometimes it fails and isn't available at exactly 60-61 seconds, and more like 62-64, will keep rechecking every 2 seconds
				-- until data becomes available
				if( QuickAuctions.db.global.autoCheck ) then
					waitingForData = true
					self.timeLeft = RECHECK_TIME
					cacheFrame.text:SetText(nil)
					
					CheckInbox()
				else
					self:Hide()
				end
				
				return
			end
			
			cacheFrame.text:SetFormattedText("%d", seconds)
		else
			self.timeLeft = self.timeLeft - elapsed
			if( self.timeLeft <= 0 ) then
				self.timeLeft = RECHECK_TIME
				CheckInbox()
			end
		end
	end)
	
	cacheFrame.text = cacheFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	cacheFrame.text:SetFont(GameFontHighlight:GetFont(), 30, "THICKOUTLINE")
	cacheFrame.text:SetPoint("CENTER", MailFrame, "TOPLEFT", 40, -35)
	cacheFrame:Hide()
	
	self.totalMail = MailFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	self.totalMail:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -60 + (FOUND_POSTAL and -24 or 0), -18)

	self:RegisterEvent("MAIL_CLOSED")
	self:RegisterEvent("MAIL_INBOX_UPDATE")
end

-- Deal swith auto looting of mail!
function Mail:StartAutoLooting()
	local total
	autoLootTotal, total = GetInboxNumItems()
	
	if( QuickAuctions.status.isCancelling and total == 0 ) then
		self.massOpening:SetText(L["Waiting..."])
		waitForCancel = true
	elseif( autoLootTotal == 0 and total == 0 ) then
		return
	end
	
	if( QuickAuctions.db.global.autoCheck and autoLootTotal == 0 and total > 0 ) then
		self.massOpening:SetText(L["Waiting..."])
	end
	
	self:RegisterEvent("UI_ERROR_MESSAGE")
	self.massOpening:Disable()
	self:AutoLoot()
end

function Mail:AutoLoot()
	-- Already looted everything after the invalid indexes we had, so fail it
	if( LOOT_MAIL_INDEX > 1 and LOOT_MAIL_INDEX > GetInboxNumItems() ) then
		if( resetIndex ) then
			self:StopAutoLooting(true)
		else
			resetIndex = true
			LOOT_MAIL_INDEX = 1
			self:AutoLoot()
		end
		return
	end
	
	local money, cod, _, items, _, _, _, _, isGM = select(5, GetInboxHeaderInfo(LOOT_MAIL_INDEX))
	if( not isGM and ( not cod or cod <= 0 ) and ( ( money and money > 0 ) or ( items and items > 0 ) ) ) then
		mailTimer = nil
		self.massOpening:SetText(L["Opening..."])
		AutoLootMailItem(LOOT_MAIL_INDEX)
	-- Can't grab the first mail, but we have a second so increase it and try again
	elseif( GetInboxNumItems() > LOOT_MAIL_INDEX ) then
		LOOT_MAIL_INDEX = LOOT_MAIL_INDEX + 1
		self:AutoLoot()
	end
end

function Mail:StopAutoLooting(failed)
	if( failed ) then
		QuickAuctions:Print(L["Cannot finish auto looting, inventory is full or too many unique items."])
	end
	
	-- Immediately send off, as we know we won't (likely) be needing anything more
	if( self:GetPendingAttachments() > 0 ) then
		self:SendMail()
	end

	resetIndex = nil
	autoLootTotal = nil
	LOOT_MAIL_INDEX = 1
	
	self:UnregisterEvent("UI_ERROR_MESSAGE")
	self.massOpening:SetText(L["Open all"])
	self.massOpening:Enable()
end

function Mail:UI_ERROR_MESSAGE(event, msg)
	if( msg == ERR_INV_FULL or msg == ERR_ITEM_MAX_COUNT ) then
		-- Send off our pending mail first to free up more room to auto loot
		if( msg == ERR_INV_FULL and activeMailTarget and self:GetPendingAttachments() > 0 ) then
			self.massOpening:SetText(L["Waiting..."])
			autoLootTotal = -1
			bagTimer = MAIL_WAIT_TIME
			eventThrottle:Show()

			self:SendMail()
			return
		end
		
		-- Try the next index in case we can still loot more such as in the case of glyphs
		LOOT_MAIL_INDEX = LOOT_MAIL_INDEX + 1
		
		-- If we've exhausted all slots, but we still have <50 and more mail pending, wait until new data comes and keep looting it
		local current, total = GetInboxNumItems()
		if( LOOT_MAIL_INDEX > current ) then
			if( LOOT_MAIL_INDEX > total and total <= 50 ) then
				self:StopAutoLooting(true)
			else
				self.massOpening:SetText(L["Waiting..."])
			end
			return
		end
		
		mailTimer = MAIL_WAIT_TIME
		eventThrottle:Show()
	end
end

function Mail:MAIL_INBOX_UPDATE()
	local current, total = GetInboxNumItems()
	-- Yay nothing else to loot, so nothing else to update the cache for!
	if( cacheFrame.endTime and current == total and lastTotal ~= total ) then
		cacheFrame.endTime = nil
		cacheFrame:Hide()
	-- Start a timer since we're over the limit of 50 items before waiting for it to recache
	elseif( ( cacheFrame.endTime and current >= 50 and lastTotal ~= total ) or ( current >= 50 and allowTimerStart ) ) then
		resetIndex = nil
		allowTimerStart = nil
		waitingForData = nil
		lastTotal = total
		cacheFrame.endTime = GetTime() + 60
		cacheFrame:Show()
	end
	
	-- We were waiting for data to show up after a cancel
	if( waitForCancel and current > 0 ) then
		waitForCancel = nil
		self:AutoLoot()
	end
	
	-- The last item we setup to auto loot is finished, time for the next one
	if( self.massOpening:IsEnabled() == 0 and autoLootTotal ~= current ) then
		autoLootTotal = GetInboxNumItems()
		
		-- If we're auto checking mail when new data is available, will wait and continue auto looting, otherwise we just stop now
		if( QuickAuctions.db.global.autoCheck and current == 0 and total > 0 ) then
			self.massOpening:SetText(L["Waiting..."])
		elseif( current == 0 and ( not QuickAuctions.db.global.autoCheck or total == 0 ) ) then
			self:StopAutoLooting()
		else
			self:AutoLoot()
		end
	end
	
	if( total > 0 ) then
		self.totalMail:SetFormattedText(L["%d mail"], total)
	else
		self.totalMail:SetText(nil)
	end
end

function Mail:MAIL_CLOSED()
	resetIndex = nil
	allowTimerStart = true
	waitingForData = nil
	self:StopAutoLooting()
end

-- Deals with auto sending mail to people
function Mail:TargetHasItems(checkLocks)
	for bag=0, 4 do
		for slot=1, GetContainerNumSlots(bag) do
			local link = QuickAuctions:GetSafeLink(GetContainerItemLink(bag, slot))
			local locked = select(3, GetContainerItemInfo(bag, slot))
			local target = QuickAuctions.db.factionrealm.mail[link] or reverseLookup[link] and QuickAuctions.db.factionrealm.mail[reverseLookup[link]]
			if( target and activeMailTarget == target and ( not checkLocks or checkLocks and not locked ) ) then
				return true
			end
		end
	end
	
	return false
end

function Mail:FindNextMailTarget()
	table.wipe(mailTargets)
	for bag=0, 4 do
		for slot=1, GetContainerNumSlots(bag) do
			local link = QuickAuctions:GetSafeLink(GetContainerItemLink(bag, slot))
			local locked = select(3, GetContainerItemInfo(bag, slot))
			local target = QuickAuctions.db.factionrealm.mail[link] or reverseLookup[link] and QuickAuctions.db.factionrealm.mail[reverseLookup[link]]
			if( not locked and target ) then
				target = string.lower(target)
				mailTargets[target] = (mailTargets[target] or 0) + 1
			end
		end
	end

	-- Obviously, we don't want to send mail to ourselves
	mailTargets[playerName] = nil
	
	-- Find the highest one to dump as much inventory as we can to make more room for looting
	local highestTarget, targetCount
	for target, count in pairs(mailTargets) do
		if( not highestTarget or targetCount < count ) then
			highestTarget = target
			targetCount = count
		end
	end
	
	return highestTarget
end

function Mail:Start()
	QuickAuctions.Manage:UpdateReverseLookup()
	activeMailTarget = self:FindNextMailTarget()
	
	-- This is more to give users the visual que that hey, it's actually going to send to this person, even thought this field has no bearing on who it's sent to
	if( activeMailTarget ) then
		SendMailNameEditBox:SetText(activeMailTarget)
	end
	
	self:RegisterEvent("BAG_UPDATE")
	self:UpdateBags()
end

function Mail:Stop()
	self:UnregisterEvent("BAG_UPDATE")
	
	bagTimer = nil
	itemTimer = nil
	waitForCancel = nil
end

function Mail:SendMail()
	if( not activeMailTarget ) then return end
	
	QuickAuctions:Print(string.format(L["Auto mailed items off to %s!"], activeMailTarget))
	SendMail(activeMailTarget, SendMailSubjectEditBox:GetText() or L["Mass mailing"], "")

	itemTimer = nil
	activeMailTarget = nil

	-- Wait twice as much time to make sure it gets sent off
	if( self.massOpening:IsEnabled() == 0 ) then
		autoLootTotal = -1
		mailTimer = MAIL_WAIT_TIME * 2
		eventThrottle:Show()
	end
end

function Mail:GetPendingAttachments()
	local totalAttached = 0
	for i=1, ATTACHMENTS_MAX_SEND do
		if( GetSendMailItem(i) ) then
			totalAttached = totalAttached + 1
		end
	end
	
	return totalAttached
end

function Mail:UpdateBags()
	-- Nothing else to send to this person, so we can send off now
	if( activeMailTarget and not self:TargetHasItems() and not itemTimer ) then
		if( self.massOpening:IsEnabled() == 0 ) then
			itemTimer = 2
			eventThrottle:Show()
		else
			self:SendMail()
		end
	end
	
	-- No mail target, let's try and find one
	if( not activeMailTarget ) then
		activeMailTarget = self:FindNextMailTarget()
		if( activeMailTarget ) then
			SendMailNameEditBox:SetText(activeMailTarget)
		end
	end

	-- If we exit before the loot after send checks then it will stop too early
	if( not activeMailTarget ) then return end

	-- Otherwise see if we can send anything off
	for bag=0, 4 do
		for slot=1, GetContainerNumSlots(bag) do
			local link = QuickAuctions:GetSafeLink(GetContainerItemLink(bag, slot))
			local quantity, locked = select(2, GetContainerItemInfo(bag, slot))
			
			if( not locked ) then lockedItems[bag .. slot] = nil end
			
			-- Can't use something that's still locked
			local target = QuickAuctions.db.factionrealm.mail[link] or reverseLookup[link] and QuickAuctions.db.factionrealm.mail[reverseLookup[link]]
			if( target and activeMailTarget and string.lower(target) == activeMailTarget ) then
				-- When creating lots of glyphs, or anything that stacks really this will stop it from sending too early
				if( locked and lockedItems[bag .. slot] and lockedItems[bag .. slot] ~= quantity ) then
					lockedItems[bag .. slot] = quantity
					itemTimer = self.massOpening:IsEnabled() == 0 and 3 or GetTradeSkillLine() == "UNKNOWN" and 1 or 10
					eventThrottle:Show()
				-- Not locked, let's add it up!
				elseif( not locked ) then
					local totalAttached = self:GetPendingAttachments()
					
					-- Too many attached, nothing we can do yet
					if( totalAttached >= ATTACHMENTS_MAX_SEND ) then return end

					PickupContainerItem(bag, slot)
					ClickSendMailItemButton()
					
					lockedItems[bag .. slot] = quantity
															
					-- Hit cap, send us off
					if( (totalAttached + 1) >= ATTACHMENTS_MAX_SEND ) then
						self:SendMail()
					-- No more unlocked items to send for this target, wait TargetHasItems
					elseif( not self:TargetHasItems(true) ) then
						itemTimer = self.massOpening:IsEnabled() == 0 and 3 or GetTradeSkillLine() == "UNKNOWN" and 1 or 10
						eventThrottle:Show()
					end
				end
			end
		end
	end
end

-- Bag updates are fun and spammy, throttle them to every 0.20 seconds
function Mail:BAG_UPDATE()
	bagTimer = 0.20
	eventThrottle:Show()
end

eventThrottle:SetScript("OnUpdate", function(self, elapsed)
	if( bagTimer ) then
		bagTimer = bagTimer - elapsed
		if( bagTimer <= 0 ) then
			bagTimer = nil
			Mail:UpdateBags()
		end
	end
	
	if( itemTimer ) then
		itemTimer = itemTimer - elapsed
		if( itemTimer <= 0 ) then
			itemTimer = nil
			
			if( activeMailTarget ) then
				Mail:SendMail()
			end
		end
	end
	
	if( mailTimer ) then
		mailTimer = mailTimer - elapsed
		if( mailTimer <= 0 ) then
			Mail:AutoLoot()
		end
	end
	
	if( not bagTimer and not itemTimer and not mailTimer ) then
		self:Hide()
	end
end)
eventThrottle:Hide()
