if SERVER then
    AddCSLuaFile()
	resource.AddFile("materials/vgui/ttt/icon_blobby25.png")
	util.AddNetworkString( "bloblify" )
	util.AddNetworkString( "reverse_blobby" )
end

if CLIENT then
	SWEP.Icon = "vgui/ttt/icon_blobby25.png"
	SWEP.PrintName = "Blobbiafier"
	SWEP.Slot = 6
    SWEP.SlotPos = 6
	SWEP.EquipMenuData = {
		type = "Weapon",
		desc = "Turns your target into blobby and removes their name tag. Right click to turn yourself into blobby (does not use ammo)."
	}
end

game.AddAmmoType({
	name = "blobby_ammo",
	dmgtype = DMG_GENERIC,
	tracer = 0,
	plydmg = 0,
	npcdmg = 0,
	force = 0,
	minsplash = 0,
	maxsplash = 0
})

local BlobbyList = {}

SWEP.Base = "weapon_tttbase"
SWEP.HoldType = "pistol"
SWEP.Kind = WEAPON_PISTOL

SWEP.Primary.Recoil = 3
SWEP.Primary.Damage = 0
SWEP.Primary.Delay = 1
SWEP.Primary.Cone = 0.01
SWEP.Primary.Automatic = false 
SWEP.Primary.ClipSize = 3
SWEP.Primary.DefaultClip = 1
SWEP.Primary.Ammo = "blobby_ammo"
SWEP.AmmoEnt = "none"

SWEP.UseHands = true 

SWEP.ViewModel = "models/weapons/cstrike/c_pist_fiveseven.mdl"
SWEP.WorldModel = "models/weapons/w_pist_fiveseven.mdl"

SWEP.Kind = WEAPON_EQUIP1
SWEP.CanBuy = {ROLE_TRAITOR}

SWEP.LimitedStock = true
SWEP.AllowDrop = true

function SWEP:PrimaryAttack()
	if self:Clip1() <= 0 then return end
	local cone = self.Primary.Cone
	local num = 1

	local bullet = {}

	self:SendWeaponAnim(self.PrimaryAnim)
	self.Owner:MuzzleFlash()
	self.Owner:SetAnimation( PLAYER_ATTACK1 )

	bullet.Dmgtype = "DMG_GENERIC"
	bullet.Num = num
	bullet.Src = self.Owner:GetShootPos()
	bullet.Dir = self.Owner:GetAimVector()
	bullet.Spread = Vector( cone, cone, 0 )
	bullet.Tracer = 0
	bullet.Force = 0
	bullet.Damage = 0
	bullet.TracerName = "TRACER_NONE"

	bullet.Callback = function(attacker, trace, damage)
		local target = trace.Entity
		if target:IsValid() and target:IsPlayer() and target:Alive() and SERVER then
			BlobbyList[target] = true
			net.Start("bloblify")
			net.WriteEntity(target)
			net.Broadcast()
 		end
	end

	self:TakePrimaryAmmo( 1 )
	self.Owner:FireBullets( bullet )
end

function SWEP:SetZoom(state)
	if not (IsValid(self:GetOwner()) and self:GetOwner():IsPlayer()) then return end
	if state then
		self:GetOwner():SetFOV(25,0.2)
	else
		self:GetOwner():SetFOV(0, 0.1)
	end
end

function SWEP:SecondaryAttack()
	if(self.Owner:IsValid() and self.Owner:IsPlayer() and self.Owner:Alive() and SERVER) then
		BlobbyList[self.Owner] = true
		net.Start("bloblify")
		net.WriteEntity(self.Owner)
		net.Broadcast()
	end
end

function SWEP:Holster()
	self:SetIronsights(false)
	self:SetZoom(false)
	return true
end
 
function SWEP:PreDrop()
	self:SetZoom(false)
	self:SetIronsights(false)
	return self.BaseClass.PreDrop(self)
end
 
function SWEP:Reload()
	self.Weapon:DefaultReload( ACT_VM_RELOAD );
	self:SetIronsights( false )
	self:SetZoom(false)
end

function SWEP:WasBought(buyer)
	if IsValid(buyer) then
	   buyer:GiveAmmo( 2, "blobby_ammo", true )
	end
end

net.Receive("bloblify", function()
	plr = net.ReadEntity()
	if plr:IsValid() and plr:IsPlayer() and plr:Alive() and BlobbyList[plr] == nil then
		if plr == LocalPlayer() and plr:IsActiveTraitor() then
			plr:ChatPrint("You are now blobby.")
		end
		plr:SetModel("models/player/bloody.mdl")
		BlobbyList[plr] = true
	end
end)


net.Receive("reverse_blobby", function()
	plr = net.ReadEntity()
	model = net.ReadString()
	if plr:IsValid() and plr:IsPlayer() and plr:Alive() then
		plr:SetModel(model)
	end
end)

hook.Add( "HUDDrawTargetID", "BlobbyDraw", function()
	local tr = util.GetPlayerTrace( LocalPlayer() )
	local trace = util.TraceLine( tr )
	if ( !trace.Hit ) then return end
	if ( !trace.HitNonWorld ) then return end
	
	if ( trace.Entity:IsPlayer() ) then
		if(BlobbyList[trace.Entity] != nil) then return false end
	end

	return

end)

hook.Add("TTTEndRound", "BlobbyEnd", function()
	if SERVER then
		for i,_ in pairs(BlobbyList) do
			net.Start("reverse_blobby")
			net.WriteEntity(i)
			net.WriteString(i:GetModel())
			net.Broadcast()
		end
	end

	BlobbyList = {}
end)
