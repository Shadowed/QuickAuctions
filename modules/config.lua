local Config = QuickAuctions:NewModule("Config", "AceEvent-3.0")
local L = QuickAuctionsLocals
local AceGUI = LibStub("AceGUI-3.0")
local categoryTree, currentTree, configFrame
local lastTree = "general"
local timeTable = {[12] = L["12 hours"], [24] = L["24 hours"], [48] = L["48 hours"]}
local _G = getfenv(0)

--[[
	TREE BUILDER
]]--

local function sortChildren(a, b)
	return a.text < b.text
end

local function updateTree()
	currentTree = {
		{ text = L["General"], value = "general" },
		{ text = L["Whitelist"], value = "whitelist" },
		{ text = L["Item groups"], value = "groups" },
	}
	
	-- Add groups
	for name in pairs(QuickAuctions.db.profile.groups) do
		currentTree[3].children = currentTree[3].children or {}
		table.insert(currentTree[3].children, { text = name, value = name})
	end
	
	-- Remove nonexistant groups
	if( currentTree[3].children ) then
		for i=#(currentTree[3].children), 1, -1 do
			if( not QuickAuctions.db.profile.groups[currentTree[3].children[i].value] ) then
				table.remove(currentTree[3].children, i)
			end
		end

		-- Alphabetizalical the children
		table.sort(currentTree[3].children, sortChildren)
	end
			
	-- Setup the tree
	categoryTree:SetTree(currentTree)
end

--[[
	RANDOM HELPER FUNCTIONS
]]
local function showTooltip(widget)
	GameTooltip:SetOwner(widget.frame, "ANCHOR_TOPLEFT")
	GameTooltip:SetText(widget:GetUserData("name"), 1, .82, 0, 1)
	GameTooltip:AddLine(widget:GetUserData("desc"), 1, 1, 1, 1)
	GameTooltip:Show()
end

local function hideTooltip()
	GameTooltip:Hide()
end

local function valueChanged(widget, event, value)
	QuickAuctions.db.profile[widget:GetUserData("config")] = value
end

local function groupValueChanged(widget, event, value)
	QuickAuctions.db.profile[widget:GetUserData("group")][widget:GetUserData("key")] = value
end

local function groupSliderChanged(widget, event, value)
	value = math.floor((value - widget.min) / widget.step + 0.5) * widget.step + widget.min

	groupValueChanged(widget, event, value)
	widget:SetValue(value)
end

local function groupGetMoney(widget)
	local money = QuickAuctions.db.profile[widget:GetUserData("group")][widget:GetUserData("key")] or QuickAuctions.defaults.profile[widget:GetUserData("group")].default or 0
	local gold = math.floor(money / COPPER_PER_GOLD)
	local silver = math.floor((money - (gold * COPPER_PER_GOLD)) / COPPER_PER_SILVER)
	local copper = math.fmod(money, COPPER_PER_SILVER)
	
	local text = ""
	if( gold > 0 ) then
		text = text .. gold .. "g"
	end
	
	if( silver > 0 ) then
		text = text .. silver .. "s"
	end
	
	if( copper > 0 or silver == 0 and gold == 0 ) then
		text = text .. copper .. "c"
	end
	
	return text ~= "" and text
end

local function groupMoneyValueChanged(widget, event, text)
	if( text == "" ) then
		QuickAuctions.db.profile[widget:GetUserData("group")][widget:GetUserData("key")] = 0
		widget:SetText("0c")
		return
	end
	
	text = string.lower(text)
	local gold = tonumber(string.match(text, "([0-9]+)g"))
	local silver = tonumber(string.match(text, "([0-9]+)s"))
	local copper = tonumber(string.match(text, "([0-9]+)c"))
	
	-- Not a fan of using the status text for errors, need to work out a better way but you can't easily flag a widget as invisible
	-- without redrawing the entire container which I don't want to do right now :|
	if( not gold and not silver and not copper ) then
		configFrame:SetStatusText(string.format(L["Invalid money format entered for \"%s\""], widget:GetUserData("name")))
		return
	else
		configFrame:SetStatusText(nil)
	end
	
	-- Convert it all into copper
	copper = (copper or 0) + ((gold or 0) * COPPER_PER_GOLD) + ((silver or 0) * COPPER_PER_SILVER)
	
	QuickAuctions.db.profile[widget:GetUserData("group")][widget:GetUserData("key")] = copper or 0
end

--[[
	AUCTION SETTINGS
]]--
local function overrideSettings(widget, event, value)
	if( value ) then
		QuickAuctions.db.profile[widget:GetUserData("group")][widget:GetUserData("key")] = QuickAuctions.db.profile[widget:GetUserData("group")][widget:GetUserData("key")] or QuickAuctions.db.profile[widget:GetUserData("group")].default
	
		local parent = widget:GetUserData("parent")
		parent:SetDisabled(false)
		
		if( parent.SetValue ) then
			parent:SetValue(QuickAuctions.db.profile[widget:GetUserData("group")][widget:GetUserData("key")])
		elseif( parent.SetText ) then
			parent:SetText(groupGetMoney(parent))
		end
	else
		QuickAuctions.db.profile[widget:GetUserData("group")][widget:GetUserData("key")] = nil

		local parent = widget:GetUserData("parent")
		parent:SetDisabled(true)
		if( parent.SetValue ) then
			parent:SetValue(QuickAuctions.db.profile[widget:GetUserData("group")].default)
		elseif( parent.SetText ) then
			parent:SetText(nil)
		end
	end
end

