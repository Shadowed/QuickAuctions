QuickAuctionsLocals = setmetatable({}, {
	__index = function(tbl, value)
		rawset(tbl, value, value)
		return value
	end,
})