QA.Tradeskill = {}

local Tradeskill = QA.Tradeskill
local professions = {
	[GetSpellInfo(2259)] = "Alchemy", [GetSpellInfo(2018)] = "Blacksmith", [GetSpellInfo(33359)] = "Cook",
	[GetSpellInfo(2108)] = "Leatherworker", [GetSpellInfo(7411)] = "Enchanter", [GetSpellInfo(4036)] = "Engineer",
	[GetSpellInfo(51311)] = "Jewelcrafter", [GetSpellInfo(3908)] = "Tailor", [GetSpellInfo(45357)] = "Scribe",
}

-- Trade skill opened/updated, save list (again) if needed
function Tradeskill:TRADE_SKILL_UPDATE()
	if( not QuickAuctionsDB.saveCraft or IsTradeSkillLinked() or not GetTradeSkillLine() or not professions[GetTradeSkillLine()] ) then
		return
	end
	
	-- This way we know we have data for this profession and can show if we can/cannot make it
	QuickAuctionsDB.crafts[professions[GetTradeSkillLine()]] = true
	
	-- Record list
	for i=1, GetNumTradeSkills() do
		local itemid = QA:GetSafeLink(GetTradeSkillItemLink(i))
		if( itemid ) then
			QuickAuctionsDB.crafts[itemid] = true
		end
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("TRADE_SKILL_UPDATE")
frame:SetScript("OnEvent", function()
	Tradeskill:TRADE_SKILL_UPDATE()
end)