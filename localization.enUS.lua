-- No localization yet, once everything is a bit more stable in wording I'll start to run the localization script
QuickAuctionsLocals = setmetatable({}, {
	__index = function(tbl, value)
		rawset(tbl, value, value)
		return value
	end,
})