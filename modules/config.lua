local QuickAuctions = select(2, ...)
local Config = QuickAuctions:NewModule("Config", "AceEvent-3.0")
local L = QuickAuctions.L
local AceDialog, AceRegistry, options
local idToGroup, groupID = {}, 1

-- Make sure the item isn't soulbound
local scanTooltip
local resultsCache = {}
local function isSoulbound(bag, slot)
	if( resultsCache[bag .. slot] ~= nil ) then return resultsCache[bag .. slot] end
	if( not scanTooltip ) then
		scanTooltip = CreateFrame("GameTooltip", "QuickAuctionsScanTooltip", UIParent, "GameTooltipTemplate")
		scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")	
	end
	
	scanTooltip:ClearLines()
	scanTooltip:SetBagItem(bag, slot)
	
	for id=1, scanTooltip:NumLines() do
		local text = _G["QuickAuctionsScanTooltipTextLeft" .. id]
		if( text and text:GetText() and text:GetText() == ITEM_SOULBOUND ) then
			resultsCache[bag .. slot] = true
			return true
		end
	end
	
	resultsCache[bag .. slot] = nil
	return false
end

local function set(info, value)
	QuickAuctions.db.global[info[#(info)]] = value
end

local function get(info, value)
	return QuickAuctions.db.global[info[#(info)]]
end

local function setGroup(info, value)
	local group = info[1] == "general" and "default" or idToGroup[info[2]]
	QuickAuctions.db.profile[info[#(info)]][group] = value
end

local function getGroupSetting(key, group)
	group = idToGroup[group] or group
	if( QuickAuctions.db.profile[key][group] ~= nil ) then
		return QuickAuctions.db.profile[key][group]
	end	
	
	return QuickAuctions.db.profile[key].default
end

local function getGroup(info)
	return getGroupSetting(info[#(info)], info[2])
end

local function validateMoney(info, value)
	local gold = tonumber(string.match(value, "([0-9]+)|c([0-9a-fA-F]+)g|r") or string.match(value, "([0-9]+)g"))
	local silver = tonumber(string.match(value, "([0-9]+)|c([0-9a-fA-F]+)s|r") or string.match(value, "([0-9]+)s"))
	local copper = tonumber(string.match(value, "([0-9]+)|c([0-9a-fA-F]+)c|r") or string.match(value, "([0-9]+)c"))
	
	if( not gold and not silver and not copper ) then
		return L["Invalid monney format entered, should be \"#g#s#c\", \"25g4s50c\" is 25 gold, 4 silver, 50 copper."]
	end
	
	return true
end

local function setGroupMoney(info, value)
	local gold = tonumber(string.match(value, "([0-9]+)|c([0-9a-fA-F]+)g|r") or string.match(value, "([0-9]+)g"))
	local silver = tonumber(string.match(value, "([0-9]+)|c([0-9a-fA-F]+)s|r") or string.match(value, "([0-9]+)s"))
	local copper = tonumber(string.match(value, "([0-9]+)|c([0-9a-fA-F]+)c|r") or string.match(value, "([0-9]+)c"))
		
	-- Convert it all into copper
	copper = (copper or 0) + ((gold or 0) * COPPER_PER_GOLD) + ((silver or 0) * COPPER_PER_SILVER)
	setGroup(info, copper)
end

local function getGroupMoney(info)
	-- Being anal, if we aren't overriding, the option will be disabled so strip color codes so it all grays out
	if( info[1] ~= "general" and QuickAuctions.db.profile[info[#(info)]][idToGroup[info[2]]] == nil ) then
		local money = QuickAuctions:FormatTextMoney(getGroup(info))
		return string.trim(string.gsub(money, "|(.-)([gsc])|r", "%2"))
	end
	
	return string.trim(QuickAuctions:FormatTextMoney(getGroup(info)))
end

local function setGroupOverride(info, value)
	if( not value ) then
		QuickAuctions.db.profile[info.arg][idToGroup[info[2]]] = nil
	else
		QuickAuctions.db.profile[info.arg][idToGroup[info[2]]] = QuickAuctions.db.profile[info.arg].default
	end
end

local function getGroupOverride(info)
	if( info[1] == "general" ) then return false end
	
	return QuickAuctions.db.profile[info.arg][idToGroup[info[2]]] ~= nil
end

local function isGroupOptionDisabled(info)
	return info[1] ~= "general" and QuickAuctions.db.profile[info[#(info)]][idToGroup[info[2]]] == nil
end

local function hideForDefault(info)
	return info[1] == "general"
end

local function hideHelpText(info)
	return QuickAuctions.db.global.hideHelp
end

-- Core group settings table!
local groupSettings = {
	general = {
		order = 6,
		type = "group",
		inline = true,
		name = L["General"],
		set = setGroup,
		get = getGroup,
		disabled = isGroupOptionDisabled,
		args = {
			desc = {
				order = 1,
				type = "description",
				name = function(info)
					local postTime = getGroupSetting("postTime", info[2])
					local ignoreStacks = getGroupSetting("ignoreStacks", info[2])
					local noCancel = getGroupSetting("noCancel", info[2])
					
					if( noCancel ) then
						return string.format(L["Posting auctions for |cfffed000%d|r hours, ignoring auctions with more than |cfffed000%d|r items in them, but will not cancel auctions even if undercut."], postTime, ignoreStacks)
					else
						return string.format(L["Posting auctions for |cfffed000%d|r hours, ignoring auctions with more than |cfffed000%d|r items in them."], postTime, ignoreStacks)
					end
				end,
				hidden = hideHelpText,
			},
			header = {
				order = 2,
				type = "header",
				name = "",
				hidden = hideHelpText,
			},
			overrideStacks = {
				order = 3,
				type = "toggle",
				name = L["Override stack settings"],
				desc = L["Allows you to override the default stack ignore settings for this group."],
				hidden = hideForDefault,
				disabled = false,
				set = setGroupOverride,
				get = getGroupOverride,
				arg = "ignoreStacks",
			},
			ignoreStacks = {
				order = 4,
				type = "range",
				min = 1, max = 1000, step = 1,
				name = L["Ignore stacks over"],
				desc = L["Items that are stacked beyond the set amount are ignored when calculating the lowest market price."],
			},
			sep = {order = 5, type = "description", name = "", hidden = hideForDefault},
			overrideCancel = {
				order = 6,
				type = "toggle",
				name = L["Override cancel settings"],
				desc = L["Allows you to override the default cancel settings for this group."],
				hidden = hideForDefault,
				disabled = false,
				set = setGroupOverride,
				get = getGroupOverride,
				arg = "noCancel",
			},
			noCancel = {
				order = 7,
				type = "toggle",
				name = L["Disable auto cancelling"],
				desc = L["Disable automatically cancelling of items in this group if undercut."],
				hidden = hideForDefault,
			},
			overrideTime = {
				order = 8,
				type = "toggle",
				name = L["Override post time"],
				desc = L["Allows you to override the default post time sttings for this group."],
				hidden = hideForDefault,
				disabled = false,
				set = setGroupOverride,
				get = getGroupOverride,
				arg = "postTime",
			},
			postTime = {
				order = 9,
				type = "select",
				name = L["Post time"],
				desc = L["How long auctions should be up for."],
				values = {[12] = L["12 hours"], [24] = L["24 hours"], [48] = L["48 hours"]},
			},
		},
	},
	quantity = {
		order = 7,
		type = "group",
		inline = true,
		name = L["Quantities"],
		set = setGroup,
		get = getGroup,
		disabled = isGroupOptionDisabled,
		args = {
			desc = {
				order = 1,
				type = "description",
				name = function(info) return string.format(L["Will post at most |cfffed000%d|r auctions in stacks of |cfffed000%d|r."], getGroupSetting("postCap", info[2]), getGroupSetting("perAuction", info[2])) end,
				hidden = hideHelpText,
			},
			header = {
				order = 2,
				type = "header",
				name = "",
				hidden = hideHelpText,
			},
			overrideCap = {
				order = 3,
				type = "toggle",
				name = L["Override post cap"],
				desc = L["Allows you to override the post cap settings for this group."],
				hidden = hideForDefault,
				disabled = false,
				set = setGroupOverride,
				get = getGroupOverride,
				arg = "postCap",
			},
			postCap = {
				order = 4,
				type = "range",
				name = L["Post cap"],
				desc = L["How many auctions at the lowest price tier can be up at any one time."],
				min = 1, max = 50, step = 1,
			},
			overridePerAuction = {
				order = 5,
				type = "toggle",
				name = L["Override per auction"],
				desc = L["Allows you to override the per auction settings for this group."],
				hidden = hideForDefault,
				disabled = false,
				set = setGroupOverride,
				get = getGroupOverride,
				arg = "perAuction",
			},
			perAuction = {
				order = 6,
				type = "range",
				name = L["Per auction"],
				desc = L["How many items should be in a single auction, 20 will mean they are posted in stacks of 20."],
				min = 1, max = 1000, step = 1,
			},
		},
	},
	price = {
		order = 8,
		type = "group",
		inline = true,
		name = L["Price"],
		set = setGroup,
		get = getGroup,
		disabled = isGroupOptionDisabled,
		args = {
			desc = {
				order = 1,
				type = "description",
				name = function(info) return string.format(L["Undercutting auctions by %s until price goes below %s, unless there is greater than a |cfffed000%.2f%%|r price difference between lowest and second lowest in which case undercutting second lowest auction."], QuickAuctions:FormatTextMoney(getGroupSetting("undercut", info[2])), QuickAuctions:FormatTextMoney(getGroupSetting("threshold", info[2])), getGroupSetting("priceThreshold", info[2]) * 100) end,
				hidden = hideHelpText,
			},
			header = {
				order = 2,
				type = "header",
				name = "",
				hidden = hideHelpText,
			},
			overrideUndercut = {
				order = 3,
				type = "toggle",
				name = L["Override undercut"],
				desc = L["Allows you to override the undercut settings for this group."],
				hidden = hideForDefault,
				disabled = false,
				set = setGroupOverride,
				get = getGroupOverride,
				arg = "undercut",
			},
			undercut = {
				order = 4,
				type = "input",
				name = L["Undercut by"],
				desc = L["How much to undercut other auctions by, format is in \"#g#s#c\" but can be in any order, \"50g30s\" means 50 gold, 30 silver and so on."],
				validate = validateMoney,
				set = setGroupMoney,
				get = getGroupMoney,
			},
			overrideBid = {
				order = 5,
				type = "toggle",
				name = L["Override bid percent"],
				desc = L["Allows you to override bid percent settings for this group."],
				hidden = hideForDefault,
				disabled = false,
				set = setGroupOverride,
				get = getGroupOverride,
				arg = "bidPercent",
			},
			bidPercent = {
				order = 6,
				type = "range",
				min = 0, max = 1, step = 0.05, isPercent = true,
				name = L["Bid percent"],
				desc = L["Percentage of the buyout as bid, if you set this to 90% then a 100g buyout will have a 90g bid."],
			},
			overrideThreshold = {
				order = 7,
				type = "toggle",
				name = L["Override threshold"],
				desc = L["Allows you to override the threshold settings for this group."],
				hidden = hideForDefault,
				disabled = false,
				set = setGroupOverride,
				get = getGroupOverride,
				arg = "threshold",
			},
			threshold = {
				order = 8,
				type = "input",
				name = L["Price threshold"],
				desc = L["How low the market can go before an item should no longer be posted."],
				validate = validateMoney,
				set = setGroupMoney,
				get = getGroupMoney,
			},
			overrideGap = {
				order = 9,
				type = "toggle",
				name = L["Override price gap"],
				desc = L["Allows you to override the price gap settings for this group."],
				hidden = hideForDefault,
				disabled = false,
				set = setGroupOverride,
				get = getGroupOverride,
				arg = "priceThreshold",
			},
			priceThreshold = {
				order = 10,
				type = "range",
				name = L["Maximum price gap"],
				desc = L["How much of a difference between auction prices should be allowed before posting at the second highest value.\n\nFor example. If Apple is posting Runed Scarlet Ruby at 50g, Orange posts one at 30g and you post one at 29g, then Oranges expires. If you set price threshold to 30% then it will cancel yours at 29g and post it at 49g next time because the difference in price is 42% and above the allowed threshold."],
				min = 0.10, max = 10, step = 0.05, isPercent = true,
			},
		},
	},
	fallback = {
		order = 9,
		type = "group",
		inline = true,
		name = L["Fallbacks"],
		set = setGroup,
		get = getGroup,
		disabled = isGroupOptionDisabled,
		args = {
			desc = {
				order = 1,
				type = "description",
				name = function(info)
					local fallback = getGroupSetting("fallback", info[2])
					local fallbackCap = getGroupSetting("fallbackCap", info[2])
					local autoFallback = getGroupSetting("autoFallback", info[2])
					local threshold = getGroupSetting("threshold", info[2])
					
					if( autoFallback ) then
						return string.format(L["Once market goes below %s, auctions will be automatically posted at the fallback price of %s."], QuickAuctions:FormatTextMoney(threshold), QuickAuctions:FormatTextMoney(fallback))
					else
						return string.format(L["When no auctions are up, or the market price is above %s auctions will be posted at the fallback price of %s."], QuickAuctions:FormatTextMoney(fallback * fallbackCap), QuickAuctions:FormatTextMoney(fallback))
					end
				end,
				hidden = hideHelpText,
			},
			header = {
				order = 2,
				type = "header",
				name = "",
				hidden = hideHelpText,
			},
			overrideFallAuto = {
				order = 3,
				type = "toggle",
				name = L["Override auto fallback"],
				desc = L["Allows you to override the auto fallback settings for this group."],
				hidden = hideForDefault,
				disabled = false,
				set = setGroupOverride,
				get = getGroupOverride,
				arg = "autoFallback",
			},
			autoFallback = {
				order = 4,
				type = "toggle",
				name = L["Enable auto fallback"],
				desc = L["When the market price of an item goes below your threshold settings, it will be posted at the fallback setting instead."],
			},
			sep = {order = 4.5, type = "description", hidden = function(info) return info[1] ~= "general" end, name = ""},
			overrideFallback = {
				order = 5,
				type = "toggle",
				name = L["Override fallback"],
				desc = L["Allows you to override the fallback price for this group."],
				hidden = hideForDefault,
				disabled = false,
				set = setGroupOverride,
				get = getGroupOverride,
				arg = "fallback",
			},
			fallback = {
				order = 6,
				type = "input",
				name = L["Fallback price"],
				desc = L["Price to fallback too if there are no other auctions up, the lowest market price is too high."],
				validate = validateMoney,
				set = setGroupMoney,
				get = getGroupMoney,
			},
			overrideFallCap = {
				order = 7,
				type = "toggle",
				name = L["Override max price"],
				desc = L["Allows you to override the fallback price for this group."],
				hidden = hideForDefault,
				disabled = false,
				set = setGroupOverride,
				get = getGroupOverride,
				arg = "fallbackCap",
			},
			fallbackCap = {
				order = 8,
				type = "range",
				name = L["Maxmimum price"],
				desc = L["If the market price is above fallback price * maximum price, items will be posted at the fallback * maximum price instead.\n\nEffective for posting prices in a sane price range when someone is posting an item at 5000g when it only goes for 100g."],
				min = 1, max = 10, step = 0.10, isPercent = true,
			},
		},
	},
}

local function loadGeneralOptions()
	options.args.general = {
		order = 1,
		type = "group",
		name = L["General"],
		set = set,
		get = get,
		args = {
			generalConfig = {
				order = 2,
				type = "group",
				inline = true,
				name = L["General"],
				args = {
					hideHelp = {
						order = 2,
						type = "toggle",
						name = L["Hide help text"],
						desc = L["Hides auction setting help text throughout the group settings options."],
					},
					autoCheck = {
						order = 3,
						type = "toggle",
						name = L["Auto recheck mail"],
						desc = L["Automatically rechecks mail every 60 seconds when you have too much mail.\n\nIf you loot all mail with this enabled, it will wait and recheck then keep auto looting."],
						width = "full",
						hidden = hideIfConflictingMail,
					},
				},
			},
			cancel = {
				order = 4,
				type = "group",
				inline = true,
				name = L["Canceling"],
				args = {
					cancelBinding = {
						order = 0,
						type = "keybinding",
						name = L["Cancel binding"],
						desc = L["Quick binding you can press to cancel auctions once scan has finished.\n\nThis can be any key including space without overwriting your jump key."],
					},
					cancelWithBid = {
						order = 1,
						type = "toggle",
						name = L["Cancel auctions with bids"],
						desc = L["Will cancel auctions even if they have a bid on them, you will take an additional gold cost if you cancel an auction with bid."],
					},
					smartCancel = {
						order = 2,
						type = "toggle",
						name = L["Smart cancelling"],
						desc = L["Disables cancelling of auctions with a market price below the threshold, also will cancel auctions if you are the only one with that item up and you can relist it for more."],
					},
					playSound = {
						order = 3,
						type = "toggle",
						name = L["Play sound after scan"],
						desc = L["After a cancel scan has finished, the ready check sound will play indicating user interaction is needed."],
					},
				},
			},
			groupHelp = {
				order = 5,
				type = "group",
				inline = true,
				name = L["Help"],
				args = {
					help = {
						order = 0,
						type = "description",
						name = L["The below are fallback settings for groups, if you do not override a setting in a group then it will use the settings below."],
					},
				},
			},
		}
	}
	
	for key, data in pairs(groupSettings) do
		options.args.general.args[key] = data
	end
end

local deleteWhitelist 
local function updateWhitelist()
	table.wipe(options.args.whitelist.args.list.args)
	local order = 1
	for player, visualName in pairs(QuickAuctions.db.factionrealm.whitelist) do
		options.args.whitelist.args.list.args[player .. "text"] = {
			order = order,
			type = "description",
			name = visualName,
			fontSize = "medium",
		}
		
		options.args.whitelist.args.list.args[player] = {
			order = order + 0.25,
			type = "execute",
			name = L["Delete"],
			func = deleteWhitelist,
			width = "half",
		}
		
		options.args.whitelist.args.list.args[player .. "sep"] = {order = order + 0.50, type = "description", name = ""}
		order = order + 1
	end
	
	if( order == 1 ) then
		options.args.whitelist.args.list.args.none = {
			order = 1,
			type = "description",
			name = L["You do not have any players on your whitelist yet."],
		}
	end
end

deleteWhitelist = function(info)
	QuickAuctions.db.factionrealm.whitelist[info[#(info)]] = nil
	updateWhitelist()
end

local function loadWhitelistOptions()
	options.args.whitelist = {
		order = 2,
		type = "group",
		name = L["Whitelist"],
		args = {
			help = {
				order = 0,
				type = "group",
				inline = true,
				name = L["Help"],
				args = {
					help = {
						order = 0,
						type = "description",
						name = function(info) return not QuickAuctions.db.global.superScan and L["Whitelists allow you to set other players besides you and your alts that you do not want to undercut; however, if somebody on your whitelist matches your buyout but lists a lower bid it will still consider them undercutting."] or L["Super scan is enabled, you will not be able to use your whitelist. Disable super scanner to use the whitelist again."] end
					},
				},
			},
			add = {
				order = 1,
				type = "group",
				inline = true,
				name = L["Add player"],
				args = {
					name = {
						order = 0,
						type = "input",
						name = L["Player name"],
						desc = L["Add a new player to your whitelist."],
						validate = function(info, value)
							value = string.trim(string.lower(value or ""))
							if( value == "" ) then return L["No name entered."] end
							
							for playerID, player in pairs(QuickAuctions.db.factionrealm.whitelist) do
								return string.format(L["The player \"%s\" is already on your whitelist."], player)
							end
							
							for player in pairs(QuickAuctions.db.factionrealm.player) do
								if( string.lower(player) == value ) then
									return string.format(L["You do not need to add \"%s\", alts are whitelisted automatically."], player)
								end
							end
							
							return true
						end,
						set = function(info, value)
							QuickAuctions.db.factionrealm[string.lower(value)] = value
							updateWhitelist()
						end,
						get = false,
					},
				},
			},
			list = {
				order = 2,
				type = "group",
				inline = true,
				name = L["Whitelist"],
				args = {
					
				},
			},
		},
	}
	
	updateWhitelist()
end

local addMailItemsTable
-- Adding groups
local addGroupTable = {
	order = 1,
	type = "execute",
	name = function(info) return idToGroup[info[#(info)]] end,
	hidden = false,
	func = function(info)
		QuickAuctions.db.factionrealm.mail[idToGroup[info[#(info)]]] = info[2]
		AceRegistry:NotifyChange("QuickAuctions")
	end,
}

local function rebuildMailGroups()
	for id in pairs(addMailItemsTable.args.groups.args) do
		if( not idToGroup[id] or QuickAuctions.db.factionrealm.mail[idToGroup[id]] ) then
			addMailItemsTable.args.groups.args[id] = nil
		end
	end
	
	for id, group in pairs(idToGroup) do
		if( type(group) == "string" and not QuickAuctions.db.factionrealm.mail[group] ) then
			addMailItemsTable.args.groups.args[id] = addGroupTable
		end
	end
end

-- Adding straight items
local addItemTable = {
	order = 1,
	type = "execute",
	name = function(info) return (select(2, GetItemInfo(info[#(info)]))) end,
	image = function(info) return (select(10, GetItemInfo(info[#(info)]))) end,
	hidden = false,
	imageHeight = 16,
	imageWidth = 16,
	width = "half",
	func = function(info)
		QuickAuctions.db.factionrealm.mail[info[#(info)]] = info[2]
		addMailItemsTable.args.items.args[info[#(info)]] = nil
	end,
}
local function rebuildMailItems()
	for bag=4, 0, -1 do
		for slot=1, GetContainerNumSlots(bag) do
			local link = QuickAuctions:GetSafeLink(GetContainerItemLink(bag, slot))
			if( link and not QuickAuctions.db.factionrealm.mail[link] ) then
				addMailItemsTable.args.items.args[link] = addItemTable
			end
		end
	end
end

local function massMailItems(info, value)
	value = string.trim(string.lower(value or ""))

	for bag=4, 0, -1 do
		for slot=1, GetContainerNumSlots(bag) do
			local link = QuickAuctions:GetSafeLink(GetContainerItemLink(bag, slot))
			local name = link and string.lower(GetItemInfo(link))
			if( link and name and string.match(name, value) and not QuickAuctions.db.factionrealm.mail[link] and not isSoulbound(bag, slot) ) then
				QuickAuctions.db.factionrealm.mail[link] = info[2]
				addMailItemsTable.args.items.args[link] = nil
			end
		end
	end
end

addMailItemsTable = {
	order = 1,
	type = "group",
	name = L["Add items/groups"],
	args = {
		general = {
			order = 1,
			type = "group",
			name = L["General"],
			inline = true,
			args = {
				help = {
					order = 1,
					type = "description",
					name = function(info) return string.format(L["Click an item or group to add it to the list of items to be automatically mailed to %s."], info[2]) end,
				},
				header = {
					order = 2,
					type = "header",
					name = "",
				},
				massItem = {
					order = 3,
					type = "input",
					name = L["Add items matching"],
					desc = function(info) return string.format(L["All items that match the entered name will be automatically added to be mailed to %s, \"Glyph of\" will add all glyphs in your inventory for example."], info[2]) end,
					set = massMailItems,
					get = false,
				},
			},
		},
		groups = {
			order = 2,
			type = "group",
			name = L["Groups"],
			inline = true,
			hidden = rebuildMailGroups,
			args = {
			},
		},
		items = {
			order = 3,
			type = "group",
			name = L["Items"],
			inline = true,
			hidden = rebuildMailItems,
			args = {
			},
		},
	}
}
-- Adding groups
local addGroupTable = {
	order = 1,
	type = "execute",
	name = function(info) return idToGroup[info[#(info)]] end,
	hidden = false,
	func = function(info)
		QuickAuctions.db.factionrealm.mail[idToGroup[info[#(info)]]] = info[2]
		AceRegistry:NotifyChange("QuickAuctions")
	end,
}

local function rebuildMailGroups()
	for id in pairs(addMailItemsTable.args.groups.args) do
		if( not idToGroup[id] or QuickAuctions.db.factionrealm.mail[idToGroup[id]] ) then
			addMailItemsTable.args.groups.args[id] = nil
		end
	end
	
end

-- Remove groups
local removeMailGroup = {
	order = 1,
	type = "execute",
	name = function(info) return idToGroup[info[#(info)]] end,
	hidden = false,
	func = function(info)
		QuickAuctions.db.factionrealm.mail[idToGroup[info[#(info)]]] = nil
		options.args.mail.args[info[2]].args.remove.args.groups.args[info[#(info)]] = nil
	end,
}

local function rebuildMailRemoveGroups(info)
	for id, group in pairs(idToGroup) do
		if( type(group) == "string" and QuickAuctions.db.factionrealm.mail[group] == info[2] ) then
			options.args.mail.args[info[2]].args.remove.args.groups.args[id] = removeMailGroup
		end
	end
end

-- Removing items
local removeMailItem = {
	order = 1,
	type = "execute",
	name = function(info) return (select(2, GetItemInfo(info[#(info)]))) end,
	image = function(info) return (select(10, GetItemInfo(info[#(info)]))) end,
	hidden = false,
	imageHeight = 16,
	imageWidth = 16,
	width = "half",
	func = function(info)
		QuickAuctions.db.factionrealm.mail[info[#(info)]] = nil
		options.args.mail.args[info[2]].args.remove.args.items.args[info[#(info)]] = nil
	end,
}
local function rebuildMailRemoveItems(info)
	for link, target in pairs(QuickAuctions.db.factionrealm.mail) do
		if( target == info[2] and not QuickAuctions.db.global.groups[link] ) then
			options.args.mail.args[info[2]].args.remove.args.items.args[link] = removeMailItem
		end
	end
end

local mailTargetTable = {
	order = 1,
	type = "group",
	name = function(info) return info[#(info)] end,
	childGroups = "tab",
	args = {
		remove = {
			order = 2,
			type = "group",
			name = L["Remove items/groups"],
			args = {
				help = {
					order = 1,
					type = "group",
					name = L["Help"],
					inline = true,
					args = {
						help = {
							order = 1,
							type = "description",
							name = function(info) return string.format(L["Clicking an item or group will stop Quick Auctions from auto mailing it to %s."], info[2]) end,
						}
					},
				},
				groups = {
					order = 2,
					type = "group",
					name = L["Groups"],
					inline = true,
					hidden = rebuildMailRemoveGroups,
					args = {},
				},
				items = {
					order = 3,
					type = "group",
					name = L["Items"],
					inline = true,
					hidden = rebuildMailRemoveItems,
					args = {},
				},
			},
		},
	},
}

local function loadMailOptions()
	options.args.mail = {
		order = 3,
		type = "group",
		name = L["Auto mailer"],
		args = {
			help = {
				order = 1,
				type = "group",
				name = L["Help"],
				inline = true,
				args = {
					help = {
						order = 0,
						type = "description",
						name = L["Auto mailing will let you setup groups and specific items that should be mailed to another character.\n\nCheck your spelling! If you typo a name it will send it to the wrong person."],
					},
				},
			},
			add = {
				order = 2,
				type = "group",
				name = L["Add mail target"],
				inline = true,
				args = {
					name = {
						order = 1,
						type = "input",
						name = L["Player name"],
						validate = function(info, value)
							value = string.trim(string.lower(value or ""))
							if( value == "" ) then return L["No player name entered."] end
							
							for _, name in pairs(QuickAuctions.db.factionrealm.mail) do
								if( string.lower(name) == value ) then
									return string.format(L["Player \"%s\" is already a mail target."], name)
								end
							end
							
							return true
						end,
						set = function(info, value)
							options.args.mail.args[value] = CopyTable(mailTargetTable)
							options.args.mail.args[value].args.add = addMailItemsTable
						end,
					}
				},
			},
		}
	}
	
	for _, target in pairs(QuickAuctions.db.factionrealm.mail) do
		if( not options.args.mail.args[target] ) then
			options.args.mail.args[target] = CopyTable(mailTargetTable)
			options.args.mail.args[target].args.add = addMailItemsTable
		end
	end
end

local updateGroups

-- Remove management
local removeItemTable = {
	type = "execute",
	name = function(info) return (select(2, GetItemInfo(info[#(info)]))) or info[#(info)] end,
	image = function(info) return (select(10, GetItemInfo(info[#(info)]))) or "Interface\\Icons\\INV_Misc_QuestionMark" end,
	hidden = false,
	imageHeight = 24,
	imageWidth = 24,
	func = function(info)
		QuickAuctions.db.global.groups[idToGroup[info[2]]][info[#(info)]] = nil
		options.args.groups.args[info[2]].args.remove.args.list.args[info[#(info)]] = nil
		
		local hasItems
		for itemID in pairs(QuickAuctions.db.global.groups[idToGroup[info[2]]]) do
			hasItems = true
			break
		end
		
		if( not hasItems ) then
			options.args.groups.args[info[2]].args.remove.args.list.args.help = {
				order = 0,
				type = "description",
				name = L["No items have been added to this group yet."],
			}	
		end
		
		Config:RebuildItemList(true)
	end,
	width = "half",
}


local throttle
local addItemsTable = {
	order = 3,
	type = "group",
	inline = true,
	name = L["Item list"],
	hidden = function()
		if( not throttle or throttle <= GetTime() ) then
			throttle = GetTime() + 5
			Config:RebuildItemList(true)
		end
	end,
	args = {},
}

local addItem = {
	type = "execute",
	name = function(info) return (select(2, GetItemInfo(info[#(info)]))) end,
	image = function(info) return (select(10, GetItemInfo(info[#(info)]))) end,
	hidden = false,
	imageHeight = 24,
	imageWidth = 24,
	func = function(info)
		QuickAuctions.db.global.groups[idToGroup[info[2]]][info[#(info)]] = true
		options.args.groups.args[info[2]].args.remove.args.list.args[info[#(info)]] = removeItemTable
		options.args.groups.args[info[2]].args.remove.args.list.args.help = nil

		updateGroups()
		Config:RebuildItemList()
	end,
	width = "half",
}

-- Delete a group :(
local function deleteGroup(info)
	local group = idToGroup[info[2]]
	QuickAuctions.db.global.groups[group] = nil
	for key, data in pairs(QuickAuctions.db.profile) do
		if( type(data) == "table" and data[group] ~= nil ) then
			data[group] = nil
		end
	end
	
	updateGroups()
end

local function validateGroupRename(info, value)
	value = string.trim(string.lower(value or ""))
	for name in pairs(QuickAuctions.db.global.groups) do
		if( string.lower(name) == value ) then
			return string.format(L["Group named \"%s\" already exists!"], name)
		end
	end
	
	return true
end

local function renameGroup(info, value)
	local oldName = idToGroup[info[2]]
	local target = QuickAuctions.db.factionrealm.mail[oldName]
	if( oldTarget ) then
		QuickAuctions.db.factionrealm.mail[oldName] = nil
		QuickAuctions.db.factionreaml.mail[value] = target
	end
	
	QuickAuctions.db.global.groups[value] = CopyTable(QuickAuctions.db.global.groups[oldName])
	QuickAuctions.db.global.groups[oldName] = nil
	for key, data in pairs(QuickAuctions.db.profile) do
		if( type(data) == "table" and data[oldName] ~= nil ) then
			data[value] = data[oldName]
			data[oldName] = nil
		end
	end
	
	-- Update reference so we don't create a new entry or change pages
	idToGroup[info[2]] = value
	idToGroup[value] = true
	idToGroup[oldName] = nil
	
	updateGroups()
end

-- Mass add by name
local function massAddItems(info, value)
	value = string.trim(string.lower(value))
	
	QuickAuctions.Manage:UpdateReverseLookup()
	
	for bag=4, 0, -1 do
		for slot=1, GetContainerNumSlots(bag) do
			local link = QuickAuctions:GetSafeLink(GetContainerItemLink(bag, slot))
			local name = link and string.lower(GetItemInfo(link))
			if( link and name and string.match(name, value) and not QuickAuctions.modules.Manage.reverseLookup[link] and not isSoulbound(bag, slot) ) then
				QuickAuctions.db.global.groups[idToGroup[info[2]]][link] = true
				options.args.groups.args[info[2]].args.remove.args.list.args[link] = removeItemTable
				options.args.groups.args[info[2]].args.remove.args.list.args.help = nil
				addItemsTable.args[link] = nil
			end
		end
	end
end

function Config:RebuildItemList(updateOnChange)
	QuickAuctions.Manage:UpdateReverseLookup()
	table.wipe(addItemsTable.args)
	
	local addedItem, hasItems
	for bag=4, 0, -1 do
		for slot=1, GetContainerNumSlots(bag) do
			local link = QuickAuctions:GetSafeLink(GetContainerItemLink(bag, slot))
			if( link and not addItemsTable.args[link] and not QuickAuctions.modules.Manage.reverseLookup[link] and not isSoulbound(bag, slot) ) then
				local itemName, itemLink, _, _, _, _, _, _, _, itemTexture = GetItemInfo(link)
				addItemsTable.args[link] = addItem
				addedItem = true
				hasItems = true
			elseif( link and addItemsTable.args[link] ) then
				hasItems = true
			end
		end
	end
	
	if( not hasItems ) then
		addItemsTable.args.help = {
			order = 0,
			type = "description",
			name = L["You do not have any items to add to this group, either your inventory is empty or all the items are already in another group."]
		}
	end
	
	-- "Trick" to get event-based changes of a GUI in AceConfig
	if( updateOnChange and addedItem ) then
		AceRegistry:NotifyChange("QuickAuctions")
	end
end
					
-- General group table					
local groupTable = {
	order = 0,
	type = "group",
	childGroups = "tab",
	name = function(info) return idToGroup[info[#(info)]] end,
	args = {
		general = {
			order = 1,
			type = "group",
			name = L["Auction settings"],
			args = {
			
			},
		},
		group = {
			order = 2,
			type = "group",
			name = L["Management"],
			args = {
				rename = {
					order = 1,
					type = "group",
					name = L["Rename"],
					inline = true,
					args = {
						rename = {
							order = 0,
							type = "input",
							name = L["New group name"],
							desc = L["Rename this group to something else!"],
							validate = validateGroupRename,
							set = renameGroup,
							get = false,
						},
					},
				},
				delete = {
					order = 2,
					type = "group",
					name = L["Delete"],
					inline = true,
					args = {
						delete = {
							order = 0,
							type = "execute",
							name = L["Delete group"],
							desc = L["Delete this group, this cannot be undone!"],
							confirm = true,
							confirmText = L["Are you SURE you want to delete this group?"],
							func = deleteGroup,
						},
					},
				},
			},
		},
		add = {
			order = 3,
			type = "group",
			name = L["Add items"],
			args = {
				help = {
					order = 1,
					type = "group",
					inline = true,
					name = L["Help"],
					args = {
						help = {
							order = 1,
							type = "description",
							name = L["Click an item to add it to this group, you can only have one item in a group at any time."]
						},
					},
				},
				massAdd = {
					order = 2,
					type = "group",
					inline = true,
					name = L["Mass add"],
					args = {
						name = {
							order = 1,
							type = "input",
							name = L["Add items matching"],
							desc = L["Mass adds all items matching the below, entering \"Glyph of\" will mass add all items starting with \"Glyph of\" to this group."],
							set = massAddItems,
							get = false,
						},
					},
				},
			},
		},
		remove = {
			order = 4,
			type = "group",
			name = L["Remove items"],
			args = {
				help = {
					order = 1,
					type = "group",
					inline = true,
					name = L["Help"],
					hidden = false,
					args = {
						help = {
							order = 1,
							type = "description",
							name = L["Click an item to remove it from this group."]
						},
					},
				},
				list = {
					order = 2,
					type = "group",
					inline = true,
					name = L["Item list"],
					hidden = false,
					args = {
					
					},
				},
			},
		},
	},
}

for key, tbl in pairs(groupSettings) do groupTable.args.general.args[key] = tbl end

updateGroups = function()
	for id, group in pairs(idToGroup) do
		if( type(group) == "string" and not QuickAuctions.db.global.groups[group] ) then
			options.args.groups.args[id] = nil
			idToGroup[id] = nil
			idToGroup[group] = nil
		end
	end

	for group, items in pairs(QuickAuctions.db.global.groups) do
		if( not idToGroup[group] ) then
			idToGroup[tostring(groupID)] = group
			idToGroup[group] = true
			options.args.groups.args[tostring(groupID)] = CopyTable(groupTable)
			options.args.groups.args[tostring(groupID)].args.add.args.list = addItemsTable

			local hasItems
			for itemID in pairs(items) do
				hasItems = true
				options.args.groups.args[tostring(groupID)].args.remove.args.list.args[itemID] = removeItemTable
			end
			
			if( not hasItems ) then
				options.args.groups.args[tostring(groupID)].args.remove.args.list.args.help = {
					order = 0,
					type = "description",
					name = L["No items have been added to this group yet."],
				}
			end

			groupID = groupID + 1
		end
	end
end

local function loadGroupOptions()
	options.args.groups = {
		order = 4,
		type = "group",
		name = L["Item groups"],
		childGroups = "tree",
		args = {
			add = {
				order = 0,
				type = "group",
				name = L["Add group"],
				inline = true,
				args = {
					name = {
						order = 0,
						type = "input",
						name = L["Group name"],
						desc = L["Name of the new group, this can be whatever you want and has no relation to how the group itself functions."],
						validate = function(info, value)
							value = string.trim(string.lower(value or ""))
							for name in pairs(QuickAuctions.db.global.groups) do
								if( string.lower(name) == value ) then
									return string.format(L["Group named \"%s\" already exists!"], name)
								end
							end
							
							return true
						end,
						set = function(info, value)
							QuickAuctions.db.global.groups[value] = {}
							updateGroups()
						end,
						get = false,
					},
				},
			},
		},
	}
	
	updateGroups()
	Config:RebuildItemList()
end

local function loadPreloadOptions()
	options.args.preload = {
		order = 3,
		type = "group",
		name = L["Preload groups"],
		hidden = true,
		args = {
		
		},
	}
end

local function loadOptions()
	options = {
		type = "group",	
		name = "Quick Auctions",
		childGroups = "tree",
		args = {},
	}
	
	loadGeneralOptions()
	loadWhitelistOptions()
	loadPreloadOptions()
	loadMailOptions()
	loadGroupOptions()
	
	options.args.profile = LibStub("AceDBOptions-3.0"):GetOptionsTable(QuickAuctions.db, true)
	options.args.profile.order = 1.5
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
		if( not AceDialog and not AceRegistry ) then
			loadOptions()
			
			AceDialog = LibStub("AceConfigDialog-3.0")
			AceRegistry = LibStub("AceConfigRegistry-3.0")
			LibStub("AceConfig-3.0"):RegisterOptionsTable("QuickAuctions", options)
			AceDialog:SetDefaultSize("QuickAuctions", 700, 500)
		end
			
		AceDialog:Open("QuickAuctions")
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
