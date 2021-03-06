-- Boss-fighting related functions


---------------------
-- Other modifiers
---------------------
LinkLuaModifier("capture_start_trigger", "boss_scripts/capture_start_trigger.lua", LUA_MODIFIER_MOTION_NONE )
LinkLuaModifier("boss_thinker_zeus", "boss_scripts/boss_thinker_zeus.lua", LUA_MODIFIER_MOTION_NONE )
LinkLuaModifier("boss_thinker_venomancer", "boss_scripts/boss_thinker_venomancer.lua", LUA_MODIFIER_MOTION_NONE )
LinkLuaModifier("boss_thinker_treant", "boss_scripts/boss_thinker_treant.lua", LUA_MODIFIER_MOTION_NONE )
LinkLuaModifier("boss_thinker_nevermore", "boss_scripts/boss_thinker_nevermore.lua", LUA_MODIFIER_MOTION_NONE )
LinkLuaModifier("boss_thinker_mega_greevil", "boss_scripts/boss_thinker_mega_greevil.lua", LUA_MODIFIER_MOTION_NONE )

---------------------
-- Arena lockdown
---------------------

function LockArena(altar, team, attacker)
	local altar_handle = Entities:FindByName(nil, altar)
	local altar_loc = altar_handle:GetAbsOrigin()

	-- Particle & Sound
	altar_handle:EmitSound("Hero_Rattletrap.Power_Cogs")
	altar_handle.arena_fence_pfx = ParticleManager:CreateParticle("particles/arena_wall/arena_lock.vpcf", PATTACH_WORLDORIGIN, nil)
	ParticleManager:SetParticleControl(altar_handle.arena_fence_pfx, 0, altar_loc)

	-- Team-exclusive sound
	for player_id = 0, 20 do
		if PlayerResource:GetPlayer(player_id) and PlayerResource:GetTeam(player_id) == team then
			EmitSoundOnClient("greevil_camp_respawn_Stinger", PlayerResource:GetPlayer(player_id))
		end
	end

	-- Apply altar controller modifier to altar entity
	local bounties = GetAltarBountyValue(altar_handle, altar)
	altar_handle:AddNewModifier(nil, nil, "modifier_altar_active", {team = team, gold_bounty = bounties[1], exp_bounty = bounties[2]})

	-- Force attacker to be inside the arena when the fight starts
	local direction = (attacker:GetAbsOrigin() - altar_loc)
	if direction:Length2D() > 850 then
		FindClearSpaceForUnit(attacker, altar_loc + direction:Normalized() * 850, false)
	end

	-- Also force the attacker's owner (if any) inside the arena
	if attacker:GetOwnerEntity() then
		local owner = attacker:GetOwnerEntity()
		local direction = (owner:GetAbsOrigin() - altar_loc)
		if direction:Length2D() > 850 then
			FindClearSpaceForUnit(owner, altar_loc + direction:Normalized() * 850, false)
		end
	end

	altar_handle.victory = false
	CustomGameEventManager:Send_ServerToTeam(team, "show_boss_hp", {})
end