local function createAuctionSettings(container, group)
	local WIDGET_WIDTH = 0.45
	
	local undercut = AceGUI:Create("EditBox")
	undercut:SetUserData("name", L["Undercut by"])
	undercut:SetUserData("desc", L["How much auctions should be undercut."])
	undercut:SetUserData("group", "undercut")
	undercut:SetUserData("key", group)
	undercut:SetCallback("OnEnter", showTooltip)
	undercut:SetCallback("OnLeave", hideTooltip)
	undercut:SetCallback("OnEnterPressed", groupMoneyValueChanged)
	undercut:SetLabel(undercut:GetUserData("name"))
	undercut:SetText(groupGetMoney(undercut))
	undercut:SetRelativeWidth(WIDGET_WIDTH)
	
	local threshold = AceGUI:Create("EditBox")
	threshold:SetUserData("name", L["Threshold price"])
	threshold:SetUserData("desc", L["The price at which an auction won't be posted, meaning if you set this to 10g then no auctions posted through Quick Auctions will go below 10g."])
	threshold:SetUserData("group", "threshold")
	threshold:SetUserData("key", group)
	threshold:SetCallback("OnEnter", showTooltip)
	threshold:SetCallback("OnLeave", hideTooltip)
	threshold:SetCallback("OnEnterPressed", groupMoneyValueChanged)
	threshold:SetLabel(threshold:GetUserData("name"))
	threshold:SetText(groupGetMoney(threshold))
	threshold:SetRelativeWidth(WIDGET_WIDTH)

	if( group ~= "default" ) then
		local enable = AceGUI:Create("CheckBox")
		enable:SetUserData("name", L["Override undercut"])
		enable:SetUserData("desc", L["Allows you to override the default undercut settings."])
		enable:SetUserData("group", "undercut")
		enable:SetUserData("key", group)
		enable:SetUserData("parent", undercut)
		enable:SetLabel(enable:GetUserData("name"))
		enable:SetCallback("OnValueChanged", overrideSettings)
		enable:SetCallback("OnEnter", showTooltip)
		enable:SetCallback("OnLeave", hideTooltip)
		enable:SetValue(QuickAuctions.db.profile[enable:GetUserData("group")][enable:GetUserData("key")] and true or false)
		enable:SetRelativeWidth(WIDGET_WIDTH)
		undercut:SetDisabled(not QuickAuctions.db.profile[enable:GetUserData("group")][enable:GetUserData("key")])
		
		container:AddChild(enable)

		local enable = AceGUI:Create("CheckBox")
		enable:SetUserData("name", L["Override threshold"])
		enable:SetUserData("desc", L["Allows you to override the default threshold settings."])
		enable:SetUserData("group", "threshold")
		enable:SetUserData("key", group)
		enable:SetUserData("parent", threshold)
		enable:SetLabel(enable:GetUserData("name"))
		enable:SetCallback("OnValueChanged", overrideSettings)
		enable:SetCallback("OnEnter", showTooltip)
		enable:SetCallback("OnLeave", hideTooltip)
		enable:SetValue(QuickAuctions.db.profile[enable:GetUserData("group")][enable:GetUserData("key")] and true or false)
		enable:SetRelativeWidth(WIDGET_WIDTH)
		threshold:SetDisabled(not QuickAuctions.db.profile[enable:GetUserData("group")][enable:GetUserData("key")])
		
		container:AddChild(enable)
		
		local sep = AceGUI:Create("Label")
		sep:SetFullWidth(true)
		container:AddChild(sep)
	end
	
	container:AddChild(undercut)
	container:AddChild(threshold)
	
	local sep = AceGUI:Create("Label")
	sep:SetFullWidth(true)
	container:AddChild(sep)

	local fallback = AceGUI:Create("EditBox")
	fallback:SetUserData("name", L["Fallback price"])
	fallback:SetUserData("desc", L["Price items should be posted at if there are no others of it's kind on the auction house."])
	fallback:SetUserData("group", "fallback")
	fallback:SetUserData("key", group)
	fallback:SetCallback("OnEnter", showTooltip)
	fallback:SetCallback("OnLeave", hideTooltip)
	fallback:SetCallback("OnEnterPressed", groupMoneyValueChanged)
	fallback:SetLabel(fallback:GetUserData("name"))
	fallback:SetText(groupGetMoney(fallback))
	fallback:SetRelativeWidth(WIDGET_WIDTH)

	local fallbackCap = AceGUI:Create("Slider")
	fallbackCap:SetUserData("name", L["Fallback after"]) 
	fallbackCap:SetUserData("desc", L["If someone posts an item at a percentage higher than the fallback, it will automatically use the fallback price instead.\n\nFor example, fallback is 100g, fallback after is set to 50% if someone posts an item at 160g it will fallback to 100g."])
	fallbackCap:SetUserData("group", "fallbackCap")
	fallbackCap:SetUserData("key", group)
	fallbackCap:SetCallback("OnEnter", showTooltip)
	fallbackCap:SetCallback("OnLeave", hideTooltip)
	fallbackCap:SetCallback("OnValueChanged", groupSliderChanged)
	fallbackCap:SetCallback("OnMouseUp", groupSliderChanged)
	fallbackCap:SetLabel(fallbackCap:GetUserData("name"))
	fallbackCap:SetSliderValues(1, 10, 0.10)
	fallbackCap:SetIsPercent(true)
	fallbackCap:SetValue(QuickAuctions.db.profile[fallbackCap:GetUserData("group")][fallbackCap:GetUserData("key")] or QuickAuctions.defaults.profile[fallbackCap:GetUserData("group")].default)
	fallbackCap:SetRelativeWidth(WIDGET_WIDTH)

	if( group ~= "default" ) then
		local enable = AceGUI:Create("CheckBox")
		enable:SetUserData("name", L["Override fallback"])
		enable:SetUserData("desc", L["Allows you to override the default fallback settings."])
		enable:SetUserData("group", "fallback")
		enable:SetUserData("key", group)
		enable:SetUserData("parent", fallback)
		enable:SetLabel(enable:GetUserData("name"))
		enable:SetCallback("OnValueChanged", overrideSettings)
		enable:SetCallback("OnEnter", showTooltip)
		enable:SetCallback("OnLeave", hideTooltip)
		enable:SetValue(QuickAuctions.db.profile[enable:GetUserData("group")][enable:GetUserData("key")] and true or false)
		enable:SetRelativeWidth(WIDGET_WIDTH)
		fallback:SetDisabled(not QuickAuctions.db.profile[enable:GetUserData("group")][enable:GetUserData("key")])
		
		container:AddChild(enable)

		local enable = AceGUI:Create("CheckBox")
		enable:SetUserData("name", L["Override fallback after"])
		enable:SetUserData("desc", L["Allows you to override the default fallback after settings."])
		enable:SetUserData("group", "fallbackCap")
		enable:SetUserData("key", group)
		enable:SetUserData("parent", fallbackCap)
		enable:SetLabel(enable:GetUserData("name"))
		enable:SetCallback("OnValueChanged", overrideSettings)
		enable:SetCallback("OnEnter", showTooltip)
		enable:SetCallback("OnLeave", hideTooltip)
		enable:SetValue(QuickAuctions.db.profile[enable:GetUserData("group")][enable:GetUserData("key")] and true or false)
		enable:SetRelativeWidth(WIDGET_WIDTH)
		fallbackCap:SetDisabled(not QuickAuctions.db.profile[enable:GetUserData("group")][enable:GetUserData("key")])
		
		container:AddChild(enable)
		
		local sep = AceGUI:Create("Label")
		sep:SetFullWidth(true)
		container:AddChild(sep)
	end
	
	container:AddChild(fallback)
	container:AddChild(fallbackCap)
	
	local postCap = AceGUI:Create("Slider")
	postCap:SetUserData("name", L["Post cap"]) 
	postCap:SetUserData("desc", L["How many auctions of the same item should be up at any one time.\n\nNote that post cap only applies if you weren't undercut, if you were undercut you can post more until you hit the post cap."])
	postCap:SetUserData("group", "postCap")
	postCap:SetUserData("key", group)
	postCap:SetCallback("OnEnter", showTooltip)
	postCap:SetCallback("OnLeave", hideTooltip)
	postCap:SetCallback("OnValueChanged", groupValueChanged)
	postCap:SetLabel(postCap:GetUserData("name"))
	postCap:SetSliderValues(1, 40, 1)
	postCap:SetValue(QuickAuctions.db.profile[postCap:GetUserData("group")][postCap:GetUserData("key")] or QuickAuctions.defaults.profile[postCap:GetUserData("group")].default)
	postCap:SetRelativeWidth(WIDGET_WIDTH)
	
	local bidPercent = AceGUI:Create("Slider")
	bidPercent:SetUserData("name", L["Bid percent"]) 
	bidPercent:SetUserData("desc", L["Percentage of the buyout the bid will be set at, if the buyout is 100g and set you set this to 90%, then the bid will be 90g."])
	bidPercent:SetUserData("group", "bidPercent")
	bidPercent:SetUserData("key", group)
	bidPercent:SetCallback("OnEnter", showTooltip)
	bidPercent:SetCallback("OnLeave", hideTooltip)
	bidPercent:SetCallback("OnValueChanged", groupSliderChanged)
	bidPercent:SetCallback("OnMouseUp", groupSliderChanged)
	bidPercent:SetLabel(bidPercent:GetUserData("name"))
	bidPercent:SetSliderValues(0, 1, 0.05)
	bidPercent:SetIsPercent(true)
	bidPercent:SetValue(QuickAuctions.db.profile[bidPercent:GetUserData("group")][bidPercent:GetUserData("key")] or QuickAuctions.defaults.profile[bidPercent:GetUserData("group")].default)
	bidPercent:SetRelativeWidth(WIDGET_WIDTH)

	if( group ~= "default" ) then
		local enable = AceGUI:Create("CheckBox")
		enable:SetUserData("name", L["Override bid percent"])
		enable:SetUserData("desc", L["Allows you to override the default bid percent settings."])
		enable:SetUserData("group", "bidPercent")
		enable:SetUserData("key", group)
		enable:SetUserData("parent", bidPercent)
		enable:SetLabel(enable:GetUserData("name"))
		enable:SetCallback("OnValueChanged", overrideSettings)
		enable:SetCallback("OnEnter", showTooltip)
		enable:SetCallback("OnLeave", hideTooltip)
		enable:SetValue(QuickAuctions.db.profile[enable:GetUserData("group")][enable:GetUserData("key")] and true or false)
		enable:SetRelativeWidth(WIDGET_WIDTH)
		bidPercent:SetDisabled(not QuickAuctions.db.profile[enable:GetUserData("group")][enable:GetUserData("key")])
		
		container:AddChild(enable)

		local enable = AceGUI:Create("CheckBox")
		enable:SetUserData("name", L["Override post cap"])
		enable:SetUserData("desc", L["Allows you to override the default post cap settings."])
		enable:SetUserData("group", "postCap")
		enable:SetUserData("key", group)
		enable:SetUserData("parent", postCap)
		enable:SetLabel(enable:GetUserData("name"))
		enable:SetCallback("OnValueChanged", overrideSettings)
		enable:SetCallback("OnEnter", showTooltip)
		enable:SetCallback("OnLeave", hideTooltip)
		enable:SetValue(QuickAuctions.db.profile[enable:GetUserData("group")][enable:GetUserData("key")] and true or false)
		enable:SetRelativeWidth(WIDGET_WIDTH)
		postCap:SetDisabled(not QuickAuctions.db.profile[enable:GetUserData("group")][enable:GetUserData("key")])
		
		container:AddChild(enable)
		
		local sep = AceGUI:Create("Label")
		sep:SetFullWidth(true)
		container:AddChild(sep)
	end
	
	container:AddChild(bidPercent)
	container:AddChild(postCap)

	local perAuction = AceGUI:Create("Slider")
	perAuction:SetUserData("name", L["Items per auction"]) 
	perAuction:SetUserData("desc", L["How many items each auction should contain, if the item cannot stack it will always post at least one item."])
	perAuction:SetUserData("group", "perAuction")
	perAuction:SetUserData("key", group)
	perAuction:SetCallback("OnEnter", showTooltip)
	perAuction:SetCallback("OnLeave", hideTooltip)
	perAuction:SetCallback("OnValueChanged", groupSliderChanged)
	perAuction:SetCallback("OnMouseUp", groupSliderChanged)
	perAuction:SetLabel(perAuction:GetUserData("name"))
	perAuction:SetSliderValues(1, 40, 1)
	perAuction:SetValue(QuickAuctions.db.profile[perAuction:GetUserData("group")][perAuction:GetUserData("key")] or QuickAuctions.defaults.profile[perAuction:GetUserData("group")].default)
	perAuction:SetRelativeWidth(WIDGET_WIDTH)

	local postTime = AceGUI:Create("Dropdown")
	postTime:SetUserData("name", L["Post time"]) 
	postTime:SetUserData("desc", L["How long auctions should be posted for."])
	postTime:SetUserData("group", "postTime")
	postTime:SetUserData("key", group)
	postTime:SetCallback("OnEnter", showTooltip)
	postTime:SetCallback("OnLeave", hideTooltip)
	postTime:SetCallback("OnValueChanged", groupValueChanged)
	postTime:SetLabel(postTime:GetUserData("name"))
	local hours = QuickAuctions.db.profile[postTime:GetUserData("group")][postTime:GetUserData("key")] or QuickAuctions.defaults.profile[postTime:GetUserData("group")].default
	postTime:SetValue(hours)
	postTime:SetText(timeTable[hours])
	postTime:SetList(timeTable)
	postTime:SetRelativeWidth(WIDGET_WIDTH)
	
	if( group ~= "default" ) then
		local enable = AceGUI:Create("CheckBox")
		enable:SetUserData("name", L["Override per auction"])
		enable:SetUserData("desc", L["Allows you to override the default items per auction."])
		enable:SetUserData("group", "perAuction")
		enable:SetUserData("key", group)
		enable:SetUserData("parent", perAuction)
		enable:SetLabel(enable:GetUserData("name"))
		enable:SetCallback("OnValueChanged", overrideSettings)
		enable:SetCallback("OnEnter", showTooltip)
		enable:SetCallback("OnLeave", hideTooltip)
		enable:SetValue(QuickAuctions.db.profile[enable:GetUserData("group")][enable:GetUserData("key")] and true or false)
		enable:SetRelativeWidth(WIDGET_WIDTH)
		perAuction:SetDisabled(not QuickAuctions.db.profile[enable:GetUserData("group")][enable:GetUserData("key")])
		
		container:AddChild(enable)

		local enable = AceGUI:Create("CheckBox")
		enable:SetUserData("name", L["Override post time"])
		enable:SetUserData("desc", L["Allows you to override the default post time settings."])
		enable:SetUserData("group", "postTime")
		enable:SetUserData("key", group)
		enable:SetUserData("parent", postTime)
		enable:SetLabel(enable:GetUserData("name"))
		enable:SetCallback("OnValueChanged", overrideSettings)
		enable:SetCallback("OnEnter", showTooltip)
		enable:SetCallback("OnLeave", hideTooltip)
		enable:SetValue(QuickAuctions.db.profile[enable:GetUserData("group")][enable:GetUserData("key")] and true or false)
		enable:SetRelativeWidth(WIDGET_WIDTH)
		postTime:SetDisabled(not QuickAuctions.db.profile[enable:GetUserData("group")][enable:GetUserData("key")])
		
		container:AddChild(enable)
	end
	
	container:AddChild(perAuction)
	container:AddChild(postTime)
