include("shared.lua")
AddCSLuaFile("cl_init.lua")

local npc_greg_acquire_distance =
	CreateConVar("npc_greg_acquire_distance", 2500, FCVAR_NONE,
	"The maximum distance at which greg will chase a target.")

local npc_greg_attack_distance =
	CreateConVar("npc_greg_attack_distance", 80, FCVAR_NONE,
	"The reach of greg's attack.")

local npc_greg_attack_interval =
	CreateConVar("npc_greg_attack_interval", 0.2, FCVAR_NONE,
	"The delay between greg's attacks.")

local npc_greg_attack_force =
	CreateConVar("npc_greg_attack_force", 800, FCVAR_NONE,
	"The physical force of greg's attack. Higher values throw things \z
	farther.")

local npc_greg_smash_props =
	CreateConVar("npc_greg_smash_props", 1, FCVAR_NONE,
	"If set to 1, greg will punch through any props placed in their way.")

local npc_greg_allow_jump =
	CreateConVar("npc_greg_allow_jump", 1, FCVAR_NONE,
	"If set to 1, greg will be able to jump.")

local npc_greg_hiding_scan_interval =
	CreateConVar("npc_greg_hiding_scan_interval", 3, FCVAR_NONE,
	"greg will only seek out hiding places every X seconds. This can be an \z
	expensive operation, so it is not recommended to lower this too much. \z
	However, if distant gregs are not hiding from you quickly enough, you \z
	may consider lowering this a small amount.")

local npc_greg_hiding_repath_interval =
	CreateConVar("npc_greg_hiding_repath_interval", 1, FCVAR_NONE,
	"The path to greg's hiding spot will be redetermined every X seconds.")

local npc_greg_chase_repath_interval =
	CreateConVar("npc_greg_chase_repath_interval", 0.1, FCVAR_NONE,
	"The path to and position of greg's target will be redetermined every \z
	X seconds.")

local npc_greg_expensive_scan_interval =
	CreateConVar("npc_greg_expensive_scan_interval", 1, FCVAR_NONE,
	"Slightly expensive operations (distance calculations and entity \z
	searching) will occur every X seconds.")

local npc_greg_force_download =
	CreateConVar("npc_greg_force_download", 1, FCVAR_ARCHIVE,
	"If set to 1, clients will be forced to download greg resources \z
	(restart required after changing).\n\z
	WARNING: If this option is disabled, clients will be unable to see or \z
	hear greg!")

 -- So we don't spam voice TOO much.
local TAUNT_INTERVAL = 1.2
local PATH_INFRACTION_TIMEOUT = 5

if npc_greg_force_download:GetBool() then
	resource.AddWorkshop(workshopID)
end

util.AddNetworkString("greg_nag")
util.AddNetworkString("greg_navgen")

 -- Pathfinding is only concerned with static geometry anyway.
local trace = {
	mask = MASK_SOLID_BRUSHONLY
}

local function isPointNearSpawn(point, distance)
	--TODO: Is this a reliable standard??
	if not GAMEMODE.SpawnPoints then return false end

	local distanceSqr = distance * distance
	for _, spawnPoint in pairs(GAMEMODE.SpawnPoints) do
		if not IsValid(spawnPoint) then continue end

		if point:DistToSqr(spawnPoint:GetPos()) <= distanceSqr then
			return true
		end
	end

	return false
end

local function isPositionExposed(pos)
	for _, ply in pairs(player.GetAll()) do
		if IsValid(ply) and ply:Alive() and ply:IsLineOfSightClear(pos) then
			-- This spot can be seen!
			return true
		end
	end

	return false
end

local VECTOR_greg_HEIGHT = Vector(0, 0, 96)
local function isPointSuitableForHiding(point)
	trace.start = point
	trace.endpos = point + VECTOR_greg_HEIGHT
	local tr = util.TraceLine(trace)

	return (not tr.Hit)
end

local g_hidingSpots = nil
local function buildHidingSpotCache()
	local rStart = SysTime()

	g_hidingSpots = {}

	-- Look in every area on the navmesh for usable hiding places.
	-- Compile them into one nice list for lookup.
	local areas = navmesh.GetAllNavAreas()
	local goodSpots, badSpots = 0, 0
	for _, area in pairs(areas) do
		for _, hidingSpot in pairs(area:GetHidingSpots()) do
			if isPointSuitableForHiding(hidingSpot) then
				g_hidingSpots[goodSpots + 1] = {
					pos = hidingSpot,
					nearSpawn = isPointNearSpawn(hidingSpot, 200),
					occupant = nil
				}
				goodSpots = goodSpots + 1
			else
				badSpots = badSpots + 1
			end
		end
	end

	print(string.format("npc_greg: found %d suitable (%d unsuitable) hiding \z
		places in %d areas over %.2fms!", goodSpots, badSpots, #areas,
		(SysTime() - rStart) * 1000))
end

local ai_ignoreplayers = GetConVar("ai_ignoreplayers")
local function isValidTarget(ent)
	-- Ignore non-existant entities.
	if not IsValid(ent) then return false end

	-- Ignore dead players (or all players if `ai_ignoreplayers' is 1)
	if ent:IsPlayer() then
		if ai_ignoreplayers:GetBool() then return false end
		return ent:Alive() and not ent:IsActiveTraitor()
	end

	-- Ignore dead NPCs, other gregs, and dummy NPCs.
	local class = ent:GetClass()
	return (ent:IsNPC()
		and ent:Health() > 0
		and class ~= "npc_greg"
		and not class:find("bullseye"))
end

hook.Add("PlayerSpawnedNPC", "gregMissingNavmeshNag", function(ply, ent)
	if not IsValid(ent) then return end
	if ent:GetClass() ~= "npc_greg" then return end
	if navmesh.GetNavAreaCount() > 0 then return end

	-- Try to explain why greg isn't working.
	net.Start("greg_nag")
	net.Send(ply)
end)

local generateStart = 0
local function navEndGenerate()
	local timeElapsedStr = string.NiceTime(SysTime() - generateStart)

	if not navmesh.IsGenerating() then
		print("npc_greg: Navmesh generation completed in " .. timeElapsedStr)
	else
		print("npc_greg: Navmesh generation aborted after " .. timeElapsedStr)
	end

	-- Turn this back off.
	RunConsoleCommand("developer", "0")
end

local DEFAULT_SEEDCLASSES = {
	-- Source games in general
	"info_player_start",

	-- Garry's Mod (Obsolete)
	"gmod_player_start", "info_spawnpoint",

	-- Half-Life 2: Deathmatch
	"info_player_combine", "info_player_rebel", "info_player_deathmatch",

	-- Counter-Strike (Source & Global Offensive)
	"info_player_counterterrorist", "info_player_terrorist",

	-- Day of Defeat: Source
	"info_player_allies", "info_player_axis",

	-- Team Fortress 2
	"info_player_teamspawn",

	-- Left 4 Dead (1 & 2)
	"info_survivor_position",

	-- Portal 2
	"info_coop_spawn",

	-- Age of Chivalry
	"aoc_spawnpoint",

	-- D.I.P.R.I.P. Warm Up
	"diprip_start_team_red", "diprip_start_team_blue",

	-- Dystopia
	"dys_spawn_point",

	-- Insurgency
	"ins_spawnpoint",

	-- Pirates, Vikings, and Knights II
	"info_player_pirate", "info_player_viking", "info_player_knight",

	-- Obsidian Conflict (and probably some generic CTF)
	"info_player_red", "info_player_blue",

	-- Synergy
	"info_player_coop",

	-- Zombie Master
	"info_player_zombiemaster",

	-- Zombie Panic: Source
	"info_player_human", "info_player_zombie",

	-- Some maps start you in a cage room with a start button, have building
	-- interiors with teleportation doors, or the like.
	-- This is so the navmesh will (hopefully) still generate correctly and
	-- fully in these cases.
	"info_teleport_destination",
}

local function addEntitiesToSet(set, ents)
	for _, ent in pairs(ents) do
		if IsValid(ent) then
			set[ent] = true
		end
	end
end

local NAV_GEN_STEP_SIZE = 25
local function navGenerate()
	local seeds = {}

	-- Add a bunch of the usual classes as walkable seeds.
	for _, class in pairs(DEFAULT_SEEDCLASSES) do
		addEntitiesToSet(seeds, ents.FindByClass(class))
	end

	-- For gamemodes that define their own spawnpoint entities.
	addEntitiesToSet(seeds, GAMEMODE.SpawnPoints or {})

	if next(seeds, nil) == nil then
		print("npc_greg: Couldn't find any places to seed nav_generate")
		return false
	end

	for seed in pairs(seeds) do
		local pos = seed:GetPos()
		pos.x = NAV_GEN_STEP_SIZE * math.Round(pos.x / NAV_GEN_STEP_SIZE)
		pos.y = NAV_GEN_STEP_SIZE * math.Round(pos.y / NAV_GEN_STEP_SIZE)

		-- Start a little above because some mappers stick the
		-- teleport destination right on the ground.
		trace.start = pos + vector_up
		trace.endpos = pos - vector_up * 16384
		local tr = util.TraceLine(trace)

		if not tr.StartSolid and tr.Hit then
			print(string.format("npc_greg: Adding seed %s at %s", seed, pos))
			navmesh.AddWalkableSeed(tr.HitPos, tr.HitNormal)
		else
			print(string.format("npc_greg: Couldn't add seed %s at %s", seed,
				pos))
		end
	end

	-- The least we can do is ensure they don't have to listen to this noise.
	for _, greg in pairs(ents.FindByClass("npc_greg")) do
		greg:Remove()
	end

	-- This isn't strictly necessary since we just added EVERY spawnpoint as a
	-- walkable seed, but I dunno. What does it hurt?
	navmesh.SetPlayerSpawnName(next(seeds, nil):GetClass())

	navmesh.BeginGeneration()

	if navmesh.IsGenerating() then
		generateStart = SysTime()
		hook.Add("ShutDown", "gregNavGen", navEndGenerate)
	else
		print("npc_greg: nav_generate failed to initialize")
		navmesh.ClearWalkableSeeds()
	end

	return navmesh.IsGenerating()
end

concommand.Add("npc_greg_learn", function(ply, cmd, args)
	if navmesh.IsGenerating() then
		return
	end

	-- Rcon or single-player only.
	local isConsole = (ply:EntIndex() == 0)
	if game.SinglePlayer() then
		print("npc_greg: Beginning nav_generate requested by " .. ply:Name())

		-- Disable expensive computations in single-player. greg doesn't use
		-- their results, and it consumes a massive amount of time and CPU.
		-- We'd do this on dedicated servers as well, except that sv_cheats
		-- needs to be enabled in order to disable visibility computations.
		RunConsoleCommand("nav_max_view_distance", "1")
		RunConsoleCommand("nav_quicksave", "1")

		-- Enable developer mode so we can see console messages in the corner.
		RunConsoleCommand("developer", "1")
	elseif isConsole then
		print("npc_greg: Beginning nav_generate requested by server console")
	else
		return
	end

	local success = navGenerate()

	-- If it fails, only the person who started it needs to know.
	local recipients = (success and player.GetHumans() or {ply})

	net.Start("greg_navgen")
		net.WriteBool(success)
	net.Send(recipients)
end)

ENT.LastPathRecompute = 0
ENT.LastTargetSearch = 0
ENT.LastJumpScan = 0
ENT.LastCeilingUnstick = 0
ENT.LastAttack = 0
ENT.LastHidingPlaceScan = 0

ENT.CurrentTarget = nil
ENT.HidingSpot = nil

function ENT:Initialize()
	-- Spawn effect resets render override. Bug!!!
	self:SetSpawnEffect(false)

	self:SetBloodColor(DONT_BLEED)

	-- Just in case.
	self:SetHealth(1e8)

	--self:DrawShadow(false) -- Why doesn't this work???

	--HACK!!! Disables shadow (for real).
	self:SetRenderMode(RENDERMODE_TRANSALPHA)
	self:SetColor(Color(255, 255, 255, 1))

	-- Human-sized collision.
	self:SetCollisionBounds(Vector(-13, -13, 0), Vector(13, 13, 72))

	-- We're a little timid on drops... Give the player a chance. :)
	self.loco:SetDeathDropHeight(600)

	-- In Sandbox, players are faster in singleplayer.
	self.loco:SetDesiredSpeed(game.SinglePlayer() and 650 or 500)

	-- Take corners a bit sharp.
	self.loco:SetAcceleration(500)
	self.loco:SetDeceleration(500)

	-- This isn't really important because we reset it all the time anyway.
	self.loco:SetJumpHeight(300)

	-- Rebuild caches.
	self:OnReloaded()
end

function ENT:OnInjured(dmg)
	-- Just in case.
	dmg:SetDamage(0)
end

function ENT:OnReloaded()
	if g_hidingSpots == nil then
		buildHidingSpotCache()
	end
end

function ENT:OnRemove()
	-- Give up our hiding spot when we're deleted.
	self:ClaimHidingSpot(nil)
end

function ENT:GetNearestTarget()
	-- Only target entities within the acquire distance.
	local maxAcquireDist = npc_greg_acquire_distance:GetInt()
	local maxAcquireDistSqr = maxAcquireDist * maxAcquireDist
	local myPos = self:GetPos()
	local acquirableEntities = ents.FindInSphere(myPos, maxAcquireDist)
	local distToSqr = myPos.DistToSqr
	local getPos = self.GetPos
	local target = nil
	local getClass = self.GetClass

	for _, ent in pairs(acquirableEntities) do
		-- Ignore invalid targets, of course.
		if not isValidTarget(ent) then continue end

		-- Find the nearest target to chase.
		local distSqr = distToSqr(getPos(ent), myPos)
		if distSqr < maxAcquireDistSqr then
			target = ent
			maxAcquireDistSqr = distSqr
		end
	end

	return target
end

--TODO: Giant ugly monolith of a function eww eww eww.
function ENT:AttackNearbyTargets(radius)
	local attackForce = npc_greg_attack_force:GetInt()
	local hitSource = self:LocalToWorld(self:OBBCenter())
	local nearEntities = ents.FindInSphere(hitSource, radius)
	local hit = false
	for _, ent in pairs(nearEntities) do
		if isValidTarget(ent) then
			local health = ent:Health()

			if ent:IsPlayer() and IsValid(ent:GetVehicle()) then
				-- Hiding in a vehicle, eh?
				local vehicle = ent:GetVehicle()

				local vehiclePos = vehicle:LocalToWorld(vehicle:OBBCenter())
				local hitDirection = (vehiclePos - hitSource):GetNormal()

				-- Give it a good whack.
				local phys = vehicle:GetPhysicsObject()
				if IsValid(phys) then
					phys:Wake()
					local hitOffset = vehicle:NearestPoint(hitSource)
					phys:ApplyForceOffset(hitDirection
						* (attackForce * phys:GetMass()),
						hitOffset)
				end
				vehicle:TakeDamage(math.max(1e8, ent:Health()), self, self)

				-- Oh, and make a nice SMASH noise.
				vehicle:EmitSound(string.format(
					"physics/metal/metal_sheet_impact_hard%d.wav",
					math.random(6, 8)), 350, 120)
			else
				ent:EmitSound(string.format(
					"physics/body/body_medium_impact_hard%d.wav",
					math.random(1, 6)), 350, 120)
			end

			local hitDirection = (ent:GetPos() - hitSource):GetNormal()
			-- Give the player a good whack. greg means business.
			-- This is for those with god mode enabled.
			ent:SetVelocity(hitDirection * attackForce + vector_up * 500)

			local dmgInfo = DamageInfo()
			dmgInfo:SetAttacker(self)
			dmgInfo:SetInflictor(self)
			dmgInfo:SetDamage(1e8)
			dmgInfo:SetDamagePosition(self:GetPos())
			dmgInfo:SetDamageForce((hitDirection * attackForce
				+ vector_up * 500) * 100)
			ent:TakeDamageInfo(dmgInfo)

            local explode = ents.Create("env_explosion")
		    explode:SetPos(tgt:GetPos())
		    explode:SetOwner(ply)
		    explode:Spawn()
		    explode:SetKeyValue("iMagnitude", "150")
		    explode:Fire("Explode", 0,0)
		    explode:EmitSound("ambient/explosions/explode_4.wav", 400, 400)

			local newHealth = ent:Health()

			-- Hits only count if we dealt some damage.
			hit = (hit or (newHealth < health))
		elseif ent:GetMoveType() == MOVETYPE_VPHYSICS then
			if not npc_greg_smash_props:GetBool() then continue end
			if ent:IsVehicle() and IsValid(ent:GetDriver()) then continue end

			-- Knock away any props put in our path.
			local entPos = ent:LocalToWorld(ent:OBBCenter())
			local hitDirection = (entPos - hitSource):GetNormal()
			local hitOffset = ent:NearestPoint(hitSource)

			-- Remove anything tying the entity down.
			-- We're crashing through here!
			constraint.RemoveAll(ent)

			-- Get the object's mass.
			local phys = ent:GetPhysicsObject()
			local mass = 0
			local material = "Default"
			if IsValid(phys) then
				mass = phys:GetMass()
				material = phys:GetMaterial()
			end

			-- Don't make a noise if the object is too light.
			-- It's probably a gib.
			if mass >= 5 then
				ent:EmitSound(material .. ".ImpactHard", 350, 120)
			end

			-- Unfreeze all bones, and give the object a good whack.
			for id = 0, ent:GetPhysicsObjectCount() - 1 do
				local phys = ent:GetPhysicsObjectNum(id)
				if IsValid(phys) then
					phys:EnableMotion(true)
					phys:ApplyForceOffset(hitDirection * (attackForce * mass),
						hitOffset)
				end
			end

			-- Deal some solid damage, too.
			ent:TakeDamage(25, self, self)
		end
	end

	return hit
end

function ENT:IsHidingSpotFull(hidingSpot)
	-- It's not full if there's no occupant, or we're the one in it.
	local occupant = hidingSpot.occupant
	if not IsValid(occupant) or occupant == self then
		return false
	end

	return true
end

--TODO: Weight spots based on how many people can see them.
function ENT:GetNearestUsableHidingSpot()
	local nearestHidingSpot = nil
	local nearestHidingDistSqr = 1e8

	local myPos = self:GetPos()
	local isHidingSpotFull = self.IsHidingSpotFull
	local distToSqr = myPos.DistToSqr

	-- This could be a long loop. Optimize the heck out of it.
	for _, hidingSpot in pairs(g_hidingSpots) do
		-- Ignore hiding spots that are near spawn, or full.
		if hidingSpot.nearSpawn or isHidingSpotFull(self, hidingSpot) then
			continue
		end

		--TODO: Disallow hiding places near spawn?
		local hidingSpotDistSqr = distToSqr(hidingSpot.pos, myPos)
		if hidingSpotDistSqr < nearestHidingDistSqr
			and not isPositionExposed(hidingSpot.pos)
		then
			nearestHidingDistSqr = hidingSpotDistSqr
			nearestHidingSpot = hidingSpot
		end
	end

	return nearestHidingSpot
end

function ENT:ClaimHidingSpot(hidingSpot)
	-- Release our claim on the old spot.
	if self.HidingSpot ~= nil then
		self.HidingSpot.occupant = nil
	end

	-- Can't claim something that doesn't exist, or a spot that's
	-- already claimed.
	if hidingSpot == nil or self:IsHidingSpotFull(hidingSpot) then
		self.HidingSpot = nil
		return false
	end

	-- Yoink.
	self.HidingSpot = hidingSpot
	self.HidingSpot.occupant = self
	return true
end

local HIGH_JUMP_HEIGHT = 500
function ENT:AttemptJumpAtTarget()
	-- No double-jumping.
	if not self:IsOnGround() then return end

	local targetPos = self.CurrentTarget:GetPos()
	local xyDistSqr = (targetPos - self:GetPos()):Length2DSqr()
	local zDifference = targetPos.z - self:GetPos().z
	local maxAttackDistance = npc_greg_attack_distance:GetInt()
	if xyDistSqr <= math.pow(maxAttackDistance + 200, 2)
		and zDifference >= maxAttackDistance
	then
		--TODO: Set up jump so target lands on parabola.
		local jumpHeight = zDifference + 50
		self.loco:SetJumpHeight(jumpHeight)
		self.loco:Jump()
		self.loco:SetJumpHeight(300)
	end
end

local VECTOR_HIGH = Vector(0, 0, 16384)
ENT.LastPathingInfraction = 0
function ENT:RecomputeTargetPath()
	if CurTime() - self.LastPathingInfraction < PATH_INFRACTION_TIMEOUT then
		-- No calculations for you today.
		return
	end

	local targetPos = self.CurrentTarget:GetPos()

	-- Run toward the position below the entity we're targetting,
	-- since we can't fly.
	trace.start = targetPos
	trace.endpos = targetPos - VECTOR_HIGH
	trace.filter = self.CurrentTarget
	local tr = util.TraceEntity(trace, self.CurrentTarget)

	-- Of course, we sure that there IS a "below the target."
	if tr.Hit and util.IsInWorld(tr.HitPos) then
		targetPos = tr.HitPos
	end

	local rTime = SysTime()
	self.MovePath:Compute(self, targetPos)

	-- If path computation takes longer than 5ms (A LONG TIME),
	-- disable computation for a little while for this bot.
	if SysTime() - rTime > 0.005 then
		self.LastPathingInfraction = CurTime()
	end
end

function ENT:BehaveStart()
	self.MovePath = Path("Follow")
	self.MovePath:SetMinLookAheadDistance(500)
	self.MovePath:SetGoalTolerance(10)
end

local ai_disabled = GetConVar("ai_disabled")
function ENT:BehaveUpdate() --TODO: Split this up more. Eww.
	if ai_disabled:GetBool() then
		-- We may be a bot, but we're still an "NPC" at heart.
		return
	end

	local currentTime = CurTime()

	local scanInterval = npc_greg_expensive_scan_interval:GetFloat()
	if currentTime - self.LastTargetSearch > scanInterval then
		local target = self:GetNearestTarget()

		if target ~= self.CurrentTarget then
			-- We have a new target! Figure out a new path immediately.
			self.LastPathRecompute = 0
		end

		self.CurrentTarget = target
		self.LastTargetSearch = currentTime
	end

	-- Do we have a target?
	if IsValid(self.CurrentTarget) then
		-- Be ready to repath to a hiding place as soon as we lose target.
		self.LastHidingPlaceScan = 0

		-- Attack anyone nearby while we're rampaging.
		local attackInterval = npc_greg_attack_interval:GetFloat()
		if currentTime - self.LastAttack > attackInterval then
			local attackDistance = npc_greg_attack_distance:GetInt()

			self:AttackNearbyTargets(attackDistance)
			self.LastAttack = currentTime
		end

		-- Recompute the path to the target every so often.
		local repathInterval = npc_greg_chase_repath_interval:GetFloat()
		if currentTime - self.LastPathRecompute > repathInterval then
			self.LastPathRecompute = currentTime
			self:RecomputeTargetPath()
		end

		-- Move!
		self.MovePath:Update(self)

		-- Try to jump at a target in the air.
		if self:IsOnGround() and npc_greg_allow_jump:GetBool()
			and currentTime - self.LastJumpScan >= scanInterval
		then
			self:AttemptJumpAtTarget()
			self.LastJumpScan = currentTime
		end
	else
		local hidingScanInterval = npc_greg_hiding_scan_interval:GetFloat()
		if currentTime - self.LastHidingPlaceScan >= hidingScanInterval then
			self.LastHidingPlaceScan = currentTime

			-- Grab a new hiding spot.
			local hidingSpot = self:GetNearestUsableHidingSpot()
			self:ClaimHidingSpot(hidingSpot)
		end

		if self.HidingSpot ~= nil then
			local hidingInterval = npc_greg_hiding_repath_interval:GetFloat()
			if currentTime - self.LastPathRecompute >= hidingInterval then
				self.LastPathRecompute = currentTime
				self.MovePath:Compute(self, self.HidingSpot.pos)
			end
			self.MovePath:Update(self)
		else
			--TODO: Wander if we didn't find a place to hide.
			-- Preferably AWAY from spawn points.
		end
	end

	-- Don't even wait until the STUCK flag is set for this.
	-- It's much more fluid this way.
	if currentTime - self.LastCeilingUnstick >= scanInterval then
		self:UnstickFromCeiling()
		self.LastCeilingUnstick = currentTime
	end

	if currentTime - self.LastStuck >= 5 then
		self.StuckTries = 0
	end
end

ENT.LastStuck = 0
ENT.StuckTries = 0
function ENT:OnStuck()
	-- Jump forward a bit on the path.
	self.LastStuck = CurTime()

	local newCursor = self.MovePath:GetCursorPosition()
		+ 40 * math.pow(2, self.StuckTries)
	self:SetPos(self.MovePath:GetPositionOnPath(newCursor))
	self.StuckTries = self.StuckTries + 1

	-- Hope that we're not stuck anymore.
	self.loco:ClearStuck()
end

function ENT:UnstickFromCeiling()
	if self:IsOnGround() then return end

	-- NextBots LOVE to get stuck. Stuck in the morning. Stuck in the evening.
	-- Stuck in the ceiling. Stuck on each other. The stuck never ends.
	local myPos = self:GetPos()
	local myHullMin, myHullMax = self:GetCollisionBounds()
	local myHull = myHullMax - myHullMin
	local myHullTop = myPos + vector_up * myHull.z
	trace.start = myPos
	trace.endpos = myHullTop
	trace.filter = self
	local upTrace = util.TraceLine(trace, self)

	if upTrace.Hit and upTrace.HitNormal ~= vector_origin
		and upTrace.Fraction > 0.5
	then
		local unstuckPos = myPos
			+ upTrace.HitNormal * (myHull.z * (1 - upTrace.Fraction))
		self:SetPos(unstuckPos)
	end
end

Spawnable()