local QuickAuctions = select(2, ...)
local Mail = QuickAuctions:NewModule("Mail", "AceEvent-3.0")
local L = QuickAuctions.L

local eventThrottle = CreateFrame("Frame", nil, MailFrame)
local reverseLookup = QuickAuctions.modules.Manage.reverseLookup
local timeElapsed, itemTimer, cacheFrame, activeMailTarget
local allowTimerStart, lastTotal, autoLootTotal = true
local lockedItems, mailTargets = {}, {}
local playerName = string.lower(UnitName("player"))
local LOOT_MAIL_INDEX = 1

function Mail:OnInitialize()
	local function showTooltip(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:SetText(self.tooltip, 1, 1, 1, nil, true)
		GameTooltip:Show()
	end
	local function hideTooltip(self)
		GameTooltip:Hide()
	end

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
		if( QuickAuctions.db.global.autoMail ) then
			self:SetChecked(true)
			Mail:Start()
		end
	end)
	check:SetScript("OnClick", function(self)
		if( self:GetChecked() ) then
			QuickAuctions.db.global.autoMail = true
			Mail:Start()
		else
			QuickAuctions.db.global.autoMail = false
			Mail:Stop()
		end
	end)
	check:SetPoint("TOPLEFT", MailFrame, "TOPLEFT", 68, -13)
	check.tooltip = L["Enables Quick Auctions auto mailer, the last patch of mails will take ~10 seconds to send.\n\n[WARNING!] You will not get any confirmation before it starts to send mails, it is your own fault if you mistype your bankers name."]
	QuickAuctionsAutoMailText:SetText(L["Auto mail"])

	if( MailFrame:IsVisible() ) then
		check:GetScript("OnShow")(check)
	end
		
	-- Mass opening
	local button = CreateFrame("Button", nil, MailFrame, "UIPanelButtonTemplate")
	button:SetText(L["Open all"])
	button:SetHeight(24)
	button:SetWidth(130)
	button:SetPoint("BOTTOM", MailFrame, "CENTER", -10, -165)
	button:SetScript("OnClick", function(self) Mail:StartAutoLooting() end)

	-- Don't show mass opening if Postal is enabled since postals button will block QAs
	if( select(6, GetAddOnInfo("Postal")) == nil ) then
		button:Hide()
	end
	
	self.massOpening = button
	
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
		local seconds = self.endTime - GetTime()
		if( seconds <= 0 ) then
			self:Hide()

			-- Look for new mail
			if( QuickAuctions.db.global.autoCheck ) then
				CheckInbox()
			end
			return
		end
		
		cacheFrame.text:SetFormattedText("%d", seconds)
	end)
	cacheFrame.text = cacheFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	cacheFrame.text:SetFont(GameFontHighlight:GetFont(), 30, "THICKOUTLINE")
	cacheFrame.text:SetPoint("CENTER", MailFrame, "TOPLEFT", 40, -35)
	cacheFrame:Hide()

	self:RegisterEvent("MAIL_CLOSED")
	self:RegisterEvent("MAIL_INBOX_UPDATE")
end

function Mail:StartAutoLooting()
	if( GetInboxNumItems() == 0 ) then return end
	self.massOpening:Disable()

	autoLootTotal = GetInboxNumItems()
	self:AutoLoot()
end

function Mail:AutoLoot()
	local money, cod, _, items, _, _, _, _, isGM = select(5, GetInboxHeaderInfo(LOOT_MAIL_INDEX))
	if( ( not cod or cod <= 0 ) and not isGM and ( ( money and money > 0 ) or ( items and items > 0 ) ) ) then
		self.massOpening:SetText(L["Opening..."])
		AutoLootMailItem(LOOT_MAIL_INDEX)
	end
end

function Mail:StopAutoLooting()
	autoLootTotal = nil
	self.massOpening:SetText(L["Open all"])
	self.massOpening:Enable()
end

function Mail:MAIL_INBOX_UPDATE()
	local current, total = GetInboxNumItems()
	-- Yay nothing else to loot, so nothing else to update the cache for!
	if( cacheFrame.endTime and current == total and lastTotal ~= total ) then
		cacheFrame.endTime = nil
		cacheFrame:Hide()
	-- Start a timer since we're over the limit of 50 items before waiting for it to recache
	elseif( ( cacheFrame.endTime and current >= 50 and lastTotal ~= total ) or ( current >= 50 and allowTimerStart ) ) then
		allowTimerStart = nil
		lastTotal = total
		cacheFrame.endTime = GetTime() + 61
		cacheFrame:Show()
	end
	
	-- Handle auto looting once it finishes a mail
	if( self.massOpening:IsEnabled() == 0 and autoLootTotal ~= current ) then
		autoLootTotal = GetInboxNumItems()
		if( current == 0 and total == 0 ) then
			self:StopAutoLooting()
		elseif( current == 0 and total > 0 ) then
			self.massOpening:SetText(L["Waiting..."])
		else
			self:AutoLoot()
		end
	end
end

function Mail:MAIL_CLOSED()
	allowTimerStart = true
	self:StopAutoLooting()
end

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
	
	self:RegisterEvent("BAG_UPDATE")
	self:UpdateBags()
end

function Mail:Stop()
	self:UnregisterEvent("BAG_UPDATE")
	
	timeElapsed = nil
	itemTimer = nil
	eventThrottle:Hide()
end

function Mail:SendMail()
	itemTimer = nil

	QuickAuctions:Print(string.format(L["Auto mailed items off to %s!"], activeMailTarget))
	SendMail(activeMailTarget, SendMailSubjectEditBox:GetText() or L["Mass mailing"], "")
end

function Mail:UpdateBags()
	-- If there is no mail targets or no more items left to send for this target, find a new one
	if( not activeMailTarget or not self:TargetHasItems() ) then
		activeMailTarget = self:FindNextMailTarget()
		if( not activeMailTarget ) then return end
	end

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
					itemTimer = GetTradeSkillLine() == "UNKNOWN" and 1 or 10
					eventThrottle:Show()
				-- Not locked, let's add it up!
				elseif( not locked ) then
					local totalAttached = 0
					for i=1, ATTACHMENTS_MAX_SEND do
						if( GetSendMailItem(i) ) then
							totalAttached = totalAttached + 1
						end
					end
					
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
						itemTimer = GetTradeSkillLine() == "UNKNOWN" and 1 or 10
						eventThrottle:Show()
					end
				end
			end
		end
	end
end

-- Bag updates are fun and spammy, throttle them to every 0.20 seconds
function Mail:BAG_UPDATE()
	timeElapsed = 0.20
	eventThrottle:Show()
end

eventThrottle:SetScript("OnUpdate", function(self, elapsed)
	if( timeElapsed ) then
		timeElapsed = timeElapsed - elapsed
		if( timeElapsed <= 0 ) then
			timeElapsed = nil
			Mail:UpdateBags()
		end
	end
	
	if( itemTimer ) then
		itemTimer = itemTimer - elapsed
		if( itemTimer <= 0 ) then
			Mail:SendMail()
		end
	end
	
	if( not timeElapsed and not itemTimer ) then
		self:Hide()
	end
end)
eventThrottle:Hide()
