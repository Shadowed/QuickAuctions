local Mail = QuickAuctions:NewModule("Mail", "AceEvent-3.0")
local L = QuickAuctionsLocals
local reverseLookup = QuickAuctions.modules.Manage.reverseLookup
local timeElapsed, itemTimer
local eventThrottle = CreateFrame("Frame")
eventThrottle:Hide()

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
	check:SetHeight(24)
	check:SetWidth(24)
	check:SetChecked(false)
	check:SetHitRectInsets(0, -70, 0, 0)
	check:SetScript("OnEnter", showTooltip)
	check:SetScript("OnLeave", hideTooltip)
	check:SetScript("OnHide", function()
		check:SetChecked(false)
		Mail:Stop()
		QuickAuctions.Manage:UpdateReverseLookup()
	end)
	check:SetScript("OnClick", function(self)
		if( self:GetChecked() ) then
			Mail:Start()
		else
			Mail:Stop()
		end
	end)
	check:SetPoint("TOPLEFT", MailFrame, "TOPLEFT", 69, -14)
	check.tooltip = L["Enables Quick Auctions auto mailer, the last patch of mails will take ~10 seconds to send.\n\n[WARNING!] You will not get any confirmation before it starts to send mails, it is your own fault if you mistype your bankers name."]
	QuickAuctionsAutoMailText:SetText(L["Auto mail"])
	QuickAuctions.Manage:UpdateReverseLookup()
	
	self.checkBox = check
	
	-- Hide Inbox/Send Mail text, it's wastes space and makes my lazyly done checkbox look bad
	InboxTitleText:Hide()
	SendMailTitleText:Hide()
end

function Mail:Start()
	if( not QuickAuctions.db.factionrealm.bank ) then
		QuickAucitons:Print(L["You have to set a banker before you can use the auto mailer."])
		self.checkBox:SetChecked(false)
		return
	elseif( string.lower(QuickAuctions.db.factionrealm.bank) == string.lower(UnitName("player")) or QuickAuctions.db.factionrealm.bank == "" ) then
		QuickAuctions:Print(L["You cannot use auto mailer on your banker as you cannot mail items to yourself."])
		self.checkBox:SetChecked(false)
		return
	end
	
	self:RegisterEvent("BAG_UPDATE")
	self:UpdateBags()
end

function Mail:Stop()
	self:UnregisterEvent("BAG_UPDATE")
	
	timeElapsed = nil
	itemTimer = nil
	eventFrame:Hide()
end

function Mail:FindTotalUnlocked()
	local total = 0
	
	for bag=0, 4 do
		for slot=1, GetContainerNumSlots(bag) do
			local link = QuickAuctions:GetSafeLink(GetContainerItemLink(bag, slot))
			local locked = select(3, GetContainerItemInfo(bag, slot))
			if( reverseLookup[link] and QuickAuctions.Manage:GetBoolConfigValue(link, "mail") and not locked ) then
				total = total + 1
			end
		end
	end
	
	return total
end

function Mail:SendMail()
	if( not QuickAuctions.db.factionrealm.bank or QuickAuctions.db.factionrealm.bank == "" ) then
		return
	end
	
	-- Make absolutely damn sure bank name is set
	SendMailNameEditBox:SetText(QuickAuctions.db.factionrealm.bank)
	SendMailFrame_SendMail()
	
	itemTimer = nil
end

function Mail:UpdateBags()
	for bag=0, 4 do
		for slot=1, GetContainerNumSlots(bag) do
			local link = QuickAuctions:GetSafeLink(GetContainerItemLink(bag, slot))
			local locked = select(3, GetContainerItemInfo(bag, slot))
			
			-- Can't use something that's still locked
			if( reverseLookup[link] and QuickAuctions.Manage:GetBoolConfigValue(link, "mail") and not locked ) then
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
				
				totalAttached = totalAttached + 1
				
				-- Hit cap, send us off
				if( totalAttached >= ATTACHMENTS_MAX_SEND ) then
					self:SendMail()
					
				-- We ran out of items that can be posted, wait 10 seconds to make no more are being crafted still
				-- then send them off
				elseif( self:FindTotalUnlocked() <= 0 ) then
					itemTimer = 10
					eventThrottle:Show()
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
			itemTimer = nil
			Mail:SendMail()
		end
	end
	
	if( not timeElapsed and not itemTimer ) then
		self:Hide()
	end
end)