function UnlockArena(altar, victory, team, aura_ability)
	local altar_handle = Entities:FindByName(nil, altar)
	ParticleManager:DestroyParticle(altar_handle.arena_fence_pfx, true)
	ParticleManager:ReleaseParticleIndex(altar_handle.arena_fence_pfx)

	CustomGameEventManager:Send_ServerToTeam(team, "hide_boss_hp", {})
	
	-- Mark relevant team as able to fight again
	if team == DOTA_TEAM_GOODGUYS then
		RADIANT_FIGHTING = false
	elseif team == DOTA_TEAM_BADGUYS then
		DIRE_FIGHTING = false
	end

	-- Cleanse nearby hero debuffs
	local nearby_heroes = FindUnitsInRadius(team, altar_handle:GetAbsOrigin(), nil, 900, DOTA_UNIT_TARGET_TEAM_FRIENDLY, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_FLAG_INVULNERABLE + DOTA_UNIT_TARGET_FLAG_OUT_OF_WORLD, FIND_ANY_ORDER, false)
	for _,hero in pairs(nearby_heroes) do
		CleanseBossDebuffs(hero)
	end

	-- Adjust altar aura if necessary
	if victory then
		altar_handle.victory = true
		if altar_handle:FindAbilityByName(aura_ability) then
			local modifier_name = "modifier_"..aura_ability
			local aura_modifier = altar_handle:FindModifierByName(modifier_name)
			aura_modifier:SetStackCount(aura_modifier:GetStackCount() + 1)
		else
			altar_handle:AddAbility(aura_ability)
			altar_handle:FindAbilityByName(aura_ability):SetLevel(1)
		end

		-- Heal winning team
		for _,hero in pairs(nearby_heroes) do
			hero:Purge(false, true, false, false, false)
			hero:AddNewModifier(hero, nil, "modifier_aegis_regen", {duration = 3.0})
		end

		-- Update altar scoreboard
		for i = 1, 7 do
			if string.find(altar, i) then
				CustomGameEventManager:Send_ServerToAllClients("update_altar", {altar = i, team = team})
				altar_handle:SetTeam(team)
			end
		end

		-- Paint relevant altar tower with the team's color
		local tower_handle = Entities:FindByName(nil, altar.."_tower")
		if team == DOTA_TEAM_GOODGUYS then
			tower_handle:SetRenderColor(0, 255, 60)
		elseif team == DOTA_TEAM_BADGUYS then
			tower_handle:SetRenderColor(255, 0, 60)
		end
	end

	-- Stop altar controlled modifier
	altar_handle:RemoveModifierByName("modifier_frostivus_immolation")
	altar_handle:RemoveModifierByName("modifier_altar_active")
end

-- Fighting boss modifier
LinkLuaModifier("modifier_fighting_boss", "boss_scripts/boss_functions.lua", LUA_MODIFIER_MOTION_NONE )

modifier_fighting_boss = class({})

function modifier_fighting_boss:IsHidden()
	return true
end

function modifier_fighting_boss:IsPurgable()
	return false
end

function modifier_fighting_boss:OnCreated(keys)
	if IsServer() then
		self.altar_handle = "no handle passed"
		if keys.altar_name then
			self.altar_handle = Entities:FindByName(nil, keys.altar_name)
		end
	end
end

-- Altar controller modifier
LinkLuaModifier("modifier_altar_active", "boss_scripts/boss_functions.lua", LUA_MODIFIER_MOTION_NONE )

modifier_altar_active = class({})

function modifier_altar_active:IsHidden()
	return true
end

function modifier_altar_active:IsPurgable()
	return false
end

function modifier_altar_active:OnCreated( params )
	if IsServer() then
		self.team = "no team passed"
		self.gold_bounty = 300
		self.exp_bounty = 300
		if params.team then
			self.team = params.team
		end
		if params.gold_bounty then
			self.gold_bounty = params.gold_bounty
		end
		if params.exp_bounty then
			self.exp_bounty = params.exp_bounty
		end

		-- Define knockback position based on the altar
		if self:GetParent():GetName() == "altar_2" then
			self.knockback_loc = Vector(-3214, 4789, 128)
		elseif self:GetParent():GetName() == "altar_3" then
			self.knockback_loc = Vector(-3108, -3725, 128)
		elseif self:GetParent():GetName() == "altar_4" then
			self.knockback_loc = Vector(1127, 905, 128)
		elseif self:GetParent():GetName() == "altar_5" then
			self.knockback_loc = Vector(2490, 3253, 128)
		elseif self:GetParent():GetName() == "altar_6" then
			self.knockback_loc = Vector(2594, -3759, 128)
		end

		self.fighting_heroes = {}
		self:StartIntervalThink(0.03)
	end
end

function modifier_altar_active:OnDestroy( params )
	if IsServer() then

		-- Clean fighting heroes list
		local altar_handle = self:GetParent()
		for _, hero in pairs(self.fighting_heroes) do

			-- Give heroes a bounty, if appropriate
			if altar_handle.victory and hero:IsRealHero() then
				hero:AddExperience(self.exp_bounty, DOTA_ModifyXP_CreepKill, false, true)
				hero:ModifyGold(self.gold_bounty, false, DOTA_ModifyGold_CreepKill)
				SendOverheadEventMessage(hero, OVERHEAD_ALERT_GOLD, hero, self.gold_bounty, nil)
			end
			hero:RemoveModifierByName("modifier_fighting_boss")
		end
	end