end

--[[
	GENERAL CONFIGURATION
]]--
local function generalConfig(container)
	local general = AceGUI:Create("InlineGroup")
	general:SetTitle(L["General"])
	general:SetLayout("Flow")
	general:SetFullWidth(true)
	container:AddChild(general)

	-- Cancel items with bids
	local cancel = AceGUI:Create("CheckBox")
	cancel:SetUserData("name", L["Cancel auctions with bids"])
	cancel:SetUserData("desc", L["Will cancel your auctions even if they have a bid on them."])
	cancel:SetUserData("config", "cancelWithBid")
	cancel:SetCallback("OnEnter", showTooltip)
	cancel:SetCallback("OnLeave", hideTooltip)
	cancel:SetCallback("OnValueChanged", valueChanged)
	cancel:SetLabel(cancel:GetUserData("name"))
	cancel:SetValue(QuickAuctions.db.profile[cancel:GetUserData("config")])
	cancel:SetFullWidth(true)
	
	general:AddChild(cancel)
	
	-- Smart Undercut
	local undercut = AceGUI:Create("CheckBox")
	undercut:SetUserData("name", L["Smart undercutting"])
	undercut:SetUserData("desc", L["Prices will be rounded to the nearest gold piece when undercutting, meaning instead of posting an auction for 1 gold and 50 silver, it would be posted for 1 gold."])
	undercut:SetUserData("config", "smartUndercut")
	undercut:SetCallback("OnEnter", showTooltip)
	undercut:SetCallback("OnLeave", hideTooltip)
	undercut:SetCallback("OnValueChanged", valueChanged)
	undercut:SetLabel(undercut:GetUserData("name"))
	undercut:SetValue(QuickAuctions.db.profile[undercut:GetUserData("config")])
	
	general:AddChild(undercut)

	-- Smart Cancel
	local cancel = AceGUI:Create("CheckBox")
	cancel:SetUserData("name", L["Smart cancelling"])
	cancel:SetUserData("desc", L["Your auctions will not be cancelled if the price goes below your threshold."])
	cancel:SetUserData("config", "smartCancel")
	cancel:SetCallback("OnEnter", showTooltip)
	cancel:SetCallback("OnLeave", hideTooltip)
	cancel:SetCallback("OnValueChanged", valueChanged)
	cancel:SetLabel(cancel:GetUserData("name"))
	cancel:SetValue(QuickAuctions.db.profile[cancel:GetUserData("config")])
	
	general:AddChild(cancel)	
	
	-- Help indicating what the default item settings do
	local help = AceGUI:Create("InlineGroup")
	help:SetTitle(L["Help"])
	help:SetLayout("Flow")
	help:SetFullWidth(true)
	container:AddChild(help)
	
	local helpText = AceGUI:Create("Label")
	helpText:SetText(L["You can set the fallback settings to use for items that do not have one set specifically for their group, or per item.\n\nMoney values should be entered as \"#g#s#c\". For example, \"50g20s\" is entered as 50 gold, 20 silver."])
	helpText:SetFullWidth(true)
	help:AddChild(helpText)
	
	-- Default auction settings
	local default = AceGUI:Create("InlineGroup")
	default:SetTitle(L["Default auction settings"])
	default:SetLayout("Flow")
	default:SetFullWidth(true)
	container:AddChild(default)
	
	createAuctionSettings(default, "default")
