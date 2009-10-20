if( GetLocale() ~= "ruRU" ) then
	return
end

QuickAuctionsLocals = setmetatable({
	["Glyph"] = "Символы",
	["Glyphs"] = "Символы",
	["Trade Goods"] = "Хозяйственные товары",
	["Herb"] = "Трава",
	["Herbs"] = "Трава",
	["Enchanting"] = "Зачаровывание",
	["Gem"] = "Самоцветы",
	["Gems"] = "Самоцветы",
	["Scrolls"] = "Свитки",
	["Item Enhancement"] = "Улучшения",
	["Consumable"] = "Расходуемые",
	["Flask"] = "Настой",
	["Flasks"] = "Настойки",
	["Elixirs"] = "Эликсиры",
	["Elixir"] = "Эликсир",
	["Food"] = "Еда",
	["Food & Drink"] = "Еда и напитки",
	["Elemental"] = "Стихии",
	["Enchanting"] = "Зачаровывание",
	["Enchant materials"] = "Наложение чар",
	["Perfect (.+)"] = "Совершенный (.+)",
	["Simple"] = "Простая",
	["Enchant scrolls"] = "Свитки улучшений",
	["Bracers"] = "Браслеты",
	["Scroll of Enchant (.+)"] = "Свиток чар для (.+)",
	["Scroll of Enchant (.+) %- .+"] = "Свиток чар для (.+) %- .+",
}, {__index = QuickAuctionsLocals})
