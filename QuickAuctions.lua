QuickAuctions = LibStub("AceAddon-3.0"):NewAddon("QuickAuctions", "AceEvent-3.0")
QuickAuctions.status = {}

local L = QuickAuctionsLocals
local status = QuickAuctions.status
local statusLog, logLine, playerName, playerID = {}

-- Addon loaded
function QuickAuctions:OnInitialize()
	self.defaults = {
		profile = {
			showStatus = true,
			smartUndercut = false,
			smartCancel = true,
			cancelWithBid = true,
			groups = {},
			undercut = {default = 0},
			postTime = {default = 12},
			bidPercent = {default = 1.0},
			fallback = {default = 0},
			fallbackCap = {default = 5},
			threshold = {default = 0},
		},
		realm = {
			player = {},
			whitelist = {},
		},
	}
	
	self.db = LibStub:GetLibrary("AceDB-3.0"):New("QuickAuctionsDB", self.defaults, true)
	self.Scan = self.modules.Scan
	self.Post = self.modules.Post
	
	-- Add this character to the alt list so it's not undercut by the player
	self.db.realm.player[UnitName("player")] = true
	
	-- Reset settings
	if( QuickAuctionsDB.revision ) then
		for key in pairs(QuickAuctionsDB) do
			if( key ~= "profileKeys" and key ~= "profiles" ) then
				QuickAuctionsDB[key] = nil
			end
		end
	end

	-- Wait for auction house to be loaded
	self:RegisterMessage("SUF_AH_LOADED", "AuctionHouseLoaded")
	self:RegisterEvent("ADDON_LOADED", function(event, addon)
		if( IsAddOnLoaded("Blizzard_AuctionUI") ) then
			QuickAuctions:UnregisterEvent("ADDON_LOADED")
			QuickAuctions:SendMessage("SUF_AH_LOADED")
		end
	end)
end

-- Doing the new line stuff so I can do live updates and show "X item Page #/#" without adding # new lines
function QuickAuctions:Log(msg, newLine)
	if( newLine or not logLine ) then logLine = #(statusLog) + 1 end
	statusLog[logLine] = msg

	self:UpdateStatusLog()
end

