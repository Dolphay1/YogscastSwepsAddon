if SERVER then
    AddCSLuaFile()
	print("lua")
end

if CLIENT then
	print("client")
	SWEP.Icon = "vgui/ttt/icon_kevin23.png"
	SWEP.PrintName = "Kevin"
	SWEP.Slot = 6
    SWEP.SlotPos = 6
	SWEP.EquipMenuData = {
		type = "Weapon",
		desc = "Shoot a player and have them skip a part of Metal Gear Solid."
	}
end

game.AddAmmoType({
	name = "boba",
	dmgtype = DMG_GENERIC,
	tracer = 0,
	plydmg = 0,
	npcdmg = 0,
	force = 0,
	minsplash = 0,
	maxsplash = 0
})

SWEP.Base = "weapon_tttbase"
SWEP.HoldType = "pistol"
SWEP.Kind = WEAPON_PISTOL

SWEP.Primary.Recoil = 3
SWEP.Primary.Damage = 0
SWEP.Primary.Delay = 1
SWEP.Primary.Cone = 0.01
SWEP.Primary.Automatic = false 
SWEP.Primary.ClipSize = 1
SWEP.Primary.DefaultClip = 1
SWEP.Primary.Ammo = "boba"
SWEP.AmmoEnt = "none"

SWEP.UseHands = true 

SWEP.ViewModel = "models/weapons/cstrike/c_pist_fiveseven.mdl"
SWEP.WorldModel = "models/weapons/w_pist_fiveseven.mdl"

SWEP.Kind = WEAPON_EQUIP1
SWEP.CanBuy = {ROLE_TRAITOR}

SWEP.LimitedStock = true
SWEP.AllowDrop = true

SWEP.IronSightsPos = Vector(-5.95, -1, 4.799)
SWEP.IronSightsAng = Vector(0, 0, 0)

print("added")
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
	bullet.Tracer = 1
	bullet.Force = 10
	bullet.Damage = 1
	bullet.TracerName = "PhyscannonImpact"

	bullet.Callback = function(attacker, trace, damage)
		local target = trace.Entity

		if CLIENT and target:IsPlayer() then
			target:ConCommand("act salute")
			target:SetCanWalk(false)

			timer.Simple(10, function() 
				if target:Alive() then
					target:SetCanWalk(true)
				end
			end )
		end

		if SERVER and target:IsPlayer() and target:Alive() then
			
			local Positions = {Vector(100,0,0), Vector(0,100,0), Vector(-100, 0, 0), Vector(0, -100, 0), Vector(75, 75, 0), Vector(-75, -75, 0), Vector(75, -75, 0), Vector(-75, 75, 0)}

			for i, v in pairs(Positions) do
				local ent = ents.Create("npc_combine_s")
				local targetPos = target:GetPos()

				ent:SetPos(targetPos + v)

				ent:Spawn()
				ent:DropToFloor()
				ent:Give("weapon_shotgun")
				ent:SetTarget(target)

				timer.Simple(10, function() 
					if ent:IsValid() then
						ent:TakeDamage(1000, ent, ent)
					end
				end )
			end

			local ent = ents.Create("prop_physics")
			ent:SetModel("models/props_doors/door03_slotted_left.mdl")

			ent:SetPos(target:GetForward()*Vector(1, 1, 0)*50 + target:GetPos() + Vector(0, 0, 50))

			ent:Spawn()
			ent:DropToFloor()
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
	if not self.IronSightsPos then return end
	if self:GetNextSecondaryFire() > CurTime() then return end
 
	local bIronsights = not self:GetIronsights()
 
	self:SetIronsights( bIronsights )
 
	self:SetZoom( bIronsights )
 
	self:SetNextSecondaryFire( CurTime() + 0.3 )
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
	   buyer:GiveAmmo( 99, "Kevin", true )
	end
 end
 