end

--[[
	WHITELIST CONFIGURATION
]]--
local deleteWhitelist
local function updateWhitelist(container)
	container:ReleaseChildren()
	
	local row = 0
	for id, name in pairs(QuickAuctions.db.factionrealm.whitelist) do
		row = row + 1
		if( row % 2 == 0 ) then
			local seperator = AceGUI:Create("Label")
			seperator:SetRelativeWidth(0.10)
			container:AddChild(seperator)
		end
		
		local label = AceGUI:Create("Label")
		label:SetText(name)
		label:SetRelativeWidth(0.25)
		container:AddChild(label)
		
		local delete = AceGUI:Create("Button")
		delete:SetUserData("id", id)
		delete:SetUserData("container", container)
		delete:SetText(L["Remove"])
		delete:SetCallback("OnClick", deleteWhitelist)
		delete:SetRelativeWidth(0.20)
		delete:SetHeight(19)
		container:AddChild(delete)
			
	end
	
	if( row == 0 ) then
		local listEmpty = AceGUI:Create("Label")
		listEmpty:SetText(L["You have nobody on your whitelist yet."])
		listEmpty:SetFullWidth(true)
		container:AddChild(listEmpty)
	end
end

deleteWhitelist = function(widget, event)
	QuickAuctions.db.factionrealm.whitelist[widget:GetUserData("id")] = nil
	updateWhitelist(widget:GetUserData("container"))
