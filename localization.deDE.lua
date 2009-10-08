if( GetLocale() ~= "deDE" ) then
	return
end

QuickAuctionsLocals = setmetatable({
	["Glyph"] = "Glyphe",
	["Glyphs"] = "Glyphen",
	["Trade Goods"] = "Handwerkswaren",
	["Herbs"] = "Kräuter",
	["Herb"] = "Kräuter",
	["Enchanting"] = "Verzauberkunst",
	["Gem"] = "Edelstein",
	["Gems"] = "Edelstein",
	["Scrolls"] = "Schriftrollen",
	["Item Enhancement"] = "Gegenstandsverbesserung",
	["Consumable"] = "Verbrauchbar",
	["Flasks"] = "Fläschchen",
	["Flask"] = "Fläschchen",
	["Elixirs"] = "Elixiere",
	["Elixir"] = "Elixier",
	["Food"] = "Essen & Trinken",
	["Food & Drink"] = "Essen & Trinken",
	["Elemental"] = "Elementar",
	["Enchanting"] = "Verzauberkunst",
	["Enchant materials"] = "Verzauberkunst",
	["Perfect (.+)"] = "Perfekt (.+)",
	["Simple"] = "Einfach",
	["Enchant scrolls"] = "Rolle",
	["Bracers"] = "Armschienen",
	["Scroll of Enchant (.+)"] = "Rolle der (.+)verzauberung",
	["Scroll of Enchant (.+) %- .+ "] = "Rolle der (.+)verzauberung %-+",
}, {__index = QuickAuctionsLocals}) 