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
			categories = {},
			undercut = {default = 0},
			postTime = {default = 12},
			bidPercent = {default = 1.0},
			fallback = {default = 0},
			fallbackCap = {default = 5},
			threshold = {default = 0},
			postCap = {default = 4},
			perAuction = {default = 1},
		},
		global = {
			summaryItems = {}
		},
		factionrealm = {
			crafts = {},
			craftQueue = {},
			player = {},
			whitelist = {},
		},
	}
	
	self.db = LibStub:GetLibrary("AceDB-3.0"):New("QuickAuctionsDB", self.defaults, true)
	self.Scan = self.modules.Scan
	self.Manage = self.modules.Manage
	self.Split = self.modules.Split
	self.Post = self.modules.Post
	self.Summary = self.modules.Summary
	self.Tradeskill = self.modules.Tradeskill
	
	-- Add this character to the alt list so it's not undercut by the player
	self.db.factionrealm.player[UnitName("player")] = true
	
	-- Reset settings
	if( QuickAuctionsDB.revision ) then
		for key in pairs(QuickAuctionsDB) do
			if( key ~= "profileKeys" and key ~= "profiles" ) then
				QuickAuctionsDB[key] = nil
			end
		end
	end

	-- Wait for auction house to be loaded
	self:RegisterMessage("QA_AH_LOADED", "AuctionHouseLoaded")
	self:RegisterEvent("ADDON_LOADED", function(event, addon)
		if( IsAddOnLoaded("Blizzard_AuctionUI") ) then
			QuickAuctions:UnregisterEvent("ADDON_LOADED")
			QuickAuctions:SendMessage("QA_AH_LOADED")
		end
	end)
end

function QuickAuctions:WipeLog()
	logLine = nil
	table.wipe(statusLog)

	self:UpdateStatusLog()
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
	-- This hides the <player>'s Auctions text
	AuctionsTitle:Hide()
	
	-- Hook auction OnHide to interrupt scans if we have to
	AuctionFrame:HookScript("OnHide", function(self)
		QuickAuctions:SendMessage("QA_AH_CLOSED")
	end)

	-- Block system messages for auctions being removed or posted
	local orig_ChatFrame_SystemEventHandler = ChatFrame_SystemEventHandler
	ChatFrame_SystemEventHandler = function(self, event, msg, ...)
		if( msg == ERR_AUCTION_REMOVED and status.isCancelling or msg == ERR_AUCTION_STARTED and status.isPosting ) then
			return true
		end
		
		return orig_ChatFrame_SystemEventHandler(self, event, msg, ...)
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
		QuickAuctions.Summary:Toggle()
	end)
	
	self.buttons.summary = button
	
	-- Post inventory items
	local button = CreateFrame("Button", nil, AuctionFrameAuctions, "UIPanelButtonTemplate")
	button.tooltip = L["Post items from your inventory into the auction house."]
	button:SetPoint("TOPRIGHT", self.buttons.summary, "TOPLEFT", -25, 0)
	button:SetText(L["Post"])
	button:SetWidth(80)
	button:SetHeight(18)
	button:SetScript("OnEnter", showTooltip)
	button:SetScript("OnLeave", hideTooltip)
	button:SetScript("OnClick", function(self)
		QuickAuctions.Manage:PostScan()
	end)
	
	self.buttons.post = button

	-- Scan our posted items
	local button = CreateFrame("Button", nil, AuctionFrameAuctions, "UIPanelButtonTemplate")
	button.tooltip = L["Cancels any posted auctions that you were undercut on."]
	button:SetPoint("TOPRIGHT", self.buttons.post, "TOPLEFT", -10, 0)
	button:SetText(L["Cancel"])
	button:SetWidth(80)
	button:SetHeight(18)
	button:SetScript("OnEnter", showTooltip)
	button:SetScript("OnLeave", hideTooltip)
	button:SetScript("OnClick", function(self)
		QuickAuctions.Manage:CancelScan()
	end)
	
	self.buttons.cancel = button

	-- Status scans what items we have in our inventory/auction
	--[[
	local button = CreateFrame("Button", nil, AuctionFrameAuctions, "UIPanelButtonTemplate")
	button.tooltip = L["Does a status scan that helps to identify auctions you can buyout to raise the price of a group your managing.\n\nThis will NOT automatically buy items for you, this just suggests that you might be able to."]
	button:SetPoint("TOPRIGHT", self.buttons.cancel, "TOPLEFT", -10, 0)
	button:SetText(L["Status"])
	button:SetWidth(80)
	button:SetHeight(18)
	button:SetScript("OnEnter", showTooltip)
	button:SetScript("OnLeave", hideTooltip)
	button:SetScript("OnClick", function(self)
	end)
	
	self.buttons.status = button
	]]
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

	local frame = CreateFrame("Frame", nil, AuctionFrameAuctions)
	frame:SetBackdrop(backdrop)
	frame:SetBackdropColor(0, 0, 0, 0.95)
	frame:SetBackdropBorderColor(0.60, 0.60, 0.60, 1)
	frame:SetFrameLevel(30)
	frame:SetFrameStrata("HIGH")
	frame:SetHeight(1)
	frame:SetWidth(1)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", AuctionsQualitySort, "BOTTOMLEFT", -2, -2)
	frame:SetPoint("BOTTOMRIGHT", AuctionsCloseButton, "TOPRIGHT", -5, 2)
	frame:SetScript("OnShow", function() QuickAuctions:UpdateStatusLog() end)
	frame:EnableMouse(true)
	frame:Hide()

	frame.rows = {}

	for i=1, 21 do
		local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetWidth(1)
		text:SetHeight(16)
		text:SetJustifyH("LEFT")
		text:SetTextColor(0.90, 0.90, 0.90, 1)

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

-- Stolen from Tekkub!
local GOLD_TEXT = "|cffffd700g|r"
local SILVER_TEXT = "|cffc7c7cfs|r"
local COPPER_TEXT = "|cffeda55fc|r"

-- Truncate tries to save space, after 10g stop showing copper, after 100g stop showing silver
function QuickAuctions:FormatTextMoney(money, truncate)
	local gold = math.floor(money / COPPER_PER_GOLD)
	local silver = math.floor((money - (gold * COPPER_PER_GOLD)) / COPPER_PER_SILVER)
	local copper = math.floor(math.fmod(money, COPPER_PER_SILVER))
	local text = ""
	
	-- Add gold
	if( gold > 0 ) then
		text = gold .. GOLD_TEXT .. " "
	end
	
	-- Add silver
	if( silver > 0 and ( not truncate or gold < 100 ) ) then
		text = text .. silver .. SILVER_TEXT .. " "
	end
	
	-- Add copper if we have no silver/gold found, or if we actually have copper
	if( text == "" or ( copper > 0 and ( not truncate or gold <= 10 ) ) ) then
		text = text .. copper .. COPPER_TEXT
	end
	
	return string.trim(text)
end

-- Makes sure this bag is an actual bag and not an ammo, soul shard, etc bag
function QuickAuctions:IsValidBag(bag)
	if( bag == 0 or bag == -1 ) then return true end
	
	-- family 0 = bag with no type, family 1/2/4 are special bags that can only hold certain types of items
	local itemFamily = GetItemFamily(GetInventoryItemLink("player", ContainerIDToInventoryID(bag)))
	return itemFamily == 0 or itemFamily > 4
end

function QuickAuctions:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99Quick Auctions|r: %s", msg))
end

function QuickAuctions:Echo(msg)
	DEFAULT_CHAT_FRAME:AddMessage(msg)
end