end

local function addWhitelist(widget, event, value)
	if( value == "" ) then
		configFrame:SetStatusText(L["No player name entered."])
		return
	end
	
	QuickAuctions.db.factionrealm.whitelist[string.lower(value)] = value

	configFrame:SetStatusText(nil)
	widget:SetText(nil)
	
	updateWhitelist(widget:GetUserData("container"))
end

local function whitelistConfig(container)
	-- Help
	local help = AceGUI:Create("InlineGroup")
	help:SetTitle(L["Help"])
	help:SetLayout("Flow")
	help:SetFullWidth(true)
	container:AddChild(help)
	
	local helpText = AceGUI:Create("Label")
	helpText:SetText(L["Whistlists give you a way of setting others users who Quick Auctions should not undercut; however, if they match your buyout and undercut your bid they will still be considered undercutting.\n\nWhile your alts are not shown in this list, your alts will be considered yourself automatically."])
	helpText:SetFullWidth(true)
	help:AddChild(helpText)
	
	-- Add new player to whitelist
	local addList = AceGUI:Create("InlineGroup")
	addList:SetTitle(L["Add new player"])
	addList:SetLayout("Flow")
	addList:SetFullWidth(true)
	container:AddChild(addList)
	
	local add = AceGUI:Create("EditBox")
	add:SetUserData("name", L["Player name"]) 
	add:SetUserData("desc", L["Adds a new player to the whitelist so they will not be undercut."])
	add:SetCallback("OnEnter", showTooltip)
	add:SetCallback("OnLeave", hideTooltip)
	add:SetLabel(add:GetUserData("name"))
	add:SetRelativeWidth(0.35)
	add:SetCallback("OnEnterPressed", addWhitelist)
	add:SetText(nil)
	addList:AddChild(add)
	
	-- Actual listing
	local whitelist = AceGUI:Create("InlineGroup")
	whitelist:SetTitle(L["List"])
	whitelist:SetLayout("Flow")
	whitelist:SetFullWidth(true)
	container:AddChild(whitelist)
	add:SetUserData("container", whitelist)
	
	updateWhitelist(whitelist)
end

--[[
	GROUP CONFIGURATION
]]
local confirmGroup, oldStrata
local function deleteGroup(widget, event)
	if( not StaticPopupDialogs["QUICKAUCTIONS_CONFIRM_DELETE"] ) then
		StaticPopupDialogs["QUICKAUCTIONS_CONFIRM_DELETE"] = {
			text = L["Are you sure you want to delete this group?"],
			button1 = L["Yes"],
			button2 = L["No"],
			OnAccept = function(dialog)
				dialog:SetFrameStrata(oldStrata)

				QuickAuctions.db.profile.groups[confirmGroup] = nil
				QuickAuctions.db.profile.undercut[confirmGroup] = nil
				QuickAuctions.db.profile.postTime[confirmGroup] = nil
				QuickAuctions.db.profile.bidPercent[confirmGroup] = nil
				QuickAuctions.db.profile.fallback[confirmGroup] = nil
				QuickAuctions.db.profile.fallbackCap[confirmGroup] = nil
				QuickAuctions.db.profile.threshold[confirmGroup] = nil
				QuickAuctions.db.profile.postCap[confirmGroup] = nil
				QuickAuctions.db.profile.perAuction[confirmGroup] = nil
				
				updateTree()
				categoryTree:SelectByPath("groups")
			end,
			OnCancel = function(dialog)
				dialog:SetFrameStrata(oldStrata)
			end,
			timeout = 30,
			whileDead = 1,
			hideOnEscape = 1,
		}
	end

	confirmGroup = widget:GetUserData("id")

	local dialog = StaticPopup_Show("QUICKAUCTIONS_CONFIRM_DELETE")
	oldStrata = dialog:GetFrameStrata()
	dialog:SetFrameStrata("TOOLTIP")
end

local function addGroup(widget, event, value)
	local name = string.lower(value)
	for groupName in pairs(QuickAuctions.db.profile.groups) do
		if( string.lower(groupName) == name ) then
			configFrame:SetStatusText(string.format(L["The group \"%s\" already exists."], value))
			return
		end
	end
	
	configFrame:SetStatusText(nil)

	QuickAuctions.db.profile.groups[value] = {}
	updateTree()
	categoryTree:SelectByPath("groups", value)
