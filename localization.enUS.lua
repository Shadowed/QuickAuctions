QuickAuctionsLocals = {
	-- Misc things
	["DB format upgraded, reset configuration."] = "DB format upgraded, reset configuration.",
	["Quick Auctions"] = "Quick Auctions",
	
	["View a summary of what the highest selling of certain items is."] = "View a summary of what the highest selling of certain items is.",
	["Summarize"] = "Summarize",
	
	["Scan posted auctions to see if any were undercut."] = "Scan posted auctions to see if any were undercut.",
	["Post items from your inventory into the auction house."] = "Post items from your inventory into the auction house.",

	["Done cancelling auctions."] = "Done cancelling auctions.",
	["Done posting auctions."] = "Done posting auctions.",

	["Scan Items"] = "Scan Items",
	["Post Items"] = "Post Items",

	["%d/%d items"] = "%d/%d items",
	
	["You only have %d of %s, and posting it in stacks of %d, not posting."] = "You only have %d of %s, and posting it in stacks of %d, not posting.",
	["No data found for %s, using %s buyout and %s bid default."] = "No data found for %s, using %s buyout and %s bid default.",
	["Cannot post remaining auctions, you do not have enough money."] = "Cannot post remaining auctions, you do not have enough money.",
	["Not posting %s, because the buyout is %s per item and the threshold is %s"] = "Not posting %s, because the buyout is %s per item and the threshold is %s",
	["Undercut on %s, by %s, buyout %s, bid %s, our buyout %s, our bid %s (per item)"] = "Undercut on %s, by %s, buyout %s, bid %s, our buyout %s, our bid %s (per item)",
	["Undercut on %s, by %s, buyout %s, our buyout %s (per item), threshold is %s so not cancelling."] = "Undercut on %s, by %s, buyout %s, our buyout %s (per item), threshold is %s so not cancelling.",
	["Nothing to cancel, all auctions are the lowest price."] = "Nothing to cancel, all auctions are the lowest price.",
	
	-- Slash commands
	["Invalid time \"%s\" passed, should be 12, 24 or 48."] = "Invalid time \"%s\" passed, should be 12, 24 or 48.",
	["Invalid item link, or item type passed."] = "Invalid item link, or item type passed.",
	["Invalid money format given, should be #g for gold, #s for silver, #c for copper. For example: 5g2s10c would set it 5 gold, 2 silver, 10 copper."] = "Invalid money format given, should be #g for gold, #s for silver, #c for copper. For example: 5g2s10c would set it 5 gold, 2 silver, 10 copper.",
	["Invalid number passed."] = "Invalid number passed.",
	["Invalid item link given."] = "Invalid item link given.",
	["Invalid item type toggle entered."] = "Invalid item type toggle entered.",

	["Added %s to the whitelist."] = "Added %s to the whitelist.",
	["Always cancelling if someone undercuts us."] = "Always cancelling if someone undercuts us.",
	["Only cancelling if the lowest price isn't below the threshold."] = "Only cancelling if the lowest price isn't below the threshold.",	
	
	["Now managing %s in Quick Auctions! Will post auctions with %s x %d"] = "Now managing %s in Quick Auctions! Will post auctions with %s x %d",
	["Now managing the item %s in Quick Auctions!"] = "Now managing the item %s in Quick Auctions!",

	["The item %s can only stack up to %d, you provided %d so set it to %d instead."] = "The item %s can only stack up to %d, you provided %d so set it to %d instead.",
	["The item %s can stack up to %d, you must set the quantity that it should post them in."] = "The item %s can stack up to %d, you must set the quantity that it should post them in.",

	["Smart undercutting is now disabled."] = "Smart undercutting is now disabled.",
	["Smart undercutting is now enabled."] = "Smart undercutting is now enabled.",

	["Bids will now be %d%% of the buyout price for all items."] = "Bids will now be %d%% of the buyout price for all items.",
	
	["Default post cap for auctions set to %s."] = "Default post cap for auctions set to %s.", 
	["Default threshold for auctions set to %s."] = "Default threshold for auctions set to %s.", 
	["Default fall back for auctions set to %s."] = "Default fall back for auctions set to %s.", 
	["Default undercut for auctions set to %s."] = "Default undercut for auctions set to %s.", 

	["No longer posting all %s."] = "No longer posting all %s.",
	["Now posting all %s."] = "Now posting all %s.",
	
	["Enabled super auctioning!"] = "Enabled super auctioning!",
	["Disabled super auctioning!"] = "Disabled super auction!",
	["[%s] Scan running..."] = "[%s] Scan running...",

	["Set undercut for %s to %s."] = "Set undercut for %s to %s.", 
	["Set threshold for %s to %s."] = "Set threshold for %s to %s.", 
	["Set post cap for %s to %s."] = "Set post cap for %s to %s.", 
	["Set auction time to %d hours."] = "Set auction time to %d hours.",
	["Set fall back for %s to %s."] = "Set fall back for %s to %s.", 
	
	["Removed undercut on %s."] = "Removed undercut on %s.",
	["Removed fall back on %s."] = "Removed fall back on %s.",
	["Removed %s from whitelist."] = "Removed %s from whitelist.",
	["Removed %s from the managed auctions list."] = "Removed %s from the managed auctions list.",
	["Removed post cap on %s."] = "Removed post cap on %s.",
	["Removed threshold on %s."] = "Removed threshold on %s.",
	
	["Slash commands"] = "Slash commands",
	["/qa smartcut - Toggles smart undercutting (Going from 1.9g -> 1g first instead of 1.9g - undercut amount."] = "/qa smartcut - Toggles smart undercutting (Going from 1.9g -> 1g first instead of 1.9g - undercut amount.",
	["/qa cancel - Disables undercutting if the lowest price falls below the the threshold."] = "/qa cancel - Disables undercutting if the lowest price falls below the the threshold.",
	["/qa bidpercent <0-100> - Percentage of the buyout that the bid should be, 200g buyout and this set at 90 will put the bid at 180g."] = "/qa bidpercent <0-100> - Percentage of the buyout that the bid should be, 200g buyout and this set at 90 will put the bid at 180g.",
	["/qa time <12/24/48> - Amount of hours to put auctions up for, only works for the current sesson."] = "/qa time <12/24/48> - Amount of hours to put auctions up for, only works for the current sesson.",
	["/qa undercut <money> <link/type> - How much to undercut people by."] = "/qa undercut <money> <link/type> - How much to undercut people by.",
	["/qa cap <amount> <link/type> - Only allow <amount> of the same kind of auction to be up at the same time."] = "/qa cap <amount> <link/type> - Only allow <amount> of the same kind of auction to be up at the same time.",
	["/qa fallback <money> <link/type> - How much money to default to if nobody else has an auction up."] = "/qa fallback <money> <link/type> - How much money to default to if nobody else has an auction up.",
	["/qa threshold <money> <link/type> - Don't post any auctions that would go below this amount."] = "/qa threshold <money> <link/type> - Don't post any auctions that would go below this amount.",
	["/qa addwhite <name> - Adds a name to the whitelist to not undercut."] = "/qa addwhite <name> - Adds a name to the whitelist to not undercut.",
	["/qa removewhite <name> - Removes a name from the whitelist."] = "/qa removewhite <name> - Removes a name from the whitelist.",
	["/qa additem <link> <quantity> - Adds an item to the list of things that should be managed, *IF* the item can stack you must provide a quantity to post it in."] = "/qa additem <link> <quantity> - Adds an item to the list of things that should be managed, *IF* the item can stack you must provide a quantity to post it in.",
	["/qa removeitem <link> - Removes an item from the managed list."] = "/qa removeitem <link> - Removes an item from the managed list.",
	["/qa toggle <gems/uncut/glyphs/enchants> - Lets you toggle entire categories of items: All cut gems, all uncut gems, and all glyphs. These will always be put onto the AH as the single item, if you want to override it to post multiple then use the additem command."] = "/qa toggle <gems/uncut/glyphs/enchants> - Lets you toggle entire categories of items: All cut gems, all uncut gems, and all glyphs. These will always be put onto the AH as the single item, if you want to override it to post multiple then use the additem command.",
	["/qa summary - Toggles the summary frame."] = "/qa summary - Toggles the summary frame.",
	["/qa cancelall - Cancel all of your auctions. REGARDLESS of if you were undercut or not."] = "/qa cancelall - Cancel all of your auctions. REGARDLESS of if you were undercut or not.",
	
	-- Summary
	["Stop"] = "Stop",
	["Auction House must be visible for you to use this."] = "Auction House must be visible for you to use this.",
	["Get Data"] = "Get Data",
	
	["Gems"] = "Gems",
	["Gem"] = "Gem",
	
	["Bracer"] = "Bracer",
	["Bracers"] = "Bracers",

	["Glyphs"] = "Glyphs",
	["Glyph"] = "Glyph",

	["Consumable"] = "Consumable",
	["Enchanting"] = "Enchanting",

	["Trade Goods"] = "Trade Goods",
	["Item Enhancement"] = "Item Enhancement",

	["Enchant scrolls"] = "Enchant scrolls",
	["Enchant materials"] = "Enchant materials",
	
	["Scroll of Enchant (.+) %- .+"] = "Scroll of Enchant (.+) %- .+",
	["Scroll of Enchant (.+)"] = "Scroll of Enchant (.+)",

	["Cannot find class or sub class index, localization issue perhaps?"] = "Cannot find class or sub class index, localization issue perhaps?",
}