if( GetLocale() ~= "deDE" ) then
	return
end

QuickAuctionsLocals = setmetatable({
	["Glyph"] = "Glyphe",
	["Glyphs"] = "Glyphen",
	["Trade Goods"] = "Handwerkswaren",
	["Herb"] = "Kr\195\164uter",
	["Herbs"] = "Kr\195\164uter",
	["Enchanting"] = "Verzauberkunst",
	["Gem"] = "Edelstein",
	["Gems"] = "Edelsteine",
	["Scrolls"] = "Schriftrollen",
	["Item Enhancement"] = "Gegenstandsverbesserung",
	["Consumable"] = "Verbrauchbar",
	["Flask"] = "Fl\195\164schchen",
	["Flasks"] = "Fl\195\164schchen",
	["Elixirs"] = "Elixiere",
	["Elixir"] = "Elixier",
	["Food"] = "Essen",
	["Food & Drink"] = "Essen & Trinken",
	["Elemental"] = "Elementar",
	["Enchanting"] = "Verzauberkunst",
	["Enchant materials"] = "Verzaubermaterialien",
	["Perfect (.+)"] = "Perfekter (.+)",
	["Simple"] = "Einfach",
	["Enchant scrolls"] = "Verzauberrollen",
	["Bracers"] = "Armschienen",
	["Scroll of Enchant (.+)"] = "Rolle der (.+)",
	["Scroll of Enchant (.+) %- .+"] = "Rolle der (.+) %- .+",
}, {__index = QuickAuctionsLocals}) 