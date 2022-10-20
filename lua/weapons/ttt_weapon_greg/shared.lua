if SERVER then
    AddCSLuaFile()
	resource.AddFile("materials/vgui/ttt/icon_greg24.png")
end

if CLIENT then
	SWEP.Icon = "vgui/ttt/icon_greg24.png"
	SWEP.PrintName = "Greg Gun"
	SWEP.Slot = 6
    SWEP.SlotPos = 6
	SWEP.EquipMenuData = {
		type = "Weapon",
		desc = "Summons Greg to do crimes."
	}
end

game.AddAmmoType({
	name = "greg_ammo",
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
SWEP.Primary.Ammo = "greg_ammo"
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

function FindSpawnLocation(pos)
    local offsets = {}

    for i = 0, 360, 15 do
        table.insert( offsets, Vector( math.sin( i ), math.cos( i ), 0 ) )
    end

        local midsize = Vector( 26, 26, 80 )
        local tstart   = pos + Vector( 0, 0, midsize.z / 2 )

        for i = 1, #offsets do
            local o = offsets[ i ]
            local v = tstart + o * midsize * 1.5

            local t = {
                start = v,
                endpos = v,
                filter = target,
                mins = midsize / -2,
                maxs = midsize / 2
            }

            local tr = util.TraceHull( t )

            if not tr.Hit then return ( v - Vector( 0, 0, midsize.z/2 ) ) end
            
        end 

        return pos
end

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
		if(trace.Hit and SERVER) then
			local ent = ents.Create("npc_greg")
			ent:SetPos(FindSpawnLocation(trace.HitPos))
			ent:Spawn()

			ent:SetSummoner(attacker)

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
	   buyer:GiveAmmo( 1, "greg_ammo", true )
	end
 end
 