function QuickAuctions:UpdateStatusLog()
	if( not self.statusFrame or not self.statusFrame:IsVisible() ) then return end
	
	local offset = math.max(0, #(statusLog) - #(self.statusFrame.rows))
	for id, row in pairs(self.statusFrame.rows) do
		row:SetText(statusLog[offset + id])
		row:Show()
	end
	
	for i=#(statusLog) + 1, #(self.statusFrame.rows) do
		self.statusFrame.rows[i]:Hide()
	end
end

function QuickAuctions:AuctionHouseLoaded()
	-- Hook auction OnHide to interrupt scans if we have to
	AuctionFrame:HookScript("OnHide", function(self)
		QuickAuctions:SendMessage("SUF_AH_CLOSED")
	end)

	-- Block system messages for auctions being removed or posted
	local orig_ChatFrame_SystemEventHandler = ChatFrame_SystemEventHandler
	ChatFrame_SystemEventHandler = function(self, event, msg)
		if( msg == ERR_AUCTION_REMOVED and status.isCancelling ) then
			return true
		elseif( msg == ERR_AUCTION_STARTED and status.isPosting ) then
			return true
		end
		
		return orig_ChatFrame_SystemEventHandler(self, event, msg)
	end

	-- Tooltips!
	local function showTooltip(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:SetText(self.tooltip)
		GameTooltip:Show()
	end
	
	local function hideTooltip(self)
		GameTooltip:Hide()
	end
	
	self.buttons = {}

	-- Show status for posting
	local button = CreateFrame("Button", nil, AuctionFrameAuctions, "UIPanelButtonTemplate")
	button.tooltip = L["Displays the Quick Auctions log describing what it's currently scanning, posting or cancelling."]
	button:SetPoint("TOPRIGHT", AuctionFrameAuctions, "TOPRIGHT", 51, -15)
	button:SetWidth(80)
	button:SetHeight(18)
	button:SetText(L["Log"])
	button:SetScript("OnEnter", showTooltip)
	button:SetScript("OnLeave", hideTooltip) 
	button:SetScript("OnShow", function(self)
		if( QuickAuctions.db.profile.showStatus ) then
			self:LockHighlight()

			QuickAuctions:CreateStatus()
			QuickAuctions.statusFrame:Show()
		end
	end)
	button:SetScript("OnClick", function(self)
		QuickAuctions.db.profile.showStatus = not QuickAuctions.db.profile.showStatus

		if( QuickAuctions.db.profile.showStatus ) then
			self:LockHighlight()

			QuickAuctions:CreateStatus()
			QuickAuctions.statusFrame:Show()
		else
			self:UnlockHighlight()
			
			if( QuickAuctions.statusFrame ) then
				QuickAuctions.statusFrame:Hide()
			end
		end
	end)
	
	self.buttons.status = button
	
	-- Scan our posted items
	local button = CreateFrame("Button", nil, AuctionFrameAuctions, "UIPanelButtonTemplate")
	button.tooltip = L["View a summary of what the highest selling of certain items is."]
	button:SetPoint("TOPRIGHT", self.buttons.status, "TOPLEFT", 0, 0)
	button:SetText(L["Summary"])
	button:SetWidth(80)
	button:SetHeight(18)
	button:SetScript("OnEnter", showTooltip)
	button:SetScript("OnLeave", hideTooltip) 
	button:SetScript("OnClick", function(self)
	end)
	
	self.buttons.summary = button
	
	-- Post inventory items
	local button = CreateFrame("Button", nil, AuctionFrameAuctions, "UIPanelButtonTemplate")
	button.tooltip = L["Post items from your inventory into the auction house."]
	button:SetPoint("TOPRIGHT", self.buttons.summary, "TOPLEFT", 0, 0)
	button:SetText(L["Post"])
	button:SetWidth(80)
	button:SetHeight(18)
	button:SetScript("OnEnter", showTooltip)
	button:SetScript("OnLeave", hideTooltip)
	button:SetScript("OnClick", function(self)
	end)
	
	self.buttons.post = button

	-- Scan our posted items
	local button = CreateFrame("Button", nil, AuctionFrameAuctions, "UIPanelButtonTemplate")
	button.tooltip = L["Cancels any posted auctions that you were undercut on."]
	button:SetPoint("TOPRIGHT", self.buttons.post, "TOPLEFT", 0, 0)
	button:SetText(L["Cancel"])
	button:SetWidth(80)
	button:SetHeight(18)
	button:SetScript("OnEnter", showTooltip)
	button:SetScript("OnLeave", hideTooltip)
	button:SetScript("OnClick", function(self)
	end)
	
	self.buttons.cancel = button
end

function QuickAuctions:GetSafeLink(link)
	link = string.match(link or "", "|H(.-):([-0-9]+):([0-9]+)|h")
	
	-- If the link just has trailing zeros, then we don't need to store that data
	return link and string.gsub(link, ":0:0:0:0:0:0", "")
end

function QuickAuctions:CreateStatus()
	if( self.statusFrame ) then return end
	
	local backdrop = {
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeSize = 1,
		insets = {left = 1, right = 1, top = 1, bottom = 1}}

	local frame = CreateFrame("Frame", nil, AuctionsScrollFrame)
	frame:SetBackdrop(backdrop)
	frame:SetBackdropColor(0, 0, 0, 1)
	frame:SetBackdropBorderColor(0.60, 0.60, 0.60, 1)
	frame:SetFrameLevel(25)
	frame:SetHeight(1)
	frame:SetWidth(1)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", BrowseCurrentBidSort, "BOTTOMLEFT", -220, 28)
	frame:SetPoint("BOTTOMRIGHT", AuctionsCloseButton, "TOPRIGHT", -26, 2)
	frame:SetScript("OnShow", function() QuickAuctions:UpdateStatusLog() end)
	frame:Hide()

	frame.rows = {}

	for i=1, 21 do
		local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetWidth(1)
		text:SetHeight(16)
		text:SetJustifyH("LEFT")

		if( i > 1 ) then
			text:SetPoint("TOPLEFT", frame.rows[i - 1], "BOTTOMLEFT", 0, 0)
			text:SetPoint("TOPRIGHT", frame.rows[i - 1], "BOTTOMRIGHT", 0, 0)
		else
			text:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, 0)
			text:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, 0)
		end

		frame.rows[i] = text
	end
	
	
	self.statusFrame = frame
end

function QuickAuctions:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99Quick Auctions|r: %s", msg))
end

function QuickAuctions:Echo(msg)
	DEFAULT_CHAT_FRAME:AddMessage(msg)
end
