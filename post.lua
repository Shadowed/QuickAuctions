local Post = QuickAuctions:NewModule("Post", "AceEvent-3.0")
local L = QuickAuctionsLocals
local status = QuickAuctions.status

function Post:OnInitialize()
	self:RegisterMessage("SUF_AH_CLOSED", "AuctionHouseClosed")
end

function Post:AuctionHouseClosed()
	if( status.isPosting ) then
		QuickAuctions:Print(L["Posting interrupted due to Auction House being closed."])
	end
	
end