end

local function groupGeneralConfig(container)
	createAuctionSettings(container, container:GetUserData("id"))
	
	local sep = AceGUI:Create("Label")
	sep:SetFullWidth(true)
	sep:SetHeight(50)
	container:AddChild(sep)
	
	local delete = AceGUI:Create("Button")
	delete:SetText(L["Delete"])
	delete:SetRelativeWidth(0.20)
	delete:SetUserData("id", container:GetUserData("id"))
	delete:SetCallback("OnClick", deleteGroup)
	container:AddChild(delete)
end

local function showItemTooltip(widget)
	GameTooltip:SetOwner(widget:GetUserData("icon") or widget.frame, "ANCHOR_TOPLEFT")
	if( widget:GetUserData("validLink") ) then
		GameTooltip:SetHyperlink(widget:GetUserData("itemID"))
	else
		GameTooltip:SetText(L["Item data not found, you will need to see this item before the name is shown."], 1, .82, 0, 1)
	end
	GameTooltip:Show()
end

local deleteItemFromGroup
local function updateEditGroupList(container)
	container:ReleaseChildren()
	
	-- InteractiveLabel tries to automatically move icons to the top if theres not enough width available, which I don't want
	-- it should always have it on the side no matter what
	local row = 0
	for itemID in pairs(QuickAuctions.db.profile.groups[container:GetUserData("id")]) do
		local itemName, itemLink, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
		
		if( row % 2 == 0 ) then
			local sep = AceGUI:Create("Label")
			sep:SetFullWidth(true)
			container:AddChild(sep)
		end

		row = row + 1
		
		local icon = AceGUI:Create("InteractiveLabel")
		icon:SetImage(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
		icon:SetUserData("group", container:GetUserData("id"))
		icon:SetUserData("itemID", itemID)
		icon:SetUserData("validLink", itemLink)
		icon:SetUserData("container", container)
		icon:SetCallback("OnClick", deleteItemFromGroup)
		icon:SetCallback("OnEnter", showItemTooltip)
		icon:SetCallback("OnLeave", hideTooltip)
		icon:SetImageSize(22, 22)
		icon:SetHighlight(0, 0, 0, 0)
		icon:SetRelativeWidth(0.10)

		container:AddChild(icon)
		
		local item = AceGUI:Create("InteractiveLabel")
		item:SetText(itemLink or itemID)
		item:SetUserData("group", container:GetUserData("id"))
		item:SetUserData("icon", icon.frame)
		item:SetUserData("itemID", itemID)
		item:SetUserData("validLink", itemLink)
		item:SetUserData("container", container)
		item:SetCallback("OnClick", deleteItemFromGroup)
		item:SetCallback("OnEnter", showItemTooltip)
		item:SetCallback("OnLeave", hideTooltip)
		item:SetRelativeWidth(0.35)
		item:SetHeight(20)
		
		container:AddChild(item)
	end
	
	if( row == 0 ) then
		local listEmpty = AceGUI:Create("Label")
		listEmpty:SetText(string.format(L["The %s group does not have any items in it yet."], container:GetUserData("id")))
		listEmpty:SetFullWidth(true)
		container:AddChild(listEmpty)
	end
end

deleteItemFromGroup = function(widget)
	QuickAuctions.db.profile.groups[widget:GetUserData("group")][widget:GetUserData("itemID")] = nil
	updateEditGroupList(widget:GetUserData("container"))
end

local function groupDeleteConfig(container)
	-- Help
	local help = AceGUI:Create("InlineGroup")
	help:SetTitle(L["Help"])
	help:SetLayout("Flow")
	help:SetFullWidth(true)
	container:AddChild(help)
	
	local helpText = AceGUI:Create("Label")
	helpText:SetText(L["Click an item to remove it from this group."])
	helpText:SetFullWidth(true)
	help:AddChild(helpText)
	
	-- Do item list
	local items = AceGUI:Create("InlineGroup")
	items:SetTitle(L["Items"])
	items:SetFullWidth(true)
	items:SetLayout("Flow")
	items:SetUserData("id", container:GetUserData("id"))
	container:AddChild(items)
	
	updateEditGroupList(items)
end

-- Make sure the item isn't soulbound
local scanTooltip
local function isSoulbound(bag, slot)
	if( not scanTooltip ) then
		scanTooltip = CreateFrame("GameTooltip", "QuickAuctionsScanTooltip", UIParent, "GameTooltipTemplate")
		scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")	
	end
	
	scanTooltip:ClearLines()
	scanTooltip:SetBagItem(bag, slot)
	
	for id=1, scanTooltip:NumLines() do
		local text = _G["QuickAuctionsScanTooltipTextLeft" .. id]
		if( text and text:GetText() and string.match(text:GetText(), ITEM_SOULBOUND) ) then
			return true
		end
	end
	
	return false
end

local function isAlreadyGrouped(itemID)
	for _, itemList in pairs(QuickAuctions.db.profile.groups) do
		if( itemList[itemID] ) then
			return true
		end
	end
	
	return false
end

local addItemToGroup
local alreadyListed = {}
local function updateAddGroupList(container)
	container:ReleaseChildren()

	local row = 0
	for bag=4, 0, -1 do
		if( QuickAuctions:IsValidBag(bag) ) then
			for slot=1, GetContainerNumSlots(bag) do
				local link = GetContainerItemLink(bag, slot)
				local itemID = QuickAuctions:GetSafeLink(link)
				if( link and not alreadyListed[itemID] and not isSoulbound(bag, slot) and not isAlreadyGrouped(itemID) ) then
					local itemName, itemLink, _, _, _, _, _, _, _, itemTexture = GetItemInfo(link)
					
					if( row % 2 == 0 ) then
						local sep = AceGUI:Create("Label")
						sep:SetFullWidth(true)
						container:AddChild(sep)
					end
					row = row + 1
					
					local icon = AceGUI:Create("InteractiveLabel")
					icon:SetImage(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
					icon:SetUserData("group", container:GetUserData("id"))
					icon:SetUserData("itemID", itemID)
					icon:SetUserData("validLink", itemLink)
					icon:SetUserData("container", container)
					icon:SetCallback("OnClick", addItemToGroup)
					icon:SetCallback("OnEnter", showItemTooltip)
					icon:SetCallback("OnLeave", hideTooltip)
					icon:SetImageSize(22, 22)
					icon:SetHighlight(0, 0, 0, 0)
					icon:SetRelativeWidth(0.10)

					container:AddChild(icon)
					
					local item = AceGUI:Create("InteractiveLabel")
					item:SetText(itemLink or itemID)
					item:SetUserData("group", container:GetUserData("id"))
					item:SetUserData("icon", icon.frame)
					item:SetUserData("itemID", itemID)
					item:SetUserData("validLink", itemLink)
					item:SetUserData("container", container)
					item:SetCallback("OnClick", addItemToGroup)
					item:SetCallback("OnEnter", showItemTooltip)
					item:SetCallback("OnLeave", hideTooltip)
					item:SetRelativeWidth(0.35)
					item:SetHeight(20)
					
					container:AddChild(item)

					alreadyListed[itemID] = true
				end
			end
		end
	end
	
	if( row == 0 ) then
		local listEmpty = AceGUI:Create("Label")
		listEmpty:SetText(L["Either your inventory is empty, or all of the items inside it are already listed in other groups."])
		listEmpty:SetFullWidth(true)
		container:AddChild(listEmpty)
	end

	table.wipe(alreadyListed)
end

addItemToGroup = function(widget)
	QuickAuctions.db.profile.groups[widget:GetUserData("group")][widget:GetUserData("itemID")] = true
	updateAddGroupList(widget:GetUserData("container"))
end

local function addByFilter(widget, event, value)
	value = string.trim(string.lower(value))
	
	local added = true
	for bag=4, 0, -1 do
		if( QuickAuctions:IsValidBag(bag) ) then
			for slot=1, GetContainerNumSlots(bag) do
				local link = GetContainerItemLink(bag, slot)
				if( link and not isSoulbound(bag, slot) and not isAlreadyGrouped(itemID) ) then
					local name = string.lower(GetItemInfo(link))
					if( string.match(name, value) ) then
						QuickAuctions.db.profile.groups[widget:GetUserData("id")][QuickAuctions:GetSafeLink(link)] = true
						added = true
					end
				end
			end
		end
	end
	
	widget:SetText(nil)
	
	if( added ) then
		updateAddGroupList(widget:GetUserData("container"))
	end
end

local function groupAddConfig(container)
	-- Help
	local help = AceGUI:Create("InlineGroup")
	help:SetTitle(L["Help"])
	help:SetLayout("Flow")
	help:SetFullWidth(true)
	container:AddChild(help)
	
	local helpText = AceGUI:Create("Label")
	helpText:SetText(L["Click an item to add it to this group, you cannot add an item that is already in another group.\n\nYou can enter a search and it will automatically add any item from your inventory that matches the filter."])
	helpText:SetFullWidth(true)
	help:AddChild(helpText)
	
	-- Add all matching filter
	local filterContainer = AceGUI:Create("InlineGroup")
	filterContainer:SetTitle(L["Add items matching filter"])
	filterContainer:SetLayout("Flow")
	filterContainer:SetFullWidth(true)
	container:AddChild(filterContainer)
	
	local add = AceGUI:Create("EditBox")
	add:SetUserData("name", L["Add items matching filter"]) 
	add:SetUserData("desc", L["Items in your inventory (and only your inventory) that match the filter will be added to this group."])
	add:SetUserData("id", container:GetUserData("id"))
	add:SetCallback("OnEnter", showTooltip)
	add:SetCallback("OnLeave", hideTooltip)
	add:SetRelativeWidth(0.50)
	add:SetCallback("OnEnterPressed", addByFilter)
	add:SetText(nil)
	filterContainer:AddChild(add)
	
	-- Do item list
	local items = AceGUI:Create("InlineGroup")
	items:SetTitle(L["Items"])
	items:SetFullWidth(true)
	items:SetLayout("Flow")
	items:SetUserData("id", container:GetUserData("id"))
	container:AddChild(items)
	
	add:SetUserData("container", items)
	
	updateAddGroupList(items)
end

-- Tabs for group selection
local function groupTabSelected(container, event, selected)
	container:ReleaseChildren()
	container:SetLayout("Fill")
	
	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("Flow")
	scroll:SetFullHeight(true)
	scroll:SetFullWidth(true)
	scroll:SetUserData("id", container:GetUserData("id"))
	
	if( selected == "general" ) then
		groupGeneralConfig(scroll)
	elseif( selected == "delete" ) then
		groupDeleteConfig(scroll)
	elseif( selected == "add" ) then
		groupAddConfig(scroll)
	end
	
	container:AddChild(scroll)
end

local groupTabs = {{value = "general", text = L["General"]}, {value = "add", text = L["Add items"]}, {value = "delete", text = L["Remove items"]}}
local function groupsConfig(container, id)
	local tabGroup = AceGUI:Create("TabGroup")
	tabGroup:SetCallback("OnGroupSelected", groupTabSelected)
	tabGroup:SetUserData("id", id)
	tabGroup:SetTabs(groupTabs)
	tabGroup:SetLayout("Flow")
	tabGroup:SelectTab("general")
	tabGroup:SetFullWidth(true)
	tabGroup:SetFullHeight(true)
	container:AddChild(tabGroup)
end


local function manageGroupsConfig(container)
	-- Help
	local help = AceGUI:Create("InlineGroup")
	help:SetTitle(L["Help"])
	help:SetLayout("Flow")
	help:SetFullWidth(true)
	container:AddChild(help)
	
	local helpText = AceGUI:Create("Label")
	helpText:SetText(L["Groups are both how you list items to be managed by Quick Auctions as well as giving you finer control for auction configuration.\n\nYou cannot have the same item in multiple groups at the same time."])
	helpText:SetFullWidth(true)
	help:AddChild(helpText)
	
	-- Create a new group
	local addList = AceGUI:Create("InlineGroup")
	addList:SetTitle(L["Add new group"])
	addList:SetLayout("Flow")
	addList:SetFullWidth(true)
	container:AddChild(addList)
	
	local add = AceGUI:Create("EditBox")
	add:SetUserData("name", L["Group name"]) 
	add:SetUserData("desc", L["Creates a new group in Quick Auctions."])
	add:SetCallback("OnEnter", showTooltip)
	add:SetCallback("OnLeave", hideTooltip)
	add:SetLabel(add:GetUserData("name"))
	add:SetRelativeWidth(0.50)
	add:SetCallback("OnEnterPressed", addGroup)
	add:SetText(nil)
	addList:AddChild(add)
end


local function categorySelected(container, event, selected)
	container:ReleaseChildren()
	container:SetLayout("Fill")
	
	-- Save last selected group for next time someone opens QA config in this session
	lastTree = selected
	
	local scroll
	if( selected == "general" or selected == "whitelist" or selected == "groups" ) then
		scroll = AceGUI:Create("ScrollFrame")
		scroll:SetLayout("Flow")
		scroll:SetFullHeight(true)
		scroll:SetFullWidth(true)
	end
	
	if( selected == "general" ) then
		generalConfig(scroll)
	elseif( selected == "whitelist" ) then
		whitelistConfig(scroll)
	else
		local selected, id = string.split("\001", selected)
		if( selected == "groups" ) then
			if( id ) then
				groupsConfig(container, id)
			else
				manageGroupsConfig(scroll)
			end
		end
	end

	if( scroll ) then
		container:AddChild(scroll)
	end
end

-- Create the core frame
local old_CloseSpecialWindows
local function createOptions()
	-- This seems to be the easiest way to hide AceGUI frames when ESCAPE is hit, which seems silly but a decent quick solution
	if( not old_CloseSpecialWindows ) then
		old_CloseSpecialWindows = CloseSpecialWindows
		CloseSpecialWindows = function()
			local found = old_CloseSpecialWindows()
			if( configFrame:IsVisible() ) then
				configFrame:Hide()
				return true
			end

			return found
		end
	end
	
	-- Create the category selection tree
	categoryTree = AceGUI:Create("TreeGroup")
	categoryTree:SetCallback("OnGroupSelected", categorySelected)
	categoryTree:SetStatusTable({groups = {["groups"] = true}})
	categoryTree:SelectByPath(lastTree)
	
	updateTree()

	-- Create the frame container
	local frame = AceGUI:Create("Frame")
	frame:SetTitle("Quick Auctions")
	frame:SetCallback("OnClose", function(container) AceGUI:Release(container) end)
	frame:SetLayout("Fill")
	frame:AddChild(categoryTree)
	frame:SetHeight(450)
	frame:SetWidth(700)
	frame:Show()
	
	configFrame = frame
end

SLASH_QA1 = nil
SLASH_QUICKAUCTION1 = nil

SLASH_QUICKAUCTIONS1 = "/qa"
SLASH_QUICKAUCTIONS2 = "/quickauction"
SLASH_QUICKAUCTIONS3 = "/quickauctions"
SlashCmdList["QUICKAUCTIONS"] = function(msg)
	local cmd, arg = string.split(" ", msg or "", 2)
	cmd = string.lower(cmd or "")
	
	-- Mass cancel
	if( cmd == "cancelall" ) then
		if( AuctionFrame and AuctionFrame:IsVisible() ) then
			local parsedArg = string.trim(string.lower(arg or ""))
			
			local groupName, cancelTime
			if( tonumber(parsedArg) ) then
				parsedArg = tonumber(parsedArg)
				if( parsedArg ~= 12 and parsedArg ~= 2 ) then
					QuickAuctions:Print(string.format(L["Invalid time entered, should either be 12 or 2 you entered \"%s\""], parsedArg))
					return
				end
				
				cancelTime = parsedArg == 12 and 3 or 2
				--1 = <30 minutes, 2 = <2 hours, 3 = <12 hours, 4 = <13 hours
				
			elseif( parsedArg ~= "" ) then
				for name in pairs(QuickAuctions.db.profile.groups) do
					if( string.lower(name) == parsedArg ) then
						groupName = name
						break
					end
				end

				if( not groupName ) then
					QuickAuctions:Print(string.format(L["No group named %s exists."], arg))
					return
				end
			end
			
			QuickAuctions.Manage:CancelAll(groupName, cancelTime)
		else
			QuickAuctions:Print(L["Cannot cancel auctions without the Auction House window open."])
		end
	-- Configuration
	elseif( cmd == "config" ) then
		if( not configFrame or not configFrame:IsVisible() ) then
			createOptions()
			configFrame:Show()
		else
			configFrame:Hide()
		end
	-- Tradeskill
	elseif( cmd == "tradeskill" ) then
		if( QuickAuctions.Tradeskill.frame and QuickAuctions.Tradeskill.frame:IsVisible() ) then
			QuickAuctions.Tradeskill.frame:Hide()
		else
			QuickAuctions.Tradeskill:CreateFrame()
			QuickAuctions.Tradeskill.frame:Show()
		end
		
	-- Summary
	elseif( cmd == "summary" ) then
		QuickAuctions.Summary:Toggle()
	else
		QuickAuctions:Print(L["Slash commands"])
		QuickAuctions:Echo(L["/qa cancelall <group/12/2> - Cancels all active auctions, or cancels auctions in a group if you pass one, or cancels auctions with less than 12 or 2 hours left."])
		QuickAuctions:Echo(L["/qa summary - Shows the auction summary"])
		QuickAuctions:Echo(L["/qa tradeskill - Toggles showing the craft queue window for tradeskills"])
		QuickAuctions:Echo(L["/qa config - Toggles the configuration"])
	end
end
