-- Skills not yet exported by the upstream data generator.
return function(skills, mod, flag, skill)
	-- The pinned 3.30 game-data export has a single level for this skill:
	-- https://github.com/repoe-fork/repoe-fork.github.io/blob/c97553d1fc14a134dd6813e672d2b45fddf5b42d/data/gems.json
	-- The statue's coverage and enemy action-speed effect are not simulated.
	skills["SummonPetrificationStatue"] = {
		name = "Petrification Statue",
		hidden = true,
		fromItem = true,
		color = 4,
		description = "Creates a Petrification Statue that slows enemies in its gaze. Enemy coverage, slow and petrification are not automatically applied to calculations.",
		skillTypes = { [SkillType.Spell] = true, [SkillType.Duration] = true, [SkillType.Triggerable] = true, [SkillType.Cooldown] = true },
		statDescriptionScope = "skill_stat_descriptions",
		castTime = 1,
		baseFlags = { spell = true, duration = true },
		constantStats = {
			{ "base_skill_effect_duration", 4000 },
			{ "petrification_statue_target_action_speed_-%", 15 },
			{ "petrification_statue_pertrify_duration_ms", 5000 },
		},
		stats = { },
		levels = { [1] = { cooldown = 30, levelRequirement = 1, storedUses = 1, statInterpolation = { } } },
	}
end
