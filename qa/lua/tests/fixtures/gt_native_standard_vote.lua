-- Source-qualified native Twitch oracle, extracted without algorithm edits.
-- Source repository commit: 93dea911a4cc464a0eb51cfdc3a443297bfc4550.
-- Vermintide-2-Source-Code/scripts/managers/twitch/twitch_manager.lua:
-- _clear_used_votes 1172-1180; _check_breed_package_loading 1182-1277;
-- _get_game_mode_whitelist/_in_whitelist 1280-1295; _next_standard_vote 1403-1453.
-- Only the owner table name is adapted to make the retained functions importable.
local MIN_VOTES_LEFT_IN_ROTATION = 2
local Native = {}

Native._clear_used_votes = function (self, force_clear)
	local used_vote_templates = self._used_vote_templates
	local game_mode_whitelist = self:_get_game_mode_whitelist()
	local num_available_vote_templates = game_mode_whitelist and #game_mode_whitelist or #TwitchVoteTemplatesLookup

	if force_clear or num_available_vote_templates - table.size(used_vote_templates) <= MIN_VOTES_LEFT_IN_ROTATION then
		table.clear(used_vote_templates)
	end
end


Native._check_breed_package_loading = function (self, wanted_template, previous_template)
	local wanted_breed_name = wanted_template.breed_name

	if not wanted_breed_name then
		return wanted_template
	end

	local is_boss = wanted_template.boss
	local is_special = wanted_template.special

	if not is_boss and not is_special then
		return wanted_template
	end

	local package_loader = Managers.level_transition_handler.enemy_package_loader
	local request_success, replacement_breed_name = true

	if not package_loader:is_breed_processed(wanted_breed_name) then
		request_success = package_loader:request_breed(wanted_breed_name)
	end

	if request_success then
		package_loader:lock_breed_package(wanted_breed_name)

		self._parent.locked_breed_packages[wanted_breed_name] = true

		return wanted_template
	else
		local replacement_breeds = {}

		for breed_name, _ in pairs(package_loader:processed_breeds()) do
			replacement_breeds[#replacement_breeds + 1] = breed_name
		end

		table.shuffle(replacement_breeds)

		local templates = is_boss and TwitchBossesSpawnBreedNamesLookup or is_special and TwitchSpecialsSpawnBreedNamesLookup

		for i = 1, #replacement_breeds do
			local breed_name = replacement_breeds[i]

			if templates[breed_name] then
				replacement_breed_name = breed_name

				break
			end
		end
	end

	local use_boss_equivalent = is_boss and previous_template and previous_template.breed_name == replacement_breed_name
	local override_template
	local used_vote_templates = self._used_vote_templates

	if use_boss_equivalent then
		local best_diff = math.huge
		local templates = TwitchBossEquivalentSpawnTemplatesLookup

		table.shuffle(templates)

		for i = 1, #templates do
			local replacement_template_name = templates[i]

			if not used_vote_templates[replacement_template_name] then
				local replacement_template = TwitchVoteTemplates[replacement_template_name]

				if wanted_template.name ~= replacement_template.name then
					local diff = math.abs(math.abs(wanted_template.cost) - math.abs(replacement_template.cost))

					if diff < best_diff then
						override_template = replacement_template
						best_diff = diff
					end
				end
			end
		end
	elseif is_boss then
		local templates = TwitchBossesSpawnBreedNamesLookup
		local replacement_template = templates[replacement_breed_name]

		override_template = replacement_template
	elseif is_special then
		local templates = TwitchSpecialsSpawnBreedNamesLookup
		local replacement_template = templates[replacement_breed_name]

		if not used_vote_templates[replacement_template.name] and (previous_template == nil or previous_template and previous_template.name ~= replacement_template.name) and wanted_template.name ~= replacement_template.name then
			override_template = replacement_template
		end
	end

	if not override_template then
		self:_clear_used_votes(true)
		print("BREED PACKAGE LOADING FAILED")

		return self:_check_breed_package_loading(wanted_template, previous_template)
	end

	return override_template
end


Native._get_game_mode_whitelist = function (self)
	local game_mode_key = Managers.state.game_mode:game_mode_key()

	return TwitchVoteWhitelists[game_mode_key]
end

Native._in_whitelist = function (self, template_name)
	local game_mode_whitelist = self:_get_game_mode_whitelist()

	if game_mode_whitelist == nil then
		return true
	else
		return table.contains(game_mode_whitelist, template_name)
	end
end


Native._next_standard_vote = function (self, template_a)
	local used_vote_templates = self._used_vote_templates
	local template_a_name = template_a.name
	local cost_a = template_a.cost
	local templates = table.clone(TwitchStandardVoteTemplatesLookup)

	table.shuffle(templates)

	local best_template
	local best_diff = math.huge

	for i = 1, #templates do
		local template_b_name = templates[i]

		if template_a_name ~= template_b_name and not used_vote_templates[template_b_name] then
			local template_b = TwitchVoteTemplates[template_b_name]
			local is_allowed = not template_b.condition_func or template_b.condition_func()

			if is_allowed then
				local invalid_matchup = template_a.boss and not template_b.boss and not template_b.boss_equivalent

				if not invalid_matchup then
					local cost_b = template_b.cost
					local vote_cost_diff = math.abs(cost_a - cost_b)

					if vote_cost_diff <= TwitchSettings.max_a_b_vote_cost_diff and vote_cost_diff < best_diff then
						best_template = template_b
						best_diff = vote_cost_diff
					end
				end
			end
		end
	end

	if not best_template then
		self:_clear_used_votes(true)

		return self:_next_standard_vote(template_a)
	end

	template_a = self:_check_breed_package_loading(template_a)
	best_template = self:_check_breed_package_loading(best_template, template_a)

	local vote_templates = {
		template_a.name,
		best_template.name,
	}

	return "standard_vote", vote_templates, nil
end


return Native