end

function modifier_altar_active:OnIntervalThink()
	if IsServer() then
		local altar_handle = self:GetParent()
		local altar_loc = altar_handle:GetAbsOrigin() 
		local nearby_fighters = FindUnitsInRadius(self.team, altar_loc, nil, 950, DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_BASIC + DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES, FIND_ANY_ORDER, false)
		for _, fighter in pairs(nearby_fighters) do

			-- Add any allies to the fighter list
			if fighter:GetTeam() ~= DOTA_TEAM_NEUTRALS and not fighter:HasModifier("modifier_fighting_boss") and fighter:IsRealHero() then
				self.fighting_heroes[#self.fighting_heroes+1] = fighter
				fighter:AddNewModifier(nil, nil, "modifier_fighting_boss", {altar_name = altar_handle:GetName()})
			end
		end

		-- Keep fighting heroes inside the ring
		for _, hero in pairs(self.fighting_heroes) do
			local hero_position = hero:GetAbsOrigin()
			local direction = (hero_position - altar_loc)
			if direction:Length2D() > 900 and hero:HasModifier("modifier_fighting_boss") then
				FindClearSpaceForUnit(hero, altar_loc + direction:Normalized() * 900, false)
			end
		end
	end
end

-- Bounty-defining function, per boss
function GetAltarBountyValue(altar, altar_name)

	local gold_bounty = 300
	local exp_bounty = 300

	return {gold_bounty, exp_bounty}
end



---------------------
-- Spawner functions
---------------------
function SpawnZeus(altar)
	local altar_loc = Entities:FindByName(nil, altar):GetAbsOrigin()
	local boss = CreateUnitByName("npc_frostivus_boss_zuus", altar_loc + Vector(0, 300, 0), true, nil, nil, DOTA_TEAM_NEUTRALS)
	boss:FaceTowards(altar_loc)
	boss:AddNewModifier(nil, nil, "capture_start_trigger", {boss_name = "zeus", altar_handle = altar})

	-- Abilities
	boss:FindAbilityByName("frostivus_boss_lightning_bolt"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_arc_lightning"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_el_thor"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_static_field"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_thundergods_wrath"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_innate"):SetLevel(1)

	-- Cosmetics
	boss.head = SpawnEntityFromTableSynchronous("prop_dynamic", {model = "models/heroes/zeus/zeus_hair_arcana.vmdl"})
	boss.head:FollowEntity(boss, true)
	boss.hands = SpawnEntityFromTableSynchronous("prop_dynamic", {model = "models/heroes/zeus/zeus_bracers.vmdl"})
	boss.hands:FollowEntity(boss, true)
	boss.pants = SpawnEntityFromTableSynchronous("prop_dynamic", {model = "models/heroes/zeus/zeus_belt.vmdl"})
	boss.pants:FollowEntity(boss, true)

	return boss
end

function SpawnVenomancer(altar)
	local altar_loc = Entities:FindByName(nil, altar):GetAbsOrigin()
	local boss = CreateUnitByName("npc_frostivus_boss_venomancer", altar_loc + Vector(0, 300, 0), true, nil, nil, DOTA_TEAM_NEUTRALS)
	boss:FaceTowards(altar_loc)
	boss:AddNewModifier(nil, nil, "capture_start_trigger", {boss_name = "venomancer", altar_handle = altar})

	-- Abilities
	boss:FindAbilityByName("frostivus_boss_plague_ward"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_venomous_gale"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_scourge_ward"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_vile_ward"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_parasite"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_poison_nova"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_unwilling_host"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_green_death"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_innate"):SetLevel(1)

	-- Cosmetics
	boss.head = SpawnEntityFromTableSynchronous("prop_dynamic", {model = "models/items/venomancer/ferocious_toxicants_embrace_head/ferocious_toxicants_embrace_head.vmdl"})
	boss.head:FollowEntity(boss, true)
	boss.shoulder = SpawnEntityFromTableSynchronous("prop_dynamic", {model = "models/items/venomancer/ferocious_toxicants_embrace_shoulder/ferocious_toxicants_embrace_shoulder.vmdl"})
	boss.shoulder:FollowEntity(boss, true)
	boss.arms = SpawnEntityFromTableSynchronous("prop_dynamic", {model = "models/items/venomancer/deathbringer_arms/deathbringer_arms.vmdl"})
	boss.arms:FollowEntity(boss, true)
	boss.tail = SpawnEntityFromTableSynchronous("prop_dynamic", {model = "models/items/venomancer/deathbringer_tail/deathbringer_tail.vmdl"})
	boss.tail:FollowEntity(boss, true)

	return boss
end

function SpawnTreant(altar)
	local altar_loc = Entities:FindByName(nil, altar):GetAbsOrigin()
	local boss = CreateUnitByName("npc_frostivus_boss_treant", altar_loc + Vector(0, 50, 0), true, nil, nil, DOTA_TEAM_NEUTRALS)
	boss:FaceTowards(altar_loc)
	boss:AddNewModifier(nil, nil, "capture_start_trigger", {boss_name = "treant", altar_handle = altar})

	-- Abilities
	boss:FindAbilityByName("frostivus_boss_vine_smash"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_rock_smash"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_ring_of_thorns"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_leech_seed"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_rapid_growth"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_eyes_in_the_forest"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_living_armor"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_overgrowth"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_natures_guise"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_innate"):SetLevel(1)

	-- Cosmetics
	boss.head = SpawnEntityFromTableSynchronous("prop_dynamic", {model = "models/items/treant/ancient_seal_protector_set_head/ancient_seal_protector_set_head.vmdl"})
	boss.head:FollowEntity(boss, true)
	boss.shoulders = SpawnEntityFromTableSynchronous("prop_dynamic", {model = "models/items/treant/lord_of_ancient_treant_shoulder/lord_of_ancient_treant_shoulder.vmdl"})
	boss.shoulders:FollowEntity(boss, true)
	boss.arms = SpawnEntityFromTableSynchronous("prop_dynamic", {model = "models/items/treant/ancient_seal_protector_set_arms/ancient_seal_protector_set_arms.vmdl"})
	boss.arms:FollowEntity(boss, true)
	boss.feet = SpawnEntityFromTableSynchronous("prop_dynamic", {model = "models/items/treant/ancient_seal_protector_set_legs/ancient_seal_protector_set_legs.vmdl"})
	boss.feet:FollowEntity(boss, true)

	return boss
end

function SpawnTiny()
	local tiny_loc = Vector(1222, 4033, 128)
	local rock_01_loc = Vector(1043, 4159, 128)
	local rock_02_loc = Vector(1100, 3896, 128)
	local rock_03_loc = Vector(1193, 3763, 128)
	local rock_04_loc = Vector(971, 4013, 128)

	-- Spawn Tiny
	local tiny = CreateUnitByName("npc_frostivus_tiny", tiny_loc, true, nil, nil, DOTA_TEAM_NEUTRALS)
	tiny:AddNewModifier(nil, nil, "modifier_frostivus_boss_add", {})
	tiny:AddNewModifier(nil, nil, "modifier_invulnerable", {})

	-- Spawn Rocks
	local rock_01 = CreateUnitByName("npc_frostivus_tiny_rock_01", rock_01_loc, true, nil, nil, DOTA_TEAM_NEUTRALS)
	rock_01:AddNewModifier(nil, nil, "modifier_frostivus_boss_add", {})
	rock_01:AddNewModifier(nil, nil, "modifier_invulnerable", {})

	local rock_02 = CreateUnitByName("npc_frostivus_tiny_rock_02", rock_02_loc, true, nil, nil, DOTA_TEAM_NEUTRALS)
	rock_02:AddNewModifier(nil, nil, "modifier_frostivus_boss_add", {})
	rock_02:AddNewModifier(nil, nil, "modifier_invulnerable", {})

	local rock_03 = CreateUnitByName("npc_frostivus_tiny_rock_03", rock_03_loc, true, nil, nil, DOTA_TEAM_NEUTRALS)
	rock_03:AddNewModifier(nil, nil, "modifier_frostivus_boss_add", {})
	rock_03:AddNewModifier(nil, nil, "modifier_invulnerable", {})

	local rock_04 = CreateUnitByName("npc_frostivus_tiny_rock_04", rock_04_loc, true, nil, nil, DOTA_TEAM_NEUTRALS)
	rock_04:AddNewModifier(nil, nil, "modifier_frostivus_boss_add", {})
	rock_04:AddNewModifier(nil, nil, "modifier_invulnerable", {})

	return {tiny, rock_01, rock_02, rock_03, rock_04}
end

function SpawnNevermore(altar)
	local altar_loc = Entities:FindByName(nil, altar):GetAbsOrigin()
	local boss = CreateUnitByName("npc_frostivus_boss_nevermore", altar_loc + Vector(0, 300, 0), true, nil, nil, DOTA_TEAM_NEUTRALS)
	boss:FaceTowards(altar_loc)
	boss:AddNewModifier(nil, nil, "capture_start_trigger", {boss_name = "nevermore", altar_handle = altar})

	-- Abilities
	boss:FindAbilityByName("frostivus_boss_necromastery"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_immolation"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_ragna_blade"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_meteorain"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_shadowraze"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_soul_harvest"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_nevermore"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_requiem_of_souls"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_innate"):SetLevel(1)

	-- Cosmetics
	boss:SetRenderColor(0, 0, 0)
	boss.head = SpawnEntityFromTableSynchronous("prop_dynamic", {model = "models/items/nevermore/diabolical_fiend_head/diabolical_fiend_head.vmdl"})
	boss.head:FollowEntity(boss, true)
	boss.wings = SpawnEntityFromTableSynchronous("prop_dynamic", {model = "models/heroes/shadow_fiend/arcana_wings.vmdl"})
	boss.wings:FollowEntity(boss, true)
	boss.wings:SetRenderColor(0, 0, 0)
	boss.shoulders = SpawnEntityFromTableSynchronous("prop_dynamic", {model = "models/items/nevermore/ferrum_chiroptera_shoulder/ferrum_chiroptera_shoulder.vmdl"})
	boss.shoulders:FollowEntity(boss, true)
	boss.shoulders:SetRenderColor(0, 0, 0)
	boss.arms = SpawnEntityFromTableSynchronous("prop_dynamic", {model = "models/items/nevermore/diabolical_fiend_arms/diabolical_fiend_arms.vmdl"})
	boss.arms:FollowEntity(boss, true)
	boss.arms:SetRenderColor(0, 0, 0)
	boss.hand = SpawnEntityFromTableSynchronous("prop_dynamic", {model = "models/heroes/shadow_fiend/fx_shadow_fiend_arcana_hand.vmdl"})
	boss.hand:FollowEntity(boss, true)
	boss.hand:SetRenderColor(0, 0, 0)

	return boss
end

function SpawnTusk()
	local boss = CreateUnitByName("npc_frostivus_boss_tusk", Vector(0, 0, 0), true, nil, nil, DOTA_TEAM_NEUTRALS)
	boss:FaceTowards(boss:GetAbsOrigin() + Vector(0, -1, 0))
	boss:SetAbsOrigin(Vector(0, 0, boss:GetAbsOrigin().z + 100))

	-- Abilities
	boss:FindAbilityByName("frostivus_tusk"):SetLevel(1)

	-- Cosmetics
	boss:SetRenderColor(0, 0, 0)

	return boss
end

function SpawnMegaGreevil(team)
	local boss = CreateUnitByName("npc_frostivus_boss_greevil", Vector(0, 0, 0), true, nil, nil, DOTA_TEAM_NEUTRALS)

	local radiant_altar = Entities:FindByName(nil, "altar_1")
	local dire_altar = Entities:FindByName(nil, "altar_7")
	if team == DOTA_TEAM_GOODGUYS then
		boss:MoveToPosition(dire_altar:GetAbsOrigin())
	elseif team == DOTA_TEAM_BADGUYS then
		boss:MoveToPosition(radiant_altar:GetAbsOrigin())
	end

	-- Abilities
	boss:FindAbilityByName("frostivus_mega_greevil"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_overgrowth"):SetLevel(1)
	boss:FindAbilityByName("frostivus_boss_poison_nova"):SetLevel(1)

	boss:RemoveModifierByName("modifier_frostivus_mega_greevil")
	boss:AddNewModifier(nil, nil, "boss_thinker_mega_greevil", {})

	-- Cosmetics
	boss:SetRenderColor(25, 0, 0)

	return boss
end

---------------------
-- Other stuff
---------------------

function BossPhaseAbilityCast(team, ability_image, ability_name, delay)
	local ability_cast_timer = 0.0
	Timers:CreateTimer(function()
		CustomGameEventManager:Send_ServerToTeam(team, "BossStartedCast", {ability_image = ability_image, ability_name = ability_name, current_cast_time = ability_cast_timer, cast_time = delay})
		if ability_cast_timer < delay then
			ability_cast_timer = ability_cast_timer + FrameTime()
			return FrameTime()
		elseif ability_cast_timer >= delay then
			ability_cast_timer = 0.0
			CustomGameEventManager:Send_ServerToTeam(team, "BossStartedCast", {ability_image = ability_image, ability_name = ability_name, current_cast_time = ability_cast_timer, cast_time = delay})
		end
	end)
end

function PlaySoundForTeam(team, sound)
	for player_id = 0, 20 do
		if PlayerResource:GetPlayer(player_id) then
			if PlayerResource:GetTeam(player_id) == team then
				EmitSoundOnClient(sound, PlayerResource:GetPlayer(player_id))
			end
		end
	end
end

function CleanseBossDebuffs(hero)
	hero:RemoveModifierByName("modifier_frostivus_zeus_positive_charge")
	hero:RemoveModifierByName("modifier_frostivus_zeus_negative_charge")
	hero:RemoveModifierByName("modifier_frostivus_venomancer_poison_sting_debuff")
	hero:RemoveModifierByName("modifier_frostivus_venomancer_venomous_gale")
	hero:RemoveModifierByName("modifier_frostivus_venomancer_poison_nova")
	hero:RemoveModifierByName("modifier_frostivus_venomancer_unwilling_host")
	hero:RemoveModifierByName("modifier_frostivus_venomancer_virulent_plague")
	hero:RemoveModifierByName("modifier_frostivus_venomancer_parasite")
	hero:RemoveModifierByName("modifier_frostivus_leech_seed_debuff")
	hero:RemoveModifierByName("modifier_frostivus_overgrowth_root")
end

function PresentWave(count)
	local north = RandomVector(100):Normalized()
	local launch_positions = {}
	for i = 1, count do
		launch_positions[i] = RotatePosition(Vector(0, 0, 0), QAngle(0, (i - 1) * 360 / count, 0), north * RandomInt(350, 750))
	end

	-- Presents stinger
	PlaySoundForTeam(DOTA_TEAM_GOODGUYS, "greevil_eventstart_Stinger")
	PlaySoundForTeam(DOTA_TEAM_BADGUYS, "greevil_eventstart_Stinger")

	-- Launch presents
	for _, launch_position in pairs(launch_positions) do
		local item = CreateItem("item_frostivus_present", nil, nil)
		CreateItemOnPositionForLaunch(Vector(0, 0, 0), item)
		item:LaunchLootInitialHeight(true, 750, 900, 0.8, launch_position)
	end
end

---------------------
-- Phase transitions
---------------------

function StartPhaseTwo()

	-- End all boss fights
	local all_heroes = HeroList:GetAllHeroes()
	for _, hero in pairs(all_heroes) do
		hero:RemoveModifierByName("modifier_fighting_boss")
		CleanseBossDebuffs(hero)
		hero:Purge(false, true, false, false, false)
		hero:AddNewModifier(hero, nil, "modifier_aegis_regen", {duration = 3.0})
	end
	RADIANT_FIGHTING = false
	DIRE_FIGHTING = false

	-- Hide boss health bars
	CustomGameEventManager:Send_ServerToTeam(DOTA_TEAM_GOODGUYS, "hide_boss_hp", {})
	CustomGameEventManager:Send_ServerToTeam(DOTA_TEAM_BADGUYS, "hide_boss_hp", {})

	-- Reset all arenas
	for i = 1, 7 do
		local altar_handle = Entities:FindByName(nil, "altar_"..i)
		altar_handle:RemoveModifierByName("modifier_altar_active")
		altar_handle:RemoveModifierByName("modifier_frostivus_immolation")
		if altar_handle.arena_fence_pfx then
			ParticleManager:DestroyParticle(altar_handle.arena_fence_pfx, true)
			ParticleManager:ReleaseParticleIndex(altar_handle.arena_fence_pfx)
		end
		local nearby_summons = FindUnitsInRadius(DOTA_TEAM_NEUTRALS, altar_handle:GetAbsOrigin(), nil, 2200, DOTA_UNIT_TARGET_TEAM_FRIENDLY, DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC, DOTA_UNIT_TARGET_FLAG_INVULNERABLE + DOTA_UNIT_TARGET_FLAG_OUT_OF_WORLD, FIND_ANY_ORDER, false)
		for _,summon in pairs(nearby_summons) do
			if not (summon:HasModifier("modifier_frostivus_boss") or summon:HasModifier("modifier_frostivus_tusk") or summon:HasModifier("modifier_frostivus_mega_greevil")) then
				summon:Kill(nil, summon)
			end
		end
	end

	-- Reset all bosses
	local all_bosses = FindUnitsInRadius(DOTA_TEAM_NEUTRALS, Vector(0, 0, 0), nil, 20000, DOTA_UNIT_TARGET_TEAM_FRIENDLY, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_FLAG_INVULNERABLE, FIND_ANY_ORDER, false)
	for _, boss in pairs(all_bosses) do
		if boss:HasModifier("modifier_frostivus_boss") then
			boss:RemoveModifierByName("boss_thinker_zeus")
			boss:RemoveModifierByName("boss_thinker_venomancer")
			boss:RemoveModifierByName("boss_thinker_treant")
			boss:RemoveModifierByName("boss_thinker_nevermore")
			boss:Purge(true, true, false, true, true)
			boss:Heal(999999, nil)
			boss:GiveMana(boss:GetMaxMana())
			boss:Stop()
			if boss:GetUnitName() == "npc_frostivus_boss_zuus" then
				boss:SetAbsOrigin(Entities:FindByName(nil, "altar_2"):GetAbsOrigin() + Vector(0, 300, 0))
			elseif boss:GetUnitName() == "npc_frostivus_boss_venomancer" then
				boss:SetAbsOrigin(Entities:FindByName(nil, "altar_3"):GetAbsOrigin() + Vector(0, 300, 0))
			elseif boss:GetUnitName() == "npc_frostivus_boss_treant" then
				boss:SetAbsOrigin(Entities:FindByName(nil, "altar_5"):GetAbsOrigin() + Vector(0, 50, 0))
			elseif boss:GetUnitName() == "npc_frostivus_boss_nevermore" then
				boss:SetAbsOrigin(Entities:FindByName(nil, "altar_6"):GetAbsOrigin() + Vector(0, 300, 0))
			end
		end
	end
end

function BossPhaseAbilityCastAlt(team, ability_image, ability_name, delay)
	local ability_cast_timer = 0.0
	Timers:CreateTimer(function()
		CustomGameEventManager:Send_ServerToTeam(team, "BossStartedCastAlt", {ability_image = ability_image, ability_name = ability_name, current_cast_time = ability_cast_timer, cast_time = delay})
		if ability_cast_timer < delay then
			ability_cast_timer = ability_cast_timer + FrameTime()
			return FrameTime()
		elseif ability_cast_timer >= delay then
			ability_cast_timer = 0.0
			CustomGameEventManager:Send_ServerToTeam(team, "BossStartedCastAlt", {ability_image = ability_image, ability_name = ability_name, current_cast_time = ability_cast_timer, cast_time = delay})
		end
	end)
end
