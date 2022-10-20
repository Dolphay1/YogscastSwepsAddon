AddCSLuaFile()

ENT.Base = "base_nextbot"

ENT.PhysgunDisabled = true
ENT.AutomaticFrameAdvance = false

local workshopID = "174117071"

local IsValid = IsValid

function Spawnable()
	list.Set("NPC", "npc_greg", {
		Name = "greg",
		Class = "npc_greg",
		Category = "Nextbot",
		AdminOnly = true
	})
end
