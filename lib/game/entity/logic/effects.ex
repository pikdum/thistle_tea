defmodule ThistleTea.Game.Entity.Logic.Effects do
  @moduledoc """
  Typed effects produced by pure logic and queued on an entity's internal
  state. Constructors validate inputs and return small enforced-key structs;
  the owning boundary later drains and interprets them.
  """
  alias __MODULE__, as: Effects
  alias ThistleTea.Game.Spell.Target

  def cancel_auto_repeat do
    %Effects.CancelAutoRepeat{}
  end

  def spell_damage(source_guid, target_guid, spell, damage, opts \\ []) do
    %Effects.SpellDamage{
      source_guid: source_guid,
      target_guid: target_guid,
      spell_id: spell.id,
      spell: spell,
      school: spell.school,
      damage: damage,
      proc_damage: Keyword.get(opts, :proc_damage),
      periodic?: Keyword.get(opts, :periodic?, false),
      proc_type: Keyword.get(opts, :proc_type, spell_damage_proc_type(opts)),
      resisted: Keyword.get(opts, :resisted, 0),
      absorbed: Keyword.get(opts, :absorbed, 0),
      crit?: Keyword.get(opts, :crit?, false),
      blocked: Keyword.get(opts, :blocked, 0)
    }
  end

  defp spell_damage_proc_type(opts) do
    if Keyword.get(opts, :periodic?, false), do: :deal_harmful_periodic, else: :deal_harmful_spell
  end

  def spell_heal(source_guid, target_guid, spell, healing, crit?, opts \\ []) do
    %Effects.SpellHeal{
      source_guid: source_guid,
      target_guid: target_guid,
      spell_id: spell.id,
      spell: spell,
      school: spell.school,
      damage: healing,
      periodic?: Keyword.get(opts, :periodic?, false),
      proc_type: Keyword.get(opts, :proc_type, spell_heal_proc_type(opts)),
      crit?: crit?
    }
  end

  defp spell_heal_proc_type(opts) do
    if Keyword.get(opts, :periodic?, false), do: :deal_helpful_periodic, else: :deal_helpful_spell
  end

  def drain_power(target_guid, power_type) when is_integer(target_guid) and is_integer(power_type) do
    %Effects.DrainPower{target_guid: target_guid, misc_value: power_type}
  end

  def grant_power(target_guid, power_type, amount)
      when is_integer(target_guid) and is_integer(power_type) and is_integer(amount) do
    %Effects.GrantPower{target_guid: target_guid, misc_value: power_type, amount: amount}
  end

  def charge(target_guid) when is_integer(target_guid) do
    %Effects.Charge{target_guid: target_guid}
  end

  def spell_log_miss(source_guid, target_guid, spell_id, reason)
      when is_integer(source_guid) and is_integer(target_guid) and is_integer(spell_id) and is_atom(reason) do
    %Effects.SpellLogMiss{source_guid: source_guid, target_guid: target_guid, spell_id: spell_id, reason: reason}
  end

  def aura_duration(slot, duration_ms) when is_integer(slot) and is_integer(duration_ms) do
    %Effects.AuraDuration{aura_slot: slot, duration_ms: duration_ms}
  end

  def remove_aura(source_guid, target_guid, spell_id)
      when is_integer(source_guid) and is_integer(target_guid) and is_integer(spell_id) do
    %Effects.RemoveAura{source_guid: source_guid, target_guid: target_guid, spell_id: spell_id}
  end

  def periodic_aura_log(source_guid, target_guid, spell, aura_type, amount, opts \\ [])
      when is_integer(source_guid) and is_integer(target_guid) and is_atom(aura_type) and is_integer(amount) do
    %Effects.PeriodicAuraLog{
      source_guid: source_guid,
      target_guid: target_guid,
      spell_id: spell.id,
      aura_type: aura_type,
      amount: amount,
      misc_value: Keyword.get(opts, :misc_value, 0)
    }
  end

  def movement_stopped do
    %Effects.MovementStopped{}
  end

  def movement_speed_changed(speed) when is_number(speed) do
    %Effects.MovementSpeedChanged{speed: speed}
  end

  def movement_root_changed(rooted?) when is_boolean(rooted?) do
    %Effects.MovementRootChanged{rooted?: rooted?}
  end

  def feather_fall_changed(enabled?) when is_boolean(enabled?) do
    %Effects.FeatherFallChanged{enabled?: enabled?}
  end

  def hover_changed(enabled?) when is_boolean(enabled?) do
    %Effects.HoverChanged{enabled?: enabled?}
  end

  def water_walk_changed(enabled?) when is_boolean(enabled?) do
    %Effects.WaterWalkChanged{enabled?: enabled?}
  end

  def heal_entity(target_guid, amount) when is_integer(target_guid) and is_integer(amount) do
    %Effects.HealEntity{target_guid: target_guid, amount: amount}
  end

  def heal_threat(source_guid, target_guid, amount)
      when is_integer(source_guid) and is_integer(target_guid) and is_number(amount) do
    %Effects.HealThreat{source_guid: source_guid, target_guid: target_guid, amount: amount}
  end

  def resurrect_request(source_guid, spell_id, health, mana)
      when is_integer(source_guid) and is_integer(spell_id) and is_integer(health) and is_integer(mana) do
    %Effects.ResurrectRequest{source_guid: source_guid, spell_id: spell_id, health: health, mana: mana}
  end

  def monster_move(opts \\ []) when is_list(opts) do
    %Effects.MonsterMove{move_opts: opts}
  end

  def spell_cast_result(spell_id) when is_integer(spell_id) do
    %Effects.SpellCastResult{spell_id: spell_id}
  end

  def spell_cast_failed(spell_id, reason) when is_integer(spell_id) and is_atom(reason) do
    %Effects.SpellCastFailed{spell_id: spell_id, reason: reason}
  end

  def spell_cooldown(source_guid, spell_id, cooldown_ms)
      when is_integer(source_guid) and is_integer(spell_id) and is_integer(cooldown_ms) do
    %Effects.SpellCooldown{source_guid: source_guid, spell_id: spell_id, duration_ms: cooldown_ms}
  end

  def spell_modifier(type, index, operation, amount)
      when type in [:flat, :pct] and is_integer(index) and is_integer(operation) and is_integer(amount) do
    %Effects.SpellModifier{modifier_type: type, effect_index: index, operation: operation, amount: amount}
  end

  def cooldown_event(source_guid, spell_id) when is_integer(source_guid) and is_integer(spell_id) do
    %Effects.CooldownEvent{source_guid: source_guid, spell_id: spell_id}
  end

  def clear_cooldown(target_guid, spell_id) when is_integer(target_guid) and is_integer(spell_id) do
    %Effects.ClearCooldown{target_guid: target_guid, spell_id: spell_id}
  end

  def stand_state(stand_state) when is_integer(stand_state) do
    %Effects.StandState{stand_state: stand_state}
  end

  def spell_start(source_guid, spell_id, cast_time_ms, %Target{} = targets)
      when is_integer(source_guid) and is_integer(spell_id) and is_integer(cast_time_ms) do
    %Effects.SpellStart{
      source_guid: source_guid,
      spell_id: spell_id,
      duration_ms: cast_time_ms,
      targets: targets
    }
  end

  def spell_go(source_guid, spell_id, hit_guids, %Target{} = targets, cast_item_guid \\ nil, misses \\ [])
      when is_integer(source_guid) and is_integer(spell_id) and is_list(hit_guids) and is_list(misses) do
    %Effects.SpellGo{
      source_guid: source_guid,
      spell_id: spell_id,
      hit_guids: hit_guids,
      misses: misses,
      targets: targets,
      cast_item_guid: cast_item_guid
    }
  end

  def channel_start(source_guid, spell_id, duration_ms)
      when is_integer(source_guid) and is_integer(spell_id) and is_integer(duration_ms) do
    %Effects.ChannelStart{source_guid: source_guid, spell_id: spell_id, channel_time_ms: duration_ms}
  end

  def channel_update(source_guid, time_ms) when is_integer(source_guid) and is_integer(time_ms) do
    %Effects.ChannelUpdate{source_guid: source_guid, channel_time_ms: time_ms}
  end

  def spell_delayed(source_guid, delay_ms) when is_integer(source_guid) and is_integer(delay_ms) do
    %Effects.SpellDelayed{source_guid: source_guid, delay_ms: delay_ms}
  end

  def delay_aura(source_guid, target_guid, spell_id, delay_ms)
      when is_integer(source_guid) and is_integer(target_guid) and is_integer(spell_id) and is_integer(delay_ms) do
    %Effects.DelayAura{source_guid: source_guid, target_guid: target_guid, spell_id: spell_id, delay_ms: delay_ms}
  end

  def deliver_attack(target_guid, attack) when is_integer(target_guid) and is_map(attack) do
    %Effects.DeliverAttack{target_guid: target_guid, attack: attack}
  end

  def deliver_spell(target_guid, cast_context, spell) when is_integer(target_guid) do
    %Effects.DeliverSpell{target_guid: target_guid, cast_context: cast_context, spell: spell}
  end

  def deliver_heal_threat(mob_guid, source_guid, target_guid, amount)
      when is_integer(mob_guid) and is_integer(source_guid) and is_integer(target_guid) and is_number(amount) do
    %Effects.DeliverHealThreat{
      mob_guid: mob_guid,
      source_guid: source_guid,
      target_guid: target_guid,
      amount: amount
    }
  end

  def deliver_spell_outcome(target_guid, source_guid, spell, outcome)
      when is_integer(target_guid) and is_integer(source_guid) and is_atom(outcome) do
    %Effects.DeliverSpellOutcome{source_guid: source_guid, target_guid: target_guid, spell: spell, outcome: outcome}
  end

  def attack_start(source_guid, target_guid) when is_integer(source_guid) and is_integer(target_guid) do
    %Effects.AttackStart{source_guid: source_guid, target_guid: target_guid}
  end

  def call_assistance(target_guid) when is_integer(target_guid) do
    %Effects.CallAssistance{target_guid: target_guid}
  end

  def call_for_help(target_guid) when is_integer(target_guid) do
    %Effects.CallForHelp{target_guid: target_guid}
  end

  def attack_stop(source_guid, target_guid) when is_integer(source_guid) and is_integer(target_guid) do
    %Effects.AttackStop{source_guid: source_guid, target_guid: target_guid}
  end

  def duel_defeat(loser_guid, winner_guid) when is_integer(loser_guid) and is_integer(winner_guid) do
    %Effects.DuelDefeat{source_guid: winner_guid, target_guid: loser_guid}
  end

  def duel_interrupted(guid) when is_integer(guid) do
    %Effects.DuelInterrupted{target_guid: guid}
  end

  def attack_not_in_range do
    %Effects.AttackNotInRange{}
  end

  def attacker_gained(target_guid) when is_integer(target_guid) do
    %Effects.AttackerGained{target_guid: target_guid}
  end

  def threat_ref_gained(target_guid) when is_integer(target_guid) do
    %Effects.ThreatRefGained{target_guid: target_guid}
  end

  def threat_ref_lost(target_guid) when is_integer(target_guid) do
    %Effects.ThreatRefLost{target_guid: target_guid}
  end

  def drop_threat(target_guid) when is_integer(target_guid) do
    %Effects.DropThreat{target_guid: target_guid}
  end

  def drop_nearby_threat do
    %Effects.DropNearbyThreat{}
  end

  def drop_nearby_threat_resolved(target_guids, metadata) when is_list(target_guids) and is_map(metadata) do
    %Effects.DropNearbyThreatResolved{target_guids: target_guids, metadata: metadata}
  end

  def blade_flurry(target_guid, damage, spell_id)
      when is_integer(target_guid) and is_integer(damage) and damage > 0 and is_integer(spell_id) do
    %Effects.BladeFlurry{target_guid: target_guid, damage: damage, spell_id: spell_id}
  end

  defguardp valid_secondary_melee?(target_guid, damage, spell_id, radius)
            when is_integer(target_guid) and is_integer(damage) and damage > 0 and is_integer(spell_id) and
                   is_number(radius) and radius > 0

  def secondary_melee(target_guid, damage, spell_id, radius)
      when valid_secondary_melee?(target_guid, damage, spell_id, radius) do
    %Effects.SecondaryMelee{target_guid: target_guid, damage: damage, spell_id: spell_id, range_yards: radius}
  end

  def attacker_lost(target_guid) when is_integer(target_guid) do
    %Effects.AttackerLost{target_guid: target_guid}
  end

  def tap_cleared do
    %Effects.TapCleared{}
  end

  def tap_claimed(player_guid, group_id) when is_integer(player_guid) do
    %Effects.TapClaimed{player_guid: player_guid, group_id: group_id}
  end

  def attack_outcome(attacker_guid, victim_guid, outcome, damage, spell_id, proc_damage \\ nil)
      when is_integer(attacker_guid) and is_integer(victim_guid) and is_atom(outcome) do
    %Effects.AttackOutcome{
      target_guid: attacker_guid,
      source_guid: victim_guid,
      outcome: outcome,
      damage: damage,
      proc_damage: proc_damage || damage,
      spell_id: spell_id
    }
  end

  def attacker_state_update(source_guid, target_guid, damage, attack \\ %{})
      when is_integer(source_guid) and is_integer(target_guid) do
    %Effects.AttackerStateUpdate{source_guid: source_guid, target_guid: target_guid, damage: damage, attack: attack}
  end

  def enqueue(entity, events) when is_list(events) do
    Enum.reduce(events, entity, &enqueue(&2, &1))
  end

  def enqueue(%{internal: %{events: events} = internal} = entity, %{__struct__: _module} = effect)
      when is_list(events) do
    %{entity | internal: %{internal | events: events ++ [effect]}}
  end

  def enqueue(%{internal: internal} = entity, %{__struct__: _module} = effect) do
    %{entity | internal: %{internal | events: [effect]}}
  end

  def teleport({_x, _y, _z, _o} = position) do
    %Effects.Teleport{position: position}
  end

  def teleport_to_world(world, {_x, _y, _z} = position) do
    %Effects.TeleportToWorld{world: world, position: position}
  end

  def charge_resolved(path, duration_ms, {_x, _y, _z, _o} = destination)
      when is_list(path) and is_integer(duration_ms) do
    %Effects.ChargeResolved{path: path, duration_ms: duration_ms, destination: destination}
  end

  def leap({_x, _y, _z, _o} = position) do
    %Effects.Leap{position: position}
  end

  def teleport_to_spell_target(spell_id) when is_integer(spell_id) do
    %Effects.TeleportToSpellTarget{spell_id: spell_id}
  end

  def deliver_spell_to_query(source_guid, source_level, spell, query, opts \\ [])
      when is_integer(source_guid) and is_integer(source_level) do
    %Effects.DeliverSpellToQuery{
      source_guid: source_guid,
      source_level: source_level,
      spell: spell,
      query: query,
      exclude_guids: Keyword.get(opts, :exclude_guids, [])
    }
  end

  def consume_cast_item(item_guid) when is_integer(item_guid) do
    %Effects.ConsumeCastItem{cast_item_guid: item_guid}
  end

  def feed_pet(item_guid, pet_guid, trigger_spell_id, range_yards)
      when is_integer(item_guid) and is_integer(pet_guid) and is_integer(trigger_spell_id) do
    %Effects.FeedPet{
      cast_item_guid: item_guid,
      target_guid: pet_guid,
      spell_id: trigger_spell_id,
      range_yards: range_yards
    }
  end

  def enchant_item(item_guid, spell, effect) when is_integer(item_guid) do
    %Effects.EnchantItem{target_guid: item_guid, spell: spell, effect: effect}
  end

  def open_gameobject(object_guid) when is_integer(object_guid) do
    %Effects.OpenGameObject{target_guid: object_guid}
  end

  def create_item(item_id, count) when is_integer(item_id) and is_integer(count) do
    %Effects.CreateItem{item_id: item_id, count: count}
  end

  def create_item(target_guid, item_id, count)
      when is_integer(target_guid) and is_integer(item_id) and is_integer(count) do
    %Effects.GiveItem{target_guid: target_guid, item_id: item_id, count: count}
  end

  def spawn_area_effect(spell, effect, {_x, _y, _z} = position, duration_ms) when is_integer(duration_ms) do
    %Effects.SpawnAreaEffect{spell: spell, effect: effect, position: position, duration_ms: duration_ms}
  end

  def spawn_farsight(spell, {_x, _y, _z} = position, duration_ms) when is_integer(duration_ms) do
    %Effects.SpawnFarsight{spell: spell, position: position, duration_ms: duration_ms}
  end

  def despawn_area_effects(spell_id) when is_integer(spell_id) do
    %Effects.DespawnAreaEffects{spell_id: spell_id}
  end

  def despawn_entity(guid) when is_integer(guid) do
    %Effects.DespawnEntity{target_guid: guid}
  end

  def leave_ritual(game_object_guid, user_guid) when is_integer(game_object_guid) and is_integer(user_guid) do
    %Effects.LeaveRitual{target_guid: game_object_guid, source_guid: user_guid}
  end

  def summon_game_object(entry, duration_ms, opts \\ []) when is_integer(entry) and is_integer(duration_ms) do
    %Effects.SummonGameObject{
      entry: entry,
      duration_ms: duration_ms,
      target_guid: Keyword.get(opts, :ritual_target_guid),
      position: Keyword.get(opts, :position)
    }
  end

  def duel_request(source_guid, source_level, target_guid, entry, {world, x, y, z}, facing)
      when is_integer(source_guid) and is_integer(target_guid) and is_integer(entry) do
    %Effects.DuelRequest{
      source_guid: source_guid,
      source_level: source_level,
      target_guid: target_guid,
      entry: entry,
      position: {world, x, y, z},
      facing: facing
    }
  end

  def summon_request(summoner_guid, target_guid, zone_id, {world, x, y, z})
      when is_integer(summoner_guid) and is_integer(target_guid) do
    %Effects.SummonRequest{
      source_guid: summoner_guid,
      target_guid: target_guid,
      amount: zone_id,
      position: {world, x, y, z}
    }
  end

  def consume_reagents(reagents) when is_list(reagents) do
    %Effects.ConsumeReagents{reagents: reagents}
  end

  def trigger_spell(source_guid, source_level, target_guid, spell_id, opts \\ [])
      when is_integer(target_guid) and is_integer(spell_id) do
    %Effects.TriggerSpell{
      source_guid: source_guid,
      source_level: source_level,
      target_guid: target_guid,
      spell_id: spell_id,
      target_role: Keyword.get(opts, :target_role),
      triggering_spell_id: Keyword.get(opts, :triggered_by_spell_id),
      slot: Keyword.get(opts, :effect_index),
      amount: Keyword.get(opts, :base_points),
      duration_ms: Keyword.get(opts, :duration_ms),
      resolve_targets?: Keyword.get(opts, :resolve_targets?, false)
    }
  end

  def trigger_spell_request(source_guid, spell_id, target_guid, opts)
      when is_integer(source_guid) and is_integer(spell_id) and is_integer(target_guid) and is_list(opts) do
    %Effects.TriggerSpellRequest{
      source_guid: source_guid,
      target_guid: target_guid,
      spell_id: spell_id,
      opts: opts
    }
  end

  def monster_talk(text, chat_type, target_guid) when is_binary(text) and is_atom(chat_type) do
    %Effects.MonsterTalk{text: text, chat_type: chat_type, target_guid: target_guid}
  end

  def emote(emote_id) when is_integer(emote_id) do
    %Effects.Emote{emote_id: emote_id}
  end

  def game_object_custom_animation(animation) when is_integer(animation) do
    %Effects.GameObjectCustomAnimation{animation: animation}
  end

  def script_steps(steps, target_guid, delay_ms) when is_list(steps) and is_integer(delay_ms) do
    %Effects.ScriptSteps{steps: steps, target_guid: target_guid, duration_ms: delay_ms}
  end

  def scripted_event_command(world, source_guid, target_guid, step) when is_integer(source_guid) and source_guid > 0 do
    %Effects.ScriptedEventCommand{
      world: world,
      source_guid: source_guid,
      target_guid: target_guid,
      step: step
    }
  end

  def summon_creature(summon, steps, target_guid) when is_map(summon) and is_list(steps) do
    %Effects.SummonCreature{summon: summon, steps: steps, target_guid: target_guid}
  end

  def control_granted(owner_guid, controlled_guid, spell_id, spells, opts \\ [])
      when is_integer(owner_guid) and is_integer(controlled_guid) and is_integer(spell_id) and is_list(spells) do
    %Effects.ControlGranted{
      source_guid: owner_guid,
      target_guid: controlled_guid,
      spell_id: spell_id,
      spells: spells,
      kind: Keyword.get(opts, :kind, :charm)
    }
  end

  def control_released(owner_guid, controlled_guid) when is_integer(owner_guid) and is_integer(controlled_guid) do
    %Effects.ControlReleased{source_guid: owner_guid, target_guid: controlled_guid}
  end

  def release_controlled(owner_guid, controlled_guid, spell_id \\ nil)
      when is_integer(owner_guid) and is_integer(controlled_guid) and (is_integer(spell_id) or is_nil(spell_id)) do
    %Effects.ReleaseControlled{source_guid: owner_guid, target_guid: controlled_guid, spell_id: spell_id}
  end

  def viewpoint_granted(owner_guid, viewpoint_guid) when is_integer(owner_guid) and is_integer(viewpoint_guid) do
    %Effects.ViewpointGranted{source_guid: owner_guid, target_guid: viewpoint_guid}
  end

  def viewpoint_released(owner_guid, viewpoint_guid) when is_integer(owner_guid) and is_integer(viewpoint_guid) do
    %Effects.ViewpointReleased{source_guid: owner_guid, target_guid: viewpoint_guid}
  end

  def summon_pet(owner_guid, entry, spell_id)
      when is_integer(owner_guid) and is_integer(entry) and entry > 0 and is_integer(spell_id) do
    %Effects.SummonPet{source_guid: owner_guid, entry: entry, spell_id: spell_id}
  end

  def tame_creature(owner_guid, entry) when is_integer(owner_guid) and is_integer(entry) and entry > 0 do
    %Effects.TameCreature{source_guid: owner_guid, entry: entry}
  end

  def dismiss_pet(pet_guid) when is_integer(pet_guid) do
    %Effects.DismissPet{target_guid: pet_guid}
  end

  def summon_totem(entry, slot, duration_ms)
      when is_integer(entry) and entry > 0 and slot in 1..4 and is_integer(duration_ms) do
    %Effects.SummonTotem{entry: entry, slot: slot, duration_ms: duration_ms}
  end

  def despawn_self(despawn_delay_ms, respawn_delay_ms)
      when is_integer(despawn_delay_ms) and is_integer(respawn_delay_ms) do
    %Effects.DespawnSelf{duration_ms: despawn_delay_ms, respawn_delay_ms: respawn_delay_ms}
  end

  def attack_start(target_guid) when is_integer(target_guid) do
    %Effects.StartAttack{target_guid: target_guid}
  end

  def forward_script_steps(target_guid, steps, source_guid) when is_integer(target_guid) and is_list(steps) do
    %Effects.ForwardScriptSteps{target_guid: target_guid, steps: steps, source_guid: source_guid}
  end

  def send_taxi_path(target_guid, path_id) when is_integer(target_guid) and is_integer(path_id) and path_id > 0 do
    %Effects.SendTaxiPath{target_guid: target_guid, path_id: path_id}
  end

  def play_sound(sound_id) when is_integer(sound_id) do
    %Effects.PlaySound{sound_id: sound_id}
  end

  def play_object_sound(sound_id) when is_integer(sound_id) do
    %Effects.PlayObjectSound{sound_id: sound_id}
  end

  def reputation_change(faction_id, value) when is_integer(faction_id) and faction_id > 0 and is_integer(value) do
    %Effects.ReputationChange{faction_id: faction_id, value: value}
  end

  def quest_cast_credit(target_guids, spell_id) when is_list(target_guids) and is_integer(spell_id) and spell_id > 0 do
    %Effects.QuestCastCredit{target_guids: target_guids, spell_id: spell_id}
  end

  def quest_event_credit(player_guid, quest_id, opts \\ [])
      when is_integer(player_guid) and player_guid > 0 and is_integer(quest_id) and quest_id > 0 do
    %Effects.QuestEventCredit{
      player_guid: player_guid,
      quest_id: quest_id,
      group?: Keyword.get(opts, :group?, false),
      distance: Keyword.get(opts, :distance, 0),
      world_object_guid: Keyword.get(opts, :world_object_guid)
    }
  end

  def quest_fail(player_guid, quest_id, opts \\ [])
      when is_integer(player_guid) and player_guid > 0 and is_integer(quest_id) and quest_id > 0 do
    %Effects.QuestFail{
      player_guid: player_guid,
      quest_id: quest_id,
      group?: Keyword.get(opts, :group?, false)
    }
  end

  def quest_interaction_credit(player_guid, target_guid)
      when is_integer(player_guid) and player_guid > 0 and is_integer(target_guid) and target_guid > 0 do
    %Effects.QuestInteractionCredit{player_guid: player_guid, target_guid: target_guid}
  end

  def quest_kill_credit(player_guid, creature_entry, opts \\ [])
      when is_integer(player_guid) and player_guid > 0 and is_integer(creature_entry) and creature_entry > 0 do
    %Effects.QuestKillCredit{
      player_guid: player_guid,
      creature_entry: creature_entry,
      group?: Keyword.get(opts, :group?, false)
    }
  end

  def forced_reactions_changed(reactions, friendly_faction_ids)
      when is_list(reactions) and is_list(friendly_faction_ids) do
    %Effects.ForcedReactionsChanged{
      reactions: reactions,
      friendly_faction_ids: friendly_faction_ids
    }
  end

  def faction_at_war_changed(index, enabled) when is_integer(index) and is_boolean(enabled) do
    %Effects.FactionAtWarChanged{index: index, enabled: enabled}
  end

  def set_facing({:angle, angle} = facing) when is_number(angle) do
    %Effects.SetFacing{facing: facing}
  end

  def set_facing({:target, target_guid} = facing) when is_integer(target_guid) do
    %Effects.SetFacing{facing: facing}
  end

  def drain(%{internal: %{events: events} = internal} = entity) when is_list(events) do
    {%{entity | internal: %{internal | events: []}}, events}
  end

  def drain(entity), do: {entity, []}
end
